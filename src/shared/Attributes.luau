--!strict
-- Attributes.luau
-- Canonical Instance attribute-name constants -- the same discipline Tags applies
-- to CollectionService tags. Server systems share per-player state through named
-- attributes instead of stringly-typed literals scattered across scripts.

local Attributes = {
	-- CFrame on a Player: where SpawnService should place the character on (re)spawn.
	-- Written by SafeRoomService (the SafeRoom a player last entered) and read by
	-- SpawnService. Absent until the player first enters a SafeRoom.
	Checkpoint = "Checkpoint",

	-- boolean on a Player: whether the player is currently inside any SafeRoom.
	-- Server-authoritative, set by SafeRoomService (handy for debugging / future
	-- systems). The flashlight does NOT read this -- it uses the enter/leave remotes.
	InSafeRoom = "InSafeRoom",
}

return table.freeze(Attributes)
