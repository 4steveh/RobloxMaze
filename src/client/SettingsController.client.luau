--!nonstrict
-- SettingsController.client.luau
-- The game's comfort/accessibility + help menu (render-only client; the FlickerController-class
-- exception CLAUDE.md permits -- these prefs shape only THIS client's view/audio, never a contested
-- outcome). It PRODUCES three personal, uncontested prefs as LocalPlayer attributes that the FX/audio
-- controllers READ on the same client; it self-detects no server-authoritative state and trusts no
-- server. A persistent gear button (top-left -- the one corner the HUD/radar/player-list don't use)
-- toggles a panel with two steppers (effects intensity, master volume) + a reduce-flashing toggle, plus
-- a HOW TO PLAY section that recalls the one-shot onboarding (controls + the red/yellow threat legend).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local S = Config.Settings
local UI = Config.UI
local OB = Config.Onboarding

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PAD = 18 -- px inner padding (matches the panel header inset the sibling controllers use)

-- Small UI helpers (the panel has several near-identical labels/buttons -- factoring the corner +
-- hairline stroke that every sibling controller applies keeps the layout readable).
local function corner(inst: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function stroke(inst: Instance)
	local s = Instance.new("UIStroke")
	s.Color = UI.StrokeColor
	s.Transparency = UI.StrokeTransparency
	s.Thickness = UI.StrokeThickness
	s.Parent = inst
end

-- The Master bus is the single mix root every other bus cascades from; scaling its Config volume by
-- the pref dims (or mutes) ALL audio at once -- there was no way to lower the audio (incl. the scream).
local function applyMasterVolume()
	local v = player:GetAttribute(Attributes.SettingMasterVolume) or S.DefaultMasterVolume
	AudioGroups.get("Master").Volume = Config.Audio.Groups.Master * v
end

-- Seed the prefs to their defaults on boot, then apply the audio one immediately. Consumers read these
-- attributes with their OWN defaults, so this producer never has to run first (ordering is a non-issue).
player:SetAttribute(Attributes.SettingFxIntensity, S.DefaultFxIntensity)
player:SetAttribute(Attributes.SettingMasterVolume, S.DefaultMasterVolume)
player:SetAttribute(Attributes.SettingReduceFlashing, S.DefaultReduceFlashing)
applyMasterVolume()
-- Re-apply whenever the master-volume pref changes (single writer, so this is the one apply path).
player:GetAttributeChangedSignal(Attributes.SettingMasterVolume):Connect(applyMasterVolume)

-- High DisplayOrder + IgnoreGuiInset so the menu sits above the base HUD (and the shop at 25).
local gui = Instance.new("ScreenGui")
gui.Name = "Settings"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = playerGui

-- Persistent gear button (top-left). Works on touch + click; the keys below also toggle the panel.
local gearBtn = Instance.new("TextButton")
gearBtn.Name = "OpenSettings"
gearBtn.Position = UDim2.fromOffset(S.ButtonMargin, S.ButtonMargin)
gearBtn.Size = UDim2.fromOffset(S.ButtonSize, S.ButtonSize)
gearBtn.BackgroundColor3 = UI.PanelColor
gearBtn.BackgroundTransparency = 0.25
gearBtn.Font = UI.HeadingFont
gearBtn.TextSize = 24
gearBtn.TextColor3 = S.GearColor
gearBtn.Text = S.GearLabel
corner(gearBtn, UI.ChipCornerRadius)
stroke(gearBtn)
gearBtn.Parent = gui

-- Panel (centered, hidden by default).
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(S.PanelWidth, S.PanelHeight)
panel.BackgroundColor3 = UI.PanelColor
panel.BackgroundTransparency = UI.PanelTransparency
panel.Visible = false
corner(panel, UI.PanelCornerRadius)
local pGradient = Instance.new("UIGradient")
pGradient.Color =
	ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1):Lerp(Color3.new(0, 0, 0), UI.PanelGradientDarken))
pGradient.Rotation = 90
pGradient.Parent = panel
stroke(panel)
panel.Parent = gui

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(PAD, 14)
title.Size = UDim2.fromOffset(S.PanelWidth - 2 * PAD - 32, 28)
title.BackgroundTransparency = 1
title.Font = UI.HeadingFont
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextSize = 22
title.TextColor3 = UI.TextColor
title.Text = S.Title
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -14, 0, 12)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.BackgroundColor3 = UI.PanelColor
closeBtn.Font = UI.SubheadingFont
closeBtn.TextSize = 18
closeBtn.TextColor3 = UI.TextColor
closeBtn.Text = "X"
corner(closeBtn, UI.ChipCornerRadius)
stroke(closeBtn)
closeBtn.Parent = panel

