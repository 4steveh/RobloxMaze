--!nonstrict
-- CompassController.client.luau
-- The wayfinding layer (the fix for "no clear direction"): every live key in the
-- world (tagged ActiveKey by KeyService) gets a glowing beacon that reads through
-- walls, and an edge-of-screen arrow points at the nearest one. Renders only -- the
-- client never decides pickups; it just shows where the keys are.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Attributes = require(ReplicatedStorage.Attributes)

local C = Config.Compass
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Beacons (one BillboardGui per live key, parented to the key so it dies with it) ---
local beacons = {} -- [keyPart] = BillboardGui

local function addBeacon(keyPart)
	if not keyPart:IsA("BasePart") or beacons[keyPart] then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "KeyBeacon"
	bb.AlwaysOnTop = true -- reads through walls -- the whole point of a wayfinder
	bb.Size = UDim2.fromOffset(C.BeaconSize, C.BeaconSize + 16)
	bb.StudsOffsetWorldSpace = Vector3.new(0, C.BeaconHeight, 0)
	bb.LightInfluence = 0

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 1)
	dot.Position = UDim2.fromScale(0.5, 1)
	dot.Size = UDim2.fromOffset(C.BeaconSize, C.BeaconSize)
	dot.BackgroundColor3 = C.BeaconColor
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(15, 20, 12)
	stroke.Thickness = 2
	stroke.Parent = dot
	dot.Parent = bb

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0)
	label.Size = UDim2.fromOffset(C.BeaconSize + 24, 14)
	label.BackgroundTransparency = 1
	label.Font = Config.UI.SubheadingFont
	label.Text = C.LabelText
	label.TextScaled = true
	label.TextColor3 = C.BeaconColor
	label.TextStrokeTransparency = Config.UI.TextStrokeTransparency
	label.Parent = bb

	bb.Parent = keyPart
	beacons[keyPart] = bb
end

local function removeBeacon(keyPart)
	local bb = beacons[keyPart]
	if bb then
		bb:Destroy()
		beacons[keyPart] = nil
	end
end

Discovery.observe(Tags.ActiveKey, addBeacon, removeBeacon)

-- EXIT beacon (the win-phase wayfinder): a through-wall "EXIT" marker over each ExitDoor, shown
-- ONLY once the team holds every key -- so finding the exit is clear at the moment you need it,
-- without marking it during the key-hunt (exploration stays tense). Mirrors the key-beacon language.
local exitBeacons = {} -- [exitPart] = BillboardGui
local function addExitBeacon(part)
	if not part:IsA("BasePart") or exitBeacons[part] then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "ExitBeacon"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(C.BeaconSize + 10, C.BeaconSize + 28)
	bb.StudsOffsetWorldSpace = Vector3.new(0, C.BeaconHeight + 2, 0)
	bb.LightInfluence = 0
	bb.Enabled = false -- until all keys are in

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 1)
	dot.Position = UDim2.fromScale(0.5, 1)
	dot.Size = UDim2.fromOffset(C.BeaconSize + 10, C.BeaconSize + 10)
	dot.BackgroundColor3 = Config.Exit.UnlockedColor
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(12, 25, 14)
	stroke.Thickness = 2
	stroke.Parent = dot
	dot.Parent = bb

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0)
	label.Size = UDim2.fromOffset(C.BeaconSize + 40, 16)
	label.BackgroundTransparency = 1
	label.Font = Config.UI.SubheadingFont
	label.Text = "EXIT"
	label.TextScaled = true
	label.TextColor3 = Config.Exit.UnlockedColor
	label.TextStrokeTransparency = Config.UI.TextStrokeTransparency
	label.Parent = bb

	bb.Parent = part
	exitBeacons[part] = bb
end
local function removeExitBeacon(part)
	local bb = exitBeacons[part]
	if bb then
		bb:Destroy()
		exitBeacons[part] = nil
	end
end
Discovery.observe(Tags.ExitDoor, addExitBeacon, removeExitBeacon)

-- Edge arrow to the nearest active key --------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "KeyCompass"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local arrow = Instance.new("TextLabel")
arrow.Name = "KeyArrow"
arrow.AnchorPoint = Vector2.new(0.5, 1)
arrow.Position = UDim2.new(0.5, 0, 1, -C.ArrowBottomOffset)
arrow.Size = UDim2.fromOffset(C.ArrowSize, C.ArrowSize)
arrow.BackgroundTransparency = 1
arrow.Font = Config.UI.SubheadingFont
arrow.Text = "\u{25B2}"
arrow.TextScaled = true
arrow.TextColor3 = C.ArrowColor
arrow.TextStrokeTransparency = Config.UI.TextStrokeTransparency
arrow.Visible = false
arrow.Parent = gui

local function nearestKey(fromPos)
	local best, bestDist = nil, math.huge
	for keyPart in beacons do
		if keyPart.Parent then
			local d = (keyPart.Position - fromPos).Magnitude
			if d < bestDist then
				best, bestDist = keyPart, d
			end
		end
	end
	return best
end

RunService.RenderStepped:Connect(function()
	-- Light the EXIT beacons once the team holds every key (KeyCount is server-set + replicated).
	local hasAllKeys = (player:GetAttribute(Attributes.KeyCount) or 0) >= Config.Keys.RequiredToWin
	for _, bb in exitBeacons do
		bb.Enabled = hasAllKeys
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not (rootPart and camera) then
		arrow.Visible = false
		return
	end

	-- Distance-fade each key beacon (search-as-exposure): a near key reads full, a far one shrinks to
	-- BeaconMinSize + dims, so the beacon gives a ROUGH direction in the random maze rather than a
	-- precise hand-holding line you can safely run down. (Wires the previously-dead Config fields.)
	for keyPart, bb in beacons do
		if keyPart.Parent then
			local frac = math.clamp((keyPart.Position - rootPart.Position).Magnitude / C.MaxBeaconDistance, 0, 1)
			local sz = C.BeaconSize + (C.BeaconMinSize - C.BeaconSize) * frac
			local dot = bb:FindFirstChild("Dot")
			if dot then
				dot.Size = UDim2.fromOffset(sz, sz)
				dot.BackgroundTransparency = frac * 0.5 -- fade toward, never fully gone (still a hint)
			end
		end
	end

	local key = nearestKey(rootPart.Position)
	arrow.Visible = key ~= nil
	if key then
		local toKey = key.Position - rootPart.Position
		local camCF = camera.CFrame
		local f = camCF.LookVector.X * toKey.X + camCF.LookVector.Z * toKey.Z
		local r = camCF.RightVector.X * toKey.X + camCF.RightVector.Z * toKey.Z
		arrow.Rotation = math.deg(math.atan2(r, f))
	end
end)
