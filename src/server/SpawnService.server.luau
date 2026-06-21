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
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local ServerSignals = require(script.Parent.ServerSignals)

-- We own WHEN characters load, not just WHERE they go: no engine auto-respawn.
Players.CharacterAutoLoads = false

-- One hidden SpawnLocation per player (created on join, destroyed on leave) lives
-- under this folder. Per-player -- not one shared pad -- so concurrent respawns in
-- future co-op never race over a single pad's position.
local spawnsFolder = Instance.new("Folder")
spawnsFolder.Name = WorldFolders.PlayerSpawns
spawnsFolder.Parent = Workspace

local spawnLocations = {}
local graceToken = {} -- [player] = number, bumped each spawn so a stale grace timer can't clear a fresh grace
local warnedNoMarker = false

-- Where this player should spawn: their checkpoint CFrame if SafeRoomService has
-- recorded one, otherwise the first PlayerStart marker. nil if neither exists.
local function spawnCFrame(player, forceStart)
	-- Honor the Config toggle: when AtCheckpoint is off, ignore any recorded
	-- checkpoint and always fall through to a PlayerStart marker. `forceStart` (a new
	-- round) likewise ignores the checkpoint so everyone restarts at the PlayerStart.
	if Config.Respawn.AtCheckpoint and not forceStart then
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
local function respawn(player, forceStart)
	local spawn = spawnLocations[player]
	if not spawn then
		return -- player has left; nothing to spawn onto
	end

	local target = spawnCFrame(player, forceStart)
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
	-- Respawn invulnerability (anti-spawn-camp): for InvulnSeconds the monster ignores
	-- this player (MonsterService skips RespawnGrace players), so a freshly loaded
	-- character can never be instantly re-caught at its spawn. The visible ForceField
	-- is only the legibility cue -- the real guard is the sensing skip (a catch sets
	-- Humanoid.Health = 0 directly, which a ForceField would not block anyway).
	-- Token this spawn so a fast death->respawn (within InvulnSeconds) can't have the
	-- PREVIOUS character's grace timer fire and strip the fresh character's grace early.
	graceToken[player] = (graceToken[player] or 0) + 1
	local mine = graceToken[player]
	player:SetAttribute(Attributes.RespawnGrace, true)
	local shield = Instance.new("ForceField")
	shield.Visible = true
	shield.Parent = character
	task.delay(Config.Respawn.InvulnSeconds, function()
		if graceToken[player] ~= mine then
			return -- a newer spawn owns grace now; leave it intact
		end
		player:SetAttribute(Attributes.RespawnGrace, false)
		if shield.Parent then
			shield:Destroy()
		end
	end)

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
	graceToken[player] = nil
end)

-- New round: respawn everyone at the PlayerStart for a fresh run (task.spawn so a
-- LoadCharacter yield never blocks the signal fire / other listeners).
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	for _, player in Players:GetPlayers() do
		task.spawn(respawn, player, true)
	end
end)
