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
	InvulnSeconds = 3, -- seconds of server-authoritative invulnerability after (re)spawn: the monster ignores the player (no instant re-kill)
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

	-- Stamina gauge (sits just above the battery gauge, same width)
	StaminaGap = 10, -- px between the stamina gauge and the battery gauge above it
	StaminaFillColor = Color3.fromRGB(120, 230, 140),
	StaminaLowColor = Color3.fromRGB(235, 180, 70),

	-- Transient feedback toast (key pickup / locked door), centered below the tracker
	ToastYScale = 0.30, -- screen-height fraction for the toast's vertical position
	ToastWidth = 420, -- px
	ToastHeight = 34, -- px
	ToastTextSize = 24, -- px

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

-- Monster: the bunny (server-authoritative FSM stalker) --------------------------
-- Speeds in studs/second (player default WalkSpeed is 16 -- ChaseSpeed exceeds it
-- so you cannot outrun it; you must break line of sight). Angles in degrees,
-- distances in studs, durations in seconds.
Config.Monster = table.freeze({
	PatrolSpeed = 10, -- WalkSpeed while patrolling / searching
	ChaseSpeed = 19, -- WalkSpeed while chasing. Base player WalkSpeed 16 still loses,
	-- but a sprint burst (Config.Player.SprintSpeed) lets a skilled player open a gap
	-- and break line of sight -- the chase is winnable, not a death sentence.

	DetectRange = 50, -- max distance the bunny can see a player
	DetectHalfAngle = 45, -- half the vision cone (so a 90-degree total cone)
	EyeHeight = 2, -- studs above the rig's HRP that the line-of-sight ray starts from

	LoseSightSeconds = 4, -- seconds of broken sight (behind a wall) before a chase drops to Search
	SearchDuration = 6, -- seconds spent searching the last-seen area before giving up
	SearchWanderRadius = 12, -- studs the bunny pokes around the last-seen point while searching

	CatchRadius = 5, -- distance to a player that counts as a catch (instant)

	RepathInterval = 0.4, -- seconds between PathfindingService recomputations during a chase
	AgentRadius = 2, -- CreatePath agent radius (fits the corridors)
	AgentHeight = 5, -- CreatePath agent height
	WaypointReachedDistance = 4, -- studs: advance to the next path waypoint within this distance

	PatrolMemory = 2, -- patrol nodes remembered as "recently visited" so it tours rather than ping-pongs
	StallEpsilon = 0.5, -- studs: movement below this in a tick counts as "not moving"
	StallTicks = 10, -- consecutive stalled ticks (with a target) that force a repath

	BodySize = Vector3.new(2.5, 3.5, 2.5), -- placeholder rig body dimensions
	BodyColor = Color3.fromRGB(220, 218, 225), -- placeholder rig tone (pale, faintly sickly)

	-- Anti-spawn-camp (the root fix for "the bunny kills you then camps the spawn").
	ResetToPatrolOnCatch = true, -- on a catch, clear the FSM and send the rig home so it can't loiter on the kill site
	PostCatchDormantSeconds = 4, -- seconds after a catch the rig senses nothing (patrols home) -- overlaps the respawn window
	NoKeySpawnRadius = 30, -- studs: KeySpots within this of any MonsterSpawn are skipped so a key never spawns in the bunny's lap

	-- Tick robustness.
	MaxTickDtFactor = 4, -- clamp a tick's dt to PollInterval*this so a server hitch can't skip the FSM past its timers

	-- Visible model: the corrupted-mascot mesh (ServerStorage.Assets.BunnyBody) welded
	-- to the invisible physics root. The mesh looms taller than the collision box on
	-- purpose; pathfinding still uses BodySize + AgentRadius, so movement is unchanged.
	ModelYOffset = 0.75, -- studs lifting the mesh so its feet meet the floor
	ModelFaceYaw = 0, -- degrees rotating the mesh so its face aligns with the rig's forward (mesh front is -Z, matching the rig)
	EyeGlowColor = Color3.fromRGB(210, 40, 40), -- a faint red "it's watching" glow that reads in the dark
	EyeGlowBrightness = 0.7,
	EyeGlowRange = 7,
})

