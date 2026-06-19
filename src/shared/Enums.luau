--!strict
-- Enums.luau
-- Enum-like constant tables. Use these instead of bare strings/numbers so state
-- is never stringly-typed.

local Enums = {}

-- High-level session state.
Enums.GameState = table.freeze({
	Playing = "Playing",
	Won = "Won",
})

-- Monster taxonomy (stub -- populated when monsters land).
Enums.MonsterType = table.freeze({})

-- Monster behaviour states for the future FSM (stub -- populated when monsters land).
Enums.MonsterState = table.freeze({})

return table.freeze(Enums)
