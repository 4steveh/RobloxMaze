--!nonstrict
-- SpawnService.server.luau
-- The single owner of the character lifecycle -- first spawn and every respawn
-- alike (there is no separate respawn service). Rather than racing the engine's
-- default spawn with repeated PivotTo writes, this service spawns the character
-- ON a SpawnLocation it has already positioned, so there is nothing to override
-- and the landing is deterministic (no one-frame flash at the origin).
--
-- It takes the character lifecycle: CharacterAutoLoads is off and we call
-- LoadCharacter ourselves. Each player gets a personal hidden SpawnLocation (its
-- RespawnLocation); before each load we move that SpawnLocation to the player's
-- checkpoint (recorded by SafeRoomService) or, if they have none yet, to a
-- PlayerStart marker. On death we wait a Config delay, then respawn the same way.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Attributes = require(ReplicatedStorage.Attributes)

-- We own WHEN characters load, not just WHERE they go: no engine auto-respawn.
Players.CharacterAutoLoads = false

-- One hidden SpawnLocation per player (created on join, destroyed on leave) lives
-- under this folder. Per-player -- not one shared pad -- so concurrent respawns in
-- future co-op never race over a single pad's position.
local spawnsFolder = Instance.new("Folder")
spawnsFolder.Name = "PlayerSpawns"
spawnsFolder.Parent = Workspace

local spawnLocations = {}
local warnedNoMarker = false

-- Where this player should spawn: their checkpoint CFrame if SafeRoomService has
-- recorded one, otherwise the first PlayerStart marker. nil if neither exists.
local function spawnCFrame(player)
	-- Honor the Config toggle: when AtCheckpoint is off, ignore any recorded
	-- checkpoint and always fall through to a PlayerStart marker.
	if Config.Respawn.AtCheckpoint then
		local checkpoint = player:GetAttribute(Attributes.Checkpoint)
		if typeof(checkpoint) == "CFrame" then
			return checkpoint
		end
	end
	for _, marker in Discovery.getAll(Tags.PlayerStart) do
		if marker:IsA("BasePart") then
			return marker.CFrame
		end
	end
	return nil
end

-- A hidden, non-colliding, forcefield-free SpawnLocation. We move its CFrame and
-- spawn the character on it; the engine has nothing of its own to override.
local function createSpawnLocation()
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.CastShadow = false
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0 -- no spawn forcefield wrapping the player on respawn
	spawn.Parent = spawnsFolder
	return spawn
end

-- Position this player's SpawnLocation at the resolved target, then (re)load the
-- character on it. The character spawns standing on the pad's top, so
-- SpawnUpOffset lifts the PAD above the marker (not a character CFrame) to clear
-- the floor. With no target resolved we still load -- never leave a player
-- characterless -- and warn once.
local function respawn(player)
	local spawn = spawnLocations[player]
	if not spawn then
		return -- player has left; nothing to spawn onto
	end

	local target = spawnCFrame(player)
	if target then
		spawn.CFrame = CFrame.new(target.Position + Vector3.new(0, Config.Respawn.SpawnUpOffset, 0))
	elseif not warnedNoMarker then
		warnedNoMarker = true
		warn("[SpawnService] No Checkpoint or PlayerStart marker found; spawning at the pad's current position.")
	end

	player.RespawnLocation = spawn -- re-assert in case anything cleared it
	player:LoadCharacter()
end

-- Wire each new body's death -> delayed respawn. Placement is the SpawnLocation's
-- job now; this handler only owns the death loop (also the window the jumpscare
-- will later fill).
local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		task.wait(Config.Respawn.RespawnDelay)
		respawn(player)
	end)
end

local function onPlayerAdded(player)
	if spawnLocations[player] then
		return -- already set up (guards the connect + GetPlayers double-process race)
	end

	-- Create the pad BEFORE the first load so RespawnLocation is valid immediately.
	local spawn = createSpawnLocation()
	spawnLocations[player] = spawn
	player.RespawnLocation = spawn

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	respawn(player) -- first spawn
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	local spawn = spawnLocations[player]
	if spawn then
		spawn:Destroy()
		spawnLocations[player] = nil
	end
end)
