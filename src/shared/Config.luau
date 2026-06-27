--!strict
-- Config.luau
-- THE single source of truth for every tunable number in the game. No magic
-- numbers may live anywhere else -- logic AND ui read from here. Sections are
-- namespaced tables so future systems (monsters, audio) slot in cleanly. Every
-- table is frozen: Config is read-only at runtime.

local Config = {}

-- Font resolution ----------------------------------------------------------------
-- The UI theme (Config.UI below) wants modern faces (Builder Sans, Creepster) that may not
-- exist on every engine/client. Indexing a missing Enum.Font member THROWS, which -- in a frozen,
-- load-time Config -- would brick the entire game. So resolve fonts by NAME against the live
-- Enum.Font set and fall back cleanly when a face is unavailable. Built once here, at load.
local fontByName: { [string]: EnumItem } = {}
for _, item in Enum.Font:GetEnumItems() do
	fontByName[item.Name] = item
end
local function uiFont(name: string, fallback: EnumItem): EnumItem
	return fontByName[name] or fallback
end

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
	GamepadToggleKey = Enum.KeyCode.ButtonY, -- gamepad button that toggles the flashlight (bound alongside ToggleKey)
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

	-- Volumetric beam SHAFT (render-only, client): a faint cone of light riding the SpotLight, so
	-- sweeping the flashlight reads as a physical shaft cutting the dark (together with the dust motes
	-- AtmosphereFX adds). Built as a Beam on the emitter (FaceCamera), so it always presents to the
	-- viewer. Kept deliberately SUBTLE -- a hint of volume, never a solid bar of light. Enabled=false
	-- removes it entirely (e.g. if a device renders beams poorly).
	Beam = table.freeze({
		Enabled = true,
		Length = 24, -- studs the shaft reaches (< Range so it fades out before the lit pool ends)
		WidthNear = 0.6, -- studs wide at the lens...
		WidthFar = 9, -- ...flaring to this at the far end (a soft cone)
		Color = Color3.fromRGB(228, 234, 245), -- cool white, matched to the beam
		Transparency = 0.9, -- VERY faint at the lens (it fades to fully clear at the far end)
		Brightness = 0.5, -- Beam.Brightness (additive glow); kept low so it never washes the scene
	}),
})

-- Keys --------------------------------------------------------------------------
Config.Keys = table.freeze({
	RequiredToWin = 3, -- keys the player must hold to open the exit
	SpawnPerRound = 3, -- keys placed in the maze each round (random subset of KeySpot markers)
	NoSpawnNearStartRadius = 26, -- studs: keys never spawn this close to a PlayerStart, so you can't auto-collect one the instant you spawn (you must go FIND them)
	-- OPTIONAL bonus keys (gold): spawned at the NEXT unused KeySpots after the required ones (the
	-- farther, more dangerous spots), NOT required to win + NOT beaconed by the compass -- a pure
	-- risk/reward detour worth round-end coins. 0 disables them. They never reduce required-key spots.
	BonusSpawnPerRound = 2,

	-- STAKES (off by default -- a balance change to validate in a real playtest, like Config.Downed):
	-- when a player is KILLED by a monster (the normal catch path, NOT the co-op downed revive), the
	-- team's most-recently-gained key drops back into the maze -- so a catch costs real objective
	-- progress and the hunt finally has a consequence (fear needs stakes). It never drops below 0, and
	-- the re-spawned key goes to a far unused KeySpot. KeyService reacts to ServerSignals.PlayerKilled.
	DropOnCatch = false, -- true = a kill decrements the team key count + re-spawns one required key
})

