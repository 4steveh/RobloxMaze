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
	LowBatteryThreshold = 20, -- seconds remaining at/below which the light dims/flickers

	Range = 60, -- SpotLight.Range, studs
	Angle = 75, -- SpotLight.Angle, degrees
	Brightness = 2, -- SpotLight.Brightness

	ToggleKey = Enum.KeyCode.F, -- key that toggles the flashlight on/off
	LowBatteryFlickerSpeed = 14, -- flicker oscillation speed (rad/s) below the low-battery threshold
	LowBatteryMinBrightnessScale = 0.35, -- brightness floor (fraction of Brightness) while flickering
})

-- Keys --------------------------------------------------------------------------
Config.Keys = table.freeze({
	RequiredToWin = 3, -- keys the player must hold to open the exit
	SpawnPerRound = 3, -- keys placed in the maze each round (random subset of KeySpot markers)
})

-- Key model (the collectible's placeholder visuals) -----------------------------
-- A glowing, ominous floating part. No asset IDs here -- swap in a real
-- model/mesh later. Pickup radius lives in Config.Spatial.KeyPickupRadius.
Config.KeyModel = table.freeze({
	Size = Vector3.new(1.6, 2.6, 0.5), -- studs
	Color = Color3.fromRGB(64, 74, 58), -- desaturated, sickly
	LightColor = Color3.fromRGB(125, 205, 95), -- eerie glow
	LightBrightness = 5,
	LightRange = 16,
	HoverHeight = 3, -- studs above the KeySpot marker
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
	AtCheckpoint = true, -- respawn at the last SafeRoom checkpoint (vs. always the PlayerStart marker)
	KeepKeysOnDeath = true, -- keep collected keys through death
	SpawnUpOffset = 5, -- studs the player's hidden SpawnLocation sits above its marker, so the character spawns clear of the floor
	RespawnDelay = 3, -- seconds between death and respawn (also the window for the upcoming death/jumpscare beat)
})

-- Win ---------------------------------------------------------------------------
Config.Win = table.freeze({
	FreezeDuration = 3, -- seconds the player is frozen during the win celebration
})

-- HUD (icon-forward; counts come from gameplay Config, never hardcoded) ----------
Config.HUD = table.freeze({
	-- Key pips (how many = Config.Keys.RequiredToWin)
	PipSize = 34, -- px diameter
	PipGap = 10, -- px between pips
	PipTopOffset = 24, -- px from the top edge
	PipFilledColor = Color3.fromRGB(240, 205, 70),
	PipEmptyColor = Color3.fromRGB(40, 40, 48),
	PipStrokeColor = Color3.fromRGB(15, 15, 18),
	PipStrokeThickness = 2,
	PipIconScale = 0.72, -- a key icon fills this fraction of a pip
	CornerRadius = 6, -- px: rounded-corner radius for gauge panels

	-- Battery gauge
	BatteryWidth = 180, -- px
	BatteryHeight = 16, -- px
	BatteryMargin = 18, -- px from the screen corner
	BatteryBackColor = Color3.fromRGB(25, 25, 30),
	BatteryFillColor = Color3.fromRGB(120, 220, 255),
	BatteryLowColor = Color3.fromRGB(220, 70, 60),

	-- Exit arrow (shown only once all keys are collected)
	ArrowSize = 64, -- px
	ArrowBottomOffset = 120, -- px from the bottom edge
	ArrowColor = Color3.fromRGB(240, 205, 70),

	-- Win overlay
	WinBackColor = Color3.fromRGB(10, 14, 12),
	WinBackTransparency = 0.25,
	WinIconSize = 140, -- px
	WinIconColor = Color3.fromRGB(120, 230, 130),
	WinTextSize = 28, -- px
	WinTextWidth = 320, -- px
	WinTextPadding = 8, -- px added to WinTextSize for the label height

	-- "Locked door" rattle (nothing punishing)
	LockedShakePixels = 8, -- px nudge amplitude
	LockedShakeTime = 0.35, -- seconds total
})

-- Future sections (fill in as milestones land) ----------------------------------
-- Config.Monster = table.freeze({ ... })
-- Config.Audio = table.freeze({ ... })

return table.freeze(Config)
