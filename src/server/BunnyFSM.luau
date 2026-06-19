--!strict
-- BunnyFSM.luau
-- Pure decision module for the bunny (one FSM per monster type, per CLAUDE.md).
-- `tick` reads sensed inputs and the current state, MUTATES the state, and returns
-- a movement intent + whether a catch happened. It performs NO Instance work --
-- MonsterService owns all world mutation, so this module is unit-testable in
-- isolation. States are Enums.MonsterState.{Patrol, Chase, Search}.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Enums)
local Config = require(ReplicatedStorage.Config)

export type PlayerSense = { player: Player, position: Vector3, visible: boolean }
export type Sensed = {
	dt: number,
	rigPosition: Vector3,
	patrolNodes: { Vector3 },
	players: { PlayerSense },
}
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
export type TickResult = { moveTarget: Vector3?, speed: number, caught: Player? }

local BunnyFSM = {}

-- Flat XZ distance (the rig and players share a floor; ignore Y).
local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Nearest patrol node to `from`, excluding any within WaypointReachedDistance of
-- `exclude`. Returns nil if none.
local function nearestNode(nodes: { Vector3 }, from: Vector3, exclude: Vector3?): Vector3?
	local best, bestDist = nil, math.huge
	for _, node in nodes do
		if exclude and flatDistance(node, exclude) < Config.Monster.WaypointReachedDistance then
			continue
		end
		local d = flatDistance(node, from)
		if d < bestDist then
			best, bestDist = node, d
		end
	end
	return best
end

-- Nearest node not within reach of any recently-visited node, so the bunny tours
-- the maze. Falls back to the nearest node other than the most-recent if every
-- node is recent (few-node layouts).
local function nextPatrolNode(nodes: { Vector3 }, from: Vector3, recent: { Vector3 }): Vector3?
	local best, bestDist = nil, math.huge
	for _, node in nodes do
		local isRecent = false
		for _, r in recent do
			if flatDistance(node, r) < Config.Monster.WaypointReachedDistance then
				isRecent = true
				break
			end
		end
		if not isRecent then
			local d = flatDistance(node, from)
			if d < bestDist then
				best, bestDist = node, d
			end
		end
	end
	if best == nil then
		best = nearestNode(nodes, from, recent[#recent])
	end
	return best
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
local function caughtPlayer(sensed: Sensed): Player?
	local best, bestDist = nil, math.huge
	for _, ps in sensed.players do
		local d = flatDistance(ps.position, sensed.rigPosition)
		if d <= Config.Monster.CatchRadius and d < bestDist then
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
local function beginChase(state: FSMState, seen: PlayerSense): TickResult
	state.name = Enums.MonsterState.Chase
	state.targetUserId = seen.player.UserId
	state.lastSeen = seen.position
	state.timeSinceSeen = 0
	return { moveTarget = seen.position, speed = Config.Monster.ChaseSpeed, caught = nil }
end

local function tickPatrol(state: FSMState, sensed: Sensed): TickResult
	local seen = nearestVisible(sensed)
	if seen then
		return beginChase(state, seen)
	end
	local reached = state.patrolTarget ~= nil
		and flatDistance(sensed.rigPosition, state.patrolTarget) < Config.Monster.WaypointReachedDistance
	if state.patrolTarget == nil or reached then
		if reached and state.patrolTarget then
			table.insert(state.recentNodes, state.patrolTarget)
			while #state.recentNodes > Config.Monster.PatrolMemory do
				table.remove(state.recentNodes, 1)
			end
		end
		state.patrolTarget = nextPatrolNode(sensed.patrolNodes, sensed.rigPosition, state.recentNodes)
	end
	return { moveTarget = state.patrolTarget, speed = Config.Monster.PatrolSpeed, caught = nil }
end

local function enterSearch(state: FSMState): TickResult
	state.name = Enums.MonsterState.Search
	state.searchElapsed = 0
	state.searchTarget = state.lastSeen
	return { moveTarget = state.searchTarget, speed = Config.Monster.PatrolSpeed, caught = nil }
end

local function tickChase(state: FSMState, sensed: Sensed): TickResult
	-- A catch ends everything this tick.
	local caught = caughtPlayer(sensed)
	if caught then
		return { moveTarget = sensed.rigPosition, speed = Config.Monster.ChaseSpeed, caught = caught }
	end

	-- Re-acquire / maintain the freshest visible target.
	local seen = nearestVisible(sensed)
	if seen then
		state.targetUserId = seen.player.UserId
		state.lastSeen = seen.position
		state.timeSinceSeen = 0
		return { moveTarget = seen.position, speed = Config.Monster.ChaseSpeed, caught = nil }
	end

	-- No one visible. If the chased target left the sensed set, give up immediately;
	-- if it is merely behind a wall (still sensed), burn the grace window.
	if not targetInSensed(state, sensed) then
		return enterSearch(state)
	end
	state.timeSinceSeen += sensed.dt
	if state.timeSinceSeen >= Config.Monster.LoseSightSeconds then
		return enterSearch(state)
	end
	return { moveTarget = state.lastSeen, speed = Config.Monster.ChaseSpeed, caught = nil }
end

local function tickSearch(state: FSMState, sensed: Sensed): TickResult
	-- Re-detection resumes the chase immediately.
	local seen = nearestVisible(sensed)
	if seen then
		return beginChase(state, seen)
	end

	state.searchElapsed += sensed.dt
	if state.searchElapsed >= Config.Monster.SearchDuration then
		state.name = Enums.MonsterState.Patrol
		state.patrolTarget = nil
		state.targetUserId = nil
		state.lastSeen = nil
		state.searchTarget = nil
		return { moveTarget = nil, speed = Config.Monster.PatrolSpeed, caught = nil }
	end

	-- Investigate: walk to the current search point; on arrival pick a new random
	-- point within SearchWanderRadius of the last-seen position.
	local anchor = state.lastSeen or sensed.rigPosition
	if
		state.searchTarget == nil
		or flatDistance(sensed.rigPosition, state.searchTarget) < Config.Monster.WaypointReachedDistance
	then
		local angle = math.random() * math.pi * 2
		local dist = math.random() * Config.Monster.SearchWanderRadius
		state.searchTarget = anchor + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	end
	return { moveTarget = state.searchTarget, speed = Config.Monster.PatrolSpeed, caught = nil }
end

function BunnyFSM.tick(state: FSMState, sensed: Sensed): TickResult
	if state.name == Enums.MonsterState.Chase then
		return tickChase(state, sensed)
	elseif state.name == Enums.MonsterState.Search then
		return tickSearch(state, sensed)
	end
	return tickPatrol(state, sensed)
end

return BunnyFSM
