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
	Shadows = true, -- the flashlight casts dynamic shadows (monsters throw a shadow before you see them).
	-- NOTE: requires Lighting.Technology = ShadowMap or Future (a Studio Lighting property; can't be set from a script).
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
	SpinSpeed = 1.1, -- rad/s the floating key slowly rotates (draws the eye)
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

-- Monster roster (server-authoritative FSM stalkers) -----------------------------
-- Speeds in studs/second (player default WalkSpeed is 16). Distances in studs,
-- angles in degrees, durations in seconds. Structured so multiple species coexist
-- without sharing one config namespace:
--   * Shared  -- cross-species movement / pathfinding / anti-camp plumbing.
--   * Species -- per-species behaviour + rig (the FSM gets Shared U Species as `cfg`).
--   * Anim    -- per-species procedural-gait params (render-only, client-side).
Config.Monster = table.freeze({
	-- Cross-species plumbing. A species slice may override any of these.
	Shared = table.freeze({
		RepathInterval = 0.4, -- seconds between PathfindingService recomputations during a chase
		AgentRadius = 2, -- CreatePath agent radius (fits the corridors)
		AgentHeight = 5, -- CreatePath agent height
		WaypointReachedDistance = 4, -- studs: advance to the next path waypoint within this distance
		StallEpsilon = 0.5, -- studs: movement below this in a tick counts as "not moving"
		StallTicks = 10, -- consecutive stalled ticks (with a target) that force a repath
		MaxTickDtFactor = 4, -- clamp a tick's dt to PollInterval*this so a hitch can't skip FSM timers
		-- Anti-spawn-camp (the root fix for "it kills you then camps the spawn").
		ResetToPatrolOnCatch = true, -- on a catch, clear the FSM and send the rig home off the kill site
		PostCatchDormantSeconds = 4, -- seconds after a catch the rig senses nothing -- overlaps the respawn window
		NoKeySpawnRadius = 30, -- studs: KeySpots within this of any MonsterSpawn are skipped (no key in its lap)
	}),

	-- Per-species behaviour + rig. The FSM reads (Shared U Species) as its `cfg` slice.
	Species = table.freeze({
		-- The bunny: the methodical VISION stalker (escape by breaking line of sight).
		-- ChaseSpeed exceeds player WalkSpeed 16 so you cannot outrun it, but a sprint
		-- burst (Config.Player.SprintSpeed 22) lets a skilled player open a gap -- winnable.
		Bunny = table.freeze({
			PatrolSpeed = 10, -- WalkSpeed while patrolling / searching
			ChaseSpeed = 19, -- WalkSpeed while chasing
			DetectRange = 50, -- max distance the bunny can see a player
			DetectHalfAngle = 45, -- half the vision cone (so a 90-degree total cone)
			EyeHeight = 2, -- studs above the rig's HRP that the line-of-sight ray starts from
			LoseSightSeconds = 4, -- seconds of broken sight (behind a wall) before a chase drops to Search
			SearchDuration = 6, -- seconds spent searching the last-seen area before giving up
			SearchWanderRadius = 12, -- studs the bunny pokes around the last-seen point while searching
			CatchRadius = 5, -- distance to a player that counts as a catch (instant)
			PatrolMemory = 2, -- patrol nodes remembered as "recently visited" so it tours, not ping-pongs

			-- Rig: the corrupted-mascot mesh (ServerStorage.Assets.<BodyAssetName>). It looms
			-- taller than the collision box on purpose; pathfinding uses BodySize +
			-- Shared.AgentRadius, so movement is unchanged.
			BodySize = Vector3.new(2.5, 3.5, 2.5), -- physics-root (collision box) dimensions
			BodyColor = Color3.fromRGB(220, 218, 225), -- fallback rig tone (pale, faintly sickly)
			BodyAssetName = "BunnyBody", -- the AI-generated MULTI-PART mascot (torso+head+4 limbs) -> articulated rig
			ModelYOffset = -0.9, -- drops the torso so the jointed legs reach the floor
			ModelFaceYaw = 0, -- head sits at the torso's -Z, which is the rig forward
			EyeGlowColor = Color3.fromRGB(210, 40, 40), -- a faint red "it's watching" glow that reads in the dark
			EyeGlowBrightness = 0.7,
			EyeGlowRange = 7,
		}),

		-- The monkey: the near-blind NOISE hunter (escape by going QUIET). It HEARS the
		-- player's server-computed noise (sprint/fast movement) THROUGH walls; sight is a
		-- short, wide cone used only to confirm a lunge. The inverse of the bunny -- the
		-- bunny makes you afraid to be SEEN, the monkey afraid to be HEARD.
		Monkey = table.freeze({
			-- Speeds (vs player WalkSpeed 16 / SprintSpeed 22 / bunny ChaseSpeed 19).
			PatrolSpeed = 11, -- ambling near its nest
			InvestigateSpeed = 18, -- > WalkSpeed (runs down a walker who stays loud), < SprintSpeed (a sprinter gains)
			LungeSpeed = 24, -- > SprintSpeed: unoutrunnable BY DESIGN, but sight-gated + short -> counter is "break sight"

			-- Hearing (no LoS -- it hears through walls). effectiveNoise = NoiseLevel x falloff(dist, HearRange).
			HearRange = 90, -- studs to zero noise (longer than bunny sight: sound travels)
			HearThreshold = 0.45, -- effectiveNoise to commit to Alert (walking+quiet sits below this -> safe)
			LoseHearThreshold = 0.25, -- effectiveNoise below which it starts losing the trail
			LoseHearSeconds = 3, -- seconds below LoseHearThreshold before Investigate -> Search

			-- Short sight (lunge confirm only). Generic sight field names so detection is
			-- species-agnostic: a SHORT, WIDE cone (vs the bunny's long, narrow one).
			DetectRange = 14, -- studs it can actually SEE
			DetectHalfAngle = 70, -- wide cone (140 total)
			EyeHeight = 2, -- studs above the rig's HRP the LoS ray starts from

			AlertDuration = 1.2, -- seconds it freezes facing the source -- the fair "it heard you" tell
			SearchDuration = 6, -- seconds poking the last point before giving up
			SearchWanderRadius = 12, -- studs it wanders around the last-heard point
			NestWanderRadius = 22, -- studs it paces around its MonkeySpawn nest while patrolling
			-- (it GUARDS its territory -- it does NOT roam the maze like the bunny, so they don't shadow each other)
			InvestigateJitter = 6, -- studs of random lateral weave per repath (slightly dodgeable)
			CatchRadius = 5, -- distance that counts as a catch (instant)
			PatrolMemory = 2, -- patrol nodes remembered as "recently visited"
			RepathInterval = 0.35, -- override Shared: repath faster so the weave stays responsive

			-- Rig (no mesh yet -> a primitive proxy until Phase 5 builds an articulated body).
			BodySize = Vector3.new(2.5, 3.5, 2.5), -- <= bunny so corridor fit is identical (do NOT exceed)
			BodyColor = Color3.fromRGB(60, 48, 44), -- dark/matted: a distinct silhouette from the pale bunny
			BodyAssetName = "MonkeyBody", -- the AI-generated MULTI-PART gorilla (torso+head+4 limbs) -> articulated rig
			ModelYOffset = -1.5, -- drops the torso so the jointed legs reach the floor
			ModelFaceYaw = 0, -- head sits at the torso's -Z, which is the rig forward
			EyeGlowColor = Color3.fromRGB(250, 210, 60), -- sickly yellow (vs bunny red): instant species read in the dark
			EyeGlowBrightness = 0.7,
			EyeGlowRange = 7,
		}),
	}),

	-- Per-species procedural-gait params (render-only; the client MonsterAnimController
	-- drives each rig's cosmetic Motor6D `Transform` from REPLICATED ground speed -- no
	-- Animator, no assets, zero bandwidth). This kills the "glides along the floor" read.
	-- The bunny is a BIPEDAL mascot mesh, so it HOPS as one body (a real bunny gait + a
	-- deeply unsettling read); cadence is derived from actual travel speed.
	Anim = table.freeze({
		Bunny = table.freeze({
			RefSpeed = 11, -- studs/s at which the move blend saturates (~patrol speed)
			SpeedSmoothing = 12, -- per-second lerp rate smoothing the measured ground speed
			WeightSmoothing = 9, -- per-second lerp rate blending move/chase weights (no snaps)
			MinMoveSpeed = 1.5, -- studs/s below which the rig is "idle" (breathing, hop frozen)
			StrideDistance = 3.8, -- studs of travel per hop -> sets cadence (strideHz = speed / this)
			ChaseStrideScale = 0.72, -- multiply hop distance in Chase (shorter, more frantic hops)
			HopHeight = 0.85, -- studs the TORSO arcs up (gentler now -- the jointed legs carry the hop)
			ChaseHopScale = 0.85, -- flatter hops while chasing
			HopPitch = 0.18, -- rad torso pitch through the hop
			ForwardSurge = 0.5, -- studs the torso lunges forward through the air
			LegExtend = 0.95, -- rad the legs extend (push) at the plant and tuck at the apex
			ArmSwing = 0.5, -- rad the arms reach/swing through the hop
			HeadBob = 0.16, -- rad head bob with the hop
			IdleBreathHz = 0.5, -- breaths/second when idle
			IdleBreathAmp = 0.1, -- studs of vertical breathing when idle
		}),

		-- The monkey: an articulated primitive primate doing a 4-beat BOUNDING gallop
		-- (front pair + rear pair half-phase apart) with a flexing spine, head thrust,
		-- and a counter-swaying tail. Its limbs actually step, so it never glides.
		Monkey = table.freeze({
			RefSpeed = 16, -- studs/s at which the gait blend saturates
			SpeedSmoothing = 12, -- per-second lerp rate smoothing the measured ground speed
			WeightSmoothing = 9, -- per-second lerp rate blending move/chase weights
			MinMoveSpeed = 1.5, -- studs/s below which the rig is "idle" (breathing, gait frozen)
			StrideDistance = 3.4, -- studs of travel per gallop bound -> sets cadence
			ChaseStrideScale = 0.7, -- shorter, faster stride in a chase/investigate (frantic scramble)

			-- Torso bob for the ARTICULATED rig: the jointed LIMBS do the walking, so the
			-- torso only bobs/rocks subtly on top (a big whole-body arc would read as floating).
			GallopHeight = 0.32, -- studs the torso rises in mid-bound (subtle -- the legs push it)
			GallopChaseScale = 0.85, -- flatter, faster in a chase
			GallopSurge = 0.2, -- studs of forward torso lean through the bound
			GallopPitch = 0.18, -- rad spine rock (nose down on the gather, up on the leap)
			GallopRoll = 0.12, -- rad lateral roll, a loping shoulder-roll
			GallopHunch = 0.22, -- rad base forward hunch (deeper while hunting)

			-- The articulated mesh LIMBS (front pair leads, rear pair a half-cycle later).
			ArmSwing = 1.0, -- rad fore/aft swing of the front limbs (arms)
			LegSwing = 0.9, -- rad fore/aft swing of the rear limbs (legs)
			LimbDesync = 0.06, -- phase offset between L/R of a pair (organic)
			HeadBob = 0.16, -- rad head bob with the gait
			HeadThrust = 0.28, -- rad forward head thrust while hunting
			TailSway = 0.5, -- rad tail side-sway
			TailLash = 0.45, -- extra tail motion while hunting
			IdleBreathHz = 0.6, -- breaths/second when idle
			IdleBreathAmp = 0.07, -- studs of vertical breathing when idle
			IdleScanSpeed = 1.3, -- idle head-scan speed
			IdleScanAmp = 0.25, -- rad idle head-scan yaw amplitude
		}),
	}),
})

-- Noise: the monkey's prey signal -----------------------------------------------
-- Server-computed (by NoiseService) from each player's actual movement SPEED -- so it
-- is unspoofable (the server owns replicated position). Sprinting is loud; walking is
-- below the monkey's HearThreshold (0.45) so the default state is genuinely safe;
-- creeping is near-silent. Noise rises fast but decays slowly, so shedding the monkey
-- means COMMITTING to being quiet. The monkey hears effectiveNoise = NoiseLevel x
-- falloff(distance, HearRange). (No client->server remote: movement is already
-- server-known; this needs no new trusted input.)
Config.Noise = table.freeze({
	SprintSpeedRef = 22, -- studs/s at/above which you are "sprinting loud" (player SprintSpeed)
	WalkSpeedRef = 16, -- studs/s "walking" reference (player WalkSpeed)
	CreepSpeedRef = 6, -- studs/s below which you are creeping (near-silent)
	SprintNoise = 1.0, -- noise level at/above sprint speed
	WalkNoise = 0.35, -- noise at walk speed (BELOW HearThreshold 0.45 -> walking is safe)
	CreepNoise = 0.1, -- noise while creeping
	IdleNoise = 0.0, -- noise while still
	RisePerSecond = 4.0, -- NoiseLevel rises toward target fast (sprinting is immediately loud)
	DecayPerSecond = 1.3, -- and decays slowly (you must COMMIT to quiet to shed the monkey)

	-- HUD noise meter (NoiseMeterController) -- teaches the monkey's counter: a marker sits
	-- at the monkey's HearThreshold, so the player SEES when they cross into "audible".
	MeterWidth = 180, -- px
	MeterHeight = 14, -- px
	MeterMargin = 18, -- px from the screen corner (bottom-right, mirroring battery/stamina)
	MeterBackColor = Color3.fromRGB(25, 25, 30),
	MeterQuietColor = Color3.fromRGB(110, 200, 120), -- fill while inaudible (safe)
	MeterLoudColor = Color3.fromRGB(235, 70, 60), -- fill once over the threshold (the monkey hears you)
	MeterThresholdColor = Color3.fromRGB(240, 220, 120), -- the "audible" marker line
	MeterLabel = "NOISE",
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

-- Chase FX: the hunt as a visual event ------------------------------------------
-- Render-only client grade driven by the NEAREST monster that is actively hunting
-- (Chase/Investigate) and how close it is -- read from replicated rig State + position
-- (exploit-safe). The ChaseFXController desaturates + red-tints the screen, closes a
-- vignette, pulses with the threat, and flares that monster's eye-glow. A SEPARATE
-- ColorCorrection instance, so the static place grade is never corrupted.
Config.Chase = table.freeze({
	ThreatStartDistance = 48, -- studs: a hunting monster begins ramping the grade in
	ThreatMaxDistance = 9, -- studs: full intensity
	AlertScale = 0.45, -- threat multiplier when a monster is only Alert (heard you) -- a softer dread
	FadeRate = 4.5, -- per-second lerp toward the target intensity (smooth in AND out)

	Saturation = -0.5, -- ColorCorrection.Saturation at full threat
	TintColor = Color3.fromRGB(255, 125, 115), -- sickly red wash
	Contrast = 0.28, -- ColorCorrection.Contrast at full threat
	BrightnessDrop = -0.07, -- ColorCorrection.Brightness at full threat

	VignetteColor = Color3.fromRGB(22, 0, 0),
	VignetteThickness = 0.42, -- fraction of the screen each edge band spans
	VignetteMinTransparency = 0.18, -- most-opaque edge alpha at full threat

	PulseHz = 2.4, -- heartbeat pulse speed (Hz) at full threat
	PulseAmp = 0.14, -- how much the intensity pulses (fraction)

	EyeGlowBrightness = 4.0, -- a hunting monster's EyeGlow brightness at full threat (base ~0.7)
	EyeGlowRange = 13, -- ...and its range (base ~7)
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
