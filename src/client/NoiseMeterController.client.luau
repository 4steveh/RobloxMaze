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
local threshold = math.clamp(Config.Monster.Species.Monkey.HearThreshold, 0, 1)
local player = Players.LocalPlayer

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

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, 0, 0, -2)
label.Size = UDim2.fromOffset(N.MeterWidth, 16)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.TextSize = 12
label.TextXAlignment = Enum.TextXAlignment.Right
label.TextColor3 = N.MeterQuietColor
label.TextStrokeTransparency = 0.5
label.Text = N.MeterLabel
label.Parent = panel

RunService.RenderStepped:Connect(function()
	local level = math.clamp(player:GetAttribute(Attributes.NoiseLevel) or 0, 0, 1)
	fill.Size = UDim2.fromScale(level, 1)
	local audible = level >= threshold
	if audible then
		-- Loud: flip red and pulse so it reads as a live alarm.
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 10)
		fill.BackgroundColor3 = N.MeterLoudColor:Lerp(Color3.new(1, 1, 1), pulse * 0.25)
		label.TextColor3 = N.MeterLoudColor
	else
		fill.BackgroundColor3 = N.MeterQuietColor
		label.TextColor3 = N.MeterQuietColor
	end
end)
