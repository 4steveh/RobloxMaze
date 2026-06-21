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
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local WorldFolders = require(ReplicatedStorage.WorldFolders)

local player = Players.LocalPlayer

local battery = Config.Flashlight.BatteryMax
local lightOn = true -- starts on
local inSafeRoom = false -- driven ONLY by server remotes, never by local detection
local light = nil -- the current SpotLight (rebuilt each character)
local emitter = nil -- invisible part the SpotLight rides; aimed at the camera each frame
local flickerPhase = 0

-- Publish the on/off state so PlayerSFXController can play the toggle click (local).
player:SetAttribute(Attributes.FlashlightOn, lightOn)

local function setupLight(character)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	-- A faster respawn may have swapped in a new character while we yielded on
	-- WaitForChild above; bail so this stale call can't clobber the live light.
	if player.Character ~= character then
		return
	end
	-- Clean any prior emitter (a fast respawn can leave one behind).
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
	emitter = part
	light = spot
end

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
		if st == Enums.MonsterState.Chase or st == Enums.MonsterState.Investigate or st == Enums.MonsterState.Alert then
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
	setupLight(character)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(function()
	light = nil
	emitter = nil
	inSafeRoom = false
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.Flashlight.ToggleKey then
		lightOn = not lightOn
		player:SetAttribute(Attributes.FlashlightOn, lightOn)
	end
end)

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
	-- Aim: keep the emitter at the head but rotate it toward the CAMERA look (smoothed),
	-- so the beam follows where you point -- including up/down -- not where the torso faces.
	if emitter then
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local camera = Workspace.CurrentCamera
		if head and camera then
			local pos = head.Position
			local look = CFrame.lookAt(pos, pos + camera.CFrame.LookVector).Rotation
			local alpha = math.min(deltaTime * Config.Flashlight.AimSmoothing, 1)
			emitter.CFrame = emitter.CFrame.Rotation:Lerp(look, alpha) + pos
		end
	end

	-- Battery: recharge while in a SafeRoom; otherwise drain while lit. Clamp [0, max].
	if inSafeRoom then
		battery = math.min(Config.Flashlight.BatteryMax, battery + Config.Flashlight.RechargePerSecond * deltaTime)
	elseif lightOn and light then
		battery = math.max(0, battery - Config.Flashlight.DrainPerSecond * deltaTime)
	end

	-- Light output: dark at empty battery; subtle flicker when low.
	if light then
		local emitting = lightOn and battery > 0
		light.Enabled = emitting
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
