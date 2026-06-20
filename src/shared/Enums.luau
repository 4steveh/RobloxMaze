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
	Bunny = "Bunny", -- the methodical VISION stalker (escape by breaking line of sight)
	Monkey = "Monkey", -- the near-blind NOISE hunter (escape by going quiet)
})

-- Monster behaviour states for the FSMs. Patrol/Chase/Search are shared; Alert and
-- Investigate are the monkey's hearing-driven states (the bunny never enters them).
Enums.MonsterState = table.freeze({
	Patrol = "Patrol", -- wandering patrol routes, scanning (sight or hearing) for players
	Chase = "Chase", -- a player was detected; pursuing at chase/lunge speed
	Search = "Search", -- lost the trail; investigating the last-known point before giving up
	Alert = "Alert", -- (monkey) heard something: snaps to face the source and holds -- the "it heard you" tell
	Investigate = "Investigate", -- (monkey) erratically rushes the last-heard point
})

return table.freeze(Enums)
