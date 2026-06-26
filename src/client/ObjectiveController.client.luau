--!nonstrict
-- ObjectiveController.client.luau
-- The first-30-seconds direction layer (fix for "no clear direction"): a spawn intro
-- banner stating the goal, a controls hint that teaches the keys, and a persistent
-- objective tracker ("KEYS 0/3 -> reach the EXIT") that updates as keys come in.
-- Renders only; counts come from the server via the KeyCollected remote and Config.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)

local O = Config.Onboarding
local HUD = Config.HUD
local required = Config.Keys.RequiredToWin

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Objective"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = playerGui

-- Objective tracker (persistent, top-center, below the key pips) -------------------
local tracker = Instance.new("TextLabel")
tracker.Name = "Tracker"
tracker.AnchorPoint = Vector2.new(0.5, 0)
tracker.Position = UDim2.new(0.5, 0, 0, HUD.PipTopOffset + HUD.PipSize + 8)
tracker.Size = UDim2.fromOffset(360, 22)
tracker.BackgroundTransparency = 1
tracker.Font = Config.UI.SubheadingFont
tracker.TextSize = 18
tracker.TextColor3 = Config.UI.TextColor
tracker.TextStrokeTransparency = Config.UI.TextStrokeTransparency
tracker.Text = ""
tracker.Parent = gui

local function refreshTracker(count)
	if count >= required then
		tracker.Text = O.ObjectiveExitText
		tracker.TextColor3 = Config.HUD.ArrowColor
	else
		tracker.Text = string.format("%s %d/%d", O.ObjectiveLabel, count, required)
		tracker.TextColor3 = Config.UI.TextColor
	end
end
refreshTracker(player:GetAttribute(Attributes.KeyCount) or 0)

local keyCollected = Remotes.get(Remotes.Names.KeyCollected)
keyCollected.OnClientEvent:Connect(function(count)
	refreshTracker(count or 0)
end)
-- Also sync from the KeyCount attribute, so a round reset to 0 updates the tracker.
player:GetAttributeChangedSignal(Attributes.KeyCount):Connect(function()
	refreshTracker(player:GetAttribute(Attributes.KeyCount) or 0)
end)

-- Intro banner (center, shown once at session start) -------------------------------
local title = Instance.new("TextLabel")
title.Name = "IntroTitle"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.4)
title.Size = UDim2.fromOffset(620, 70)
title.BackgroundTransparency = 1
title.Font = Config.UI.DisplayFont
title.TextSize = 52
title.TextColor3 = Config.UI.TextColor
title.TextStrokeTransparency = Config.UI.TextStrokeTransparency
title.Text = string.format("%s %d %s", O.IntroVerb, required, O.IntroNoun)
title.Parent = gui

local subtitle = Instance.new("TextLabel")
subtitle.Name = "IntroSub"
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.Position = UDim2.fromScale(0.5, 0.4)
subtitle.Size = UDim2.fromOffset(620, 30)
subtitle.BackgroundTransparency = 1
subtitle.Font = Config.UI.BodyFont
subtitle.TextSize = 22
subtitle.TextColor3 = Config.UI.MutedTextColor
subtitle.TextStrokeTransparency = Config.UI.TextStrokeTransparency
subtitle.Text = O.IntroSub
subtitle.Parent = gui

-- Threat legend (intro): a colour->counter key for the two hunters, shown under the banner so a
-- new player learns what they're up against BEFORE the first encounter. The colours mirror the
-- radar blips + eye-glow tells, so legend / radar / glowing eyes all teach one colour language.
local legend = Instance.new("Frame")
legend.Name = "ThreatLegend"
legend.AnchorPoint = Vector2.new(0.5, 0)
legend.Position = UDim2.fromScale(0.5, 0.52)
legend.Size = UDim2.fromOffset(620, 96)
legend.BackgroundTransparency = 1
legend.Parent = gui

local legendLayout = Instance.new("UIListLayout")
legendLayout.FillDirection = Enum.FillDirection.Vertical
legendLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
legendLayout.Padding = UDim.new(0, 6)
legendLayout.Parent = legend

local function legendLine(text, color, order, size, font)
	local lbl = Instance.new("TextLabel")
	lbl.LayoutOrder = order
	lbl.Size = UDim2.fromOffset(620, size + 6)
	lbl.BackgroundTransparency = 1
	lbl.Font = font
	lbl.TextSize = size
	lbl.TextColor3 = color
	lbl.TextStrokeColor3 = Config.UI.TextStrokeColor
	lbl.TextStrokeTransparency = Config.UI.TextStrokeTransparency
	lbl.Text = text
	lbl.Parent = legend
	return lbl
end

local legendLines = {
	legendLine(O.LegendTitle, Config.UI.MutedTextColor, 1, 16, Config.UI.SubheadingFont),
	legendLine(O.LegendBunnyText, O.LegendBunnyColor, 2, 19, Config.UI.BodyFont),
	legendLine(O.LegendMonkeyText, O.LegendMonkeyColor, 3, 19, Config.UI.BodyFont),
}

-- Controls hint (bottom-center, fades after a timer or first move) ------------------
local controls = Instance.new("TextLabel")
controls.Name = "ControlsHint"
controls.AnchorPoint = Vector2.new(0.5, 1)
controls.Position = UDim2.new(0.5, 0, 1, -70)
controls.Size = UDim2.fromOffset(520, 26)
controls.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
controls.BackgroundTransparency = 0.5
controls.Font = Config.UI.BodyFont
controls.TextSize = 17
controls.TextColor3 = Config.UI.TextColor
controls.Text = O.ControlsHint
local controlsCorner = Instance.new("UICorner")
controlsCorner.CornerRadius = UDim.new(0, 6)
controlsCorner.Parent = controls
local controlsStroke = Instance.new("UIStroke")
controlsStroke.Color = Config.UI.StrokeColor
controlsStroke.Transparency = Config.UI.StrokeTransparency
controlsStroke.Thickness = Config.UI.StrokeThickness
controlsStroke.Parent = controls
controls.Parent = gui

local function fadeOut(label, duration)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 })
		:Play()
end

-- Hold the intro, then fade title + subtitle together.
task.delay(O.IntroBannerSeconds, function()
	fadeOut(title, 1)
	fadeOut(subtitle, 1)
end)

-- The legend holds a little longer (it's denser to read), then fades on its own.
task.delay(O.LegendSeconds, function()
	for _, line in legendLines do
		fadeOut(line, 1)
	end
end)

-- Fade the controls hint after its timer OR the first movement key, whichever first.
local controlsDismissed = false
local function dismissControls()
	if controlsDismissed then
		return
	end
	controlsDismissed = true
	fadeOut(controls, 0.8)
end

task.delay(O.ControlsHintSeconds, dismissControls)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if
		input.KeyCode == Enum.KeyCode.W
		or input.KeyCode == Enum.KeyCode.A
		or input.KeyCode == Enum.KeyCode.S
		or input.KeyCode == Enum.KeyCode.D
	then
		dismissControls()
	end
end)
