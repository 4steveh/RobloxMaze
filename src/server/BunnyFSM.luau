--!strict
-- BunnyFSM.luau
-- Pure decision module for the bunny (one FSM per monster type, per CLAUDE.md).
-- `tick(state, sensed, cfg)` reads sensed inputs, the current state, and the bunny's
-- resolved Config slice (`cfg` = Config.Monster.Shared U Config.Monster.Species.Bunny,
-- injected so multiple species can coexist without sharing one config namespace),
-- MUTATES the state, and returns a movement intent + whether a catch happened. It
-- performs NO Instance work -- MonsterService owns all world mutation -- so this module
-- is unit-testable in isolation. States are Enums.MonsterState.{Patrol, Chase, Search}.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Enums)
local MonsterTypes = require(ReplicatedStorage.MonsterTypes)

export type PlayerSense = MonsterTypes.PlayerSense
export type Sensed = MonsterTypes.Sensed
export type TickResult = MonsterTypes.TickResult

-- The fields of the resolved Config slice this FSM reads (a subset of Shared U Species).
export type Config = {
	PatrolSpeed: number,
	ChaseSpeed: number,
	CatchRadius: number,
	LoseSightSeconds: number,
	SearchDuration: number,
	SearchWanderRadius: number,
	WaypointReachedDistance: number,
	PatrolMemory: number,
	PatrolNodeChoices: number,
}

-- The bunny's full FSM state -- a superset of MonsterTypes.FSMState (`name`,
-- `targetUserId`), which is all MonsterService reads off it.
export type FSMState = {
	name: string,
	patrolTarget: Vector3?,
	recentNodes: { Vector3 },
	targetUserId: number?,
	lastSeen: Vector3?,
	timeSinceSeen: number,
	searchElapsed: number,
	searchTarget: Vector3?,
}

local BunnyFSM = {}

-- Flat XZ distance (the rig and players share a floor; ignore Y).
local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Nearest patrol node to `from`, excluding any within WaypointReachedDistance of
-- `exclude`. Returns nil if none.
local function nearestNode(nodes: { Vector3 }, from: Vector3, exclude: Vector3?, cfg: Config): Vector3?
	local best, bestDist = nil, math.huge
	for _, node in nodes do
		if exclude and flatDistance(node, exclude) < cfg.WaypointReachedDistance then
			continue
		end
		local d = flatDistance(node, from)
		if d < bestDist then
			best, bestDist = node, d
		end
	end
	return best
end

