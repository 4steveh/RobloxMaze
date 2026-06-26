--!nonstrict
-- DecoyController.client.luau
-- Sends the THROW-DECOY intent (no payload) and shows the cooldown. DecoyService owns the
-- throw entirely (landing point, cooldown, the rattling decoy, the NoiseEvent) -- this script
-- only captures input + renders a local cooldown HUD/button. The server re-validates everything,
-- so the local cooldown is purely for feel (it never gates the authoritative server cooldown).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local C = Config.Decoy
local TC = Config.TouchControls
local ST = Config.Audio.Stingers
local throwRemote = Remotes.get(Remotes.Names.ThrowDecoy)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Local release confirmation: a short 2D one-shot the instant the throw is accepted, so the input
-- feels immediate (the landed decoy's 3D rattle is server-side). Routed through the SFX bus.
local throwSound = Instance.new("Sound")
throwSound.SoundId = ST.DecoyThrowId
throwSound.Volume = ST.DecoyThrowVolume
throwSound.PlaybackSpeed = ST.DecoyThrowPitch
throwSound.SoundGroup = AudioGroups.get("SFX")
throwSound.Parent = SoundService

local cooldownUntil = 0 -- os.clock() until which the local UI shows "on cooldown"

local function tryThrow()
	if os.clock() < cooldownUntil then
		return
	end
	cooldownUntil = os.clock() + C.Cooldown
	throwRemote:FireServer()
	throwSound:Play()
end

-- Keyboard (PC) + a gamepad button bound to the same action. createTouchButton=false: touch
-- devices get the custom button below.
ContextActionService:BindAction("ThrowDecoy", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		tryThrow()
	end
	return Enum.ContextActionResult.Sink
end, false, C.ThrowKey, C.GamepadThrowKey)

-- HUD cooldown chip (all devices): "DECOY" + a draining fill while on cooldown, bottom-left.
local gui = Instance.new("ScreenGui")
gui.Name = "DecoyHud"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local chip = Instance.new("Frame")
chip.Name = "Chip"
chip.AnchorPoint = Vector2.new(0, 1)
chip.Position = UDim2.new(0, 18, 1, -C.ChipBottomOffset) -- above the battery+stamina gauges, not over them
chip.Size = UDim2.fromOffset(120, 26)
chip.BackgroundColor3 = TC.BackgroundColor
chip.BackgroundTransparency = TC.BackgroundTransparency
local chipCorner = Instance.new("UICorner")
chipCorner.CornerRadius = UDim.new(0, 6)
chipCorner.Parent = chip
chip.Parent = gui

local fill = Instance.new("Frame")
fill.Name = "Cooldown"
fill.AnchorPoint = Vector2.new(0, 0.5)
fill.Position = UDim2.fromScale(0, 0.5)
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = C.ButtonColor
fill.BackgroundTransparency = 0.55
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = fill
fill.Parent = chip

local readyHint = UserInputService.TouchEnabled and C.Label or (C.Label .. "  [" .. C.ThrowKey.Name .. "]")
local chipLabel = Instance.new("TextLabel")
chipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
chipLabel.Position = UDim2.fromScale(0.5, 0.5)
chipLabel.Size = UDim2.fromScale(1, 1)
chipLabel.BackgroundTransparency = 1
chipLabel.Font = Enum.Font.GothamBold
chipLabel.TextSize = 14
chipLabel.TextColor3 = TC.TextColor
chipLabel.Text = readyHint
chipLabel.ZIndex = 2
chipLabel.Parent = chip

-- Custom circular tap button for touch devices, stacked above the LIGHT button.
if UserInputService.TouchEnabled then
	local btn = Instance.new("TextButton")
	btn.Name = "DecoyButton"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -TC.EdgeMargin, 1, -C.TouchBottomOffset)
	btn.Size = UDim2.fromOffset(TC.ButtonSize, TC.ButtonSize)
	btn.BackgroundColor3 = TC.BackgroundColor
	btn.BackgroundTransparency = TC.BackgroundTransparency
	btn.AutoButtonColor = true
	btn.Active = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = TC.TextSize
	btn.TextColor3 = TC.TextColor
	btn.Text = C.Label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = btn
	local ring = Instance.new("UIStroke")
	ring.Color = C.ButtonColor
	ring.Thickness = 3
	ring.Parent = btn
	btn.Activated:Connect(tryThrow)
	btn.Parent = gui
end

-- Drain the cooldown fill (full = on cooldown, empty = ready).
RunService.Heartbeat:Connect(function()
	local remaining = cooldownUntil - os.clock()
	if remaining <= 0 then
		fill.Size = UDim2.fromScale(0, 1)
	else
		fill.Size = UDim2.fromScale(math.clamp(remaining / C.Cooldown, 0, 1), 1)
	end
end)
