--!strict
-- Types.luau
-- Shared Luau type definitions. Start minimal; grow as systems are added.
-- Consumers: `local Types = require(ReplicatedStorage.Types)` then reference the
-- exported types through the module, e.g. `Types.PlayerState`.

local Types = {}

-- High-level session state (mirrors the values in Enums.GameState).
export type GameState = "Playing" | "Won"

-- Per-player run state, owned and validated by the server.
export type PlayerState = {
	keys: number, -- keys currently held
	state: GameState, -- whether this player is still Playing or has Won
	checkpoint: Vector3?, -- last PlayerStart reached (nil until the first checkpoint)
}

return Types
