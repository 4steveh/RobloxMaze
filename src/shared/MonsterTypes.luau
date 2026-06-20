--!strict
-- MonsterTypes.luau
-- The shared FSM contract for the monster roster. The per-monster brains
-- (`BunnyFSM`, `MonkeyFSM`) are sibling PURE modules -- no shared base class (two
-- deliberately different behaviours), but they share these input/output types and a
-- common state "head" so `MonsterService` can drive any of them uniformly. Each FSM
-- keeps its own concrete (superset) state type internally and takes its own `cfg`
-- slice; this module is only the boundary they agree on.

local MonsterTypes = {}

-- One sensed player this tick: where they are and whether the rig can SEE them
-- (cone + line of sight, decided by MonsterService). `noise` is the server-computed
-- audible level (0..1) the MONKEY hears through walls; nil/0 for the deaf bunny.
export type PlayerSense = {
	player: Player,
	position: Vector3,
	visible: boolean,
	noise: number?,
}

-- The full sensed world handed to an FSM tick (no Instance handles beyond Players,
-- so the FSM stays pure and unit-testable). `homePosition` is the rig's spawn/nest --
-- the bunny ignores it (it roams the patrolNodes), the monkey paces near it (its territory).
export type Sensed = {
	dt: number,
	rigPosition: Vector3,
	patrolNodes: { Vector3 },
	homePosition: Vector3,
	players: { PlayerSense },
}

-- An FSM's decision for this tick: where to move, how fast, whether it caught, and
-- (optional) a point to FACE while standing still -- the monkey's Alert "it heard you"
-- snap, applied by MonsterService when there is no moveTarget.
export type TickResult = { moveTarget: Vector3?, speed: number, caught: Player?, faceTarget: Vector3? }

-- The common head every FSM state exposes. MonsterService reads ONLY these fields
-- (the current state name for the rig attribute / chase signal, and who it is chasing);
-- each FSM's real state is a superset it owns privately.
export type FSMState = {
	name: string,
	targetUserId: number?,
}

return MonsterTypes
