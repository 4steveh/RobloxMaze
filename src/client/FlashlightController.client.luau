--!nonstrict
-- FlashlightController.client.luau
-- The player's flashlight: a Head-parented SpotLight (so it points where the
-- character faces) toggled with Config.Flashlight.ToggleKey, plus a client-side
-- battery.
--
-- Battery is intentionally CLIENT-SIDE (see CLAUDE.md): it is personal,
-- uncontested, latency-sensitive, and nothing else depends on it. Drain is fully
-- local; the recharge GATE is server-authoritative -- the client learns it is in
-- a SafeRoom only from SafeRoomService's enter/leave remotes and NEVER decides
-- safe-room occupancy itself.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local Cosmetics = require(ReplicatedStorage.Cosmetics)

local player = Players.LocalPlayer

local battery = Config.Flashlight.BatteryMax
local lightOn = true -- starts on
local inSafeRoom = false -- driven ONLY by server remotes, never by local detection
local light = nil -- the current SpotLight (rebuilt each character)
local emitter = nil -- invisible part the SpotLight rides; aimed at the camera each frame
local beam = nil -- the volumetric shaft Beam riding the emitter (nil when Config.Flashlight.Beam.Enabled is false)
local flickerPhase = 0

-- Publish the on/off state so PlayerSFXController can play the toggle click (local).
player:SetAttribute(Attributes.FlashlightOn, lightOn)

-- Tint the beam with the player's equipped flashlight-color cosmetic (purely cosmetic --
-- never touches Range/Brightness/detection, so the shop stays non-pay-to-win).
local function applyEquippedColor()
	if not light then
		return
	end
	local id = player:GetAttribute(Attributes.EquippedFlashlightColor)
	local cosmetic = id and Cosmetics.get(id)
	if cosmetic and cosmetic.kind == "FlashlightColor" then
		light.Color = cosmetic.payload
	else
		light.Color = Color3.new(1, 1, 1)
	end
end

-- Idempotent, SELF-HEALING light builder -- safe to call every frame. It (re)builds the
-- emitter + SpotLight only when they're missing/detached and the Head exists. This is the
-- watchdog that fixes "the flashlight sometimes doesn't work": the old one-shot rebuild used
-- WaitForChild and a stale-character guard that, on a fast death->respawn race, could leave
-- light/emitter permanently nil until the NEXT respawn. Now a lost race recovers next frame.
local function ensureLight(character)
	if not character or player.Character ~= character then
		return -- never attach to a stale / dead body
	end
	-- Already valid for THIS character? Nothing to do.
	if light and light.Parent and emitter and emitter.Parent == character then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return -- head hasn't streamed in yet; retry next frame
	end
	-- Clean any stale emitter, then build fresh.
	local prior = character:FindFirstChild("FlashlightEmitter")
	if prior then
		prior:Destroy()
	end

	-- The SpotLight rides an invisible emitter part (not the head): we CFrame the emitter
	-- to the head position but oriented along the CAMERA each frame, so the beam points
	-- where you LOOK (pitch included) instead of where the torso faces.
	local part = Instance.new("Part")
	part.Name = "FlashlightEmitter"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.CFrame = head.CFrame
	part.Parent = character

	local spot = Instance.new("SpotLight")
	spot.Name = "Flashlight"
	spot.Range = Config.Flashlight.Range
	spot.Angle = Config.Flashlight.Angle
	spot.Brightness = Config.Flashlight.Brightness
	spot.Shadows = Config.Flashlight.Shadows -- monsters throw a shadow before you see them (Future tech on)
	spot.Face = Enum.NormalId.Front -- beam along the emitter's LookVector, which we aim at the camera
	spot.Parent = part

	-- Volumetric shaft: a faint cone of light riding the emitter so a sweep of the flashlight
	-- reads as a physical beam cutting the dark (decides nothing -- render-only cosmetic). The
	-- emitter's Front face (= +LookVector) is where the light points, which for a Part is its -Z;
	-- so the near attachment sits at the lens and the far one at (0,0,-Length) down that -Z forward.
	if Config.Flashlight.Beam.Enabled then
		local B = Config.Flashlight.Beam
		local near = Instance.new("Attachment")
		near.Name = "FlashlightBeamNear"
		near.CFrame = CFrame.new() -- at the lens (emitter origin)
		near.Parent = part
		local far = Instance.new("Attachment")
		far.Name = "FlashlightBeamFar"
		far.CFrame = CFrame.new(0, 0, -B.Length) -- straight forward along the emitter's -Z (where the SpotLight points)
		far.Parent = part

		local shaft = Instance.new("Beam")
		shaft.Name = "FlashlightBeam"
		shaft.Attachment0 = near
		shaft.Attachment1 = far
		shaft.FaceCamera = true -- always present the ribbon flat to the viewer, so the shaft reads from any angle
		shaft.Segments = 6 -- a short straight shaft needs no tessellation; keep it cheap
		shaft.Width0 = B.WidthNear
		shaft.Width1 = B.WidthFar -- flares to a soft cone toward the far end
		shaft.Color = ColorSequence.new(B.Color)
		shaft.Brightness = B.Brightness
		shaft.LightInfluence = 0 -- self-lit glow, independent of scene lighting (it IS the light)
		-- Faint at the lens, ramping to fully clear at the far end -- a soft fade-out, never a hard bar.
		shaft.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, B.Transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		shaft.Parent = part
		beam = shaft
	end

	emitter = part
	light = spot
	applyEquippedColor()