-- Lighting / atmosphere ---------------------------------------------------------
-- Only the FLICKER animation tunables the FlickerController reads live here. The
-- static place lighting (Lighting service, Atmosphere, ColorCorrection) is content
-- saved on the place, not Config -- those aren't numbers any logic reads.
Config.Lighting = table.freeze({
	FlickerSpeed = 11, -- base oscillation speed (rad/s) of a flickering fixture
	FlickerMinScale = 0.35, -- brightness floor as a fraction of the fixture's base brightness
	FlickerOffChance = 0.015, -- per-frame chance a fixture briefly cuts out entirely
	FlickerOffTime = 0.12, -- seconds a fixture stays cut out
})

-- Player movement: sprint + stamina ---------------------------------------------
-- The player's escape tool. Base WalkSpeed loses to the bunny's ChaseSpeed (19), but
-- a stamina-limited sprint burst (22 > 19) lets a skilled player open a gap and break
-- line of sight -- so a chase is winnable. Sprint is a client INTENT validated on the
-- server (the first client->server remote); the server owns stamina and WalkSpeed.
Config.Player = table.freeze({
	WalkSpeed = 16, -- base move speed (Roblox default)
	SprintSpeed = 22, -- move speed while sprinting with stamina remaining
	StaminaMax = 4, -- seconds of sprint on a full bar
	StaminaDrain = 1, -- stamina seconds spent per real second while sprinting
	StaminaRegen = 0.7, -- stamina seconds restored per real second while not sprinting
	StaminaRegenDelay = 0.6, -- seconds after sprinting before stamina starts to regen
	SprintKey = Enum.KeyCode.LeftShift,
	IntentRateLimit = 0.08, -- min seconds between accepted SprintIntent messages (anti-spam)
})

-- Compass: key-finding wayfinding (the fix for "no clear direction") --------------
-- The server tags each live key ActiveKey; the client beacons them through walls and
-- points an edge arrow at the nearest one, so players are never lost in the fog.
Config.Compass = table.freeze({
	BeaconColor = Color3.fromRGB(140, 220, 110), -- echoes the key's eerie green glow
	BeaconHeight = 5.5, -- studs above a key the beacon floats
	BeaconSize = 26, -- px diameter of the on-screen beacon dot
	BeaconMinSize = 10, -- px the beacon shrinks to at MaxBeaconDistance
	MaxBeaconDistance = 220, -- studs at/beyond which a beacon is at its smallest
	ArrowSize = 54, -- px edge arrow toward the nearest active key
	ArrowBottomOffset = 200, -- px from the bottom edge (sits above the exit arrow)
	ArrowColor = Color3.fromRGB(150, 230, 110),
	LabelText = "KEY",
})

-- Onboarding: first-30-seconds direction (intro, controls, objective tracker) -----
Config.Onboarding = table.freeze({
	IntroVerb = "FIND", -- composed with the key count: "FIND 3 KEYS"
	IntroNoun = "KEYS",
	IntroSub = "...then escape through the EXIT.",
	IntroBannerSeconds = 5, -- how long the center intro banner holds before fading
	ControlsHint = "WASD Move      F Flashlight      Shift Sprint",
	ControlsHintSeconds = 9, -- how long the controls hint shows (or until first move)
	ObjectiveLabel = "KEYS", -- "KEYS 0/3"
	ObjectiveExitText = "ALL KEYS — REACH THE EXIT", -- objective tracker once keys are done
})

-- Feedback: legible event messaging (toasts + win/caught copy) --------------------
Config.Feedback = table.freeze({
	KeyToastSeconds = 2.0, -- "KEY 1/3" toast hold time
	LockedToastSeconds = 2.5, -- "EXIT LOCKED" toast hold time
	ToastColor = Color3.fromRGB(240, 230, 210),
	CaughtText = "CAUGHT!",
	CaughtColor = Color3.fromRGB(220, 60, 55),
	LockedTextPrefix = "EXIT LOCKED", -- shown with the live count: "EXIT LOCKED — 3 KEYS NEEDED"
})