-- Each setting row refreshes its display from the live attribute when the panel opens.
local refreshers = {}

-- Snap a 0..1 value onto the AdjustStep grid (so repeated +0.1 steps stay clean: 0.30, not 0.30000004).
local function snap(v: number): number
	return math.clamp(math.floor(v / S.AdjustStep + 0.5) * S.AdjustStep, 0, 1)
end

local function percent(v: number): string
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

-- A −/+ stepper row writing a 0..1 attribute, with a fill bar showing the level. Returns nothing; it
-- registers its own refresher. `y` is the row's top offset inside the panel (layout glue).
local function stepperRow(y: number, label: string, attr: string)
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(PAD, y)
	row.Size = UDim2.fromOffset(S.PanelWidth - 2 * PAD, S.RowHeight)
	row.BackgroundColor3 = UI.PanelColor
	row.BackgroundTransparency = 0.35
	corner(row, UI.ChipCornerRadius)
	stroke(row)
	row.Parent = panel

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(12, 4)
	name.Size = UDim2.fromOffset(200, 22)
	name.BackgroundTransparency = 1
	name.Font = UI.SubheadingFont
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextSize = 15
	name.TextColor3 = UI.TextColor
	name.Text = label
	name.Parent = row

	local minusBtn = Instance.new("TextButton")
	minusBtn.AnchorPoint = Vector2.new(1, 0)
	minusBtn.Position = UDim2.new(1, -112, 0, 4)
	minusBtn.Size = UDim2.fromOffset(28, 28)
	minusBtn.BackgroundColor3 = UI.PanelColor
	minusBtn.Font = UI.HeadingFont
	minusBtn.TextSize = 20
	minusBtn.TextColor3 = UI.TextColor
	minusBtn.Text = "−"
	corner(minusBtn, UI.ChipCornerRadius)
	stroke(minusBtn)
	minusBtn.Parent = row

	local value = Instance.new("TextLabel")
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -40, 0, 6)
	value.Size = UDim2.fromOffset(66, 24)
	value.BackgroundTransparency = 1
	value.Font = UI.HeadingFont
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.TextSize = 16
	value.TextColor3 = UI.AccentColor
	value.Parent = row

	local plusBtn = Instance.new("TextButton")
	plusBtn.AnchorPoint = Vector2.new(1, 0)
	plusBtn.Position = UDim2.new(1, 0, 0, 4)
	plusBtn.Size = UDim2.fromOffset(28, 28)
	plusBtn.BackgroundColor3 = UI.PanelColor
	plusBtn.Font = UI.HeadingFont
	plusBtn.TextSize = 20
	plusBtn.TextColor3 = UI.TextColor
	plusBtn.Text = "+"
	corner(plusBtn, UI.ChipCornerRadius)
	stroke(plusBtn)
	plusBtn.Parent = row

	-- A thin level bar along the bottom edge of the row (a quick visual read of the 0..1 value).
	local barBg = Instance.new("Frame")
	barBg.AnchorPoint = Vector2.new(0, 1)
	barBg.Position = UDim2.new(0, 12, 1, -6)
	barBg.Size = UDim2.new(1, -24, 0, 4)
	barBg.BackgroundColor3 = UI.StrokeColor
	barBg.BackgroundTransparency = 0.3
	corner(barBg, UI.ChipCornerRadius)
	barBg.Parent = row

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = UI.AccentColor
	corner(barFill, UI.ChipCornerRadius)
	barFill.Parent = barBg

	local function refresh()
		local v = player:GetAttribute(attr) or 0
		value.Text = percent(v)
		barFill.Size = UDim2.fromScale(v, 1)
	end
	refreshers[#refreshers + 1] = refresh

	local function step(delta: number)
		player:SetAttribute(attr, snap((player:GetAttribute(attr) or 0) + delta))
		refresh()
	end
	minusBtn.Activated:Connect(function()
		step(-S.AdjustStep)
	end)
	plusBtn.Activated:Connect(function()
		step(S.AdjustStep)
	end)
end

-- A simple ON/OFF toggle row writing a boolean attribute.
local function toggleRow(y: number, label: string, attr: string)
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(PAD, y)
	row.Size = UDim2.fromOffset(S.PanelWidth - 2 * PAD, S.RowHeight)
	row.BackgroundColor3 = UI.PanelColor
	row.BackgroundTransparency = 0.35
	corner(row, UI.ChipCornerRadius)
	stroke(row)
	row.Parent = panel

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(12, 0)
	name.Size = UDim2.fromOffset(220, S.RowHeight)
	name.BackgroundTransparency = 1
	name.Font = UI.SubheadingFont
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextSize = 15
	name.TextColor3 = UI.TextColor
	name.Text = label
	name.Parent = row

	local toggle = Instance.new("TextButton")
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, -12, 0.5, 0)
	toggle.Size = UDim2.fromOffset(72, 30)
	toggle.Font = UI.SubheadingFont
	toggle.TextSize = 15
	toggle.TextColor3 = Color3.fromRGB(20, 22, 26)
	corner(toggle, UI.ChipCornerRadius)
	stroke(toggle)
	toggle.Parent = row

	local function refresh()
		local on = player:GetAttribute(attr) == true
		toggle.Text = if on then "ON" else "OFF"
		toggle.BackgroundColor3 = if on then UI.SafeColor else UI.MutedTextColor
	end
	refreshers[#refreshers + 1] = refresh

	toggle.Activated:Connect(function()
		player:SetAttribute(attr, player:GetAttribute(attr) ~= true)
		refresh()
	end)
end

-- A plain text line in the help section (returns the next y so the section stacks cleanly).
local function helpLine(y: number, text: string, font: Enum.Font, size: number, color: Color3): number
	local line = Instance.new("TextLabel")
	line.Position = UDim2.fromOffset(PAD, y)
	line.Size = UDim2.fromOffset(S.PanelWidth - 2 * PAD, size + 6)
	line.BackgroundTransparency = 1
	line.Font = font
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextSize = size
	line.TextColor3 = color
	line.TextWrapped = true
	line.Text = text
	line.Parent = panel
	return y + size + 8
end

-- Lay the three setting rows out from a running cursor (the panel is short enough to need no scroll).
local rowGap = 8
local y = 52
stepperRow(y, S.FxIntensityLabel, Attributes.SettingFxIntensity)
y += S.RowHeight + rowGap
stepperRow(y, S.VolumeLabel, Attributes.SettingMasterVolume)
y += S.RowHeight + rowGap
toggleRow(y, S.ReduceFlashingLabel, Attributes.SettingReduceFlashing)
y += S.RowHeight + rowGap + 8

-- HOW TO PLAY: recall the one-shot onboarding a player may have missed (controls + the threat legend),
-- plus the menu/shop keys so they're discoverable. Key names come off the Config keybinds, not literals.
y = helpLine(y, S.HelpTitle, UI.HeadingFont, 18, UI.TextColor)
y = helpLine(y, OB.ControlsHint, UI.BodyFont, 14, UI.MutedTextColor)
y = helpLine(
	y,
	string.format("%s  Settings        %s  Shop", S.ToggleKey.Name, Config.Shop.OpenKey.Name),
	UI.BodyFont,
	14,
	UI.MutedTextColor
)
y += 6
y = helpLine(y, OB.LegendTitle, UI.SubheadingFont, 15, UI.TextColor)
y = helpLine(y, OB.LegendBunnyText, UI.BodyFont, 14, OB.LegendBunnyColor)
y = helpLine(y, OB.LegendMonkeyText, UI.BodyFont, 14, OB.LegendMonkeyColor)

local function setOpen(open: boolean)
	panel.Visible = open
	if open then
		for _, refresh in refreshers do
			refresh()
		end
	end
end

gearBtn.Activated:Connect(function()
	setOpen(not panel.Visible)
end)
closeBtn.Activated:Connect(function()
	setOpen(false)
end)

-- Keyboard ToggleKey + gamepad GamepadToggleKey both arrive here as a KeyCode (matches how the sibling
-- shop binds its open key); gameProcessed guards against toggling while typing in a text box.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == S.ToggleKey or input.KeyCode == S.GamepadToggleKey then
		setOpen(not panel.Visible)
	end
end)