end

-- Re-tint live when the player equips a different colour in the shop.
player:GetAttributeChangedSignal(Attributes.EquippedFlashlightColor):Connect(applyEquippedColor)

-- Extra flicker when a HUNTING monster is near: returns 0..1 (subtracted from beam
-- brightness). A fear beat + a tell that something is on you. Reads only replicated rig
-- State + position (exploit-safe), same as ChaseFXController. 0 when nothing hunts.
local function monsterProximityFlicker()
	local FL = Config.Flashlight
	if FL.MonsterFlickerMaxScale <= 0 then
		return 0
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)
	if not (hrp and monsters) then
		return 0
	end
	local threat = 0
	for _, rig in monsters:GetChildren() do
		local st = rig:GetAttribute(Attributes.MonsterState)
		if st == Enums.MonsterState.Chase or st == Enums.MonsterState.Investigate then -- pursuing only (not Alert): the beam stays dependable while the monkey is just listening
			local rRoot = rig:FindFirstChild("HumanoidRootPart")
			if rRoot then
				local d = (rRoot.Position - hrp.Position).Magnitude
				local prox = math.clamp((FL.MonsterFlickerStartDistance - d) / FL.MonsterFlickerStartDistance, 0, 1)
				if prox > threat then
					threat = prox
				end
			end
		end
	end
	if threat <= 0 then
		return 0
	end
	-- An erratic stutter that deepens with closeness (an occasional harder dropout).
	local osc = 0.5 + 0.5 * math.sin(os.clock() * FL.MonsterFlickerSpeed)
	local dropout = if math.random() < 0.1 * threat then 1 else 0
	return math.clamp(threat * FL.MonsterFlickerMaxScale * (0.55 * osc + 0.6 * dropout), 0, 0.95)
end

local function onCharacterAdded(character)
	-- New body: forget the old safe-room belief (the server re-fires "entered" if
	-- we spawned inside one) and rebuild the light. Battery persists across deaths.
	inSafeRoom = false
	ensureLight(character)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(function()
	light = nil
	emitter = nil
	beam = nil -- the Beam dies with the emitter part it rides; just drop the stale reference
	inSafeRoom = false
end)

local function setLight(on)
	lightOn = on
	player:SetAttribute(Attributes.FlashlightOn, lightOn)
end

-- Keyboard toggle (PC). createTouchButton=false: touch devices get the custom on-screen
-- button below instead of CAS's small generic auto-button.
local TOGGLE_ACTION = "ToggleFlashlight"
ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		setLight(not lightOn)
	end
	return Enum.ContextActionResult.Sink
end, false, Config.Flashlight.ToggleKey)