-- Audio -------------------------------------------------------------------------
-- Every cue is data-driven (per the Config discipline). All asset IDs are free
-- Creator-Store uploads, each verified to load in Studio. Server owns truth (the
-- rig State attribute + the MonsterStateChanged remote drive escalation); the
-- client renders all sound. AudioGroups builds the SoundService bus tree from
-- Config.Audio.Groups; controllers route each Sound via AudioGroups.get(name).
Config.Audio = table.freeze({
	-- SoundGroup bus volumes (Master > Music/Ambient/Monster/SFX/UI).
	Groups = table.freeze({
		Master = 1.0,
		Music = 0.5,
		Ambient = 0.6,
		Monster = 0.85,
		SFX = 0.9,
		UI = 0.7,
	}),

	-- Global reverb, switched by server-authoritative SafeRoom occupancy (client reads
	-- the SafeRoom enter/leave remotes; it never detects occupancy itself).
	Reverb = table.freeze({
		Maze = Enum.ReverbType.Hallway, -- the corridors
		SafeRoom = Enum.ReverbType.PaddedCell, -- muffled "you're safe" tone
	}),

	RollOffMin = 6, -- studs: shared RollOffMinDistance for all 3D (spatial) Sounds

	-- Ambient bed + the intermittent 3D daycare music-box motif (the signature scare).
	Ambient = table.freeze({
		DroneId = "rbxassetid://140704980462451", -- low dread drone (looped)
		DroneVolume = 0.35,
		RoomToneId = "rbxassetid://9125446564", -- HVAC/room hum (looped)
		RoomToneVolume = 0.5,
		MusicBoxId = "rbxassetid://133759804695426", -- 3D music box on the mascot statue
		MusicBoxVolume = 0.65,
		MusicBoxMinGap = 45, -- seconds between music-box plays (randomized in [min,max])
		MusicBoxMaxGap = 110,
		MusicBoxPlaySeconds = 14, -- seconds of the (long) music-box clip to play per drift-in
		MusicBoxRange = 75, -- studs RollOffMaxDistance for the 3D music box
	}),

	-- Monster cues: 3D breathing/footsteps on the rig + a non-spatial heartbeat the
	-- client scales by nearest-rig distance + a Patrol->Chase sting (per-player).
	Monster = table.freeze({
		BreathingId = "rbxassetid://105236570094495", -- looped, 3D on the rig HRP
		BreathingVolume = 0.65,
		BreathingRange = 45, -- studs RollOffMaxDistance
		FootstepId = "rbxassetid://81623756670923", -- triggered per step, 3D on the rig
		FootstepVolume = 0.5,
		FootstepRange = 42,
		FootstepStride = 3.5, -- studs the rig travels per footstep sound
		ChaseStingId = "rbxassetid://1841353932", -- one-shot on Patrol->Chase
		ChaseStingVolume = 0.75,
		HeartbeatId = "rbxassetid://139481207162657", -- non-spatial, scaled by distance
		HeartbeatVolume = 0.7,
		HeartbeatStartDistance = 45, -- studs at which the heartbeat fades in (slow/faint)
		HeartbeatMaxDistance = 8, -- studs at which it is loudest/fastest
		HeartbeatMinRate = 0.75, -- PlaybackSpeed at start distance
		HeartbeatMaxRate = 1.9, -- PlaybackSpeed at closest
	}),

	-- Player SFX (footsteps, flashlight click, low-battery beep). All uncontested.
	Player = table.freeze({
		FootstepIds = table.freeze({
			"rbxassetid://81623756670923",
			"rbxassetid://78754179999047",
			"rbxassetid://112240321395589",
		}),
		FootstepVolume = 0.3,
		FootstepRange = 30, -- studs RollOffMaxDistance for the local player's footsteps
		FootstepWalkInterval = 0.5, -- seconds per step at base WalkSpeed (scaled by actual speed)
		FlashlightClickId = "rbxassetid://9119717523",
		FlashlightClickVolume = 0.5,
		LowBatteryBeepId = "rbxassetid://8500212950",
		LowBatteryBeepVolume = 0.45,
	}),

	-- One-shot event stingers wired to the EXISTING remotes.
	Stingers = table.freeze({
		KeyChimeId = "rbxassetid://7381723941", -- KeyCollected (UI bus)
		KeyChimeVolume = 0.6,
		LockedThunkId = "rbxassetid://9120188626", -- ExitLocked (SFX bus)
		LockedThunkVolume = 0.65,
		WinJingleId = "rbxassetid://9041792228", -- GameWon (Music bus)
		WinJingleVolume = 0.75,
		JumpscareId = "rbxassetid://139306955269282", -- MonsterCaught (full-volume, ducks others)
		JumpscareVolume = 1.0,
	}),
})

return table.freeze(Config)
