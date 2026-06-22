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
dish.ClipsDescendants = true -- keep the sweep arm + blips inside the circular dish
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

-- The rotating sonar sweep arm (pivots at the dish centre; shown only while the sonar is active).
local sweepArm = Instance.new("Frame")
sweepArm.Name = "Sweep"
sweepArm.AnchorPoint = Vector2.new(0.5, 1) -- pivot at the bottom edge = the dish centre
sweepArm.Position = UDim2.fromScale(0.5, 0.5)
sweepArm.Size = UDim2.fromOffset(2, R.Size / 2 - 3)
sweepArm.BorderSizePixel = 0
sweepArm.BackgroundColor3 = R.SweepColor
sweepArm.BackgroundTransparency = R.SweepArmTransparency
sweepArm.ZIndex = 2
sweepArm.Parent = dish

-- Label sits ABOVE the dish; the dish clips its own descendants, so parent the label to the gui.
local label = Instance.new("TextLabel")
label.Name = "Label"
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, -R.Margin, 0, R.Margin)
label.Size = UDim2.fromOffset(R.Size, 14)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.TextSize = 12
label.TextColor3 = R.RingColor
label.Text = R.Label
label.Parent = gui

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
	b.BorderSizePixel = 0
	b.ZIndex = 3
	b.Visible = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	b.Parent = dish
	return b
end

-- [rig] = { frame, pingPos: Vector3?, pingClock: number } -- a blip holds the LAST-PINGED world
-- snapshot, not the live position, so a fast hunter's mark lags where it actually is (the dread).
local blips = {}
local maxOffset = R.Size / 2 - R.BlipSize / 2 - 3 -- keep blips inside the dish

local TWO_PI = math.pi * 2
local sweepAngle = 0
local prevAngle = 0
local active = true -- sonar phase: true = sweeping (drains charge), false = dark (recharging)
local charge = 1 -- 0..1

-- Was bearing `b` (0..2π) crossed as the sweep advanced prev -> cur (cur may have wrapped past 0)?
local function crossed(b: number, prev: number, cur: number): boolean
	if cur >= prev then
		return b > prev and b <= cur
	end
	return b > prev or b <= cur -- wrapped
end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)
	local camera = Workspace.CurrentCamera

	-- Charge cycle (the "not always available" fix): drain while sweeping, refill while dark.
	if active then
		charge = math.max(0, charge - dt / R.ActiveSeconds)
		if charge <= 0 then
			active = false
		end
	else
		charge = math.min(1, charge + dt / R.RechargeSeconds)
		if charge >= R.ChargeReadyFraction then
			active = true
		end
	end

	-- Phase UI: the ring + label show whether the sonar is live or recharging.
	if active then
		dishStroke.Color = R.SweepColor
		dishStroke.Transparency = 0.2 + (1 - charge) * 0.5 -- ring dims as the charge drains
		label.Text = R.Label
		label.TextColor3 = R.RingColor
	else
		dishStroke.Color = R.DepletedColor
		dishStroke.Transparency = 0.2
		label.Text = R.RechargingLabel
		label.TextColor3 = R.DepletedColor
	end
	sweepArm.Visible = active

	if not (hrp and monsters and camera and active) then
		for _, st in blips do
			st.frame.Visible = false
		end
		return -- dark phase (or no character/camera): no live tracking; sweep angle freezes
	end

	-- Advance the sweep arm.
	prevAngle = sweepAngle
	sweepAngle = (sweepAngle + TWO_PI * dt / R.SweepSeconds) % TWO_PI
	sweepArm.Rotation = math.deg(sweepAngle)

	-- Camera-relative ground axes (forward = up on the radar). Skip if looking near-vertical.
	local camCF = camera.CFrame
	local fwd = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
	if fwd.Magnitude < 0.05 or right.Magnitude < 0.05 then
		return
	end
	fwd, right = fwd.Unit, right.Unit

	local now = os.clock()
	local seen = {}
	for _, rig in monsters:GetChildren() do
		local rRoot = rig:FindFirstChild("HumanoidRootPart")
		if rRoot then
			seen[rig] = true
			local st = blips[rig]
			if not st then
				st = { frame = makeBlip(), pingPos = nil, pingClock = 0 }
				blips[rig] = st
			end

			-- Bearing of the monster on the radar (clockwise from "up" = camera forward).
			local rel = Vector3.new(rRoot.Position.X - hrp.Position.X, 0, rRoot.Position.Z - hrp.Position.Z)
			local dist = rel.Magnitude
			local ux, uy = 0, 1
			if dist > 0.01 then
				ux = right:Dot(rel) / dist
				uy = fwd:Dot(rel) / dist
			end
			local bearing = math.atan2(ux, uy) % TWO_PI

			-- PING: refresh the snapshot ONLY as the sweep line crosses the monster's bearing, and
			-- only if it's in range. Between pings the blip stays put and fades (a stale contact).
			if dist <= R.Range and crossed(bearing, prevAngle, sweepAngle) then
				st.pingPos = rRoot.Position
				st.pingClock = now
			end

			local frame = st.frame
			if st.pingPos then
				local hunting = HUNTING[rig:GetAttribute(Attributes.MonsterState)] == true
				local fade = if hunting then R.HuntFadeSeconds else R.IdleFadeSeconds
				local alpha = 1 - (now - st.pingClock) / fade -- 1 at the ping -> 0 when decayed
				if alpha <= 0 then
					frame.Visible = false
				else
					-- Reproject the LAST-PINGED world position against the current camera (so the
					-- stale mark stays correctly oriented as you turn).
					local prel = Vector3.new(st.pingPos.X - hrp.Position.X, 0, st.pingPos.Z - hrp.Position.Z)
					local pdist = prel.Magnitude
					local frac = math.clamp(pdist / R.Range, 0, 1)
					local px, py = 0, 0
					if pdist > 0.01 then
						px = right:Dot(prel) / pdist
						py = fwd:Dot(prel) / pdist
					end
					frame.Position = UDim2.new(0.5, px * frac * maxOffset, 0.5, -py * frac * maxOffset)
					frame.BackgroundColor3 = speciesColor(rig)
					frame.BackgroundTransparency = R.MinPingTransparency + (1 - alpha) * (1 - R.MinPingTransparency)
					local sz = if hunting then R.BlipSize else R.BlipSize * R.IdleSizeScale
					frame.Size = UDim2.fromOffset(sz, sz)
					frame.Visible = true
				end
			else
				frame.Visible = false
			end
		end
	end

	for rig, st in blips do
		if not seen[rig] then
			st.frame:Destroy()
			blips[rig] = nil
		end
	end
end)
