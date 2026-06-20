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

	-- number on a Player: keys collected this round. Server-authoritative (set by
	-- KeyService), survives death/respawn, read by ExitService and the HUD.
	KeyCount = "KeyCount",

	-- string on a Player: the player's current Enums.GameState ("Playing"/"Won"),
	-- set by ExitService.
	GameState = "GameState",

	-- number on a Player: current flashlight battery. Set CLIENT-side by
	-- FlashlightController purely so the HUD gauge can read it (never server-read).
	FlashlightBattery = "FlashlightBattery",

	-- boolean on a Player: true for a short window after (re)spawn. Server-authoritative
	-- (set by SpawnService); MonsterService ignores players carrying it so a freshly
	-- respawned character can never be instantly re-caught. The root anti-spawn-camp guard.
	RespawnGrace = "RespawnGrace",

	-- number on a Player: current sprint stamina (seconds remaining). Server-authoritative
	-- (set by SprintService), read by the HUD stamina gauge.
	Stamina = "Stamina",

	-- boolean on a Player: whether the flashlight is currently ON. Set CLIENT-side by
	-- FlashlightController so PlayerSFXController can play the toggle click. Local only.
	FlashlightOn = "FlashlightOn",

	-- string on a MONSTER RIG (not a Player): which Enums.MonsterType the rig is
	-- ("Bunny"/"Monkey"). Server-set in the rig builder; read by the client
	-- MonsterAnimController (to pick the gait recipe) and per-type monster audio.
	MonsterSpecies = "Species",

	-- number on a Player (0..1): server-computed audible NOISE this player is making
	-- (from movement speed -- sprinting is loud, creeping is near-silent). Owned by
	-- NoiseService (never client-set), read by the monkey's hearing detection and the
	-- HUD noise meter. Zeroed in a SafeRoom / Won / RespawnGrace.
	NoiseLevel = "NoiseLevel",
}

return table.freeze(Attributes)
