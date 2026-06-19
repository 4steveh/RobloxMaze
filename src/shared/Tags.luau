--!strict
-- Tags.luau
-- Canonical CollectionService tag names. Every tag reference in the codebase
-- MUST come from this module -- never raw string literals -- so nothing is
-- stringly-typed. Add new tags here.

local Tags = {
	-- Active level markers (used from the skeleton milestone onward).
	PlayerStart = "PlayerStart", -- spawn / checkpoint markers
	ExitDoor = "ExitDoor", -- maze exit trigger volume(s)
	KeySpot = "KeySpot", -- candidate key spawn locations
	SafeRoom = "SafeRoom", -- battery-recharge / safe zones

	-- Temporary test tag (Prompt 2 only -- remove once spatial detection is proven).
	KillBrick = "KillBrick",

	-- Future milestones (monsters). Defined now so code is never stringly-typed.
	MonsterSpawn = "MonsterSpawn", -- where monsters enter the maze
	PatrolPoint = "PatrolPoint", -- nodes a patrolling monster walks between
	AmbushNode = "AmbushNode", -- scripted scare / ambush locations
}

return table.freeze(Tags)