-- Pick the next patrol node: gather every node NOT recently visited, then choose RANDOMLY
-- among the `PatrolNodeChoices` nearest of them -- so the bunny tours unpredictably instead of
-- always tracing the identical single-nearest route (the "it patrols the exact same spots" fix).
-- Falls back to the nearest non-most-recent node when every node is recent (few-node layouts).
local function nextPatrolNode(nodes: { Vector3 }, from: Vector3, recent: { Vector3 }, cfg: Config): Vector3?
	local candidates = {}
	for _, node in nodes do
		local isRecent = false
		for _, r in recent do
			if flatDistance(node, r) < cfg.WaypointReachedDistance then
				isRecent = true
				break
			end
		end
		if not isRecent then
			table.insert(candidates, node)
		end
	end
	if #candidates == 0 then
		return nearestNode(nodes, from, recent[#recent], cfg)
	end
	table.sort(candidates, function(a, b)
		return flatDistance(a, from) < flatDistance(b, from)
	end)
	local pool = math.min(#candidates, math.max(1, cfg.PatrolNodeChoices))
	return candidates[math.random(pool)]
end

-- Nearest player flagged visible this tick, or nil.
local function nearestVisible(sensed: Sensed): PlayerSense?
	local best, bestDist = nil, math.huge
	for _, ps in sensed.players do
		if ps.visible then
			local d = flatDistance(ps.position, sensed.rigPosition)
			if d < bestDist then
				best, bestDist = ps, d
			end
		end
	end
	return best
end

-- Nearest eligible player within CatchRadius of the rig, or nil. Catch is pure
-- proximity (it is on top of you), independent of the vision cone.
local function caughtPlayer(sensed: Sensed, cfg: Config): Player?
	local best, bestDist = nil, math.huge
	for _, ps in sensed.players do
		local d = flatDistance(ps.position, sensed.rigPosition)
		if d <= cfg.CatchRadius and d < bestDist then
			best, bestDist = ps.player, d
		end
	end
	return best
end

-- Is the player we are chasing still in the sensed set? Absence means it left the
-- eligible set entirely (entered a SafeRoom, died, won, or left) -- not merely
-- broke line of sight behind a wall (which keeps it sensed with visible = false).
local function targetInSensed(state: FSMState, sensed: Sensed): boolean
	if state.targetUserId == nil then
		return false
	end
	for _, ps in sensed.players do
		if ps.player.UserId == state.targetUserId then
			return true
		end
	end
	return false
end

function BunnyFSM.newState(): FSMState
	return {
		name = Enums.MonsterState.Patrol,
		patrolTarget = nil,
		recentNodes = {},
		targetUserId = nil,
		lastSeen = nil,
		timeSinceSeen = 0,
		searchElapsed = 0,
		searchTarget = nil,
	}
end

-- Enter Chase aimed at a freshly-seen player. Shared by Patrol and Search.
local function beginChase(state: FSMState, seen: PlayerSense, cfg: Config): TickResult
	state.name = Enums.MonsterState.Chase
	state.targetUserId = seen.player.UserId
	state.lastSeen = seen.position
	state.timeSinceSeen = 0
	return { moveTarget = seen.position, speed = cfg.ChaseSpeed, caught = nil }
end

local function tickPatrol(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	local seen = nearestVisible(sensed)
	if seen then
		return beginChase(state, seen, cfg)
	end
	local reached = state.patrolTarget ~= nil
		and flatDistance(sensed.rigPosition, state.patrolTarget) < cfg.WaypointReachedDistance
	if state.patrolTarget == nil or reached then
		if reached and state.patrolTarget then
			table.insert(state.recentNodes, state.patrolTarget)
			while #state.recentNodes > cfg.PatrolMemory do
				table.remove(state.recentNodes, 1)
			end
		end
		state.patrolTarget = nextPatrolNode(sensed.patrolNodes, sensed.rigPosition, state.recentNodes, cfg)
	end
	return { moveTarget = state.patrolTarget, speed = cfg.PatrolSpeed, caught = nil }
end

local function enterSearch(state: FSMState, cfg: Config): TickResult
	state.name = Enums.MonsterState.Search
	state.searchElapsed = 0
	state.searchTarget = state.lastSeen
	return { moveTarget = state.searchTarget, speed = cfg.PatrolSpeed, caught = nil }
end

local function tickChase(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	-- A catch ends everything this tick.
	local caught = caughtPlayer(sensed, cfg)
	if caught then
		return { moveTarget = sensed.rigPosition, speed = cfg.ChaseSpeed, caught = caught }
	end

	-- Re-acquire / maintain the freshest visible target.
	local seen = nearestVisible(sensed)
	if seen then
		state.targetUserId = seen.player.UserId
		state.lastSeen = seen.position
		state.timeSinceSeen = 0
		return { moveTarget = seen.position, speed = cfg.ChaseSpeed, caught = nil }
	end

	-- No one visible. If the chased target left the sensed set, give up immediately;
	-- if it is merely behind a wall (still sensed), burn the grace window.
	if not targetInSensed(state, sensed) then
		return enterSearch(state, cfg)
	end
	state.timeSinceSeen += sensed.dt
	if state.timeSinceSeen >= cfg.LoseSightSeconds then
		return enterSearch(state, cfg)
	end
	return { moveTarget = state.lastSeen, speed = cfg.ChaseSpeed, caught = nil }
end

local function tickSearch(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	-- Re-detection resumes the chase immediately.
	local seen = nearestVisible(sensed)
	if seen then
		return beginChase(state, seen, cfg)
	end

	state.searchElapsed += sensed.dt
	if state.searchElapsed >= cfg.SearchDuration then
		state.name = Enums.MonsterState.Patrol
		state.patrolTarget = nil
		state.targetUserId = nil
		state.lastSeen = nil
		state.searchTarget = nil
		return { moveTarget = nil, speed = cfg.PatrolSpeed, caught = nil }
	end

	-- Investigate: walk to the current search point; on arrival pick a new random
	-- point within SearchWanderRadius of the last-seen position.
	local anchor = state.lastSeen or sensed.rigPosition
	if
		state.searchTarget == nil
		or flatDistance(sensed.rigPosition, state.searchTarget) < cfg.WaypointReachedDistance
	then
		local angle = math.random() * math.pi * 2
		local dist = math.random() * cfg.SearchWanderRadius
		state.searchTarget = anchor + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	end
	return { moveTarget = state.searchTarget, speed = cfg.PatrolSpeed, caught = nil }
end

function BunnyFSM.tick(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	if state.name == Enums.MonsterState.Chase then
		return tickChase(state, sensed, cfg)
	elseif state.name == Enums.MonsterState.Search then
		return tickSearch(state, sensed, cfg)
	end
	return tickPatrol(state, sensed, cfg)
end

return BunnyFSM