-- Custom on-screen flashlight button for touch devices (iPad/iPhone) -- a clear, big, always-
-- visible tap target (render-only; CLAUDE.md permits client cosmetic UI). Hidden on PC.
if UserInputService.TouchEnabled then
	local TC = Config.TouchControls
	local touchGui = Instance.new("ScreenGui")
	touchGui.Name = "FlashlightTouch"
	touchGui.ResetOnSpawn = false
	touchGui.Parent = player:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.Name = "FlashlightButton"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -TC.EdgeMargin, 1, -TC.FlashlightBottomOffset)
	btn.Size = UDim2.fromOffset(TC.ButtonSize, TC.ButtonSize)
	btn.BackgroundColor3 = TC.BackgroundColor
	btn.BackgroundTransparency = TC.BackgroundTransparency
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = TC.TextSize
	btn.TextColor3 = TC.TextColor
	btn.Text = TC.FlashlightLabel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- circular
	corner.Parent = btn
	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.Parent = btn
	-- Optional icon image (placeholder until a real asset id is set).
	if TC.FlashlightIconImage ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.6, 0.6)
		icon.Image = TC.FlashlightIconImage
		icon.Parent = btn
		btn.Text = ""
	end
	local function refreshRing()
		ring.Color = if lightOn then TC.FlashlightOnColor else TC.FlashlightOffColor
	end
	refreshRing()
	btn.Activated:Connect(function()
		setLight(not lightOn)
		refreshRing()
	end)
	btn.Parent = touchGui
end

-- Safe-room state comes ONLY from the server.
local enteredRemote = Remotes.get(Remotes.Names.SafeRoomEntered)
local leftRemote = Remotes.get(Remotes.Names.SafeRoomLeft)
enteredRemote.OnClientEvent:Connect(function()
	inSafeRoom = true
end)
leftRemote.OnClientEvent:Connect(function()
	inSafeRoom = false
end)

RunService.RenderStepped:Connect(function(deltaTime)
	-- Watchdog: (re)build the light if it's missing (e.g. a death->respawn race dropped it),
	-- so the flashlight self-heals within a frame instead of staying dark until the next spawn.
	if player.Character then
		ensureLight(player.Character)
	end

	-- Aim: keep the emitter at the head but rotate it toward the CAMERA look (smoothed),
	-- so the beam follows where you point -- including up/down -- not where the torso faces.
	if emitter then
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local camera = Workspace.CurrentCamera
		if head and camera then
			local pos = head.Position
			local camCF = camera.CFrame
			-- Use the camera's own up vector (always perpendicular to its look) so lookAt
			-- never degenerates to NaN when looking straight up or down.
			local look = CFrame.lookAt(pos, pos + camCF.LookVector, camCF.UpVector).Rotation
			local alpha = math.min(deltaTime * Config.Flashlight.AimSmoothing, 1)
			emitter.CFrame = emitter.CFrame.Rotation:Lerp(look, alpha) + pos
		end
	end

	-- Battery: recharge while in a SafeRoom; otherwise drain while lit. Clamp [0, max].
	if inSafeRoom then
		battery = math.min(Config.Flashlight.BatteryMax, battery + Config.Flashlight.RechargePerSecond * deltaTime)
	elseif lightOn and light then
		battery = math.max(0, battery - Config.Flashlight.DrainPerSecond * deltaTime)
	else
		-- Light OFF (and not in a SafeRoom): trickle-recharge anywhere so the flashlight can
		-- never permanently die and leave the player blind -- toggling off lets it recover.
		battery = math.min(Config.Flashlight.BatteryMax, battery + Config.Flashlight.IdleRechargePerSecond * deltaTime)
	end

	-- Light output: ON whenever toggled on (never fully off); dims + flickers as battery runs low.
	if light then
		local emitting = lightOn -- NEVER fully off: a drained battery only DIMS it (the low-battery flicker floors brightness), never darkness, so the flashlight always works
		light.Enabled = emitting
		-- The volumetric shaft tracks the light's on/off so it never lingers as a glowing bar
		-- when you cut the flashlight (it rides the same emitter, so aiming is already handled).
		if beam then
			beam.Enabled = emitting
		end
		if emitting then
			local brightness = Config.Flashlight.Brightness
			if battery <= Config.Flashlight.LowBatteryThreshold then
				flickerPhase += deltaTime * Config.Flashlight.LowBatteryFlickerSpeed
				local wave = 0.5 + 0.5 * math.sin(flickerPhase)
				local scale = Config.Flashlight.LowBatteryMinBrightnessScale
				brightness *= scale + (1 - scale) * wave
			end
			brightness *= 1 - monsterProximityFlicker()
			light.Brightness = brightness
		end
	end

	-- Expose the battery so the HUD gauge (HUDController) can read it. Client-only;
	-- the battery value never leaves the client (see CLAUDE.md).
	player:SetAttribute(Attributes.FlashlightBattery, battery)
end)
