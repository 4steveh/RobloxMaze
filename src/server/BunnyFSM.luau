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

function BunnyFSM.tick(state: FSMState, sensed: Sensed): TickResult
	if state.name == Enums.MonsterState.Patrol then
		return tickPatrol(state, sensed)
	end
	-- Chase and Search are added in later tasks; default to patrolling so the
	-- function is total in the meantime.
	return tickPatrol(state, sensed)
end

return BunnyFSM
