--!nonstrict
-- AmbushService.server.luau
-- Server-authoritative micro-scares between monster encounters -- finally wiring the
-- AmbushNode tag (it was DEFINED but DEAD -- nothing read it). On the shared spatial poll
-- (never Touched -- see CLAUDE.md) each living player's HumanoidRootPart is tested against
-- every AmbushNode marker; passing within Config.Ambush.TriggerRadius of a node it hasn't
-- recently sprung (a per-player-per-node cooldown) fires AmbushTriggered to ALL clients
-- with the node's position -> AmbushFXController plays a localized 3D skitter + a brief
-- light cut. The scare decides NOTHING (a pure audiovisual beat). It skips InSafeRoom / Won
-- / Downed players so the sanctuary stays calm and a finished/downed player isn't taunted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)

Remotes.init()
local ambushRemote = Remotes.get(Remotes.Names.AmbushTriggered)
local C = Config.Ambush

-- Inert until enabled (and until AmbushNode markers are placed): no poll, no work.
if not C.Enabled then
	return
end

-- [userId] = { [node] = os.clock() the player last got scared by that node }. The
-- per-player-per-node cooldown stops a player loitering by one node from machine-gunning
-- the scare, while different nodes (and other players) still fire independently.
local lastScare = {}
-- Drop a departed player's cooldown table so it can't grow unbounded over a long-lived
-- server (mirrors MonsterService's lastHuntAlert cleanup).
Players.PlayerRemoving:Connect(function(player)
	lastScare[player.UserId] = nil
end)

-- A scare only fires for a player actually in the maze: never inside a SafeRoom (the
-- sanctuary stays quiet), never after winning, never while downed (no taunting a body).
local function eligible(player: Player): boolean
	return player:GetAttribute(Attributes.InSafeRoom) ~= true
		and player:GetAttribute(Attributes.GameState) ~= Enums.GameState.Won
		and player:GetAttribute(Attributes.Downed) ~= true
end

-- Per-player check, factored out so it can be pcall-isolated: a throw on one player (HRP
-- cleared mid-frame, a node destroyed) must not freeze ambush detection server-wide.
local function processPlayer(player, nodes, now)
	if not eligible(player) then
		return
	end
	local rootPart = PlayerUtil.livingRootPart(player)
	if not rootPart then
		return -- No living HRP this tick (spawning/dead): skip without erroring.
	end
	local position = rootPart.Position

	local seen = lastScare[player.UserId]
	if not seen then
		seen = {}
		lastScare[player.UserId] = seen
	end

	for _, node in nodes do
		if node:IsA("BasePart") and Spatial.withinRange(position, node.Position, C.TriggerRadius) then
			-- Spring once, then hold this node quiet for this player until the cooldown elapses.
			if now - (seen[node] or -math.huge) >= C.Cooldown then
				seen[node] = now
				ambushRemote:FireAllClients(node.Position) -- spatialized client-side, so distant players barely hear it
			end
		end
	end
end

while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	local nodes = Discovery.getAll(Tags.AmbushNode)
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(processPlayer, player, nodes, now)
		if not ok then
			warn("[AmbushService] tick error for a player (skipped this tick):", err)
		end
	end
end
