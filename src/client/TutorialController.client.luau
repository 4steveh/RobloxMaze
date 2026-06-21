--!nonstrict
-- TutorialController.client.luau
-- Just-in-time onboarding: teaches each monster's COUNTER the first time you actually face
-- it (Roblox's own FTUE guidance — teach in the moment, not in an up-front wall of text).
-- The first time a monster CHASES you it explains sprint + breaking line of sight; the first
-- time one goes ALERT (the monkey heard you) it explains going quiet. Each tip fires once per
-- session. Render-only, driven by the existing MonsterStateChanged remote (no new wiring).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Enums = require(ReplicatedStorage.Enums)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)

local O = Config.Onboarding
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Tutorial"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
gui.Parent = playerGui

local tip = Instance.new("TextLabel")
tip.Name = "Tip"
tip.AnchorPoint = Vector2.new(0.5, 1)
tip.Position = UDim2.fromScale(0.5, 0.82)
tip.Size = UDim2.fromOffset(620, 34)
tip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.GothamBold
tip.TextSize = 20
tip.TextColor3 = Color3.fromRGB(245, 235, 220)
tip.TextStrokeTransparency = 1
tip.TextTransparency = 1
tip.Text = ""
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = tip
tip.Parent = gui

local token = 0
local function showTip(text)
	token += 1
	local mine = token
	tip.Text = text
	tip.TextTransparency = 0
	tip.TextStrokeTransparency = 0.4
	tip.BackgroundTransparency = 0.45
	task.delay(O.TipSeconds, function()
		if mine == token then
			TweenService:Create(
				tip,
				TweenInfo.new(0.6),
				{ TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }
			):Play()
		end
	end)
end

local shown = {}
local stateRemote = Remotes.get(Remotes.Names.MonsterStateChanged)
stateRemote.OnClientEvent:Connect(function(state)
	if state == Enums.MonsterState.Chase and not shown.chase then
		shown.chase = true
		showTip(O.ChaseTip)
	elseif state == Enums.MonsterState.Alert and not shown.alert then
		shown.alert = true
		showTip(O.AlertTip)
	end
end)

-- Trap warning: the first time the player gets near a floor trap, warn them BEFORE they can
-- step on it blind (the "I died and had no idea why" moment). Throttled proximity poll.
local traps = {}
Discovery.observe(Tags.Trap, function(part)
	if part:IsA("BasePart") then
		traps[part] = true
	end
end, function(part)
	traps[part] = nil
end)

local sinceCheck = 0
RunService.Heartbeat:Connect(function(dt)
	if shown.trap then
		return
	end
	sinceCheck += dt
	if sinceCheck < 0.25 then
		return
	end
	sinceCheck = 0
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	for part in traps do
		if part.Parent and (part.Position - hrp.Position).Magnitude <= O.TrapTipRadius then
			shown.trap = true
			showTip(O.TrapTip)
			break
		end
	end
end)
