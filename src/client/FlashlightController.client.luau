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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer

local battery = Config.Flashlight.BatteryMax
local lightOn = true -- starts on
local inSafeRoom = false -- driven ONLY by server remotes, never by local detection
local light = nil -- the current SpotLight (rebuilt each character)
local flickerPhase = 0

-- Temporary debug readout of the battery, replaced by a real HUD gauge in
-- Prompt 2. Also mirrored to a clearly-named attribute for quick inspection.
local debugLabel = nil
local function ensureDebugUi()
	-- NOTE: the layout/style literals below (size, padding, text size, transparency)
	-- are throwaway debug-only values, intentionally exempt from the Config
	-- single-source-of-truth rule -- this whole readout is deleted with the Prompt 2 HUD.
	local gui = Instance.new("ScreenGui")
	gui.Name = "FlashlightDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(260, 30)
	label.Position = UDim2.fromOffset(12, 12)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = gui
	debugLabel = label
end

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
	local existing = head:FindFirstChild("Flashlight")
	if existing then
		existing:Destroy()
	end

	local spot = Instance.new("SpotLight")
	spot.Name = "Flashlight"
	spot.Range = Config.Flashlight.Range
	spot.Angle = Config.Flashlight.Angle
	spot.Brightness = Config.Flashlight.Brightness
	spot.Face = Enum.NormalId.Front
	-- Head-aligned for now: the light points where the head faces. Camera-aligned
	-- aiming -- updating the light's CFrame each RenderStep to follow the camera --
	-- is the later upgrade.
	spot.Parent = head
	light = spot
end

-- Stub: extra flicker when a monster is near. Returns 0..1 (0 = none). Monsters
-- arrive in a later milestone; the hook is wired now so the light already reacts.
local function monsterProximityFlicker()
	return 0
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
	inSafeRoom = false
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.Flashlight.ToggleKey then
		lightOn = not lightOn
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

ensureDebugUi()

RunService.RenderStepped:Connect(function(deltaTime)
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

	-- Temporary debug surface (removed when the Prompt 2 HUD lands).
	player:SetAttribute("DebugFlashlightBattery", battery)
	if debugLabel then
		local state = inSafeRoom and "RECHARGING (safe)" or (lightOn and "draining" or "off")
		debugLabel.Text =
			string.format(" Flashlight  %d / %d  -  %s", math.floor(battery + 0.5), Config.Flashlight.BatteryMax, state)
	end
end)
