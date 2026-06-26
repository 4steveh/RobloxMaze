--!nonstrict
-- KeyService.server.luau
-- Spawns the round's collectible keys at a random subset of KeySpot markers
-- (the per-round variety mechanic), and detects pickups server-authoritatively by
-- spatial check -- never Touched (see CLAUDE.md).
--
-- Keys are a SHARED TEAM objective (co-op, like Flee the Facility's computers): any
-- player picking up a key advances ONE team count, mirrored to every player's KeyCount
-- attribute, so the whole lobby can reach RequiredToWin and escape. (Per-player counts
-- with a fixed shared key pool locked everyone but one player out in multiplayer.)
-- Splitting up to gather keys faster is the co-op play; the team count survives any one
-- player's death/respawn and is exposed via KeyCount for ExitService, the HUD, and the
-- aggression ramp.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local ServerSignals = require(script.Parent.ServerSignals)

Remotes.init()
local keyCollectedRemote = Remotes.get(Remotes.Names.KeyCollected)

local teamKeyCount = 0 -- ONE shared count for the whole lobby (survives any player's respawn)
local liveKeys = {} -- array of currently-collectible key parts
local rng = Random.new()

local keysFolder = Instance.new("Folder")
keysFolder.Name = WorldFolders.Keys
keysFolder.Parent = Workspace

local function makeKey(position)
	-- The collectible is the ornate skeleton-key mesh (ServerStorage.Assets.KeyModel) if
	-- present, else a glowing placeholder block. An eerie green PointLight + the slow spin
	-- (below) make it read down a dark corridor.
	local assets = ServerStorage:FindFirstChild("Assets")
	local meshSrc = assets and assets:FindFirstChild("KeyModel")
	local key
	if meshSrc and meshSrc:IsA("BasePart") then
		key = meshSrc:Clone()
		key:ClearAllChildren()
	else
		key = Instance.new("Part")
		key.Material = Enum.Material.Neon
		key.Size = Config.KeyModel.Size
		key.Color = Config.KeyModel.Color
	end
	key.Name = "Key"
	key.Anchored = true
	key.CanCollide = false
	key.CanQuery = false
	key.CastShadow = false
	key.CFrame = CFrame.new(position + Vector3.new(0, Config.KeyModel.HoverHeight, 0))

	local light = Instance.new("PointLight")
	light.Color = Config.KeyModel.LightColor
	light.Brightness = Config.KeyModel.LightBrightness
	light.Range = Config.KeyModel.LightRange
	light.Parent = key

	-- A few slow motes rising off the key so it glints like treasure down a dark corridor.
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = Config.KeyModel.SparkleTexture
	sparkle.Color = ColorSequence.new(Config.KeyModel.SparkleColor)
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, Config.KeyModel.SparkleSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkle.Lifetime = NumberRange.new(Config.KeyModel.SparkleLifetime * 0.7, Config.KeyModel.SparkleLifetime)
	sparkle.Rate = Config.KeyModel.SparkleRate
	sparkle.Speed = NumberRange.new(Config.KeyModel.SparkleSpeed * 0.5, Config.KeyModel.SparkleSpeed)
	sparkle.SpreadAngle = Vector2.new(40, 40)
	sparkle.Acceleration = Vector3.new(0, 0.5, 0)
	sparkle.LightEmission = 0.6 -- the motes glow (they're magic keys, not dust)
	sparkle.Parent = key

	key.Parent = keysFolder
	-- Tag it so the client compass can beacon live keys (tag-based discovery, not a
	-- hardcoded path). Removed implicitly on Destroy when collected.
	CollectionService:AddTag(key, Tags.ActiveKey)
	table.insert(liveKeys, key)
end

-- A slow hypnotic spin so a glowing key catches the eye down a corridor. Anchored +
-- rotation about its own centre, so the pickup's flat position is unchanged.
RunService.Heartbeat:Connect(function(dt)
	local step = CFrame.Angles(0, Config.KeyModel.SpinSpeed * dt, 0)
	for _, key in liveKeys do
		if key.Parent then
			key.CFrame = key.CFrame * step
		end
	end
end)

-- Round start (once): place keys at a random subset of the KeySpot markers, biased
-- away from any MonsterSpawn so a required key never spawns inside the bunny's
-- detection bubble (see Config.Monster.Shared.NoKeySpawnRadius).
local function shuffleInPlace(t)
	for i = #t, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

local function spawnRoundKeys()
	-- Keys avoid two kinds of spot: inside a monster's spawn bubble (so a required key never
	-- sits in the bunny's lap), AND right on top of a PlayerStart (so you can't auto-collect
	-- one the instant you spawn -- you must go FIND them).
	local monsterSpawns, playerStarts = {}, {}
	for _, m in Discovery.getAll(Tags.MonsterSpawn) do
		if m:IsA("BasePart") then
			table.insert(monsterSpawns, m.Position)
		end
	end
	for _, m in Discovery.getAll(Tags.PlayerStart) do
		if m:IsA("BasePart") then
			table.insert(playerStarts, m.Position)
		end
	end
	-- Flat XZ distance (ground-plane), consistent with the monsters' sensing.
	local function nearAny(pos, list, radius)
		for _, p in list do
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < radius then
				return true
			end
		end
		return false
	end
	local function nearAvoid(pos)
		return nearAny(pos, monsterSpawns, Config.Monster.Shared.NoKeySpawnRadius)
			or nearAny(pos, playerStarts, Config.Keys.NoSpawnNearStartRadius)
	end

	-- Partition spots: prefer "far" ones; "near" are a fallback only if there aren't
	-- enough far spots to fill the round (so the round always gets SpawnPerRound keys).
	local far, near = {}, {}
	for _, marker in Discovery.getAll(Tags.KeySpot) do
		if marker:IsA("BasePart") then
			table.insert(if nearAvoid(marker.Position) then near else far, marker)
		end
	end
	shuffleInPlace(far)
	shuffleInPlace(near)

	local ordered = {}
	for _, m in far do
		table.insert(ordered, m)
	end
	for _, m in near do
		table.insert(ordered, m)
	end

	local count = math.min(Config.Keys.SpawnPerRound, #ordered)
	for i = 1, count do
		makeKey(ordered[i].Position)
	end
end

-- Mirror the shared team count onto every player's KeyCount attribute (HUD, ExitService,
-- aggression ramp all read it). Called on every pickup and on a round reset.
local function setTeamCount(count)
	teamKeyCount = count
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Attributes.KeyCount, count)
	end
end

-- A joiner (or rejoiner) syncs to the team's current progress, never to 0 mid-round.
local function onPlayerAdded(player)
	player:SetAttribute(Attributes.KeyCount, teamKeyCount)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

spawnRoundKeys()

-- New round (ServerSignals.RoundReset): clear any remaining keys, zero everyone's count
-- (the attribute change re-syncs the HUD/objective), and re-randomize a fresh key layout.
local function clearKeys()
	for _, key in liveKeys do
		if key.Parent then
			key:Destroy()
		end
	end
	table.clear(liveKeys)
end

ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	clearKeys()
	setTeamCount(0)
	spawnRoundKeys()
end)

