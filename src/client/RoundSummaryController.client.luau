--!nonstrict
-- RoundSummaryController.client.luau
-- The end-of-round results card off the RoundSummary remote: coins earned this round, the
-- breakdown (keys held + escaped/caught), and the new total. Render-only -- the server decides
-- the award. A run always pays SOMETHING, so this never reads as "you got nothing".

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Remotes)
local Config = require(ReplicatedStorage.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "RoundSummary"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.32)
panel.Size = UDim2.fromOffset(360, 150)
panel.BackgroundColor3 = Config.UI.PanelColor
panel.BackgroundTransparency = 1
panel.Visible = false
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, Config.UI.PanelCornerRadius)
panelCorner.Parent = panel
local panelGradient = Instance.new("UIGradient")
panelGradient.Color =
	ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1):Lerp(Color3.new(0, 0, 0), Config.UI.PanelGradientDarken))
panelGradient.Rotation = 90
panelGradient.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Config.UI.StrokeColor
panelStroke.Thickness = Config.UI.StrokeThickness
panelStroke.Transparency = 1
panelStroke.Parent = panel
panel.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 14)
title.Size = UDim2.fromOffset(340, 32)
title.BackgroundTransparency = 1
title.Font = Config.UI.HeadingFont
title.TextSize = 26
title.TextTransparency = 1
title.Parent = panel

local coins = Instance.new("TextLabel")
coins.AnchorPoint = Vector2.new(0.5, 0)
coins.Position = UDim2.new(0.5, 0, 0, 52)
coins.Size = UDim2.fromOffset(340, 40)
coins.BackgroundTransparency = 1
coins.Font = Config.UI.HeadingFont
coins.TextSize = 36
coins.TextColor3 = Config.UI.WarnColor
coins.TextTransparency = 1
coins.Parent = panel

local breakdown = Instance.new("TextLabel")
breakdown.AnchorPoint = Vector2.new(0.5, 0)
breakdown.Position = UDim2.new(0.5, 0, 0, 98)
breakdown.Size = UDim2.fromOffset(340, 20)
breakdown.BackgroundTransparency = 1
breakdown.Font = Config.UI.BodyFont
breakdown.TextSize = 15
breakdown.TextColor3 = Config.UI.MutedTextColor
breakdown.TextTransparency = 1
breakdown.Parent = panel

local total = Instance.new("TextLabel")
total.AnchorPoint = Vector2.new(0.5, 0)
total.Position = UDim2.new(0.5, 0, 0, 120)
total.Size = UDim2.fromOffset(340, 20)
total.BackgroundTransparency = 1
total.Font = Config.UI.BodyFont
total.TextSize = 15
total.TextColor3 = Config.UI.MutedTextColor
total.TextTransparency = 1
total.Parent = panel

local token = 0
local function fade(inst, prop, to, t)
	TweenService:Create(inst, TweenInfo.new(t), { [prop] = to }):Play()
end

Remotes.get(Remotes.Names.RoundSummary).OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	token += 1
	local mine = token

	title.Text = if data.escaped then "ESCAPED!" else "ROUND OVER"
	title.TextColor3 = if data.escaped then Config.UI.SafeColor else Config.UI.TextColor
	coins.Text = string.format("+%d", data.coinsGained or 0)
	-- Surface the optional gold bonus keys only when the team grabbed any (so the line stays clean).
	local bonus = data.bonusKeys or 0
	local bonusText = if bonus > 0 then string.format("  ·  %d bonus", bonus) else ""
	breakdown.Text =
		string.format("%d keys%s  ·  %s", data.keys or 0, bonusText, if data.escaped then "escaped" else "caught")
	total.Text = string.format("Total: %d coins", data.total or 0)

	panel.Visible = true
	fade(panel, "BackgroundTransparency", 0.15, 0.3)
	fade(panelStroke, "Transparency", 0.1, 0.3)
	for _, l in { title, coins, breakdown, total } do
		fade(l, "TextTransparency", 0, 0.3)
	end

	task.delay(4.5, function()
		if mine ~= token then
			return
		end
		fade(panel, "BackgroundTransparency", 1, 0.6)
		fade(panelStroke, "Transparency", 1, 0.6)
		for _, l in { title, coins, breakdown, total } do
			fade(l, "TextTransparency", 1, 0.6)
		end
		task.delay(0.6, function()
			if mine == token then
				panel.Visible = false
			end
		end)
	end)
end)
