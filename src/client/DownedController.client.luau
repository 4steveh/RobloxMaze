--!nonstrict
-- DownedController.client.luau
-- The downed/revive HUD (render-only — DownedService owns the truth via player attributes):
--   * When YOU are downed: a dark wash + "DOWNED" + a shrinking BLEEDOUT bar (from
--     DownedUntil) and a filling REVIVE bar (from ReviveProgress), so you can read your odds.
--   * When a TEAMMATE is downed: a world-space "REVIVE" beacon over them with a revive bar,
--     so you can find and save them — just stay within range and it fills.
-- No client input or detection: revive is server-authoritative spatial (DownedService); this
-- only renders the attributes it pushes. The FlickerController-class client cosmetic.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)

local D = Config.Downed
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "DownedHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90 -- below the jumpscare (100), above the base HUD
gui.Parent = playerGui

-- Local downed overlay --------------------------------------------------------------
local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = D.OverlayColor
overlay.BackgroundTransparency = D.OverlayTransparency
overlay.Visible = false
overlay.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.4)
title.Size = UDim2.fromOffset(560, 80)
title.BackgroundTransparency = 1
title.Font = Config.UI.DisplayFont
title.TextSize = 64
title.TextColor3 = D.BleedoutBarColor
title.TextStrokeTransparency = Config.UI.TextStrokeTransparency
title.Text = D.DownedText
title.Parent = overlay

local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.Position = UDim2.fromScale(0.5, 0.48)
subtitle.Size = UDim2.fromOffset(560, 28)
subtitle.BackgroundTransparency = 1
subtitle.Font = Config.UI.BodyFont
subtitle.TextSize = 20
subtitle.TextColor3 = Config.UI.MutedTextColor
subtitle.TextStrokeTransparency = Config.UI.TextStrokeTransparency
subtitle.Text = D.DownedSubText
subtitle.Parent = overlay

-- A labelled progress bar (back panel + fill + caption above it).
local function makeBar(yScale, fillColor, caption)
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, yScale)
	back.Size = UDim2.fromOffset(D.BarWidth, D.BarHeight)
	back.BackgroundColor3 = Color3.fromRGB(20, 18, 20)
	back.BackgroundTransparency = 0.2
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
	backCorner.Parent = back

	local backStroke = Instance.new("UIStroke")
	backStroke.Color = Config.UI.StrokeColor
	backStroke.Transparency = Config.UI.StrokeTransparency
	backStroke.Thickness = Config.UI.StrokeThickness
	backStroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
	fillCorner.Parent = fill
	fill.Parent = back

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -2)
	label.Size = UDim2.fromOffset(D.BarWidth, 16)
	label.BackgroundTransparency = 1
	label.Font = Config.UI.SubheadingFont
	label.TextSize = 13
	label.TextColor3 = fillColor
	label.Text = caption
	label.Parent = back

	back.Parent = overlay
	return fill
end

local bleedFill = makeBar(0.58, D.BleedoutBarColor, "TIME LEFT")
local reviveFill = makeBar(0.66, D.ReviveBarColor, "REVIVE")

RunService.RenderStepped:Connect(function()
	local downed = player:GetAttribute(Attributes.Downed) == true
	overlay.Visible = downed
	if not downed then
		return
	end
	local deadline = player:GetAttribute(Attributes.DownedUntil)
	local timeFrac = 1
	if deadline then
		timeFrac = math.clamp((deadline - Workspace:GetServerTimeNow()) / math.max(D.BleedoutSeconds, 1), 0, 1)
	end
	bleedFill.Size = UDim2.fromScale(timeFrac, 1)
	reviveFill.Size = UDim2.fromScale(math.clamp(player:GetAttribute(Attributes.ReviveProgress) or 0, 0, 1), 1)
end)

-- Teammate revive beacons ------------------------------------------------------------
-- One BillboardGui per OTHER downed player, adornee'd to their head, with a revive bar.
local beacons = {} -- [otherPlayer] = BillboardGui

