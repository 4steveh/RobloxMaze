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
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)

Remotes.init()
local keyCollectedRemote = Remotes.get(Remotes.Names.KeyCollected)

local keyCounts = {} -- [player] = number (survives respawn; not tied to the character)
local liveKeys = {} -- array of currently-collectible key parts
local rng = Random.new()

local keysFolder = Instance.new("Folder")
keysFolder.Name = "Keys"
keysFolder.Parent = Workspace

local function makeKey(position)
	local key = Instance.new("Part")
	key.Name = "Key"
	key.Anchored = true
	key.CanCollide = false
	key.CastShadow = false
	key.Material = Enum.Material.Neon
	key.Size = Config.KeyModel.Size
	key.Color = Config.KeyModel.Color
	key.Position = position + Vector3.new(0, Config.KeyModel.HoverHeight, 0)

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

-- Round start (once): place keys at a random subset of the KeySpot markers, biased
-- away from any MonsterSpawn so a required key never spawns inside the bunny's
-- detection bubble (see Config.Monster.NoKeySpawnRadius).
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
				(Vector3.new(pos.X, 0, pos.Z) - Vector3.new(sp.X, 0, sp.Z)).Magnitude < Config.Monster.NoKeySpawnRadius
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

while true do
	task.wait(Config.Spatial.PollInterval)
	for _, player in Players:GetPlayers() do
		local rootPart = PlayerUtil.livingRootPart(player)
		if rootPart then
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
	end
end
