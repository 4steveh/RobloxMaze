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

	-- number on a Player: OPTIONAL bonus keys the team has grabbed this round (gold, not required
	-- to win -- a risk/reward detour in dangerous spots). Server-authoritative (KeyService), mirrored
	-- to every player like KeyCount; read by RoundService into the round summary (round-end coin bonus)
	-- and the HUD (a pickup toast). Does NOT gate the exit -- only KeyCount does.
	BonusKeyCount = "BonusKeyCount",

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

	-- number on a MONSTER RIG (not a Player): `workspace:GetServerTimeNow()` until which the rig
	-- is STUNNED (frozen) after tripping a floor trap. Set by TrapService when a hunting rig runs
	-- over an armed trap; MonsterService freezes the rig (WalkSpeed 0, no move) while now < this.
	-- The seam that makes traps a chase tool without coupling TrapService to monster internals.
	MonsterStunnedUntil = "StunnedUntil",

	-- string on a MONSTER RIG (not a Player): the rig's current Enums.MonsterState
	-- ("Patrol"/"Chase"/...). Server-authoritative (written by MonsterService each tick);
	-- read by the client MonsterAnimController (gait blend), MonsterAudioController
	-- (heartbeat/sting), ChaseFXController (the grade), and the adaptive audio. The same
	-- producer/consumer discipline MonsterSpecies follows -- one constant, no literals.
	MonsterState = "State",

	-- boolean on a Player: true while DOWNED — caught by a monster but revivable (collapsed,
	-- immobilized, bleeding out). Server-authoritative (DownedService). MonsterService,
	-- SprintService, NoiseService and ExitService ALL skip a downed player; the client
	-- DownedController renders the downed overlay + the teammate revive beacon from it.
	Downed = "Downed",

	-- number on a Player: `workspace:GetServerTimeNow()` at which a downed player bleeds out
	-- (dies → checkpoint respawn) if not revived. The client renders the countdown bar from it.
	DownedUntil = "DownedUntil",

	-- number on a Player (0..1): revive progress while DOWNED (a teammate staying within
	-- Config.Downed.ReviveRadius fills it). Server-authoritative; the client renders the bar.
	ReviveProgress = "ReviveProgress",

	-- number on a Player: persistent coin balance (server-authoritative, DataService). A MIRROR
	-- of the in-memory profile for the HUD to read -- never read back as the source of truth.
	Coins = "Coins",

	-- string on a Player: the equipped flashlight-color cosmetic id (Cosmetics catalog). Mirror
	-- of the profile; FlashlightController reads it to tint the beam (cosmetic only).
	EquippedFlashlightColor = "EquippedFlashlightColor",

	-- boolean on a Player: true while HIDDEN inside a HidingSpot (server-authoritative, HidingService).
	-- The monster's senses (sight + hearing + contact-catch) and NoiseService ALL skip a hidden player,
	-- exactly like InSafeRoom -- but a hunting monster lingering at your spot can FLUSH you out (it's a
	-- last resort, not god-mode). The client HideController renders the hidden overlay + the "press to
	-- hide" prompt from it. A fresh character is never hidden.
	Hidden = "Hidden",

	-- CLIENT-LOCAL prefs on the LocalPlayer (NOT replicated, NOT server-read): set by the client
	-- SettingsController and read by the FX/audio controllers on the SAME client. Personal, uncontested
	-- comfort/accessibility settings (the FlickerController-class client exception) -- they shape only
	-- the local view/audio, never a contested outcome, so they correctly live off the server.
	SettingFxIntensity = "SettingFxIntensity", -- number 0..1: global FX strength multiplier (1 = full)
	SettingReduceFlashing = "SettingReduceFlashing", -- boolean: floor flicker / cut screen strobes
	SettingMasterVolume = "SettingMasterVolume", -- number 0..1: scales the AudioGroups Master bus

	-- number on a Player: flare charges remaining this round. Server-authoritative (FlareService,
	-- refilled on RoundReset), a READ-ONLY mirror for the HUD like Stamina/KeyCount -- the throw handler
	-- validates against the server's own copy; the client only displays it. The blind itself reuses the
	-- EXISTING MonsterStunnedUntil rig attribute (no new rig attribute).
	FlareCharges = "FlareCharges",

	-- number on a Player (0..1): server-computed audible NOISE this player is making
	-- (from movement speed -- sprinting is loud, creeping is near-silent). Owned by
	-- NoiseService (never client-set), read by the monkey's hearing detection and the
	-- HUD noise meter. Zeroed in a SafeRoom / Won / RespawnGrace.
	NoiseLevel = "NoiseLevel",
}

return table.freeze(Attributes)
