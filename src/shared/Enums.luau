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

-- Monster taxonomy.
Enums.MonsterType = table.freeze({
	Bunny = "Bunny",
})

-- Monster behaviour states for the FSM.
Enums.MonsterState = table.freeze({
	Patrol = "Patrol", -- wandering patrol routes, scanning for players
	Chase = "Chase", -- a player was detected; pursuing at chase speed
	Search = "Search", -- lost sight; investigating the last-seen point before giving up
})

return table.freeze(Enums)
