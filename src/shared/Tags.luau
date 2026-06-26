--!strict
-- Tags.luau
-- Canonical CollectionService tag names. Every tag reference in the codebase
-- MUST come from this module -- never raw string literals -- so nothing is
-- stringly-typed. Add new tags here.

local Tags = {
	-- Active level markers (used from the skeleton milestone onward).
	PlayerStart = "PlayerStart", -- spawn / checkpoint markers
	ExitDoor = "ExitDoor", -- maze exit trigger volume(s)
	ExitGate = "ExitGate", -- the SOLID door part(s) that physically block the exit; ExitService slides them open on a win
	KeySpot = "KeySpot", -- candidate key spawn locations
	SafeRoom = "SafeRoom", -- battery-recharge / safe zones

	-- Runtime markers (applied by code, not placed in Studio).
	ActiveKey = "ActiveKey", -- a key part live in the world this round; the client compass beacons these

	-- Hazards.
	Trap = "Trap", -- a telegraphed floor trap (red arrow); TrapService arms/fires it spatially

	-- Hiding spots (the genre's last-resort escape: a locker/cabinet you duck into). HidingService
	-- confirms occupancy spatially + hides you from the monster's senses; placed in Studio like SafeRoom.
	HidingSpot = "HidingSpot",

	-- Monster markers.
	MonsterSpawn = "MonsterSpawn", -- where the bunny enters the maze
	MonkeySpawn = "MonkeySpawn", -- where the monkey nests/enters (placed in a different region)
	PatrolPoint = "PatrolPoint", -- nodes a patrolling monster walks between (shared graph)
	AmbushNode = "AmbushNode", -- scripted scare / ambush locations

	-- Atmosphere: practical lights the client FlickerController makes flicker.
	FlickerLight = "FlickerLight", -- a Light instance that flickers like a failing fixture
	MusicBoxEmitter = "MusicBoxEmitter", -- a part the AmbientController plays the intermittent 3D music-box motif from
}

return table.freeze(Tags)
