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
	DrainPerSecond = 0.5, -- gentler drain: ~200s of light (was a punishing 100s that left players blind)
	RechargePerSecond = 5, -- fast recharge while in a (server-gated) SafeRoom
	IdleRechargePerSecond = 2.5, -- passive recharge while the light is OFF (anywhere), so it NEVER permanently dies
	LowBatteryThreshold = 20, -- seconds remaining at/below which the light dims/flickers

	Range = 64, -- SpotLight.Range, studs
	Angle = 75, -- SpotLight.Angle, degrees (wide enough to actually navigate by)
	Brightness = 4, -- SpotLight.Brightness (a strong near-field that beats the fog + reads on dim iPad screens)

	ToggleKey = Enum.KeyCode.F, -- key that toggles the flashlight on/off
	LowBatteryFlickerSpeed = 14, -- flicker oscillation speed (rad/s) below the low-battery threshold
	LowBatteryMinBrightnessScale = 0.35, -- brightness floor (fraction of Brightness) while flickering
	Shadows = false, -- OFF for a reliable lit cone: SpotLight shadows only exist under Future, and
	-- under Future-on-mobile they darken/patch the beam -- a known "flashlight looks broken" cause.
	-- We run ShadowMap now (see Config.Environment.Technology), where this is a no-op anyway.

	-- Camera-aligned aiming: the beam tracks where you LOOK (incl. pitch up/down), not
	-- where the torso faces -- so the flashlight feels like an instrument you point.
	AimSmoothing = 20, -- per-second lerp rate the beam rotates toward the camera look (snappy but weighty)

	-- Monster-proximity flicker: a hunting monster nearby makes the beam stutter/dim --
	-- a fear beat AND a tell that something is hunting you. Render-only (reads replicated
	-- rig State + distance, exploit-safe). Set MonsterFlickerMaxScale = 0 to disable.
	MonsterFlickerStartDistance = 28, -- studs: only a CLOSE hunter stutters the beam (was too eager at 40)
	MonsterFlickerMaxScale = 0.28, -- max fraction of brightness the stutter can subtract: a fear beat, never a blackout
	MonsterFlickerSpeed = 27, -- rad/s of the stutter oscillation
})

