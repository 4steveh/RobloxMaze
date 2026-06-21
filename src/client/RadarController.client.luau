--!nonstrict
-- RadarController.client.luau
-- A compact monster RADAR (top-right): YOU at the center, a blip per monster placed by its
-- camera-relative BEARING and clamped DISTANCE (forward = up). Blips are tinted by SPECIES
-- (red bunny / yellow monkey, mirroring their eye-glow tells) and made prominent by THREAT:
-- a hunting monster (Chase/Investigate/Alert) is bright + full size, a patrolling one is faint
-- + small (still shown so you can avoid an ambush, but clearly less urgent). Reads each rig's
-- REPLICATED HumanoidRootPart + State + Species -- exploit-safe, no server trust, zero
-- bandwidth. Render-only -- the FlickerController-class client cosmetic CLAUDE.md permits.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local WorldFolders = require(ReplicatedStorage.WorldFolders)

local R = Config.Radar
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Radar"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false -- sit below the Roblox topbar
gui.Parent = playerGui

-- The radar dish (top-right).
local dish = Instance.new("Frame")
dish.Name = "Dish"
dish.AnchorPoint = Vector2.new(1, 0)
dish.Position = UDim2.new(1, -R.Margin, 0, R.Margin)
dish.Size = UDim2.fromOffset(R.Size, R.Size)
dish.BackgroundColor3 = R.BackgroundColor
dish.BackgroundTransparency = R.BackgroundTransparency
dish.Parent = gui
local dishCorner = Instance.new("UICorner")
dishCorner.CornerRadius = UDim.new(0.5, 0) -- circular
dishCorner.Parent = dish
local dishStroke = Instance.new("UIStroke")
dishStroke.Color = R.RingColor
dishStroke.Thickness = 2
dishStroke.Transparency = 0.2
dishStroke.Parent = dish

-- Center "you" dot.
local center = Instance.new("Frame")
center.Name = "You"
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(8, 8)
center.BackgroundColor3 = R.PlayerColor
local centerCorner = Instance.new("UICorner")
centerCorner.CornerRadius = UDim.new(0.5, 0)
centerCorner.Parent = center
center.Parent = dish

local label = Instance.new("TextLabel")
label.Name = "Label"
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.new(0.5, 0, 0, -2)
label.Size = UDim2.fromOffset(R.Size, 14)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.TextSize = 12
label.TextColor3 = R.RingColor
label.Text = R.Label
label.Parent = dish

local HUNTING = {
	[Enums.MonsterState.Chase] = true,
	[Enums.MonsterState.Investigate] = true,
	[Enums.MonsterState.Alert] = true,
}

local function speciesColor(rig)
	local sp = rig:GetAttribute(Attributes.MonsterSpecies)
	if sp == Enums.MonsterType.Bunny then
		return R.BunnyBlipColor
	elseif sp == Enums.MonsterType.Monkey then
		return R.MonkeyBlipColor
	end
	return R.UnknownBlipColor
end

local function makeBlip()
	local b = Instance.new("Frame")
	b.Name = "Blip"
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(R.BlipSize, R.BlipSize)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	b.Parent = dish
	return b
end

local blips = {} -- [rig] = Frame (pooled)
local maxOffset = R.Size / 2 - R.BlipSize / 2 - 3 -- keep blips inside the dish

RunService.RenderStepped:Connect(function()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)
	local camera = Workspace.CurrentCamera
	if not (hrp and monsters and camera) then
		for _, b in blips do
			b.Visible = false
		end
		return
	end

	-- Camera-relative ground axes (forward = up on the radar). Skip if looking near-vertical.
	local camCF = camera.CFrame
	local fwd = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
	if fwd.Magnitude < 0.05 or right.Magnitude < 0.05 then
		return
	end
	fwd, right = fwd.Unit, right.Unit

	local seen = {}
	for _, rig in monsters:GetChildren() do
		local rRoot = rig:FindFirstChild("HumanoidRootPart")
		if rRoot then
			seen[rig] = true
			local b = blips[rig]
			if not b then
				b = makeBlip()
				blips[rig] = b
			end
			local relFlat = Vector3.new(rRoot.Position.X - hrp.Position.X, 0, rRoot.Position.Z - hrp.Position.Z)
			local dist = relFlat.Magnitude
			local frac = math.clamp(dist / R.Range, 0, 1)
			local ux, uy = 0, 0
			if dist > 0.01 then
				ux = right:Dot(relFlat) / dist
				uy = fwd:Dot(relFlat) / dist
			end
			b.Position = UDim2.new(0.5, ux * frac * maxOffset, 0.5, -uy * frac * maxOffset)
			local hunting = HUNTING[rig:GetAttribute(Attributes.MonsterState)] == true
			b.BackgroundColor3 = speciesColor(rig)
			b.BackgroundTransparency = if hunting then R.HuntingTransparency else R.IdleTransparency
			local sz = if hunting then R.BlipSize else R.BlipSize * R.IdleSizeScale
			b.Size = UDim2.fromOffset(sz, sz)
			b.Visible = true
		end
	end

	for rig, b in blips do
		if not seen[rig] then
			b:Destroy()
			blips[rig] = nil
		end
	end
end)