-- Per-player pickup scan, factored out so it can be pcall-isolated: a throw on one
-- player (HRP cleared mid-frame, a key destroyed concurrently) must not freeze key
-- collection for the whole server.
local function processPlayerPickups(player)
	local rootPart = PlayerUtil.livingRootPart(player)
	if not rootPart then
		return
	end
	-- Iterate backwards so we can remove collected keys in place.
	for index = #liveKeys, 1, -1 do
		local key = liveKeys[index]
		if not key.Parent then
			table.remove(liveKeys, index) -- already gone
		elseif Spatial.withinRange(rootPart.Position, key.Position, Config.Spatial.KeyPickupRadius) then
			table.remove(liveKeys, index) -- claim it before doing anything else
			key:Destroy()
			-- Advances the shared team count; tell EVERY player (their HUD pip fills, the chime
			-- + "KEY n/3" toast fires) so the lobby sees co-op progress, not just the finder.
			setTeamCount(teamKeyCount + 1)
			for _, p in Players:GetPlayers() do
				keyCollectedRemote:FireClient(p, teamKeyCount)
			end
		end
	end
end

while true do
	task.wait(Config.Spatial.PollInterval)
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(processPlayerPickups, player)
		if not ok then
			warn("[KeyService] pickup tick error for a player (skipped this tick):", err)
		end
	end
end