-- Keys --------------------------------------------------------------------------
Config.Keys = table.freeze({
	RequiredToWin = 3, -- keys the player must hold to open the exit
	SpawnPerRound = 3, -- keys placed in the maze each round (random subset of KeySpot markers)
	NoSpawnNearStartRadius = 26, -- studs: keys never spawn this close to a PlayerStart, so you can't auto-collect one the instant you spawn (you must go FIND them)
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
	-- Distance to the ExitDoor that counts as "reaching" it. Measured to the door's
	-- closest SURFACE point (Spatial.distanceToPart), NOT its centre -- so a player
	-- pressed against the gate always triggers even if the door part is large/thick
	-- (the old centre-distance check left the win just out of reach behind the gate).
	ExitTriggerRadius = 9, -- studs from the door surface
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

-- Downed & revive (co-op: a catch becomes a RESCUE, not an instant respawn) -------
-- When a monster catches a player AND a teammate could possibly save them, they go
-- DOWNED — collapsed + immobilized + bleeding out — instead of dying. Any living
-- teammate who STAYS within ReviveRadius for ReviveSeconds revives them (spatial +
-- server-authoritative, no client input — the SafeRoom-occupancy pattern). Bleed out
-- with no rescue → the normal checkpoint respawn. SOLO, or a full wipe (no possible
-- rescuer), skips straight to that respawn — so single-player is UNCHANGED. The monster
-- ignores a downed player (it moves on; no camping the body — the anti-spawn-camp ethos).
Config.Downed = table.freeze({
	-- OFF by default: a catch is a RELIABLE instant respawn at your checkpoint (the proven
	-- path). Set to true to enable the co-op DOWNED/revive flow — best tested with 2+ players
	-- (a downed solo player with no possible rescuer just respawns either way). The downed
	-- code is fully fixed (it anchors the body in place rather than ragdolling, which used to
	-- clip players through the floor); it's gated only until the 2-player flow is playtested.
	Enabled = false,
	BleedoutSeconds = 18, -- seconds downed before you die/respawn if no one reaches you
	ReviveRadius = 7, -- studs a living teammate must be within to revive you
	ReviveSeconds = 3.5, -- seconds of a teammate staying close to complete the revive
	ReviveDecayScale = 1.5, -- revive progress drains at this × the fill rate when no rescuer is near
	ReviveGraceSeconds = 3, -- seconds of monster-ignore invulnerability right after a revive

	-- Downed/revive HUD (DownedController; render-only) ---------------------------
	OverlayColor = Color3.fromRGB(45, 0, 0), -- the downed-screen wash
	OverlayTransparency = 0.4,
	DownedText = "DOWNED",
	DownedSubText = "stay near a teammate to be revived",
	BleedoutBarColor = Color3.fromRGB(225, 60, 55), -- the shrinking time-left bar
	ReviveBarColor = Color3.fromRGB(120, 230, 130), -- the filling revive bar
	BarWidth = 280, -- px width of the downed-screen bars
	BarHeight = 14, -- px
	-- Revive beacon shown over a downed TEAMMATE (so others find + save you).
	BeaconText = "REVIVE",
	BeaconColor = Color3.fromRGB(120, 230, 130),
	BeaconHeight = 4.5, -- studs above the downed player's head
	BeaconWidth = 170, -- px width of the billboard
	BeaconHeightPx = 52, -- px height of the billboard
})

-- Exit gate (the maze's payoff: a real door that LOCKS until the keys are in) ------
-- The ExitDoor tag is the trigger VOLUME; the ExitGate tag is the SOLID part(s) that
-- physically block the corridor. ExitService keeps the gate shut + visibly LOCKED
-- (red indicator) until the team holds RequiredToWin keys (indicator -> green), then
-- slides it open when a player reaches it -- so escaping is a felt event, not a silent
-- attribute flip against a wall. The gate re-closes/re-locks on a round reset.
Config.Exit = table.freeze({
	OpenLiftStuds = 15, -- studs the gate slides UP (into the ceiling) when it opens -- clears a 14-tall doorway
	OpenSeconds = 1.1, -- seconds the open slide takes (a heavy door heave)
	-- Lock indicator: a PointLight ExitService parents to each gate. Red = locked,
	-- green = the team has every key (the door is now openable). It reads in the dark
	-- so players can SEE the exit state from down the corridor.
	IndicatorRange = 14, -- studs the indicator light reaches
	IndicatorBrightness = 2.2,
	LockedColor = Color3.fromRGB(220, 40, 40), -- red: not enough keys yet
	UnlockedColor = Color3.fromRGB(90, 230, 110), -- green: all keys in -- go!
	-- Door SFX (reuse a verified free Creator-Store id: the heavy thunk doubles as a heave).
	OpenSoundId = "rbxassetid://9120188626",
	OpenSoundVolume = 0.85,
})

-- Round loop --------------------------------------------------------------------
-- The game LOOPS (it used to be single-shot: keys spawned once, a win latched forever).
-- RoundService watches for a win (any player's GameState -> Won), holds a celebration,
-- then begins a fresh round via ServerSignals.RoundReset -- which re-randomizes the keys,
-- clears win/key/checkpoint state, respawns everyone at the start, and resets the monsters.
Config.Round = table.freeze({
	WinCelebrationSeconds = 5, -- hold after a win (> Win.FreezeDuration) before the next round begins
	ResetSettleSeconds = 1, -- guard window after a reset before another win can start a new round

	-- Pre-round PEACE window (the genre's calm->dread contrast: DOORS' safe early doors, Specter's
	-- peace timer). At each round start the monsters stay DORMANT -- they roam their territory but
	-- sense nothing -- so players orient and start the key-hunt in calm; then the hunt switches on.
	-- The threat being ABSENT for a beat is what makes its arrival land. 0 disables the window.
	PeaceSeconds = 20, -- seconds of calm at round start before the monsters begin hunting
})

-- Aggression: the maze gets HOTTER as you near the win -------------------------
-- Monster move speed + sense range scale up with how close ANY player is to winning
-- (best player's KeyCount / RequiredToWin, server-read -- no new state). A flat, encounter-
-- optional stroll becomes a tightening hunt, and going quiet vs the monkey gets harder the
-- closer you are to escaping. Applied in MonsterService (it owns monster behaviour).
Config.Aggression = table.freeze({
	Enabled = true,
	MaxSpeedBonus = 0.18, -- +18% monster WalkSpeed at full aggression (all keys collected)
	MaxRangeBonus = 0.35, -- +35% sight/hearing range at full aggression
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
		-- A wander target (the monkey's random nest-pace / investigate point) is normally only
		-- abandoned on ARRIVAL. But ~1 in 5 random points land inside a wall, which the rig can
		-- never reach to within WaypointReachedDistance -- so it would steer into the wall forever.
		-- Re-pick a wander target after this long without reaching it, breaking that wedge.
		WanderRepickSeconds = 4,
		StallEpsilon = 0.5, -- studs: movement below this in a tick counts as "not moving"
		StallTicks = 10, -- consecutive stalled ticks (with a target) that force a repath
		MaxTickDtFactor = 4, -- clamp a tick's dt to PollInterval*this so a hitch can't skip FSM timers
		-- Anti-spawn-camp (the root fix for "it kills you then camps the spawn").
		ResetToPatrolOnCatch = true, -- on a catch, clear the FSM and send the rig home off the kill site
		PostCatchDormantSeconds = 4, -- seconds after a catch the rig senses nothing -- overlaps the respawn window
		NoKeySpawnRadius = 30, -- studs: KeySpots within this of any MonsterSpawn are skipped (no key in its lap)

		-- Territory split (fixes BOTH "the two monsters shadow each other" AND "I never saw the
		-- monkey"). The two own DISTINCT halves of the map: the BUNNY roams the south DAYCARE
		-- (PatrolPoints 1-5), the MONKEY roams the north MAZE (its nest is the maze centre). Patrol
		-- nodes within this of ANY MonkeySpawn are dropped from the bunny's graph, so the bunny stays
		-- in the daycare and the whole maze belongs to the monkey -- which the player traverses to
		-- reach the keys + exit, so the monkey is now ENCOUNTERED during the run (not camped at the
		-- far exit). Sized to drop the 4 maze PatrolPoints (Z>=94) while keeping the 5 daycare ones.
		NestExclusionRadius = 75, -- studs around a MonkeySpawn the bunny's patrol graph excludes
		-- Patrol variety: the bunny picks RANDOMLY among the N nearest unvisited nodes rather than
		-- always the single nearest, so its route varies round to round (the fix for "it patrols
		-- the exact same spots"). 1 = the old deterministic nearest-node tour.
		PatrolNodeChoices = 3,

		-- World-noise events (a sprung trap, etc., via ServerSignals.NoiseEvent): a HEARING rig
		-- (the monkey) within this range of the event investigates it -- so a careless trap-trip
		-- actively summons the near-blind hunter (traps + the noise monkey become one system). The
		-- event is delivered to each eligible rig ONCE; this is how long after it fires it stays
		-- "hearable" (covers the poll cadence + a little slack). The deaf bunny never reacts.
		NoiseEventReactSeconds = 1.5, -- seconds a fired noise event remains sensable

		-- Mutual exclusion (the fix for the genre's cheapest death: two lethal chasers converging on
		-- one player with no escape). If BOTH monsters are actively hunting the SAME player, the one
		-- FARTHER from them peels off (FSM reset + brief dormancy) so only one lethal chaser presses
		-- at a time. With the monkey guarding the exit and the bunny driving you there, this keeps the
		-- climax fair (the bunny backs off, the monkey takes the hand-off).
		MutualExclusion = true,
		CoopPeelSeconds = 2.5, -- seconds the peeled-off rig disengages before it may re-acquire

		-- Bloodlust (DbD's anti-stall): a SINGLE unbroken chase that drags on past DelaySeconds ramps
		-- the chaser's speed so you cannot circle one pillar forever -- but it RESETS the instant the
		-- chase ends (catch, or losing the target), so the OPENING of every chase stays fair. Separate
		-- from Config.Aggression (which ramps with key-progress, not chase duration).
		Bloodlust = table.freeze({
			Enabled = true,
			DelaySeconds = 12, -- a chase must exceed this before the ramp starts
			RampSeconds = 10, -- ...then climbs to the max bonus over this many more seconds
			MaxSpeedBonus = 0.25, -- +25% chaser WalkSpeed at full bloodlust
		}),
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
			PatrolMemory = 4, -- patrol nodes remembered as "recently visited" so it tours widely, not ping-pongs (raised from 2 with the wider PatrolNodeChoices so routes vary)

			-- Rig: the corrupted-mascot mesh (ServerStorage.Assets.<BodyAssetName>). It looms
			-- taller than the collision box on purpose; pathfinding uses BodySize +
			-- Shared.AgentRadius, so movement is unchanged.
			BodySize = Vector3.new(2.5, 3.5, 2.5), -- physics-root (collision box) dimensions
			BodyColor = Color3.fromRGB(220, 218, 225), -- fallback rig tone (pale, faintly sickly)
			BodyMaterial = Enum.Material.Fabric, -- matted plush (the primitive fallback that a no-assets build renders)
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
			NestWanderRadius = 40, -- studs it ROAMS around its MonkeySpawn (the maze centre) while patrolling
			-- (wide enough to range the whole maze body so the player encounters it -- pathfinding +
			-- WanderRepickSeconds handle the random points that land in walls; the bunny owns the daycare)
			InvestigateJitter = 6, -- studs of random lateral weave per repath (slightly dodgeable)
			CatchRadius = 5, -- distance that counts as a catch (instant)
			PatrolMemory = 2, -- patrol nodes remembered as "recently visited"
			RepathInterval = 0.35, -- override Shared: repath faster so the weave stays responsive

			-- Rig (no mesh yet -> a primitive proxy until Phase 5 builds an articulated body).
			BodySize = Vector3.new(2.5, 3.5, 2.5), -- <= bunny so corridor fit is identical (do NOT exceed)
			BodyColor = Color3.fromRGB(60, 48, 44), -- dark/matted: a distinct silhouette from the pale bunny
			BodyMaterial = Enum.Material.Concrete, -- rough matte hide (the primitive fallback a no-assets build renders)
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
			HopHeight = 0.85, -- studs the TORSO arcs up at a full lunge hop (legs carry the rest)
			WalkArcScale = 0.3, -- patrol body arc as a fraction of the hop (a low creep, not a hop)
			WalkLegScale = 0.55, -- patrol leg-swing amplitude (alternating walk) vs the full hop extend
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
	MaxPlausibleSpeed = 80, -- studs/s above which a position delta is a TELEPORT (respawn jump),
	-- not real running -- such a tick is ignored for noise so a respawn can't spike NoiseLevel.

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

-- Noise DECOY: noise as a WEAPON, not just a liability (the Granny lesson) ----------
-- The monkey is the near-blind NOISE hunter; the decoy lets you USE that against it. Throw a
-- rattling noisemaker ahead of you -> it lands + fires ServerSignals.NoiseEvent there -> the
-- monkey investigates the WRONG spot, and you slip past. Server-authoritative: the client sends
-- only intent (no payload), the server computes the landing point from the player's OWN known
-- position+facing (never a client-supplied position) and clamps it to the first wall, so it can't
-- be aimed through geometry or spoofed. A cooldown stops spam. Only the deaf bunny ignores it.
Config.Decoy = table.freeze({
	ThrowKey = Enum.KeyCode.Q, -- toss a decoy
	ThrowDistance = 42, -- studs ahead the decoy lands (clamped to the first wall along the throw)
	Cooldown = 8, -- seconds between throws (server-authoritative)
	IntentRateLimit = 0.25, -- min seconds between accepted ThrowDecoy messages (anti-spam, hostile input)
	WallPadding = 2.5, -- studs short of a hit wall the decoy lands (so it never lands inside geometry)
	-- The monkey re-homes on each pulse, so a few spaced pulses keep it drawn to the spot while the
	-- decoy rattles (each NoiseEvent is a fresh one-shot the monkey investigates).
	NoisePulses = 3,
	PulseInterval = 0.45, -- seconds between pulses
	LifeSeconds = 2.0, -- the decoy part rattles this long, then despawns

	-- The decoy part (a small rattling noisemaker, server-spawned so all clients see/hear it).
	Size = Vector3.new(0.8, 0.8, 0.8),
	Color = Color3.fromRGB(220, 210, 120),
	Material = Enum.Material.Metal,
	LightColor = Color3.fromRGB(255, 240, 150),
	LightBrightness = 2.0,
	LightRange = 12,
	RattleSoundId = "rbxassetid://9119717523", -- the verified mechanical-click id (a rattling tick)
	RattleVolume = 0.7,
	RattleRange = 70, -- studs RollOffMaxDistance (it should read from a distance -- that's the point)

	-- On-screen touch button (mobile), stacked above the RUN/LIGHT buttons.
	TouchBottomOffset = 370, -- px from the bottom (above LIGHT at 250)
	ButtonColor = Color3.fromRGB(220, 210, 120),
	Label = "DECOY",
})

-- Traps: telegraphed hazards -----------------------------------------------------
-- Server-authoritative floor traps (spatial, never Touched). Each is FAIR: an always-
-- visible red arrow + faint glow telegraphs it, and entering it starts a short wind-up
-- (the arrow flashes + clicks) so an attentive player can back off before it fires. A
-- sprung trap kills (Health=0 -> the normal checkpoint respawn) AND spikes your noise,
-- so even surviving one can draw the monkey. The counter is simply: watch the floor.
Config.Traps = table.freeze({
	TriggerRadius = 4.5, -- studs: entering this of a Trap marker begins the wind-up
	WindupSeconds = 1.2, -- the reaction window: long enough to SEE the flash and step off in time (was a too-fast 0.55)
	RearmSeconds = 3, -- seconds after firing/disarming before the trap can trigger again
	NoiseOnTrigger = 1.0, -- spikes the victim's NoiseLevel when it fires (a sprung trap is LOUD)

	-- Traps as a CHASE TOOL (the fix for "traps aren't part of anything"): an armed trap also
	-- springs on a HUNTING monster that runs over it -- INSTANTLY (no telegraph; a monster doesn't
	-- read warnings) -- freezing it so a chased player can bait a pursuer across one to escape. A
	-- monster trip mid-windup also SPARES the player (the trap fires on the monster instead). Only
	-- a hunting rig trips it, so a monster pacing its nest never stuns itself on a nearby trap.
	MonsterTriggerRadius = 5, -- studs: a hunting rig within this of an armed trap springs it
	MonsterStunSeconds = 2.6, -- seconds the tripped monster stands frozen (a real escape window)

	-- Telegraph (always-visible, built into the placed marker): a red arrow + faint glow.
	ArrowColor = Color3.fromRGB(190, 30, 30),
	ArrowFlashColor = Color3.fromRGB(255, 70, 60), -- the brighter flash during wind-up
	GlowColor = Color3.fromRGB(255, 45, 40),
	GlowBrightness = 1.6, -- clearly visible danger glow (TrapService ensures it on each trap on boot)
	GlowRange = 14,
	GlowPulseHz = 1.6, -- the glow gently pulses so a trap reads as "alive / dangerous", not decoration
	GlowPulseDepth = 0.4, -- fraction of brightness the pulse dips (0..1)

	-- Fire effect (client renders a dart streaking along the arrow + an impact flash).
	DartColor = Color3.fromRGB(200, 200, 210),
	DartLength = 6, -- studs of the dart streak
	DartSpeed = 130, -- studs/s the dart visual travels across the corridor

	-- Audio (reuse the already-verified free Creator-Store sound ids).
	ClickId = "rbxassetid://9119717523", -- mechanical click on wind-up
	FireId = "rbxassetid://9120188626", -- a hard thunk on fire
	FireVolume = 0.8,
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

-- Environment / atmosphere (the mood foundation, reproduced FROM CODE) ------------
-- The whole horror mood (lighting model, darkness, fog, post-FX, base grade) used to
-- live only in unsaved Studio place content, so a fresh `rojo build` rendered flat,
-- bright, and fogless and the flashlight/monster shadows silently no-op'd. This section
-- + EnvironmentService rebuild it deterministically on boot: dark, foggy, contrasty,
-- with real-time shadows on (so the flashlight throws a creature's shadow up the wall
-- before you see it). Tune the dread here; nothing about it is in the place anymore.
Config.Environment = table.freeze({
	-- Core Lighting. Future tech is what makes the flashlight + monster shadows real
	-- (it IS script-writable). ClockTime 0 = midnight; the practical flicker fixtures
	-- and your flashlight are the only real light, which is the point.
	-- ShadowMap (NOT Future): Future falls back below graphics-quality 5 on mobile/iPad, where
	-- the flashlight SpotLight goes dim/blocky or the scene washes out -- the #1 reason the
	-- flashlight "doesn't work" + the map reads wrong on iPad. ShadowMap lights SpotLights
	-- dependably at every tier and is faster on mobile (tradeoff: the flashlight no longer
	-- casts a real-time monster shadow -- a gimmick we trade for mobile playability).
	Technology = Enum.Technology.ShadowMap,
	ClockTime = 0, -- midnight
	GeographicLatitude = 0,
	-- Dark + moody but NAVIGABLE on mobile: carry baseline visibility on flat AMBIENT (which
	-- the mobile quality scaler can't strip), keep ExposureCompensation at 0 (never negative --
	-- it crushes blacks into mush on cheap panels), and keep fog thin so the flashlight reaches.
	Brightness = 3.4, -- sun/moon fill (a moonlit interior you can clearly navigate)
	ExposureCompensation = 0, -- never negative on mobile
	Ambient = Color3.fromRGB(78, 80, 92), -- clearly navigable: walls/corridors read even with the light off (lifted hard after repeated "too dark")
	OutdoorAmbient = Color3.fromRGB(72, 74, 88), -- skylight fill (cool, dim but visible)
	EnvironmentDiffuseScale = 0.5, -- ambient bounce (helps PC; near-inert at midnight, not the floor)
	EnvironmentSpecularScale = 0.25,
	GlobalShadows = true,
	ShadowSoftness = 0.5,

	-- Atmosphere (the modern volumetric haze; supersedes legacy Fog under Future).
	Atmosphere = table.freeze({
		Density = 0.22, -- thin: density darkens AND eats flashlight reach -- the top "can't see the next corner" culprit
		Offset = 0.1,
		Color = Color3.fromRGB(150, 150, 162), -- cool grey air
		Decay = Color3.fromRGB(70, 70, 85), -- the colour haze decays toward
		Glare = 0.05,
		Haze = 1.0, -- less milky wash, more silhouette contrast
	}),

	-- Bloom: only genuinely bright things bleed (eye-glow, neon keys, flicker tubes),
	-- so light sources read as menacing in the dark rather than washing the scene.
	Bloom = table.freeze({
		Intensity = 0.7,
		Size = 24,
		Threshold = 1.05,
	}),

	-- Depth of field: subtle cinematic fall-off so the far dark reads as depth.
	DepthOfField = table.freeze({
		FarIntensity = 0.12,
		FocusDistance = 28,
		InFocusRadius = 22,
		NearIntensity = 0.1,
	}),

	-- Base colour grade (a SEPARATE ColorCorrection named "BaseGrade"; the client's
	-- ChaseFX grade composes ON TOP of it, so the chase wash never corrupts this).
	BaseGrade = table.freeze({
		Brightness = -0.02,
		Contrast = 0.14,
		Saturation = -0.2, -- drained, sickly
		TintColor = Color3.fromRGB(206, 212, 224), -- a cold cast
	}),
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

	-- Sprint FOV kick (CLIENT cosmetic only -- SprintFXController). The camera FOV widens
	-- as you actually sprint, the chase-juice staple that makes a server-authoritative
	-- sprint FEEL immediate and fast (it reads real ground speed, so it never lies when
	-- you're out of stamina or wedged on a wall). Uncontested + render-only (CLAUDE.md OK).
	SprintFovKick = 12, -- degrees added to the base FOV at full sprint speed
	SprintFovSmoothing = 8, -- per-second lerp rate the FOV eases toward its target (snappy but not jarring)
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
	ControlsHint = "WASD Move    F Flashlight    Shift Sprint    Q Decoy",
	ControlsHintSeconds = 9, -- how long the controls hint shows (or until first move)
	ObjectiveLabel = "KEYS", -- "KEYS 0/3"
	ObjectiveExitText = "ALL KEYS — REACH THE EXIT", -- objective tracker once keys are done

	-- Just-in-time tips (TutorialController): each shown ONCE, the first time you actually
	-- face that threat, so the COUNTER is taught in the moment rather than in an up-front wall
	-- of text (Roblox's own FTUE guidance). Driven by the MonsterStateChanged remote.
	ChaseTip = "RUN!  Hold Shift to sprint and break line of sight",
	AlertTip = "It HEARD you — move quietly, or throw a DECOY (Q) to send it the wrong way",
	-- Shown the first time you approach a floor trap, BEFORE you can step on it blind. Teaches
	-- BOTH halves of the new trap design: avoid them yourself, but bait a chasing monster across one.
	TrapTip = "⚠ Glowing RED floor marks are TRAPS — avoid them, but lure a chasing monster onto one",
	TrapTipRadius = 16, -- studs: a trap within this (first time) triggers the warning tip
	TipSeconds = 5, -- how long a tip holds before fading
})

-- On-screen touch controls (mobile / iPad) --------------------------------------
-- Custom, clearly-visible buttons (bigger + more legible than the default
-- ContextActionService auto-buttons). Each owning controller builds its own button at
-- these coordinates, shown ONLY on touch devices; the keyboard keys still work on PC.
-- They stack bottom-RIGHT above Roblox's built-in jump button without overlapping it or the
-- movement thumbstick (bottom-left). Drop a real icon into `*IconImage` later.
Config.TouchControls = table.freeze({
	ButtonSize = 100, -- px square tap target
	EdgeMargin = 26, -- px from the right edge
	FlashlightBottomOffset = 250, -- px from the bottom (sits above the jump button)
	SprintBottomOffset = 130, -- px from the bottom (closest to the thumb, below the flashlight)
	BackgroundColor = Color3.fromRGB(18, 20, 26),
	BackgroundTransparency = 0.3,
	TextColor = Color3.fromRGB(245, 240, 230),
	TextSize = 19,
	FlashlightOnColor = Color3.fromRGB(245, 222, 120), -- ring tint while the light is ON
	FlashlightOffColor = Color3.fromRGB(140, 142, 150), -- ...and while OFF
	FlashlightLabel = "LIGHT",
	FlashlightIconImage = "", -- TODO: a flashlight icon asset id
	SprintColor = Color3.fromRGB(150, 220, 165),
	SprintLabel = "RUN",
	SprintIconImage = "", -- TODO: a run icon asset id
})

-- Monster radar (a SWEEPING sonar -- you get periodic, decaying pings, not a live feed) ----
-- The old radar showed both monsters' EXACT live positions every frame, so you always knew
-- where they were -- it killed the fear of the unknown. Now it's a rotating sonar SWEEP: a
-- monster's blip is only refreshed when the sweep line passes its bearing, then it FADES, so
-- between pings you see a stale "last known" mark -- a fast hunter's blip lags behind where it
-- actually is. A calm (patrolling/searching) monster pings FAINT and fades FAST (a fleeting
-- ghost you can't track); only a HUNTING monster pings bright and lingers long enough to read.
-- Still reads each rig's replicated HRP + State (exploit-safe; no server trust). Render-only.
Config.Radar = table.freeze({
	Size = 156, -- px diameter of the radar disc
	Margin = 20, -- px from the top-right corner
	Range = 130, -- studs: a monster at/beyond this sits on the radar's edge (and out of sweep range)
	BackgroundColor = Color3.fromRGB(10, 12, 16),
	BackgroundTransparency = 0.35,
	RingColor = Color3.fromRGB(70, 80, 95),
	PlayerColor = Color3.fromRGB(150, 220, 255), -- the center dot (you)
	BlipSize = 16, -- px (a hunting monster's blip; patrolling ones are drawn smaller)
	-- Blips are tinted by SPECIES (mirroring each monster's eye-glow tell) so you can tell the
	-- two apart, and made prominent by THREAT.
	BunnyBlipColor = Color3.fromRGB(210, 40, 40), -- the vision stalker (red eyes)
	MonkeyBlipColor = Color3.fromRGB(250, 210, 60), -- the noise hunter (yellow eyes)
	UnknownBlipColor = Color3.fromRGB(200, 200, 200),
	IdleSizeScale = 0.7, -- patrolling blips are this fraction of BlipSize
	Label = "SONAR",

	-- Sweep: a line rotates the dish; a blip only refreshes ("pings") as the line crosses it.
	SweepSeconds = 3.2, -- seconds for one full rotation of the sweep line
	SweepColor = Color3.fromRGB(120, 230, 150), -- the sonar sweep arm (sickly green)
	SweepArmTransparency = 0.25, -- the sweep arm's opacity
	-- A freshly pinged blip starts opaque and fades over its species' memory window. A HUNTING
	-- monster lingers (you can roughly track it); a calm one fades before the next sweep (a ghost).
	HuntFadeSeconds = 2.8, -- a hunting monster's blip fades over this (≈ most of a sweep -> trackable)
	IdleFadeSeconds = 1.1, -- a patrolling/searching monster's blip fades fast (a fleeting contact)
	MinPingTransparency = 0.0, -- alpha a blip is at the instant it's pinged (then decays to 1 = gone)

	-- CHARGE cycle (the fix for "the radar is too easy -- you can ALWAYS see them"). The sonar is
	-- NOT always on: it runs on a charge that drains while sweeping and refills while dark, so you
	-- get an ACTIVE window then a BLIND window -- you must time your glances and survive the gaps
	-- on your own senses. A charge ring + "RECHARGING" label tells you which phase you're in.
	ActiveSeconds = 9, -- seconds the sonar sweeps on a full charge before it depletes
	RechargeSeconds = 7, -- seconds it stays DARK (no blips) recharging from empty back to full
	ChargeReadyFraction = 1.0, -- must recharge fully (1.0) before it reactivates (no flickering on/off)
	DepletedColor = Color3.fromRGB(120, 70, 70), -- the ring/label tint while recharging (dim red)
	RechargingLabel = "RECHARGING",
})

-- Economy: end-of-round coin payout (the retention loop) --------------------------
-- A run is NEVER worth zero -- you always bank the floor + per-key progress + capped
-- survival, even on a loss. Escaping is the jackpot. Read by the pure Progression.computeAward.
Config.Economy = table.freeze({
	ParticipationFloor = 5, -- coins just for playing the round
	KeyReward = 10, -- coins per key the team held at round end
	EscapeBonus = 50, -- coins for reaching the exit
	SurvivalPerSecond = 0.25, -- coins per second survived...
	SurvivalCap = 240, -- ...capped at this many seconds (so camping isn't farmed)
	ShopActionRateLimit = 0.2, -- min seconds between accepted ShopAction messages (anti-spam, hostile input)
})

-- Persistence: DataStore tuning (DataService is the only DataStore toucher) --------
-- Coins + owned/equipped cosmetics persist per player. DataStore needs Studio's
-- "Enable Studio Access to API Services" on a PUBLISHED experience to work in Studio;
-- with it off, DataService degrades to in-memory only (the game still plays, just no save).
Config.Persistence = table.freeze({
	DataStoreName = "PlayerData_v1", -- bump the suffix to wipe/migrate; never silently change the schema under v1
	AutosaveInterval = 120, -- seconds between background saves of dirty profiles
	MaxRetries = 4, -- DataStore call retries on failure...
	RetryBaseDelay = 1, -- ...with exponential backoff starting here (seconds)
	SessionLockStaleSeconds = 1200, -- a session lock older than this is treated as abandoned (crash recovery)
	BindToCloseBudgetSeconds = 25, -- max seconds to spend flushing saves on server shutdown
})

-- Feedback: legible event messaging (toasts + win/caught copy) --------------------
Config.Feedback = table.freeze({
	KeyToastSeconds = 2.0, -- "KEY 1/3" toast hold time
	LockedToastSeconds = 2.5, -- "EXIT LOCKED" toast hold time
	ToastColor = Color3.fromRGB(240, 230, 210),
	CaughtText = "CAUGHT!",
	CaughtColor = Color3.fromRGB(220, 60, 55),
	LockedTextPrefix = "EXIT LOCKED", -- shown with the live count: "EXIT LOCKED — 3 KEYS NEEDED"
	-- Shown to OTHER players (not the escapee) when someone reaches the exit and the shared
	-- round is about to reset -- so a co-op escape reads as an event, not a silent yank.
	EscapedSuffix = "ESCAPED!", -- composed with the escapee's name: "Steve ESCAPED!"
	EscapedColor = Color3.fromRGB(120, 230, 130),
	EscapedToastSeconds = 3.0,
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
		-- Dread ramp: each drift-in starts at a random point in the (long) clip, with a slight
		-- detune wobble (a haunted, winding-down box) and a fade-out instead of a hard stop.
		MusicBoxStartRange = 30, -- max random TimePosition (s) the clip starts from
		MusicBoxPitchWobble = 0.06, -- +/- PlaybackSpeed wobble (a detuning music box)
		MusicBoxWobbleHz = 0.4, -- Hz of the detune wobble
		MusicBoxFadeSeconds = 1.5, -- fade-out time when a drift-in ends (vs an abrupt Stop)
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
		-- The heartbeat is gated by the nearest rig's STATE (see MonsterAudioController): it
		-- ramps full only when a monster is HUNTING you (Chase/Investigate), softer when it
		-- merely heard you (Alert, scaled by Config.Chase.AlertScale), and stays silent for a
		-- patrolling/searching monster UNLESS it is right on top of you (this panic radius) --
		-- so the heartbeat MEANS "it is hunting you", not "a monster exists somewhere".
		HeartbeatPanicRadius = 10, -- studs: a non-hunting rig within this still spikes the pulse

		-- Per-species voice: same verified clips, but pitched/levelled so the two monsters
		-- sound distinct by ear (the bunny lighter + higher, the monkey heavier + lower).
		SpeciesMix = table.freeze({
			Bunny = table.freeze({ Pitch = 1.12, VolumeScale = 0.9 }),
			Monkey = table.freeze({ Pitch = 0.82, VolumeScale = 1.12 }),
		}),

		-- Wall occlusion: a rig behind geometry is muffled (low-pass) and quieter, so "it's
		-- close but WHERE" tension returns. One throttled ray (player -> rig) decides LoS.
		Occlusion = table.freeze({
			Interval = 0.2, -- seconds between occlusion raycasts per rig (throttled)
			VolumeScale = 0.45, -- volume multiplier while occluded
			HighGain = -26, -- EqualizerSoundEffect HighGain (dB) while occluded (muffled highs)
			MidGain = -9, -- ...mid attenuation
			LowGain = 0, -- lows pass (a dull thud through the wall)
		}),
	}),

	-- Adaptive TENSION bed on the Music bus: silent when safe, swelling as a monster HUNTS
	-- you (driven by the same replicated rig State + distance the heartbeat reads), so the
	-- score builds with the threat. Reuses the verified dread-drone asset, pitched low.
	-- (Crossfaded by MonsterAudioController; the win jingle is the only other Music cue.)
	Music = table.freeze({
		TensionId = "rbxassetid://140704980462451", -- the dread drone, pitched down into a tension layer
		TensionMaxVolume = 0.55, -- volume at full threat
		TensionPitch = 0.7, -- pitched down for dread
		FadeRate = 2.5, -- per-second lerp of the tension volume toward the threat target
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
		-- The low-battery beep QUICKENS as the battery empties (an audible countdown to dark),
		-- then sounds once pitched-down when it hits zero (the light "dies"). Reuses the beep id.
		LowBatteryBeepMaxInterval = 2.2, -- seconds between beeps at the low-battery threshold
		LowBatteryBeepMinInterval = 0.45, -- ...shrinking to this as the battery nears empty
		LightDiesPitch = 0.6, -- PlaybackSpeed of the final beep when the battery reaches zero
		-- Footstep loudness tracks the movement TIER, so your ears confirm the NoiseMeter:
		-- sprinting is loud, walking normal, creeping near-silent.
		FootstepCreepSpeed = 6, -- studs/s below which steps are near-silent
		FootstepSprintSpeed = 22, -- studs/s at/above which steps are loudest
		FootstepCreepVolumeScale = 0.35, -- volume multiplier while creeping
		FootstepSprintVolumeScale = 1.6, -- volume multiplier while sprinting
	}),

	-- One-shot event stingers wired to the EXISTING remotes.
	Stingers = table.freeze({
		KeyChimeId = "rbxassetid://7381723941", -- KeyCollected (UI bus)
		KeyChimeVolume = 0.6,
		LockedThunkId = "rbxassetid://9120188626", -- ExitLocked (SFX bus)
		LockedThunkVolume = 0.65,
		WinJingleId = "rbxassetid://9041792228", -- GameWon (Music bus)
		WinJingleVolume = 0.75,
		HuntBeginsId = "rbxassetid://1841353932", -- HuntBegins: the peace window ended (reuses the verified chase-sting id; Monster bus)
		HuntBeginsVolume = 0.7,
		JumpscareId = "rbxassetid://139306955269282", -- MonsterCaught (full-volume, ducks others)
		JumpscareVolume = 1.0,
	}),
})

return table.freeze(Config)
