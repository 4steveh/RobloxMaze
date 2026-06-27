--!nonstrict
-- FlareController.client.luau
-- Input + HUD for the FLARE (the throwable light burst that freezes a monster). FlareService owns the
-- throw entirely (landing point, charges, cooldown, the burning flare, the blind) -- this script only
-- captures input + renders a local "FLARE xN" chip and the on-screen touch button. The server
-- re-validates everything, so the local cooldown/charge check is purely for feel (it never gates the
-- authoritative server checks). Mirrors DecoyController.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local C = Config.Flare
local TC = Config.TouchControls
local ST = Config.Audio.Stingers

if not C.Enabled then
	return -- feature off: don't bind input or build the FLARE HUD
end

local throwRemote = Remotes.get(Remotes.Names.ThrowFlare)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Local release confirmation: a short 2D one-shot the instant the throw fires, so input feels immediate
-- (the landed flare's 3D ignite is server-side, possibly far away). Routed through the SFX bus.
local throwSound = Instance.new("Sound")
throwSound.SoundId = ST.DecoyThrowId
throwSound.Volume = ST.DecoyThrowVolume
throwSound.PlaybackSpeed = ST.DecoyThrowPitch
throwSound.SoundGroup = AudioGroups.get("SFX")
throwSound.Parent = SoundService

local cooldownUntil = 0 -- os.clock() until which the local UI shows "on cooldown"

local function charges(): number
	return player:GetAttribute(Attributes.FlareCharges) or 0
end

local function tryThrow()
	if os.clock() < cooldownUntil or charges() <= 0 then
		return
	end
	cooldownUntil = os.clock() + C.Cooldown
	throwRemote:FireServer()
	throwSound:Play()
end

-- Keyboard (PC) + a gamepad button bound to the same action. createTouchButton=false: touch
-- devices get the custom button below.
ContextActionService:BindAction("ThrowFlare", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		tryThrow()
	end
	return Enum.ContextActionResult.Sink
end, false, C.ThrowKey, C.GamepadThrowKey)

-- HUD chip (all devices): "FLARE xN" + a draining fill while on cooldown, bottom-left above the DECOY chip.
local gui = Instance.new("ScreenGui")
gui.Name = "FlareHud"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local chip = Instance.new("Frame")
chip.Name = "Chip"
chip.AnchorPoint = Vector2.new(0, 1)
chip.Position = UDim2.new(0, 18, 1, -C.ChipBottomOffset) -- above the DECOY chip + the gauges, not over them
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

local chipLabel = Instance.new("TextLabel")
chipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
chipLabel.Position = UDim2.fromScale(0.5, 0.5)
chipLabel.Size = UDim2.fromScale(1, 1)
chipLabel.BackgroundTransparency = 1
chipLabel.Font = Enum.Font.GothamBold
chipLabel.TextSize = 14
chipLabel.TextColor3 = TC.TextColor
chipLabel.ZIndex = 2
chipLabel.Parent = chip

-- Custom circular tap button for touch devices, stacked above the HIDE button.
local touchButton, touchScale
if UserInputService.TouchEnabled then
	local btn = Instance.new("TextButton")
	btn.Name = "FlareButton"
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
	ring.Thickness = TC.RingThickness
	ring.Parent = btn
	touchScale = Instance.new("UIScale")
	touchScale.Parent = btn
	btn.Activated:Connect(function()
		-- Tactile tap punch kids can SEE (mirrors the other touch buttons).
		touchScale.Scale = TC.PressScale
		TweenService:Create(
			touchScale,
			TweenInfo.new(TC.PressReturnSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
		tryThrow()
	end)
	btn.Parent = gui
	touchButton = btn
end

-- Per-frame: drain the cooldown fill (full = on cooldown), update the charge count, and dim everything
-- when out of flares so the affordance reads "empty".
local touchLabel = UserInputService.TouchEnabled
RunService.Heartbeat:Connect(function()
	local n = charges()
	local hint = touchLabel and ("FLARE x" .. n) or ("FLARE x" .. n .. "  [" .. C.ThrowKey.Name .. "]")
	chipLabel.Text = hint

	local remaining = cooldownUntil - os.clock()
	if remaining <= 0 then
		fill.Size = UDim2.fromScale(0, 1)
	else
		fill.Size = UDim2.fromScale(math.clamp(remaining / C.Cooldown, 0, 1), 1)
	end

	local empty = n <= 0
	chip.BackgroundTransparency = empty and math.min(0.85, TC.BackgroundTransparency + 0.35)
		or TC.BackgroundTransparency
	chipLabel.TextTransparency = empty and 0.4 or 0
	if touchButton then
		touchButton.BackgroundTransparency = empty and math.min(0.85, TC.BackgroundTransparency + 0.35)
			or TC.BackgroundTransparency
		touchButton.TextTransparency = empty and 0.4 or 0
	end
end)
