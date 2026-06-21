--!strict
-- MonkeyFSM.luau
-- Pure decision module for the monkey: the near-blind NOISE hunter (the inverse of the
-- bunny's vision stalker). It HEARS each player's server-computed effectiveNoise
-- (`ps.noise`, = NoiseLevel x distance-falloff, set by MonsterService) THROUGH walls,
-- and only SEES (`ps.visible`) at short range to confirm a lunge. Same contract as
-- BunnyFSM (newState / tick(state, sensed, cfg), no Instance work, unit-testable).
--
-- Flow: Patrol --hear--> Alert (freeze + face: the fair "it heard you" tell) -->
-- Investigate (erratic rush at the noise) --see--> Chase (committed lunge) --catch.
-- Losing the trail (sight broken AND gone quiet) drops to Search, then Patrol. The
-- counter is the one thing the bunny ignores: go QUIET (walk, don't sprint).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Enums)
local MonsterTypes = require(ReplicatedStorage.MonsterTypes)

export type PlayerSense = MonsterTypes.PlayerSense
export type Sensed = MonsterTypes.Sensed
export type TickResult = MonsterTypes.TickResult

-- Fields of the resolved Config slice this FSM reads (Shared U Species.Monkey).
export type Config = {
	PatrolSpeed: number,
	InvestigateSpeed: number,
	LungeSpeed: number,
	HearThreshold: number,
	LoseHearThreshold: number,
	LoseHearSeconds: number,
	AlertDuration: number,
	SearchDuration: number,
	SearchWanderRadius: number,
	NestWanderRadius: number,
	InvestigateJitter: number,
	CatchRadius: number,
	WaypointReachedDistance: number,
	WanderRepickSeconds: number,
	PatrolMemory: number,
}

-- The monkey's full FSM state -- a superset of MonsterTypes.FSMState (name, targetUserId).
export type FSMState = {
	name: string,
	targetUserId: number?,
	lastHeard: Vector3?,
	alertElapsed: number,
	quietElapsed: number,
	searchElapsed: number,
	searchTarget: Vector3?,
	patrolTarget: Vector3?,
	patrolElapsed: number, -- time spent heading to patrolTarget (re-pick if it's unreachable)
	recentNodes: { Vector3 },
	investigateTarget: Vector3?,
	investigateElapsed: number, -- time spent heading to investigateTarget (re-pick if unreachable)
}

local MonkeyFSM = {}

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function noiseOf(ps: PlayerSense): number
	return ps.noise or 0
end

-- Loudest sensed player at/above HearThreshold, or nil (the commit-to-Alert signal).
local function loudestHeard(sensed: Sensed, cfg: Config): PlayerSense?
	local best, bestN = nil, cfg.HearThreshold
	for _, ps in sensed.players do
		local n = noiseOf(ps)
		if n >= bestN then
			best, bestN = ps, n
		end
	end
	return best
end

-- Highest effectiveNoise among sensed players (0 if none) -- for losing the trail.
local function maxNoise(sensed: Sensed): number
	local m = 0
	for _, ps in sensed.players do
		m = math.max(m, noiseOf(ps))
	end
	return m
end

-- Nearest player the monkey can actually SEE this tick (short cone, confirms a lunge).
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

-- Nearest player within CatchRadius (pure proximity, it is on top of you).
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

function MonkeyFSM.newState(): FSMState
	return {
		name = Enums.MonsterState.Patrol,
		targetUserId = nil,
		lastHeard = nil,
		alertElapsed = 0,
		quietElapsed = 0,
		searchElapsed = 0,
		searchTarget = nil,
		patrolTarget = nil,
		patrolElapsed = 0,
		recentNodes = {},
		investigateTarget = nil,
		investigateElapsed = 0,
	}
end

-- Transitions ----------------------------------------------------------------------

local function enterAlert(state: FSMState, heard: PlayerSense): TickResult
	state.name = Enums.MonsterState.Alert
	state.targetUserId = heard.player.UserId
	state.lastHeard = heard.position
	state.alertElapsed = 0
	return { moveTarget = nil, speed = 0, caught = nil, faceTarget = heard.position }
end

local function enterInvestigate(state: FSMState, cfg: Config): TickResult
	state.name = Enums.MonsterState.Investigate
	state.quietElapsed = 0
	state.investigateTarget = state.lastHeard
	state.investigateElapsed = 0
	return { moveTarget = state.investigateTarget, speed = cfg.InvestigateSpeed, caught = nil }
end

local function enterChase(state: FSMState, seen: PlayerSense, cfg: Config): TickResult
	state.name = Enums.MonsterState.Chase
	state.targetUserId = seen.player.UserId
	state.lastHeard = seen.position
	return { moveTarget = seen.position, speed = cfg.LungeSpeed, caught = nil }
end

local function enterSearch(state: FSMState, cfg: Config): TickResult
	state.name = Enums.MonsterState.Search
	state.searchElapsed = 0
	state.searchTarget = state.lastHeard
	return { moveTarget = state.searchTarget, speed = cfg.PatrolSpeed, caught = nil }
end

-- States ---------------------------------------------------------------------------

local function tickPatrol(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	local heard = loudestHeard(sensed, cfg)
	if heard then
		return enterAlert(state, heard)
	end
	-- TERRITORIAL: the monkey PACES within NestWanderRadius of its nest -- it guards its
	-- den and never roams the maze like the bunny, so the two never shadow each other. On
	-- arrival it picks a fresh nearby point; if it has strayed (after an investigation),
	-- aiming back near home walks it home.
	state.patrolElapsed += sensed.dt
	-- Re-pick on ARRIVAL or after WanderRepickSeconds of failing to arrive: a random nest
	-- point can land inside a wall (the rig then never gets within WaypointReachedDistance of
	-- it and would steer into the wall forever) -- the timeout abandons it and picks anew.
	if
		state.patrolTarget == nil
		or flatDistance(sensed.rigPosition, state.patrolTarget) < cfg.WaypointReachedDistance
		or state.patrolElapsed >= cfg.WanderRepickSeconds
	then
		local a = math.random() * math.pi * 2
		local d = math.random() * cfg.NestWanderRadius
		state.patrolTarget = sensed.homePosition + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		state.patrolElapsed = 0
	end
	return { moveTarget = state.patrolTarget, speed = cfg.PatrolSpeed, caught = nil }
end

local function tickAlert(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	state.alertElapsed += sensed.dt
	local heard = loudestHeard(sensed, cfg)
	if heard then
		state.lastHeard = heard.position
		state.targetUserId = heard.player.UserId
	end
	if state.alertElapsed >= cfg.AlertDuration then
		if heard then
			return enterInvestigate(state, cfg)
		end
		-- it went quiet during the alert hold: shrug it off and resume patrolling.
		state.name = Enums.MonsterState.Patrol
		state.patrolTarget = nil
		state.targetUserId = nil
		return { moveTarget = nil, speed = cfg.PatrolSpeed, caught = nil }
	end
	-- Hold: stand still and face the source (the "it heard you" tell).
	return { moveTarget = nil, speed = 0, caught = nil, faceTarget = state.lastHeard }
end

local function tickInvestigate(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	local caught = caughtPlayer(sensed, cfg)
	if caught then
		return { moveTarget = sensed.rigPosition, speed = cfg.InvestigateSpeed, caught = caught }
	end
	local seen = nearestVisible(sensed)
	if seen then
		return enterChase(state, seen, cfg)
	end

	local heard = loudestHeard(sensed, cfg)
	if heard then
		state.lastHeard = heard.position
		state.targetUserId = heard.player.UserId
		state.quietElapsed = 0
	elseif maxNoise(sensed) < cfg.LoseHearThreshold then
		state.quietElapsed += sensed.dt
		if state.quietElapsed >= cfg.LoseHearSeconds then
			return enterSearch(state, cfg)
		end
	else
		state.quietElapsed = 0
	end

	-- Rush the last-heard point with a random lateral weave (slightly dodgeable). Re-pick on
	-- arrival OR after WanderRepickSeconds stuck (a weave point can land in a wall) so it
	-- never wedges mid-investigation the way an un-timed wander target would.
	state.investigateElapsed += sensed.dt
	local anchor = state.lastHeard or sensed.rigPosition
	if
		state.investigateTarget == nil
		or flatDistance(sensed.rigPosition, state.investigateTarget) < cfg.WaypointReachedDistance
		or state.investigateElapsed >= cfg.WanderRepickSeconds
	then
		local a = math.random() * math.pi * 2
		local j = math.random() * cfg.InvestigateJitter
		state.investigateTarget = anchor + Vector3.new(math.cos(a) * j, 0, math.sin(a) * j)
		state.investigateElapsed = 0
	end
	return { moveTarget = state.investigateTarget, speed = cfg.InvestigateSpeed, caught = nil }
end

local function tickChase(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	local caught = caughtPlayer(sensed, cfg)
	if caught then
		return { moveTarget = sensed.rigPosition, speed = cfg.LungeSpeed, caught = caught }
	end
	local seen = nearestVisible(sensed)
	if seen then
		state.targetUserId = seen.player.UserId
		state.lastHeard = seen.position
		return { moveTarget = seen.position, speed = cfg.LungeSpeed, caught = nil }
	end
	-- Lost sight (broke LoS / out of short range). Fall back to hearing: still loud ->
	-- weave after the noise (Investigate); gone quiet -> give up the lunge (Search).
	local heard = loudestHeard(sensed, cfg)
	if heard then
		return enterInvestigate(state, cfg)
	end
	return enterSearch(state, cfg)
end

local function tickSearch(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	local caught = caughtPlayer(sensed, cfg)
	if caught then
		return { moveTarget = sensed.rigPosition, speed = cfg.PatrolSpeed, caught = caught }
	end
	local seen = nearestVisible(sensed)
	if seen then
		return enterChase(state, seen, cfg)
	end
	local heard = loudestHeard(sensed, cfg)
	if heard then
		return enterInvestigate(state, cfg)
	end

	state.searchElapsed += sensed.dt
	if state.searchElapsed >= cfg.SearchDuration then
		state.name = Enums.MonsterState.Patrol
		state.patrolTarget = nil
		state.targetUserId = nil
		state.lastHeard = nil
		state.searchTarget = nil
		return { moveTarget = nil, speed = cfg.PatrolSpeed, caught = nil }
	end

	local anchor = state.lastHeard or sensed.rigPosition
	if
		state.searchTarget == nil
		or flatDistance(sensed.rigPosition, state.searchTarget) < cfg.WaypointReachedDistance
	then
		local a = math.random() * math.pi * 2
		local d = math.random() * cfg.SearchWanderRadius
		state.searchTarget = anchor + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
	end
	return { moveTarget = state.searchTarget, speed = cfg.PatrolSpeed, caught = nil }
end

function MonkeyFSM.tick(state: FSMState, sensed: Sensed, cfg: Config): TickResult
	if state.name == Enums.MonsterState.Chase then
		return tickChase(state, sensed, cfg)
	elseif state.name == Enums.MonsterState.Investigate then
		return tickInvestigate(state, sensed, cfg)
	elseif state.name == Enums.MonsterState.Alert then
		return tickAlert(state, sensed, cfg)
	elseif state.name == Enums.MonsterState.Search then
		return tickSearch(state, sensed, cfg)
	end
	return tickPatrol(state, sensed, cfg)
end

return MonkeyFSM