-- Key model (the collectible's placeholder visuals) -----------------------------
-- A glowing, ominous floating part. No asset IDs here -- swap in a real
-- model/mesh later. Pickup radius lives in Config.Spatial.KeyPickupRadius.
Config.KeyModel = table.freeze({
	Size = Vector3.new(1.6, 2.6, 0.5), -- studs
	Color = Color3.fromRGB(64, 74, 58), -- desaturated, sickly
	LightColor = Color3.fromRGB(125, 205, 95), -- eerie glow
	-- Bonus keys reuse this whole model but recoloured GOLD, so they read as clearly DIFFERENT from the
	-- green required keys (treasure you may grab, not an objective you must). KeyService applies these.
	BonusColor = Color3.fromRGB(120, 96, 36), -- desaturated old-gold body
	BonusLightColor = Color3.fromRGB(255, 205, 90), -- warm gold glow
	BonusSparkleColor = Color3.fromRGB(255, 220, 130),
	LightBrightness = 7, -- brighter so a key is a clear beacon down a dark corridor (was a faint 5)
	LightRange = 20,
	HoverHeight = 3, -- studs above the KeySpot marker
	SpinSpeed = 1.1, -- rad/s the floating key slowly rotates (draws the eye)
	-- A gentle vertical BOB on top of the spin, so the key FLOATS like a live, magical object (an
	-- inert spinning part reads as scenery; a bobbing one reads as "pick me up"). KeyService applies it.
	BobHeight = 0.45, -- studs the key rises/falls
	BobSpeed = 2.2, -- rad/s of the bob cycle

	-- Sparkle: a few slow motes glinting off the key so it reads as TREASURE down a dark
	-- corridor (server-built ParticleEmitter, so it replicates -- the whole lobby sees it).
	SparkleTexture = "rbxasset://textures/particles/sparkles_main.dds", -- built-in (no upload)
	SparkleColor = Color3.fromRGB(175, 240, 135), -- echoes the key's green glow
	SparkleRate = 11, -- motes/second (more glint so it reads as treasure)
	SparkleSize = 0.55, -- studs
	SparkleLifetime = 1.3, -- seconds
	SparkleSpeed = 1.5, -- studs/s upward drift
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
	Enabled = true, -- co-op DOWNED/revive ON (was false). A NO-OP for SOLO play (no possible rescuer -> the unchanged kill->checkpoint path), and the best co-op beat for kids together. Balance-sensitive; tune the mercy values below.
	BleedoutSeconds = 12, -- seconds downed before you die/respawn if no one reaches you (was 18; a shorter frozen wait for a young player when no friend is coming)
	ReviveRadius = 8, -- studs a living teammate must be within to revive you (was 7; touch players position imprecisely)
	ReviveSeconds = 3, -- seconds of a teammate staying close to complete the revive (was 3.5; less time the rescuer is exposed in the danger zone)
	ReviveDecayScale = 1.5, -- revive progress drains at this × the fill rate when no rescuer is near
	ReviveGraceSeconds = 3, -- seconds of monster-ignore invulnerability right after a revive
	MaxTickDtFactor = 4, -- clamp the revive/decay poll's dt to PollInterval*this so a server hitch (e.g. a ComputeAsync stall) can't snap revive progress past its threshold in one tick (mirrors Noise / Monster.Shared)

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

-- Runtime maze randomization (the replayability lever) ---------------------------
-- A different maze layout every round so it can't be memorized. SAFE approach (avoids a confirmed
-- unfixed Roblox navmesh bug where DESTROYED parts leave phantom navmesh): a permanent wall
-- SUPERSTRUCTURE -- one anchored wall per potential interior edge -- where "open" SLIDES the wall
-- down into a well below the floor (+ CanCollide off) and "closed" raises it. Moving anchored parts
-- re-rasterizes the navmesh reliably; destroying/creating them is the buggy path. MazeService builds
-- the superstructure FROM CODE (reproducible) and carves a fresh spanning tree (Maze.generate) each
-- round; markers sit at CELL CENTRES (always open floor), so nothing is ever walled in. The grid:
-- Cols x Rows cells of CellSize, SW corner at (OriginX, OriginZ); cell (c,r) centre =
-- (OriginX + CellSize*c + CellSize/2, OriginZ + CellSize*r + CellSize/2). The exit alcove + gate sit
-- NORTH of the grid at ExitCol; the daycare doorway is the south-perimeter gap at EntranceCol.
Config.Maze = table.freeze({
	Enabled = true, -- master switch (false = keep a single static layout)

	-- Grid (matches the existing maze footprint: floor X[-60..60], interior rows up to the exit alcove).
	Cols = 10,
	Rows = 9,
	CellSize = 12, -- studs per cell (the existing grid)
	OriginX = -60, -- world X of the west edge of column 0
	OriginZ = 64, -- world Z of the south edge of row 0
	FloorY = 0, -- top surface of the maze floor (walls stand on it)

	-- Wall superstructure.
	WallThickness = 2,
	WallHeight = 14, -- floor-to-ceiling (matches the perimeter walls)
	WellDepth = 20, -- studs an OPEN wall slides DOWN (its top ends well below the floor, hidden)
	WallColor = Color3.fromRGB(70, 74, 70), -- matches the maze's slate walls (the fallback when WallVariation is empty)
	WallMaterial = Enum.Material.Slate,

	-- Regional wall variation: instead of one flat grey grid, walls cycle through these {Color, Material}
	-- pairs by grid region, so corridors read as distinct ZONES (a cheap "this is a different part of the
	-- building" tell in a procedural maze). Picked per wall from its world position when the superstructure
	-- is built -- zero runtime cost. Materials stay rough + industrial so the place still reads as ONE
	-- derelict structure, just with texture/tone variety. Empty = the single WallColor/WallMaterial above.
	WallVariation = table.freeze({
		table.freeze({ Color = Color3.fromRGB(70, 74, 70), Material = Enum.Material.Slate }), -- cold grey stone
		table.freeze({ Color = Color3.fromRGB(80, 71, 62), Material = Enum.Material.Concrete }), -- grimy poured concrete
		table.freeze({ Color = Color3.fromRGB(60, 66, 72), Material = Enum.Material.Cobblestone }), -- dank blue-grey block
	}),

	-- Generation.
	BraidFraction = 0.08, -- open ~8% of extra edges (fewer dead-ends; only OPENS, can't disconnect)
	StartCol = 5, -- the recursive-backtracker seed cell (the entrance column, row 0)
	EntranceCol = 5, -- south-perimeter gap = the daycare doorway (must stay open)
	ExitCol = 5, -- north-perimeter gap = the ExitGate column (the exit alcove sits beyond it)

	-- Verification + settle (the navmesh-safety gate).
	NavmeshSettleSeconds = 1.5, -- wait after a carve before the path smoke test (tiles re-rasterize)
	MaxCarveRetries = 6, -- re-seed this many times if the ComputeAsync smoke test fails, then fall back

	-- Code-built practical lights (the maze had ZERO -- it leaned on flat ambient, so corridors had no
	-- light/dark rhythm and the flashlight, dust motes, and bloom had nothing to read against). MazeService
	-- hangs sparse fixtures at a deterministic subset of CELL CENTRES (always-open floor -- a fixture can
	-- never sit inside a wall, and cells don't move, so they're built ONCE with the wall superstructure)
	-- and tags them FlickerLight, so the existing client FlickerController makes a share of them flicker
	-- like failing fluorescents for FREE. This is a PURE ADDITION (no ambient drop), so it can't re-trigger
	-- the hard-won "too dark" regression -- it only adds pools of light + contrast. Sparse spacing also
	-- keeps the per-frame light count down (Roblox culls offscreen lights; only a few render per corridor).
	Lighting = table.freeze({
		Enabled = true,
		CellStride = 3, -- a fixture roughly every Nth cell (placed where (c + r) % stride == 0 -> a spread grid, not clusters)
		HangHeight = 11, -- studs above the floor the fixture hangs (just under the 14-tall ceiling line)
		Color = Color3.fromRGB(255, 244, 214), -- a warm dim bulb (vs the cold ambient -> a hearth-ish pool)
		Brightness = 1.4, -- modest: a pool, not daylight (and the flicker dips it further)
		Range = 18, -- studs the pool reaches (overlaps a bit cell-to-cell so corridors aren't pitch black between)
		Shadows = false, -- a wash, not a caster (perf + reliable on mobile, like the SafeRoom/key lights)
		FixtureSize = 0.7, -- studs: a small emissive bulb part the light hangs on
		FixtureColor = Color3.fromRGB(36, 34, 30), -- the dark housing around the bulb
		FlickerFraction = 0.5, -- this fraction of fixtures get the FlickerLight tag (the rest burn steady)
	}),
})

-- Per-round maze THEMES (replayability via visual variety) -----------------------
-- Each round the maze picks a theme: a wall palette + an Atmosphere/grade COLOUR remix, so no two
-- rounds look the same. COLOUR ONLY -- themes never touch Lighting Brightness/Ambient or Atmosphere
-- Density (the navigability-critical values Config.Environment guards), so a themed round is recoloured
-- but never darker/foggier than the tuned baseline. MazeService recolours the walls (by the same
-- position-bucket as WallVariation) + broadcasts the index; EnvironmentService applies the atmosphere/
-- grade tint. Empty list = the static look (no themes). The first entry mirrors Config.Environment so
-- "Derelict" reads identically to the un-themed baseline.
Config.MazeThemes = table.freeze({
	table.freeze({
		Name = "Derelict", -- the cold grey baseline (== Config.Environment)
		Walls = table.freeze({
			table.freeze({ Color = Color3.fromRGB(70, 74, 70), Material = Enum.Material.Slate }),
			table.freeze({ Color = Color3.fromRGB(80, 71, 62), Material = Enum.Material.Concrete }),
			table.freeze({ Color = Color3.fromRGB(60, 66, 72), Material = Enum.Material.Cobblestone }),
		}),
		AtmosphereColor = Color3.fromRGB(150, 150, 162),
		AtmosphereDecay = Color3.fromRGB(70, 70, 85),
		GradeTint = Color3.fromRGB(206, 212, 224),
	}),
	table.freeze({
		Name = "Boiler", -- rusted industrial, warm amber haze
		Walls = table.freeze({
			table.freeze({ Color = Color3.fromRGB(86, 60, 44), Material = Enum.Material.CorrodedMetal }),
			table.freeze({ Color = Color3.fromRGB(74, 58, 48), Material = Enum.Material.Concrete }),
			table.freeze({ Color = Color3.fromRGB(92, 66, 40), Material = Enum.Material.Brick }),
		}),
		AtmosphereColor = Color3.fromRGB(170, 140, 110),
		AtmosphereDecay = Color3.fromRGB(90, 64, 44),
		GradeTint = Color3.fromRGB(230, 200, 170),
	}),
	table.freeze({
		Name = "Cryo", -- cold blue-white morgue, icy haze
		Walls = table.freeze({
			table.freeze({ Color = Color3.fromRGB(64, 72, 84), Material = Enum.Material.Slate }),
			table.freeze({ Color = Color3.fromRGB(72, 80, 90), Material = Enum.Material.Metal }),
			table.freeze({ Color = Color3.fromRGB(58, 68, 80), Material = Enum.Material.Concrete }),
		}),
		AtmosphereColor = Color3.fromRGB(140, 160, 185),
		AtmosphereDecay = Color3.fromRGB(60, 74, 96),
		GradeTint = Color3.fromRGB(196, 212, 235),
	}),
	table.freeze({
		Name = "Overgrown", -- mossy, sickly green haze
		Walls = table.freeze({
			table.freeze({ Color = Color3.fromRGB(62, 72, 56), Material = Enum.Material.Concrete }),
			table.freeze({ Color = Color3.fromRGB(70, 76, 60), Material = Enum.Material.Slate }),
			table.freeze({ Color = Color3.fromRGB(56, 66, 50), Material = Enum.Material.Cobblestone }),
		}),
		AtmosphereColor = Color3.fromRGB(140, 158, 130),
		AtmosphereDecay = Color3.fromRGB(58, 72, 54),
		GradeTint = Color3.fromRGB(200, 214, 196),
	}),
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
	PeaceSeconds = 25, -- seconds of calm at round start before the monsters begin hunting (was 20; a gentler per-round on-ramp for kids to re-learn the touch controls + grab a first key)

	-- A round that NOBODY escapes still has to END -- otherwise the maze never re-carves and the
	-- "a run is never worth zero" economy floor never pays out (a lobby that keeps dying is stuck on
	-- one stale maze forever). After this long with no win, RoundService forces a fresh round (which
	-- awards the floor + per-key + survival, escaped=false). PLAYTEST the length. 0 disables the timeout.
	MaxRoundSeconds = 300, -- 5 minutes: a generous ceiling, mostly a safety net vs a stuck lobby
})

-- Aggression: the maze gets HOTTER as you near the win -------------------------
-- Monster move speed + sense range scale up with how close ANY player is to winning
-- (best player's KeyCount / RequiredToWin, server-read -- no new state). A flat, encounter-
-- optional stroll becomes a tightening hunt, and going quiet vs the monkey gets harder the
-- closer you are to escaping. Applied in MonsterService (it owns monster behaviour).
Config.Aggression = table.freeze({
	Enabled = true,
	MaxSpeedBonus = 0.18, -- +18% monster WalkSpeed at full aggression (all keys collected)
	MaxRangeBonus = 0.25, -- +25% sight/hearing range at full aggression (was 0.35; the endgame sense ramp stays felt but the final dash to the exit isn't near-deterministic for kids)
})

-- HUD (icon-forward; counts come from gameplay Config, never hardcoded) ----------
Config.HUD = table.freeze({
	-- Key pips (how many = Config.Keys.RequiredToWin)
	PipSize = 40, -- px diameter (was 34: bigger key pips = clearer objective progress for kids)
	PipGap = 10, -- px between pips
	PipTopOffset = 30, -- px from the top edge (was 24: more headroom under the Roblox topbar)
	PipFilledColor = Color3.fromRGB(240, 205, 70),
	PipEmptyColor = Color3.fromRGB(40, 40, 48),
	PipStrokeColor = Color3.fromRGB(15, 15, 18),
	PipStrokeThickness = 2,
	PipIconScale = 0.72, -- a key icon fills this fraction of a pip
	CornerRadius = 6, -- px: rounded-corner radius for gauge panels

	-- Battery gauge
	BatteryWidth = 200, -- px (was 180: wider gauge reads at a glance on iPad)
	BatteryHeight = 16, -- px
	BatteryMargin = 18, -- px from the screen corner
	BatteryBackColor = Color3.fromRGB(25, 25, 30),
	BatteryFillColor = Color3.fromRGB(120, 220, 255),
	BatteryLowColor = Color3.fromRGB(220, 70, 60),
	BatteryLowPulseHz = 2.5, -- the low-battery fill THROBS its transparency at this rate (a "your light is dying" tell paired with the low-battery beep)
	BatteryLowPulseDepth = 0.45, -- how deep the throb dips the fill transparency (shallow -- a throb, not a strobe; honors REDUCE-FLASHING)

	-- Stamina gauge (sits just above the battery gauge, same width)
	StaminaGap = 10, -- px between the stamina gauge and the battery gauge above it
	StaminaFillColor = Color3.fromRGB(120, 230, 140),
	StaminaLowColor = Color3.fromRGB(235, 180, 70),

	-- Gauge captions (so a new player knows what the two unlabeled left-corner bars ARE -- mirrors
	-- the NoiseMeter's "NOISE" caption on the right). Small all-caps tags sitting above each gauge.
	GaugeLabelSize = 13, -- px text size for the BATTERY / STAMINA captions (was 11: legible for kids)
	BatteryLabel = "BATTERY",
	StaminaLabel = "STAMINA",

	-- Transient feedback toast (key pickup / locked door), centered below the tracker
	ToastYScale = 0.30, -- screen-height fraction for the toast's vertical position
	ToastWidth = 420, -- px
	ToastHeight = 34, -- px
	ToastTextSize = 26, -- px (was 24: larger toast text for young readers)

	-- Exit arrow (shown only once all keys are collected)
	ArrowSize = 64, -- px
	ArrowBottomOffset = 120, -- px from the bottom edge
	ArrowColor = Color3.fromRGB(240, 205, 70),
	ArrowLabel = "EXIT", -- caption under the gold exit arrow, so its glyph can't be mistaken for the green KEY arrow
	ArrowLabelSize = 14, -- px
	ExitArrowPulseHz = 2.0, -- the exit arrow gently throbs its scale at this rate once all keys are in (eyes snap to the run-for-it goal)
	ExitArrowPulseScale = 0.12, -- peak extra scale of the throb (subtle)

	-- Key-pickup SCREEN PULSE: a brief full-screen gold flash on every pickup, so a key grabbed
	-- mid-chase (eyes on the monster, not the pip row) still registers. Render-only juice atop the pip pop.
	PickupPulseColor = Color3.fromRGB(240, 205, 70),
	PickupPulseTransparency = 0.78, -- the pulse's most-opaque alpha at its peak (subtle -- a wash, not a blink)
	PickupPulseSeconds = 0.45, -- seconds the pulse fades from peak to clear

	-- ALL-KEYS celebration: the moment the team grabs the LAST key (count == RequiredToWin), a GREEN
	-- full-screen flash + a "RUN FOR THE EXIT" toast, so the objective-complete beat reads even with eyes
	-- on the monster (completes the existing KeyComplete audio sting). Green (not the per-key gold) so
	-- "done -- go!" is distinct. Render-only; honors REDUCE-FLASHING.
	AllKeysFlashColor = Color3.fromRGB(150, 255, 175),
	AllKeysFlashPeak = 0.45, -- most-opaque alpha at the flash peak (a wash, not a blackout)
	AllKeysFlashSeconds = 0.7, -- seconds the flash fades to clear
	AllKeysToastText = "ALL KEYS! RUN FOR THE EXIT",
	AllKeysToastColor = Color3.fromRGB(150, 255, 175),
	AllKeysToastSeconds = 2.6, -- seconds the all-keys toast holds

	-- Win overlay
	WinBackColor = Color3.fromRGB(10, 14, 12),
	WinBackTransparency = 0.25,
	WinIconSize = 140, -- px
	WinIconColor = Color3.fromRGB(120, 230, 130),
	WinTextSize = 28, -- px
	WinTextWidth = 320, -- px
	WinTextPadding = 8, -- px added to WinTextSize for the label height

	-- Win CELEBRATION: the escape is the run's payoff, so it ARRIVES as a sequence (a bright
	-- bloom -> the overlay eases in -> the icon pops with an overshoot -> the label rises in)
	-- rather than a hard Visible flip. Render-only; the win jingle already lands via StingerController.
	WinFlashColor = Color3.fromRGB(236, 255, 242), -- the relief bloom that washes in then clears
	WinFlashSeconds = 0.55, -- seconds the bloom takes to fade to clear
	WinOverlayFadeSeconds = 0.6, -- seconds the dark overlay eases in (under the bloom)
	WinIconPopSeconds = 0.55, -- seconds the escaped icon scales up (Back overshoot from 0)
	WinTextRiseSeconds = 0.5, -- seconds the ESCAPED label fades + rises into place
	WinTextRisePixels = 26, -- px the label travels up as it fades in

	-- Key pip POP: a collected key should feel TACTILE, so the just-filled pip overshoots in
	-- scale and flashes its stroke bright, then settles -- not a flat BackgroundColor flip.
	PipPopScale = 1.5, -- the filled pip overshoots to this x its size...
	PipPopSeconds = 0.5, -- ...then Back-eases back to 1x over this long (lengthened so a mid-chase pickup still registers)
	PipPopStrokeColor = Color3.fromRGB(255, 246, 190), -- the brief bright stroke flash on fill
	PipPopStrokeThickness = 4, -- px the stroke thickens to during the flash

	-- Sprint EXHAUSTION feedback: when stamina empties mid-chase the server cuts your speed, which
	-- reads as "Shift stopped working". A one-shot jolt + toast at the moment of exhaustion tells the
	-- player WHY they slowed. Fires once per drain; re-arms only after stamina climbs back to usable.
	ExhaustFraction = 0.02, -- stamina/Max at/below which you've JUST exhausted
	ExhaustRecoverFraction = 0.3, -- stamina/Max you must climb back to before another exhaust can fire
	ExhaustText = "OUT OF BREATH",
	ExhaustToastSeconds = 1.1, -- the micro-toast hold time
	ExhaustColor = Color3.fromRGB(235, 120, 70), -- a winded amber (distinct from the red danger toast)
	ExhaustShakePixels = 7, -- px the stamina gauge jolts on exhaustion
	ExhaustShakeTime = 0.3, -- seconds of the jolt

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
		-- Only PEEL a second hunter when it's actually part of a death-PINCER (close to the player),
		-- not whenever two rigs merely share a target far apart -- which made the farther one ping-pong
		-- in/out of dormancy every CoopPeelSeconds. With the territory split they're usually far anyway.
		PeelConvergenceDistance = 30, -- studs: the farther hunter peels only if THIS close to the player

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
			ChaseSpeed = 18, -- WalkSpeed while chasing (was 19; still > walk 16, so a sprint burst gains 4/s not 3/s -- kid mercy)
			-- Hard CAP on the bunny's hunt speed after Aggression x Bloodlust stack: kept BELOW player
			-- SprintSpeed 22 so a sprint burst can ALWAYS open a gap ("a chase is winnable"). Without
			-- it, 19 x 1.18 (aggro) x 1.25 (bloodlust) = 28 > 22 made the bunny literally unoutrunnable.
			MaxHuntSpeed = 21, -- < SprintSpeed 22: a sprinter still slowly gains even at full ramp
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
			EyeGlowColor = Color3.fromRGB(210, 40, 40), -- a red "it's watching" glow that reads in the dark
			EyeGlowBrightness = 1.4, -- brighter so the eyes read as a menacing pair in the fog at idle (ChaseFX still flares them to 4.0 in a hunt)
			EyeGlowRange = 9,
		}),

		-- The monkey: the near-blind NOISE hunter (escape by going QUIET). It HEARS the
		-- player's server-computed noise (sprint/fast movement) THROUGH walls; sight is a
		-- short, wide cone used only to confirm a lunge. The inverse of the bunny -- the
		-- bunny makes you afraid to be SEEN, the monkey afraid to be HEARD.
		Monkey = table.freeze({
			-- Speeds (vs player WalkSpeed 16 / SprintSpeed 22 / bunny ChaseSpeed 19).
			PatrolSpeed = 11, -- ambling near its nest
			InvestigateSpeed = 18, -- > WalkSpeed (runs down a walker who stays loud), < SprintSpeed (a sprinter gains)
			LungeSpeed = 23, -- > SprintSpeed: unoutrunnable BY DESIGN, but sight-gated + short -> counter is "break sight" (was 24; ~2x the corner-escape window for kids, still > sprint 22)
			-- Cap the monkey's hunt speed after the ramp: the LUNGE is meant to exceed sprint (sight-
			-- gated + brief), but 24 x 1.475 = 35 is absurd; hold it to a tense-but-fair ceiling.
			MaxHuntSpeed = 27, -- the lunge stays unoutrunnable but not teleporty at full aggression

			-- Hearing (no LoS -- it hears through walls). effectiveNoise = NoiseLevel x falloff(dist, HearRange).
			HearRange = 90, -- studs to zero noise (longer than bunny sight: sound travels)
			-- Falloff SHAPE: <1 = gentler than linear, so a SPRINTING player (loud) is heard across MORE
			-- of the maze (the fix for "the monkey feels deaf/passive in a big maze"). A sprinter now
			-- crosses HearThreshold at ~65 studs (was ~49 with linear). WALKING stays safe (0.35<0.45).
			HearFalloffPower = 0.6,
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
			EyeGlowBrightness = 1.5, -- a touch brighter than the bunny -- the bigger silhouette's eyes loom harder in the dark
			EyeGlowRange = 9,
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
			-- Weight + naturalness (the fix for "it glides like a skin, not a creature"): the body
			-- DROPS on each footfall while walking (mass/impact, not a constant-height float) and the
			-- walk legs use an ANTI-SLIDE stride (planted foot sweeps back, no skate) instead of a sine.
			FootfallDip = 0.2, -- studs the body sinks on each footfall (2 per stride) while walking
			WalkLean = 0.12, -- rad forward body lean into a walk (positive = forward, deeper while hunting)
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
			-- Weight + naturalness (anti-glide): the torso DROPS on each footfall while walking and the
			-- walk limbs use an ANTI-SLIDE stride (planted limb sweeps back) instead of a sine.
			FootfallDip = 0.13, -- studs the torso sinks on each footfall while walking
			WalkLean = 0.1, -- rad extra forward lean into a walk (adds to the hunch)
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
	RisePerSecond = 3.0, -- NoiseLevel rises toward target fast (was 4.0; a panic-tap of the RUN button no longer instantly summons the monkey, a committed sprint still goes loud in ~0.3s)
	DecayPerSecond = 1.7, -- and decays slowly (was 1.3; a kid who stops sprinting falls below the hear threshold sooner -- still a deliberate decay, quiet is still a commitment)
	MaxPlausibleSpeed = 80, -- studs/s above which a position delta is a TELEPORT (respawn jump),
	-- not real running -- such a tick is ignored for noise so a respawn can't spike NoiseLevel.
	MaxTickDtFactor = 4, -- clamp a tick's dt to PollInterval*this so a server hitch can't snap the
	-- smoothing straight to target (mirrors Monster.Shared.MaxTickDtFactor; keeps rise-fast/decay-slow).

	-- HUD noise meter (NoiseMeterController) -- teaches the monkey's counter: a marker sits
	-- at the monkey's HearThreshold, so the player SEES when they cross into "audible".
	MeterWidth = 200, -- px (was 180: mirrors the wider battery/stamina gauges)
	MeterHeight = 14, -- px
	MeterMargin = 18, -- px from the screen corner (bottom-right, mirroring battery/stamina)
	MeterBackColor = Color3.fromRGB(25, 25, 30),
	MeterQuietColor = Color3.fromRGB(110, 200, 120), -- fill while inaudible (safe)
	MeterLoudColor = Color3.fromRGB(235, 70, 60), -- fill once over the threshold (the monkey hears you)
	MeterThresholdColor = Color3.fromRGB(240, 220, 120), -- the "audible" marker line
	MeterLabel = "NOISE",
	-- A tiny caption pinned over the threshold marker so the line's MEANING is explicit: cross it and
	-- the monkey can hear you. Teaches the noise counter at the HUD element itself (not only via a tip).
	MeterThresholdLabel = "MONKEY HEARS", -- centered over the marker line
	MeterThresholdLabelSize = 10, -- px
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
	GamepadThrowKey = Enum.KeyCode.ButtonX, -- gamepad button that throws a decoy (bound alongside ThrowKey)
	ThrowDistance = 42, -- studs ahead the decoy lands (clamped to the first wall along the throw)
	Cooldown = 8, -- seconds between throws (server-authoritative)
	IntentRateLimit = 0.25, -- min seconds between accepted ThrowDecoy messages (anti-spam, hostile input)
	WallPadding = 2.5, -- studs short of a hit wall the decoy lands (so it never lands inside geometry)
	LandingHeight = 0.6, -- studs above the floor the decoy rests (so it reads as sitting ON the ground, not buried)
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
	-- Visible LIFE while it rattles: a steady spin + a brightness flash on each noise pulse, so the
	-- decoy reads as an active, attention-grabbing noisemaker (which is exactly what it is to the monkey).
	SpinSpeed = 4.0, -- rad/s the anchored decoy spins as it rattles
	PulseBrightnessScale = 2.0, -- the light flashes to this x its base brightness on each NoiseEvent pulse, then eases back
	RattleSoundId = "rbxassetid://9119717523", -- the verified mechanical-click id (a rattling tick)
	RattleVolume = 0.7,
	RattleRange = 70, -- studs RollOffMaxDistance (it should read from a distance -- that's the point)

	-- On-screen touch button (mobile), stacked above the RUN/LIGHT buttons.
	TouchBottomOffset = 370, -- px from the bottom (above LIGHT at 250)
	ChipBottomOffset = 74, -- px from the bottom the cooldown chip sits (ABOVE the battery+stamina gauges, not over them)
	ButtonColor = Color3.fromRGB(220, 210, 120),
	Label = "DECOY",
})

-- Flare: the dark-vs-light theme made a player VERB (light as a WEAPON) -----------------------------
-- A throwable LIGHT burst that FREEZES any monster caught in its glow for a beat -- the universal
-- "get it off me NOW" tool that works on BOTH monsters (the decoy only fools the near-blind monkey
-- via noise; this PUSHES both off you). Server-authoritative + exploit-safe, modeled on the decoy:
-- the client sends ONLY intent (no payload); the server computes the landing from the player's OWN
-- known position+facing (never a client position), clamps it to the first wall, spawns a replicated
-- burning flare, and blinds every rig within BlindRadius by writing the EXISTING MonsterStunnedUntil
-- seam (the same one TrapService uses) -- so MonsterService needs ZERO changes. Balance-sensitive (a
-- universal freeze): shipped on but tune Charges/Cooldown/BlindSeconds in a real playtest, like Downed.
Config.Flare = table.freeze({
	Enabled = true,
	Charges = 2, -- flares per ROUND (server-authoritative; refilled on RoundReset; a death does NOT refund)
	Cooldown = 12, -- seconds between throws even with charges left (server-authoritative)
	IntentRateLimit = 0.25, -- min seconds between accepted ThrowFlare messages (anti-spam, HOSTILE input)

	-- Throw geometry (reuses the decoy's clamp-to-first-wall model -> can't be aimed through geometry).
	ThrowDistance = 12, -- studs ahead it lands (a PANIC toss: lands close so the BlindRadius 18 + LightRange 26 burst envelops the THROWER -- a monster ON you or just behind is frozen, the "get it off me NOW" case -- while the burst still reaches ~30 ahead to blind a chaser on a teammate)
	WallPadding = 2.5, -- studs short of a hit wall it rests (never inside geometry)
	LandingHeight = 0.6, -- studs above the floor it rests

	-- The blind (monster-side; SPATIAL + server-authoritative; reuses the MonsterStunnedUntil seam).
	BlindRadius = 18, -- studs: a rig within this of the ignited flare is frozen
	BlindSeconds = 2.4, -- seconds a caught monster stands frozen (~ the trap's stun -- a real escape gap, never a kill)
	IgniteDelay = 0.15, -- seconds after landing before it ignites + blinds (a travel beat; not telekinetic)
	LifeSeconds = 6.0, -- seconds it keeps burning (a lingering light pool) then despawns
	RepeatBlindInterval = 0.6, -- re-apply the blind each interval while burning, so a monster wandering INTO the pool is caught too

	-- The flare part (server-spawned -> replicated; the whole lobby sees/hears it).
	Size = Vector3.new(0.5, 0.5, 1.6),
	Color = Color3.fromRGB(255, 240, 220),
	Material = Enum.Material.Neon,
	LightColor = Color3.fromRGB(255, 150, 90), -- hot red-orange road-flare glow
	LightBrightness = 8, -- bright: the burst must beat the dark and read as a flash
	LightRange = 26, -- studs the pool reaches (>= BlindRadius so the lit area shows the safe zone)
	IgniteFlashBrightness = 16, -- brightness spike at ignition, eased back to LightBrightness over IgniteFlashSeconds
	IgniteFlashSeconds = 0.35,
	SparkTexture = "rbxasset://textures/particles/fire_main.dds", -- built-in particle texture (no upload)
	SparkColor = Color3.fromRGB(255, 170, 90),
	SparkRate = 28,
	SparkSize = 1.1,
	SparkLifetime = 0.7,

	-- Audio (reuse already-verified free ids used elsewhere in Config -- no new uploads).
	IgniteSoundId = "rbxassetid://9120188626", -- the verified whoosh/thunk (also Exit.OpenSound / Traps.FireId)
	IgniteVolume = 0.8,
	BurnSoundId = "rbxassetid://9125446564", -- the verified room-tone hum, looped (also Ambient.RoomTone)
	BurnVolume = 0.4,
	BurnPitch = 1.6, -- pitched up so the room-tone hum reads as a burning HISS, not HVAC
	BurnRange = 40, -- studs RollOffMaxDistance for the 3D burn loop

	-- Input.
	ThrowKey = Enum.KeyCode.R, -- FREE (F light, Q decoy, E hide, Shift sprint, P settings, B shop)
	GamepadThrowKey = Enum.KeyCode.ButtonR3, -- FREE (ButtonY light, X decoy, B hide, L3 sprint)

	-- HUD / touch. Bottom-right thumb-stack ABOVE the HIDE button; bottom-left cooldown/charge chip
	-- ABOVE the DECOY chip. (ButtonSize stays 100 so the 5-button stack RUN/LIGHT/DECOY/HIDE/FLARE
	-- still fits a 768-tall iPad: FLARE top = 610 + 100 = 710 < 768.)
	Label = "FLARE",
	TouchBottomOffset = 610, -- px from the bottom (LIGHT 250 / RUN 130 / DECOY 370 / HIDE 490 -> FLARE 610)
	ChipBottomOffset = 110, -- px the FLARE xN chip sits, above the DECOY chip (74) and the gauges
	ButtonColor = Color3.fromRGB(255, 170, 90),
})

-- Traps: telegraphed hazards -----------------------------------------------------
-- Server-authoritative floor traps (spatial, never Touched). Each is FAIR: an always-
-- visible red arrow + faint glow telegraphs it, and entering it starts a short wind-up
-- (the arrow flashes + clicks) so an attentive player can back off before it fires. A
-- sprung trap kills (Health=0 -> the normal checkpoint respawn) AND spikes your noise,
-- so even surviving one can draw the monkey. The counter is simply: watch the floor.
Config.Traps = table.freeze({
	TriggerRadius = 4.5, -- studs: entering this of a Trap marker begins the wind-up
	WindupSeconds = 1.5, -- the reaction window: long enough to SEE the flash and step off in time (was 1.2; more reaction room on a touchscreen where eyes are on the monster behind you)
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

	-- A flat translucent danger PAD on the floor under each trap (server-built, replicated): the threat
	-- ZONE reads as a clear red area you learn to avoid -- the red half of a red=danger / green=safe
	-- language (SafeRooms get a green outline). Neon so it self-lights in the dark; sized to TriggerRadius.
	-- Cosmetic only -- detection is the spatial poll, unchanged. TrapService builds it on each trap on boot.
	PadColor = Color3.fromRGB(150, 26, 22),
	PadTransparency = 0.55,
	PadThickness = 0.1, -- studs (a thin disc lying just over the floor)

	-- Fire effect (client renders a dart streaking along the arrow + an impact flash).
	DartColor = Color3.fromRGB(200, 200, 210),
	DartLength = 6, -- studs of the dart streak
	DartSpeed = 130, -- studs/s the dart visual travels across the corridor

	-- Audio (reuse the already-verified free Creator-Store sound ids).
	ClickId = "rbxassetid://9119717523", -- mechanical click on wind-up
	FireId = "rbxassetid://9120188626", -- a hard thunk on fire
	FireVolume = 0.8,
	-- The trap click/fire are now SPATIAL (parented to the trap part with roll-off), so a trap
	-- sprung across the maze attenuates instead of thunking at full volume in every ear. The local
	-- player standing on the trap is at ~0 distance = full volume, so the reaction click is unaffected.
	SfxRange = 60, -- studs RollOffMaxDistance for the 3D trap click/fire
})

-- Safe-room marking (server-built, replicated) ------------------------------------
-- The one sanctuary was invisible from outside (a trigger volume with only a client grade on ENTRY).
-- A calm green outline + soft glow on each SafeRoom makes safety FINDABLE down a corridor -- the green
-- half of the red=danger (trap pad) / green=safe language. SafeRoomService owns occupancy detection;
-- this is just the cosmetic tell it also builds on boot (one SelectionBox + one PointLight per room).
Config.SafeRoom = table.freeze({
	OutlineColor = Color3.fromRGB(90, 220, 130), -- calm green: the inverse of the trap's red
	OutlineTransparency = 0.4,
	GlowColor = Color3.fromRGB(120, 230, 150),
	GlowBrightness = 1.1, -- a gentle inviting glow (not a beacon -- it shouldn't outshine the keys/exit)
	GlowRange = 20,
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
	StaminaMax = 5, -- seconds of sprint on a full bar (was 4 -- kid mercy: a full corner-break burst)
	StaminaDrain = 1, -- stamina seconds spent per real second while sprinting
	StaminaRegen = 0.9, -- stamina seconds restored per real second while not sprinting (was 0.7)
	StaminaRegenDelay = 0.5, -- seconds after sprinting before stamina starts to regen (was 0.6)
	SprintKey = Enum.KeyCode.LeftShift,
	GamepadSprintKey = Enum.KeyCode.ButtonL3, -- gamepad: click the left stick to sprint (bound alongside SprintKey)
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
	ArrowCaption = "KEY", -- small caption under the green edge arrow (pairs with the gold "EXIT" arrow so the two glyphs never read alike)
	ArrowCaptionSize = 13, -- px
})

-- Onboarding: first-30-seconds direction (intro, controls, objective tracker) -----
Config.Onboarding = table.freeze({
	IntroVerb = "FIND", -- composed with the key count: "FIND 3 KEYS"
	IntroNoun = "KEYS",
	IntroSub = "...then escape through the EXIT.",
	IntroBannerSeconds = 5, -- how long the center intro banner holds before fading
	ControlsHint = "WASD Move   F Flashlight   Shift Sprint   Q Decoy   E Hide",
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
	-- Shown the first time the player's OWN noise crosses the monkey's hearing threshold (i.e. they
	-- sprinted). The Chase/Alert tips only reach the monster's CURRENT target, so a co-op teammate
	-- never learns the noise counter; this fires off the player's LOCAL NoiseLevel, so everyone does.
	LoudTip = "You're LOUD — the MONKEY hears sprinting. Walk to go silent, or throw a DECOY (Q)",
	-- Shown lobby-wide when the pre-round PEACE window ends (a VISUAL companion to the HuntBegins sting).
	HuntBeginsTip = "THE HUNT BEGINS — the monsters are awake now",
	TipSeconds = 5, -- how long a tip holds before fading

	-- Threat legend (intro): a brief two-line key pairing each monster's COLOUR to its COUNTER, shown
	-- under the spawn banner so a new player knows what the two creatures are BEFORE meeting them. The
	-- colours mirror the radar blips + eye-glow tells (red = the seeing bunny, yellow = the hearing
	-- monkey), so the legend, the radar, and the glowing eyes all teach the SAME colour language.
	LegendTitle = "KNOW YOUR HUNTERS",
	LegendBunnyColor = Color3.fromRGB(220, 70, 66), -- red: the VISION stalker (mirrors its eye-glow / radar blip)
	LegendBunnyText = "RED — it SEES you. Break line of sight & sprint.",
	LegendMonkeyColor = Color3.fromRGB(245, 205, 70), -- yellow: the NOISE hunter
	LegendMonkeyText = "YELLOW — it HEARS you. Move quietly or throw a DECOY (Q).",
	LegendSeconds = 7, -- how long the legend holds before fading (a touch longer than the banner -- it's denser)
})

-- On-screen touch controls (mobile / iPad) --------------------------------------
-- Custom, clearly-visible buttons (bigger + more legible than the default
-- ContextActionService auto-buttons). Each owning controller builds its own button at
-- these coordinates, shown ONLY on touch devices; the keyboard keys still work on PC.
-- They stack bottom-RIGHT above Roblox's built-in jump button without overlapping it or the
-- movement thumbstick (bottom-left). Drop a real icon into `*IconImage` later.
Config.TouchControls = table.freeze({
	ButtonSize = 100, -- px square tap target
	EdgeMargin = 30, -- px from the right edge (was 26; clears the iPad rounded-corner safe area)
	FlashlightBottomOffset = 250, -- px from the bottom (sits above the jump button)
	SprintBottomOffset = 130, -- px from the bottom (closest to the thumb, below the flashlight)
	BackgroundColor = Color3.fromRGB(18, 20, 26),
	BackgroundTransparency = 0.12, -- was 0.3: more opaque so the dark buttons are findable over a dark corridor
	TextColor = Color3.fromRGB(245, 240, 230),
	TextSize = 22, -- was 19: bigger labels for young readers on an iPad at arm's length
	RingThickness = 4, -- px accent ring around each circular touch button (was a hardcoded 3 in every touch controller -- now Config-driven)
	PressScale = 0.9, -- a touch button scale-punches to this on tap, then springs back (tactile feedback kids can SEE)
	PressReturnSeconds = 0.18, -- seconds the press-punch eases back to 1x
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
	-- Pushed DOWN this far so the dish clears the default Roblox player list (which sits top-right
	-- and is now populated -- PlayerData mirrors Coins + Escapes to leaderstats). Sized for a small
	-- co-op lobby's leaderstat rows; raise it if a longer player list still overlaps the dish.
	TopOffset = 96, -- px added below Margin so the radar doesn't collide with the player list
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
	BonusKeyReward = 20, -- coins per OPTIONAL gold bonus key grabbed (more than a normal key -- it's the risky detour)
	EscapeBonus = 50, -- coins for reaching the exit
	-- Bonus on top of EscapeBonus when 2+ players escape the SAME round -- a small reward for
	-- winning TOGETHER (an incentive to cooperate, not just share a lobby). Kept SUBLINEAR (well
	-- under EscapeBonus) so solo play is never under-rewarded by comparison. 0 disables it.
	CoopEscapeBonus = 25,
	SurvivalPerSecond = 0.25, -- coins per second survived...
	SurvivalCap = 240, -- ...capped at this many seconds (so camping isn't farmed)
	ShopActionRateLimit = 0.2, -- min seconds between accepted ShopAction messages (anti-spam, hostile input)
})

-- Achievements: persistent milestone rewards (the long-tail retention carrot) --------
-- Lifetime stats (PlayerData.stats) cross a threshold -> a ONE-TIME coin reward (tracked so it
-- pays once, persisted). Pure milestone coins -- no gameplay power, so it stays cosmetic-economy
-- only. Each: { id (STABLE -- the DataStore remembers earned ids forever; never rename/reuse), the
-- `stat` key it watches, the `threshold` to cross, the `reward` coins, and a display `name`. Checked
-- by the pure shared/Achievements module after each round's stats update (StatsService).
Config.Achievements = table.freeze({
	List = table.freeze({
		table.freeze({ id = "first_escape", stat = "escapes", threshold = 1, reward = 40, name = "FIRST ESCAPE" }),
		table.freeze({ id = "escape_10", stat = "escapes", threshold = 10, reward = 150, name = "SERIAL SURVIVOR" }),
		table.freeze({ id = "escape_50", stat = "escapes", threshold = 50, reward = 600, name = "UNCATCHABLE" }),
		table.freeze({ id = "rounds_25", stat = "roundsPlayed", threshold = 25, reward = 120, name = "REGULAR" }),
		table.freeze({ id = "rounds_100", stat = "roundsPlayed", threshold = 100, reward = 500, name = "VETERAN" }),
		table.freeze({ id = "bonus_10", stat = "bonusKeys", threshold = 10, reward = 150, name = "TREASURE HUNTER" }),
		table.freeze({ id = "bonus_50", stat = "bonusKeys", threshold = 50, reward = 600, name = "HOARDER" }),
	}),
	-- The unlock toast (client). Colour = the coins/keys warn gold (a positive milestone).
	ToastPrefix = "ACHIEVEMENT", -- "ACHIEVEMENT — FIRST ESCAPE  (+40)"
	ToastSeconds = 4.0,
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
	-- Co-op key attribution: when a TEAMMATE grabs a key, the toast names them ("Steve got a key 2/3")
	-- so the lobby SEES who's contributing -- shared progress reads as teamwork, not an anonymous tick.
	KeyBySuffix = "got a key",
	LockedTextPrefix = "EXIT LOCKED", -- shown with the live count: "EXIT LOCKED — 3 KEYS NEEDED"
	-- Shown to OTHER players (not the escapee) when someone reaches the exit and the shared
	-- round is about to reset -- so a co-op escape reads as an event, not a silent yank.
	EscapedSuffix = "ESCAPED!", -- composed with the escapee's name: "Steve ESCAPED!"
	EscapedColor = Color3.fromRGB(120, 230, 130),
	EscapedToastSeconds = 3.0,

	-- Co-op HUNT ALERT: when a monster starts actively hunting a TEAMMATE, everyone else gets a brief
	-- toast ("Steve is being HUNTED!") so the team has situational awareness (help them or scatter) --
	-- the hunted player already feels it via the chase sting/grade. Throttled per target so a monster
	-- losing + re-acquiring the same player in quick succession can't spam the lobby.
	HuntedSuffix = "is being HUNTED!", -- composed with the target's name
	HuntedColor = Color3.fromRGB(235, 90, 70),
	HuntedToastSeconds = 2.5,
	HuntAlertCooldown = 6, -- min seconds between hunt alerts for the SAME player (server-side throttle)
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

-- SafeRoom "exhale" FX (the relief counterpart to the chase grade) ----------------
-- A safe room is the only sanctuary, but entering one was nearly invisible (just a reverb
-- swap). SafeRoomFXController gives crossing the threshold a FELT arrival: a warm grade blooms
-- in then settles to a gentle steady warmth while you're inside, a soft "SAFE" cue appears, and
-- it all fades on leaving. Render-only, off the server-authoritative SafeRoom enter/leave remotes
-- (the client never detects occupancy itself); its OWN ColorCorrection, so the place grade and the
-- ChaseGrade are untouched. The inverse of Config.Chase: warmth + a lift, not desaturation + red.
Config.SafeRoomFX = table.freeze({
	TintColor = Color3.fromRGB(255, 226, 170), -- a warm hearth tint (vs the chase's sickly red)
	BloomTint = 1.0, -- TintColor weight at the entry bloom's peak (settles to HoldTint)
	HoldTint = 0.35, -- the gentle steady warmth held while inside
	Brightness = 0.05, -- a slight lift at the bloom peak (the lights-come-up exhale)
	Saturation = 0.12, -- a touch more colour at the bloom peak (the world feels alive again)
	BloomSeconds = 0.5, -- seconds the warm grade blooms IN on entry
	SettleSeconds = 1.2, -- seconds it eases from the bloom peak down to the steady hold
	FadeSeconds = 0.6, -- seconds it fades back to neutral on leaving

	-- A one-shot "SAFE" toast on entry (centered, brief), and a soft warm screen-edge glow held
	-- while inside so the sanctuary reads at a glance even with the grade settled low.
	ToastText = "SAFE",
	ToastColor = Color3.fromRGB(255, 232, 180),
	ToastSeconds = 1.4,
	ToastYScale = 0.4, -- screen-height fraction for the SAFE toast (below the key toast at 0.30)
	GlowColor = Color3.fromRGB(255, 220, 160),
	GlowThickness = 0.34, -- fraction of the screen each warm edge band spans
	GlowHoldTransparency = 0.86, -- the steady edge-glow alpha while inside (subtle)
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
		-- Per-drift-in random TRANSPOSE: each play picks a fixed base PlaybackSpeed within +/- this of 1
		-- (the continuous wobble rides on top), so no two drift-ins sit at the same pitch -- a haunted box
		-- that's a little different every time, which fights habituation over a long session.
		MusicBoxTransposeRange = 0.07,
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
		-- A SOFTER sting on entering Alert (the monkey heard you) -- the "it heard you" beat had only the
		-- heartbeat ramp, no discrete hit. Reuses the verified chase-sting id, quieter + pitched down so
		-- it reads as a warning, not the full chase commit (which still gets the louder ChaseSting above).
		AlertStingVolume = 0.42,
		AlertStingPitch = 0.85,
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
		-- The FINAL key (team hits RequiredToWin) is a triumphant beat the mix was missing -- a brighter,
		-- louder flourish layered over the normal chime. Reuses the verified chime id, pitched UP so it
		-- reads as "objective complete!" (distinct from the per-key chime and from the win jingle).
		KeyCompleteId = "rbxassetid://7381723941",
		KeyCompleteVolume = 0.85,
		KeyCompletePitch = 1.35,
		-- Entering a SafeRoom was acoustically invisible (only a reverb swap). A warm, low bell "exhale"
		-- on entry gives the sanctuary an audible arrival to match SafeRoomFXController's visual bloom.
		-- Reuses the verified chime id, pitched DOWN into a soft hearth tone (Ambient bus, low volume).
		SafeRoomReliefId = "rbxassetid://7381723941",
		SafeRoomReliefVolume = 0.4,
		SafeRoomReliefPitch = 0.6,
		LockedThunkId = "rbxassetid://9120188626", -- ExitLocked (SFX bus)
		LockedThunkVolume = 0.65,
		WinJingleId = "rbxassetid://9041792228", -- GameWon (Music bus)
		WinJingleVolume = 0.75,
		HuntBeginsId = "rbxassetid://1841353932", -- HuntBegins: the peace window ended (reuses the verified chase-sting id; Monster bus)
		HuntBeginsVolume = 0.7,
		JumpscareId = "rbxassetid://139306955269282", -- MonsterCaught (full-volume, ducks others)
		JumpscareVolume = 1.0,

		-- Co-op + progression payoffs that previously had NO audio. All reuse already-verified ids,
		-- pitched/levelled so each reads distinctly by ear (the content the architecture already supported).
		-- A TEAMMATE is being hunted (HuntingAlert): a quieter, lower warning so you never confuse it with
		-- your OWN ChaseSting -- "someone's in trouble", not "it's on me".
		HuntedAlertId = "rbxassetid://1841353932",
		HuntedAlertVolume = 0.4,
		HuntedAlertPitch = 0.78,
		-- An achievement unlocked: a bright rising chime (reuses the key-complete flourish, pitched up).
		AchievementId = "rbxassetid://7381723941",
		AchievementVolume = 0.7,
		AchievementPitch = 1.5,
		-- The round-summary card appears: a soft results tone (reuses the key chime, low + warm).
		RoundSummaryId = "rbxassetid://7381723941",
		RoundSummaryVolume = 0.5,
		RoundSummaryPitch = 0.9,
		-- Throwing a decoy: an immediate local release/whoosh so the input is confirmed before the
		-- thrown part's 3D rattle is audible (reuses the mechanical click, a touch up-pitched).
		DecoyThrowId = "rbxassetid://9119717523",
		DecoyThrowVolume = 0.55,
		DecoyThrowPitch = 1.2,
	}),
})

-- UI theme (the single source of UI typography + styling) ------------------------
-- Before this, every HUD controller hardcoded its own fonts/strokes/corners -> a flat, dated,
-- inconsistent look (30+ scattered Gotham references, zero gradients). These are the shared
-- design tokens the controllers compose, so the whole HUD reads as ONE designed system. Fonts
-- resolve through uiFont() so a modern face is used where available and degrades cleanly.
Config.UI = table.freeze({
	-- Typography. Builder Sans is Roblox's modern UI face; Creepster is the horror display cut
	-- (used only for short impact words -- CAUGHT!, the intro title -- never body text).
	DisplayFont = uiFont("Creepster", Enum.Font.GothamBlack), -- horror display: scares + the intro title
	HeadingFont = uiFont("BuilderSansExtraBold", Enum.Font.GothamBlack), -- panel titles / big numbers
	SubheadingFont = uiFont("BuilderSansBold", Enum.Font.GothamBold), -- labels / buttons
	BodyFont = uiFont("BuilderSansMedium", Enum.Font.GothamMedium), -- body / secondary text

	-- Palette (cool, desaturated, horror). Controllers read these instead of hardcoding RGB so
	-- the HUD can be re-themed in one place.
	TextColor = Color3.fromRGB(232, 234, 240), -- primary text (near-white, faint cool cast)
	MutedTextColor = Color3.fromRGB(150, 156, 168), -- secondary / captions
	AccentColor = Color3.fromRGB(120, 220, 255), -- the cold "interactive / info" cyan (battery, links)
	DangerColor = Color3.fromRGB(224, 64, 58), -- threat / locked / bleedout
	SafeColor = Color3.fromRGB(120, 230, 140), -- safe / success / escaped
	WarnColor = Color3.fromRGB(238, 196, 92), -- caution / stamina-low / coins / keys

	-- Panels. A subtle vertical gradient + cool hairline stroke gives flat frames depth (no
	-- assets -- gradient + stroke only, which render dependably on every device).
	PanelColor = Color3.fromRGB(18, 20, 26), -- base panel fill (the gradient darkens from this)
	PanelGradientDarken = 0.45, -- the gradient's bottom is this fraction darker than the top
	PanelTransparency = 0.08, -- panels are nearly opaque (readable over the dark maze)
	PanelCornerRadius = 10, -- px corner radius for panels
	ChipCornerRadius = 6, -- px corner radius for small chips / bars / buttons

	StrokeColor = Color3.fromRGB(70, 78, 92), -- the cool hairline around panels/chips
	StrokeTransparency = 0.35,
	StrokeThickness = 1.5,

	-- Text stroke (standardized so text weight reads consistently across every controller).
	TextStrokeColor = Color3.fromRGB(0, 0, 0),
	TextStrokeTransparency = 0.4,
})

-- Ambient atmosphere FX (the mood the maze was missing) ---------------------------
-- Fine dust drifting in the air, emitted in a volume that follows the camera so it always
-- surrounds the player and -- crucially -- CATCHES THE FLASHLIGHT BEAM (LightInfluence on), the
-- single biggest "this place is real" tell in a dark corridor. Render-only, client-side, zero
-- gameplay effect (the FlickerController-class cosmetic CLAUDE.md permits).
Config.AtmosphereFX = table.freeze({
	Enabled = true,
	DustTexture = "rbxasset://textures/particles/smoke_main.dds", -- a soft built-in puff (no upload)
	DustColor = Color3.fromRGB(150, 156, 170), -- cool grey, matched to the Atmosphere haze
	VolumeSize = 30, -- studs: the cube around the camera that dust spawns within
	Rate = 16, -- particles/second
	LifetimeMin = 5, -- seconds a mote lives (min)...
	LifetimeMax = 9, -- ...and max
	SizeMin = 0.18, -- studs (tiny motes)
	SizeMax = 0.5,
	TransparencyMin = 0.55, -- faint...
	TransparencyMax = 0.85, -- ...to nearly invisible (only the flashlight really reveals them)
	Speed = 0.6, -- studs/s of slow drift
	DriftRise = 0.12, -- studs/s^2 faint upward acceleration (warm air rising)
	SpinDeg = 35, -- deg/s lazy mote spin
	LightInfluence = 1, -- fully lit by nearby lights -> motes glow only in the beam
	LightEmission = 0.1, -- a hair of self-emission so they're not pure black in shadow
})

-- Monster presence FX (make the creatures feel PHYSICAL, not ghostly) -------------
-- Client cosmetics on each rig: dust kicked up under the feet while it moves (scaled by its
-- replicated ground speed) and a faint breath fog from its head -- so a creature glimpsed in the
-- dark reads as a living, breathing, ground-disturbing thing. Render-only, off replicated
-- position/state only (exploit-safe; the MonsterAnimController cosmetic class).
Config.MonsterFX = table.freeze({
	Enabled = true,
	-- Footfall dust under a moving rig.
	DustTexture = "rbxasset://textures/particles/smoke_main.dds",
	DustColor = Color3.fromRGB(120, 120, 128),
	DustMoveSpeed = 4, -- studs/s of rig motion above which dust starts to kick up
	DustFullSpeed = 16, -- studs/s the dust rate maxes at
	DustMaxRate = 11, -- particles/s at/above full speed
	DustSize = 1.2, -- studs
	DustLifetime = 0.9, -- seconds
	DustRise = 1.6, -- studs/s the dust puffs upward as it fades
	-- Breath fog drifting from the head (always faintly on -- the thing is alive).
	BreathTexture = "rbxasset://textures/particles/smoke_main.dds",
	BreathColor = Color3.fromRGB(182, 186, 198),
	BreathRate = 3, -- puffs/second
	BreathSize = 0.85, -- studs
	BreathLifetime = 1.5, -- seconds
	BreathSpeed = 1.3, -- studs/s forward drift
	BreathTransparency = 0.72,
})

-- Camera shake (the threat you FEEL) ---------------------------------------------
-- A subtle continuous tremble scaled by the nearest hunting monster's proximity (the same
-- exploit-safe threat model as Config.Chase) plus sharp one-shot impulses on discrete scares (a
-- trap firing near you, being caught). Bound AFTER the camera update so it layers on top of
-- whatever camera mode is active. Render-only; reads replicated state + cue remotes only. Kept
-- deliberately small -- enough to feel, never enough to nauseate or hurt navigation.
Config.CameraShake = table.freeze({
	Enabled = true,
	ThreatStartDistance = 38, -- studs: a hunting monster begins adding tremble
	ThreatMaxDistance = 8, -- studs: full continuous tremble
	AlertScale = 0.4, -- tremble multiplier when a monster is only Alert (heard you)
	FadeRate = 4, -- per-second lerp toward the target tremble level (smooth in AND out)
	MaxOffset = 0.16, -- studs of positional sway at full threat
	MaxTilt = 0.9, -- degrees of rotational sway at full threat
	Frequency = 9, -- Hz the continuous tremble oscillates at

	-- One-shot impulses (decay quickly). Magnitude scales the same offset/tilt units.
	TrapImpulse = 0.9, -- a trap FIRING near the player (TrapTriggered "fire")
	TrapImpulseRadius = 40, -- studs: the impulse falls off to 0 across this distance
	CaughtImpulse = 2.2, -- being grabbed (MonsterCaught)
	ImpulseDecay = 7, -- per-second exponential decay of an active impulse
	ImpulseFrequency = 22, -- Hz the impulse rattles at (snappier than the ambient tremble)
})

-- Player comfort & accessibility (the FX-heavy horror game shipped with NO settings layer) ---------
-- A render-only client menu (SettingsController) writing personal, uncontested prefs as LocalPlayer
-- attributes (the FlickerController-class client exception CLAUDE.md permits -- they affect only the
-- local view/audio, never any contested outcome). FX controllers READ these attributes:
--   * FxIntensity (0..1): multiplies the strength of the chase grade, camera shake, flashlight
--     flicker, the noise-meter pulse, and the jumpscare flash. 1 = full (default), 0 = effects off.
--   * ReduceFlashing (bool): floors the rapid brightness flicker + cuts screen strobes (photosensitivity).
--   * MasterVolume (0..1): scales the AudioGroups Master bus (the single mix root) -- there was no way
--     to lower the audio (incl. the scream) at all.
-- The menu ALSO recalls the onboarding (controls + the red/yellow threat legend) so a player who
-- missed the one-shot intro can re-read it. Opened by a gear button (always visible, touch-friendly),
-- ToggleKey, or the gamepad button. Prefs are per-session (client-local attributes; no server trust).
Config.Settings = table.freeze({
	ToggleKey = Enum.KeyCode.P, -- keyboard key to open/close the settings + help menu
	GamepadToggleKey = Enum.KeyCode.DPadUp, -- gamepad: D-pad up opens the menu
	DefaultFxIntensity = 1.0, -- 0..1 starting FX strength
	DefaultMasterVolume = 1.0, -- 0..1 starting master volume
	DefaultReduceFlashing = false,

	-- The gear button: top-left, BELOW the shop's coin button (at y 70) so it clears BOTH the Roblox
	-- topbar/menu (which sits at the very top-left) and the shop button. The objective tracker is
	-- top-CENTRE, so this left column is otherwise free. Nudge ButtonTop if your device's topbar/shop
	-- button overlap it.
	ButtonSize = 46, -- px
	ButtonLeft = 14, -- px from the left edge (aligned under the shop button)
	ButtonTop = 112, -- px from the top (below the shop's coin button at ~70..104; clears the topbar)
	GearLabel = "⚙",
	GearColor = Color3.fromRGB(206, 210, 222),

	-- Panel.
	PanelWidth = 440, -- px
	PanelHeight = 500, -- px
	Title = "SETTINGS",
	HelpTitle = "HOW TO PLAY",
	RowHeight = 46, -- px per setting row
	AdjustStep = 0.1, -- master volume / FX intensity adjust in 1/10 increments
	-- ReduceFlashing floors a flicker/flash amplitude to this fraction of base (a faint steady dim,
	-- never a strobe). Read by the FX controllers when the ReduceFlashing pref is on.
	ReduceFlashingFloor = 0.85,

	FxIntensityLabel = "EFFECTS INTENSITY",
	VolumeLabel = "MASTER VOLUME",
	ReduceFlashingLabel = "REDUCE FLASHING",
})

-- Hiding spots (the genre's missing last-resort escape: Granny/Piggy lockers) ----------------------
-- When you're cornered -- out of stamina, decoy on cooldown -- you can DUCK INTO a tagged HidingSpot.
-- Server-authoritative: the client sends only HideIntent (no payload); HidingService confirms you're
-- within EnterRadius of a HidingSpot from your OWN server-known position, teleports + anchors you into
-- the spot, and sets the Hidden attribute -- then MonsterService skips you (sight + hearing + contact)
-- and NoiseService zeroes your noise, exactly like a SafeRoom. It is NOT god-mode: a HUNTING monster
-- (Chase/Investigate) that lingers within DiscoverRadius of your spot for DiscoverSeconds FLUSHES you
-- out (so you must break line of sight BEFORE hiding). Inert until HidingSpot markers are placed.
Config.Hiding = table.freeze({
	Enabled = true,
	HideKey = Enum.KeyCode.E, -- press near a HidingSpot to duck in / out
	GamepadHideKey = Enum.KeyCode.ButtonB, -- gamepad: B to hide/unhide
	IntentRateLimit = 0.25, -- min seconds between accepted HideIntent messages (anti-spam, hostile input)
	EnterRadius = 7, -- studs: you must be within this of a HidingSpot to duck in
	ExitNudge = 4, -- studs in front of the spot the server places you when you climb back out
	DiscoverRadius = 9, -- studs: a HUNTING monster this close to your spot begins to find you
	DiscoverSeconds = 2.5, -- seconds a hunter lingers within DiscoverRadius before it FLUSHES you out
	FlushGraceSeconds = 0.6, -- a beat of RespawnGrace on a flush so being found isn't an instant grab
	MaxTickDtFactor = 4, -- clamp the discover poll's dt to PollInterval*this so a server hitch can't snap discoverTime past DiscoverSeconds in one tick (mirrors Noise / Monster.Shared / Downed)

	-- HUD (HideController, render-only): a prompt when near a usable spot + the hidden overlay.
	PromptText = "HIDE", -- the "press E to HIDE" affordance shown near a spot
	HiddenText = "HIDDEN — stay still", -- shown while you're tucked away
	PromptColor = Color3.fromRGB(150, 200, 235),

	-- On-screen touch HIDE button (mobile/iPad), bottom-right stack ABOVE the DECOY button (370).
	TouchLabel = "HIDE",
	TouchBottomOffset = 490, -- px from the bottom (above DECOY at 370, keeping the stack's 20px gap)
	TouchColor = Color3.fromRGB(150, 200, 235),
})

-- Ambush micro-scares (the AmbushNode tag was DEFINED but DEAD -- nothing read it) ------------------
-- Long randomized corridors had stretches of dead-quiet traversal between monster encounters.
-- AmbushService polls players vs AmbushNode markers; passing within TriggerRadius (once, then a
-- cooldown) fires AmbushTriggered -> AmbushFXController plays a localized 3D skitter + briefly cuts the
-- nearest practical light: a cheap "something just moved" beat that decides NOTHING. Inert until placed.
Config.Ambush = table.freeze({
	Enabled = true,
	TriggerRadius = 11, -- studs: passing within this of an AmbushNode springs its scare
	Cooldown = 25, -- seconds before the same node can scare the same player again
	SkitterId = "rbxassetid://81623756670923", -- a quick scuttle (reuses the verified footstep id, pitched)
	SkitterPitch = 1.5, -- pitched up so it reads as a fast skitter, not a footstep
	SkitterVolume = 0.65,
	SkitterRange = 45, -- studs RollOffMaxDistance (3D, at the node)
	LightCutSeconds = 0.45, -- briefly drop the nearest FlickerLight to sell the scare
})

-- Endgame ALARM (the climax made felt) ------------------------------------------------------------
-- When the team grabs the LAST key the exit opens and it's a sprint for the door -- but the only
-- escalation was the subtle aggression ramp. ExitService now fires AlarmStateChanged(true) on the
-- all-keys transition (and (false) on a round reset / re-lock), and the client AlarmFXController throws
-- a pulsing red emergency wash + an alarm sting (and a low looping bed) until the round ends. (Monster
-- speed/range is already at max at full keys via Config.Aggression, so this is the AUDIOVISUAL half.)
Config.Endgame = table.freeze({
	AlarmEnabled = true,
	WashColor = Color3.fromRGB(255, 40, 30), -- the red emergency tint
	WashMaxTransparency = 0.8, -- the wash's most-opaque alpha at a pulse peak (a wash, not a blackout)
	PulseHz = 1.3, -- the emergency pulse speed
	FadeSeconds = 0.8, -- fade the wash in on alarm-on, out on alarm-off
	StingId = "rbxassetid://1841353932", -- one-shot on the all-keys transition (reuses the verified chase sting)
	StingVolume = 0.85,
	BedId = "rbxassetid://140704980462451", -- a low looping alarm bed (reuses the verified dread drone)
	BedVolume = 0.4,
	BedPitch = 1.35, -- pitched up so the drone reads as an alarm, not the ambient bed
})

-- Shop open key (ShopController; was a hardcoded UserInputService 'B' -- moved here so a gamepad
-- button can also open it, and so the keybind lives in Config like every other control).
-- (ShopController already shows an always-visible top-left "SHOP <coins>" button that opens the
-- panel on tap, so the shop is reachable on touch without a keyboard; these keys are just shortcuts.)
Config.Shop = table.freeze({
	OpenKey = Enum.KeyCode.B, -- keyboard key to open/close the cosmetics shop
	GamepadOpenKey = Enum.KeyCode.DPadDown, -- gamepad: D-pad down opens the shop
})

return table.freeze(Config)