local function removeBeacon(other)
	local b = beacons[other]
	if b then
		b:Destroy()
		beacons[other] = nil
	end
end

local function makeBeacon(other)
	local character = other.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "ReviveBeacon"
	bb.Adornee = head
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(D.BeaconWidth, D.BeaconHeightPx)
	bb.StudsOffsetWorldSpace = Vector3.new(0, D.BeaconHeight, 0)
	bb.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundColor3 = Config.UI.PanelColor
	label.BackgroundTransparency = Config.UI.PanelTransparency
	label.Font = Config.UI.SubheadingFont
	label.TextSize = 18
	label.TextColor3 = D.BeaconColor
	label.TextStrokeTransparency = Config.UI.TextStrokeTransparency
	label.Text = D.BeaconText
	label.Parent = bb

	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
	labelCorner.Parent = label

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Config.UI.StrokeColor
	labelStroke.Transparency = Config.UI.StrokeTransparency
	labelStroke.Thickness = Config.UI.StrokeThickness
	labelStroke.Parent = label

	local labelGrad = Instance.new("UIGradient")
	labelGrad.Color = ColorSequence.new(
		Color3.new(1, 1, 1),
		Color3.new(1, 1, 1):Lerp(Color3.new(0, 0, 0), Config.UI.PanelGradientDarken)
	)
	labelGrad.Rotation = 90
	labelGrad.Parent = label

	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.fromScale(0.5, 1)
	back.Size = UDim2.new(1, -20, 0, 8)
	back.BackgroundColor3 = Color3.fromRGB(20, 18, 20)
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(1, 0)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = D.BeaconColor
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	fill.Parent = back
	back.Parent = bb

	beacons[other] = bb
end

local function refreshBeacon(other)
	if other == player then
		return
	end
	if other:GetAttribute(Attributes.Downed) == true then
		if not beacons[other] then
			makeBeacon(other)
		end
	else
		removeBeacon(other)
	end
end

-- Per-other-player connections, so a departed player's signal handlers (and the closures
-- that retain the Player object) are disconnected on leave instead of leaking every round.
local connections = {} -- [otherPlayer] = { RBXScriptConnection }

local function watch(other)
	if other == player then
		return
	end
	if connections[other] then
		return -- already watching: PlayerAdded + the initial roster sweep can race; don't double-connect (leaks)
	end
	connections[other] = {
		other:GetAttributeChangedSignal(Attributes.Downed):Connect(function()
			refreshBeacon(other)
		end),
		other.CharacterAdded:Connect(function()
			removeBeacon(other) -- stale adornee; re-evaluate against the fresh body
			task.defer(refreshBeacon, other)
		end),
	}
	refreshBeacon(other)
end

-- Disconnect this player's signals AND drop their beacon (called on leave).
local function unwatch(other)
	local conns = connections[other]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
		connections[other] = nil
	end
	removeBeacon(other)
end

Players.PlayerAdded:Connect(watch)
for _, other in Players:GetPlayers() do
	watch(other)
end
Players.PlayerRemoving:Connect(unwatch)

RunService.RenderStepped:Connect(function()
	-- Lazily (re)try a beacon for any downed teammate whose adornee (head/HRP) wasn't
	-- present the instant Downed flipped — the body can stream in a frame or two later, and
	-- makeBeacon no-ops until it resolves, so without this retry they'd get NO beacon all down.
	for other in connections do
		if not beacons[other] and other:GetAttribute(Attributes.Downed) == true then
			makeBeacon(other)
		end
	end
	for other, bb in beacons do
		local fill = bb:FindFirstChild("Fill", true)
		if fill then
			fill.Size = UDim2.fromScale(math.clamp(other:GetAttribute(Attributes.ReviveProgress) or 0, 0, 1), 1)
		end
	end
end)
