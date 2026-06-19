--!strict
-- Config.luau
-- THE single source of truth for every tunable number in the game. No magic
-- numbers may live anywhere else -- logic AND ui read from here. Sections are
-- namespaced tables so future systems (monsters, audio) slot in cleanly. Every
-- table is frozen: Config is read-only at runtime.

local Config = {}

-- Flashlight --------------------------------------------------------------------
-- The one deliberate client-side resource: uncontested, latency-sensitive, and
-- nothing else depends on it (see CLAUDE.md). Battery is measured in "seconds of
-- light remaining".
Config.Flashlight = table.freeze({
	BatteryMax = 100, -- seconds of light on a full battery
	DrainPerSecond = 1, -- battery seconds spent per real second while ON
	RechargePerSecond = 5, -- battery seconds restored per real second while in a (server-gated) SafeRoom
	LowBatteryThreshold = 20, -- seconds remaining at/below which the UI shows a warning

	Range = 60, -- SpotLight.Range, studs
	Angle = 75, -- SpotLight.Angle, degrees
	Brightness = 2, -- SpotLight.Brightness
})

-- Keys --------------------------------------------------------------------------
Config.Keys = table.freeze({
	RequiredToWin = 3, -- keys the player must hold to open the exit
	SpawnPerRound = 3, -- keys actually placed in the maze each round
})

-- Spatial detection -------------------------------------------------------------
-- Server-authoritative occupancy/proximity scanning (never Touched events).
Config.Spatial = table.freeze({
	PollInterval = 0.15, -- seconds between server occupancy/proximity scans
	KeyPickupRadius = 6, -- studs: distance to a KeySpot that counts as a pickup
	ExitTriggerRadius = 8, -- studs: distance to an ExitDoor that counts as reaching it
})

-- Respawn -----------------------------------------------------------------------
Config.Respawn = table.freeze({
	AtCheckpoint = true, -- respawn at the last PlayerStart checkpoint (vs. default spawn)
	KeepKeysOnDeath = true, -- keep collected keys through death
})

-- Win ---------------------------------------------------------------------------
Config.Win = table.freeze({
	FreezeDuration = 3, -- seconds the player is frozen during the win celebration
})

-- Future sections (fill in as milestones land) ----------------------------------
-- Config.Monster = table.freeze({ ... })
-- Config.Audio = table.freeze({ ... })

return table.freeze(Config)
