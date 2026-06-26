--!nonstrict
-- NoiseMeterController.client.luau
-- The HUD noise meter -- the readable tell that teaches the MONKEY's counter. It renders
-- the SERVER-authoritative `NoiseLevel` attribute (set by NoiseService from real movement
-- speed) as a bar, with a fixed marker at the monkey's HearThreshold: while the fill sits
-- BELOW the marker you are inaudible (green, safe); cross it (by sprinting/running) and the
-- bar flips red and pulses -- "the monkey can hear you now." So the player LEARNS that
-- going quiet is the counter. Render-only: reads replicated truth, decides nothing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)

local N = Config.Noise
local S = Config.Settings
local threshold = math.clamp(Config.Monster.Species.Monkey.HearThreshold, 0, 1)
local player = Players.LocalPlayer

-- Player accessibility prefs (client-local attributes, no server trust). FxIntensity scales the
-- attention-grabbing red PULSE; ReduceFlashing kills the strobe outright. The BAR's level + the
-- safe/loud meaning never depend on these -- only the flash that draws the eye does.
local fxIntensity = S.DefaultFxIntensity
local reduceFlashing = S.DefaultReduceFlashing
local function refreshPrefs()
	local fx = player:GetAttribute(Attributes.SettingFxIntensity)
	fxIntensity = math.clamp(if typeof(fx) == "number" then fx else S.DefaultFxIntensity, 0, 1)
	local rf = player:GetAttribute(Attributes.SettingReduceFlashing)
	reduceFlashing = if typeof(rf) == "boolean" then rf else S.DefaultReduceFlashing
end
refreshPrefs()
player:GetAttributeChangedSignal(Attributes.SettingFxIntensity):Connect(refreshPrefs)
player:GetAttributeChangedSignal(Attributes.SettingReduceFlashing):Connect(refreshPrefs)

local gui = Instance.new("ScreenGui")
gui.Name = "NoiseMeterGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

-- Bottom-right, mirroring the battery/stamina gauges on the left.
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -N.MeterMargin, 1, -N.MeterMargin)
panel.Size = UDim2.fromOffset(N.MeterWidth, N.MeterHeight)
panel.BackgroundColor3 = N.MeterBackColor
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Config.UI.StrokeColor
panelStroke.Transparency = Config.UI.StrokeTransparency
panelStroke.Thickness = Config.UI.StrokeThickness
panelStroke.Parent = panel
local panelGrad = Instance.new("UIGradient")
panelGrad.Color =
	ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1):Lerp(Color3.new(0, 0, 0), Config.UI.PanelGradientDarken))
panelGrad.Rotation = 90
panelGrad.Parent = panel

local fill = Instance.new("Frame")
fill.AnchorPoint = Vector2.new(0, 0.5)
fill.Position = UDim2.fromScale(0, 0.5)
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = N.MeterQuietColor
fill.BorderSizePixel = 0
fill.Parent = panel
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = fill

-- The "audible" marker: cross it and the monkey hears you.
local marker = Instance.new("Frame")
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Position = UDim2.fromScale(threshold, 0.5)
marker.Size = UDim2.new(0, 2, 1, 4)
marker.BackgroundColor3 = N.MeterThresholdColor
marker.BorderSizePixel = 0
marker.ZIndex = 3
marker.Parent = panel

-- A tiny caption centered over the marker so the line's MEANING is explicit at a glance: cross it
-- and the monkey can hear you. Teaches the noise counter at the HUD itself, not only via a JIT tip.
local thresholdLabel = Instance.new("TextLabel")
thresholdLabel.Name = "ThresholdLabel"
thresholdLabel.AnchorPoint = Vector2.new(0.5, 1)
thresholdLabel.Position = UDim2.new(threshold, 0, 0, -3)
thresholdLabel.Size = UDim2.fromOffset(100, N.MeterThresholdLabelSize + 4)
thresholdLabel.BackgroundTransparency = 1
thresholdLabel.Font = Config.UI.BodyFont
thresholdLabel.TextSize = N.MeterThresholdLabelSize
thresholdLabel.TextColor3 = N.MeterThresholdColor
thresholdLabel.TextStrokeColor3 = Config.UI.TextStrokeColor
thresholdLabel.TextStrokeTransparency = Config.UI.TextStrokeTransparency
thresholdLabel.Text = N.MeterThresholdLabel
thresholdLabel.ZIndex = 3
thresholdLabel.Parent = panel

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, 0, 0, -2)
label.Size = UDim2.fromOffset(N.MeterWidth, 16)
label.BackgroundTransparency = 1
label.Font = Config.UI.SubheadingFont
label.TextSize = 12
label.TextXAlignment = Enum.TextXAlignment.Right
label.TextColor3 = N.MeterQuietColor
label.TextStrokeTransparency = Config.UI.TextStrokeTransparency
label.Text = N.MeterLabel
label.Parent = panel

-- Colorblind redundancy: green-vs-red alone can't tell deuteranopia/protanopia "safe" from "audible",
-- so a word carries the same meaning -- "QUIET" below the threshold, "LOUD" at/above it. Top-left of the
-- meter (mirroring the right-aligned "NOISE" caption), so the safe/loud read survives without hue.
local stateLabel = Instance.new("TextLabel")
stateLabel.Name = "StateLabel"
stateLabel.AnchorPoint = Vector2.new(0, 1)
stateLabel.Position = UDim2.fromOffset(0, -2)
stateLabel.Size = UDim2.fromOffset(60, 16)
stateLabel.BackgroundTransparency = 1
stateLabel.Font = Config.UI.SubheadingFont
stateLabel.TextSize = 12
stateLabel.TextXAlignment = Enum.TextXAlignment.Left
stateLabel.TextColor3 = N.MeterQuietColor
stateLabel.TextStrokeColor3 = Config.UI.TextStrokeColor
stateLabel.TextStrokeTransparency = Config.UI.TextStrokeTransparency
stateLabel.Text = "QUIET"
stateLabel.Parent = panel

RunService.RenderStepped:Connect(function()
	local level = math.clamp(player:GetAttribute(Attributes.NoiseLevel) or 0, 0, 1)
	fill.Size = UDim2.fromScale(level, 1)
	local audible = level >= threshold
	if audible then
		-- Loud: flip red and pulse so it reads as a live alarm -- the marker + its caption flash too,
		-- so the eye is drawn to exactly the line you just crossed ("the monkey can hear you NOW").
		-- ReduceFlashing holds a STEADY red (no strobe); FxIntensity scales how hard the flash brightens
		-- (0 = also steady). The fill/label still flip red regardless, so the alarm's meaning is never lost.
		local pulse = if reduceFlashing then 0 else (0.5 + 0.5 * math.sin(os.clock() * 10)) * fxIntensity
		fill.BackgroundColor3 = N.MeterLoudColor:Lerp(Color3.new(1, 1, 1), pulse * 0.25)
		label.TextColor3 = N.MeterLoudColor
		marker.BackgroundColor3 = N.MeterLoudColor
		thresholdLabel.TextColor3 = N.MeterLoudColor:Lerp(Color3.new(1, 1, 1), pulse * 0.4)
		stateLabel.Text = "LOUD"
		stateLabel.TextColor3 = N.MeterLoudColor
	else
		fill.BackgroundColor3 = N.MeterQuietColor
		label.TextColor3 = N.MeterQuietColor
		marker.BackgroundColor3 = N.MeterThresholdColor
		thresholdLabel.TextColor3 = N.MeterThresholdColor
		stateLabel.Text = "QUIET"
		stateLabel.TextColor3 = N.MeterQuietColor
	end
end)
