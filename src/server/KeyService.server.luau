--!nonstrict
-- KeyService.server.luau
-- Spawns the round's collectible keys at a random subset of KeySpot markers
-- (the per-round variety mechanic), and detects pickups server-authoritatively by
-- spatial check -- never Touched (see CLAUDE.md). Each player's key count is kept
-- on the server so it survives death/respawn, and exposed via the KeyCount
-- attribute for other server systems (ExitService) and the HUD.

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

local keyCounts = {} -- [player] = number (survives respawn; not tied to the character)
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
	local spawnPositions = {}
	for _, m in Discovery.getAll(Tags.MonsterSpawn) do
		if m:IsA("BasePart") then
			table.insert(spawnPositions, m.Position)
		end
	end
	local function nearAnySpawn(pos)
		for _, sp in spawnPositions do
			-- Flat XZ distance, consistent with the bunny's ground-plane sensing.
			if
				(Vector3.new(pos.X, 0, pos.Z) - Vector3.new(sp.X, 0, sp.Z)).Magnitude
				< Config.Monster.Shared.NoKeySpawnRadius
			then
				return true
			end
		end
		return false
	end

	-- Partition spots: prefer "far" ones; "near" are a fallback only if there aren't
	-- enough far spots to fill the round (so the round always gets SpawnPerRound keys).
	local far, near = {}, {}
	for _, marker in Discovery.getAll(Tags.KeySpot) do
		if marker:IsA("BasePart") then
			table.insert(if nearAnySpawn(marker.Position) then near else far, marker)
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

local function setCount(player, count)
	keyCounts[player] = count
	player:SetAttribute(Attributes.KeyCount, count)
end

local function onPlayerAdded(player)
	setCount(player, keyCounts[player] or 0)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	keyCounts[player] = nil
end)

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
	for _, player in Players:GetPlayers() do
		setCount(player, 0)
	end
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
			setCount(player, (keyCounts[player] or 0) + 1)
			keyCollectedRemote:FireClient(player, keyCounts[player])
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
