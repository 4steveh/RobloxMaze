--!nonstrict
-- MonsterAudioController.client.luau
-- The highest-tension audio. Per rig: 3D breathing + footsteps pitched/levelled PER SPECIES
-- (the bunny lighter+higher, the monkey heavier+lower) so you can tell which is near by ear,
-- and MUFFLED by wall occlusion (a throttled player->rig ray + a low-pass) so "it's close
-- but WHERE" tension returns. Globally: a non-spatial heartbeat and an adaptive TENSION bed
-- that both ramp with the nearest HUNTING rig (its replicated State + distance) -- so the
-- score and the pulse mean "it is hunting YOU", not merely "a monster exists somewhere".
-- All rendering; the rig State + remotes are the server-authoritative truth (exploit-safe).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Enums = require(ReplicatedStorage.Enums)
local Attributes = require(ReplicatedStorage.Attributes)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local MA = Config.Audio.Monster
local MUS = Config.Audio.Music
local OCC = MA.Occlusion
local player = Players.LocalPlayer
local monsterBus = AudioGroups.get("Monster")

-- A catch/round-reset teleports the rig home (PivotTo); that one-frame jump reads as a huge
-- instantaneous speed. Real creature locomotion stays well under this, so a step that fast is a
-- teleport frame to reject -- not real motion that should fire a spurious footstep at the home.
local MAX_PLAUSIBLE_SPEED = 80 -- studs/s

-- Non-spatial heartbeat (volume + rate ramp with the nearest HUNTING rig's closeness).
local heartbeat = Instance.new("Sound")
heartbeat.Name = "Heartbeat"
heartbeat.SoundId = MA.HeartbeatId
heartbeat.Looped = true
heartbeat.Volume = 0
heartbeat.SoundGroup = monsterBus
heartbeat.Parent = SoundService
heartbeat:Play()

-- Adaptive tension bed on the Music bus: silent when safe, swelling while hunted.
local tension = Instance.new("Sound")
tension.Name = "TensionBed"
tension.SoundId = MUS.TensionId
tension.Looped = true
tension.Volume = 0
tension.PlaybackSpeed = MUS.TensionPitch
tension.SoundGroup = AudioGroups.get("Music")
tension.Parent = SoundService
tension:Play()

-- One-shot chase sting, fired when a rig chasing THIS player enters Chase.
local sting = Instance.new("Sound")
sting.Name = "ChaseSting"
sting.SoundId = MA.ChaseStingId
sting.Volume = MA.ChaseStingVolume
sting.SoundGroup = monsterBus
sting.Parent = SoundService

-- A SOFTER sting on Alert (the monkey heard you) -- the "it heard you" beat had only the heartbeat
-- ramp before, no discrete hit. Reuses the chase-sting clip, quieter + pitched down (a warning, not
-- the full commit). Distinct enough by ear that Alert and Chase read differently.
local alertSting = Instance.new("Sound")
alertSting.Name = "AlertSting"
alertSting.SoundId = MA.ChaseStingId
alertSting.Volume = MA.AlertStingVolume
alertSting.PlaybackSpeed = MA.AlertStingPitch
alertSting.SoundGroup = monsterBus
alertSting.Parent = SoundService

-- Per-target threat (the fix for co-op false dread): the rig State attribute is GLOBAL -- a rig
-- chasing a TEAMMATE reads as Chase to everyone -- so the continuous beds must NOT key off it
-- alone. The MonsterStateChanged remote, by contrast, fires only to the player a rig targets, so
-- it tells us whether a monster is hunting ME. We track that here and gate the heartbeat/tension
-- ramp on it, so the score means "it is hunting YOU", not "a monster exists somewhere".
local personalThreat = "none" -- "hunt" (Chase/Investigate on me), "alert" (Alert on me), or "none"
local stateRemote = Remotes.get(Remotes.Names.MonsterStateChanged)
stateRemote.OnClientEvent:Connect(function(state)
	if state == Enums.MonsterState.Chase then
		sting:Play()
	elseif state == Enums.MonsterState.Alert then
		alertSting:Play()
	end
	if state == Enums.MonsterState.Chase or state == Enums.MonsterState.Investigate then
		personalThreat = "hunt"
	elseif state == Enums.MonsterState.Alert then
		personalThreat = "alert"
	else
		personalThreat = "none" -- Search/Patrol: it stopped hunting me
	end
end)

-- Safe-room suppression: inside the sanctuary the beds go silent even if a monster lingers just
-- outside the wall (server-authoritative occupancy via the InSafeRoom attribute; the client never
-- self-detects). Without this a monster hovering by the safe-room wall kept the heart pounding,
-- undercutting the PaddedCell reverb + relief bell the sanctuary plays.
local inSafeRoom = player:GetAttribute(Attributes.InSafeRoom) == true
player:GetAttributeChangedSignal(Attributes.InSafeRoom):Connect(function()
	inSafeRoom = player:GetAttribute(Attributes.InSafeRoom) == true
end)

-- Per-rig 3D sounds (breathing loop + footstep one-shots) on the rig's HRP.
local rigAudio = {} -- [rig] = { hrp, breathing, footstep, lastPos, stepAccum, mix, occluded, occAccum, breathBase, footBase, speciesConn }

local function mixFor(species)
	return MA.SpeciesMix[species] or MA.SpeciesMix[Enums.MonsterType.Bunny]
end

local function makeSpatial(id, volume, range, looped)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = Config.Audio.RollOffMin
	s.RollOffMaxDistance = range
	s.SoundGroup = monsterBus
	-- Low-pass for wall occlusion (toggled on when a wall is between you and the rig).
	local eq = Instance.new("EqualizerSoundEffect")
	eq.Name = "Occlude"
	eq.Enabled = false
	eq.Parent = s
	return s
end

-- A ray from the player to the rig, blocked only by world geometry (exclude every rig and
-- every player character), so "occluded" means a WALL is between you and the monster.
local function occlusionParams(rig)
	local filter = { rig }
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)
	if monsters then
		table.insert(filter, monsters)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(filter, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	return params
end

local function applyOcclusion(a, occluded)
	a.occluded = occluded
	a.breathing.Volume = if occluded then a.breathBase * OCC.VolumeScale else a.breathBase
	a.footstep.Volume = if occluded then a.footBase * OCC.VolumeScale else a.footBase
	for _, snd in { a.breathing, a.footstep } do
		local eq = snd:FindFirstChild("Occlude")
		if eq then
			eq.Enabled = occluded
			eq.HighGain = OCC.HighGain
			eq.MidGain = OCC.MidGain
			eq.LowGain = OCC.LowGain
		end
	end
end

-- (Re)derive the per-species mix and push it onto this rig's live sounds. Species can replicate
-- AFTER the HRP (the rig model arrives, its MonsterSpecies attribute lands a frame or two later),
-- so a single early read would strand a monkey rig on the bunny mix forever; addRig applies this
-- once and again on every MonsterSpecies change (RadarController re-reads Species each ping for
-- exactly this reason).
local function applySpecies(a, rig)
	local mix = mixFor(rig:GetAttribute(Attributes.MonsterSpecies) or Enums.MonsterType.Bunny)
	a.mix = mix
	a.breathBase = MA.BreathingVolume * mix.VolumeScale
	a.footBase = MA.FootstepVolume * mix.VolumeScale
	a.breathing.PlaybackSpeed = mix.Pitch
	applyOcclusion(a, a.occluded) -- re-push the breath/foot volumes honoring the current occlusion
end

local function addRig(rig)
	if not rig:IsA("Model") or rigAudio[rig] then
		return
	end
	task.spawn(function()
		local hrp = rig:FindFirstChild("HumanoidRootPart") or rig:WaitForChild("HumanoidRootPart", 5)
		if not hrp or rigAudio[rig] then
			return
		end
		-- Created with placeholder volumes/pitch; applySpecies below sets the real species-derived mix.
		local breathing = makeSpatial(MA.BreathingId, MA.BreathingVolume, MA.BreathingRange, true)
		breathing.Name = "Breathing"
		breathing.Parent = hrp
		breathing:Play()
		local footstep = makeSpatial(MA.FootstepId, MA.FootstepVolume, MA.FootstepRange, false)
		footstep.Name = "Footstep"
		footstep.Parent = hrp
		local a = {
			hrp = hrp,
			breathing = breathing,
			footstep = footstep,
			lastPos = hrp.Position,
			stepAccum = 0,
			mix = mixFor(Enums.MonsterType.Bunny),
			occluded = false,
			occAccum = math.random() * OCC.Interval, -- stagger the rays across rigs
			breathBase = MA.BreathingVolume,
			footBase = MA.FootstepVolume,
		}
		rigAudio[rig] = a
		applySpecies(a, rig)
		a.speciesConn = rig:GetAttributeChangedSignal(Attributes.MonsterSpecies):Connect(function()
			if rigAudio[rig] == a then -- still the live entry (not removed/replaced)
				applySpecies(a, rig)
			end
		end)
	end)
end

local function removeRig(rig)
	local a = rigAudio[rig]
	if a then
		if a.speciesConn then
			a.speciesConn:Disconnect()
		end
		a.breathing:Destroy()
		a.footstep:Destroy()
		rigAudio[rig] = nil
	end
end

-- Bounded wait: if MonsterService errors before parenting the folder, don't yield forever
-- (which would silently disable the rig audio) -- warn and bail. Connect ChildAdded BEFORE the
-- initial sweep so a rig parented mid-sweep can't be missed (addRig is idempotent).
local monstersFolder = Workspace:FindFirstChild(WorldFolders.Monsters)
	or Workspace:WaitForChild(WorldFolders.Monsters, 30)
if not monstersFolder then
	warn("MonsterAudioController: Monsters folder never appeared; rig audio disabled")
	return
end
monstersFolder.ChildAdded:Connect(addRig)
monstersFolder.ChildRemoved:Connect(removeRig)
for _, rig in monstersFolder:GetChildren() do
	addRig(rig)
end

-- The closeness of the nearest HUNTING rig (0..1), scaled by its state: full for
-- Chase/Investigate, softer for Alert, and only if right on top of you otherwise.
local function threatLevel(phrp): number
	local best = 0
	for rig, a in rigAudio do
		if a.hrp.Parent then
			local d = (a.hrp.Position - phrp.Position).Magnitude
			local st = rig:GetAttribute(Attributes.MonsterState)
			local scale = 0
			-- State-driven ramp ONLY when a monster is hunting ME (per-target flag above); a rig
			-- chasing a teammate must not ramp my bed. The panic branch stays target-agnostic: ANY
			-- monster right on top of you spikes the pulse regardless of who it's hunting.
			if
				personalThreat == "hunt" and (st == Enums.MonsterState.Chase or st == Enums.MonsterState.Investigate)
			then
				scale = 1
			elseif personalThreat == "alert" and st == Enums.MonsterState.Alert then
				scale = Config.Chase.AlertScale
			elseif d <= MA.HeartbeatPanicRadius then
				scale = 0.6 -- a monster RIGHT next to you still spikes the pulse (whoever it hunts)
			end
			if scale > 0 and d <= MA.HeartbeatStartDistance then
				local span = math.max(MA.HeartbeatStartDistance - MA.HeartbeatMaxDistance, 1e-3)
				local t = math.clamp((MA.HeartbeatStartDistance - d) / span, 0, 1) * scale
				if t > best then
					best = t
				end
			end
		end
	end
	return best
end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local phrp = character and character:FindFirstChild("HumanoidRootPart")

	-- Per rig: footstep cadence + throttled wall occlusion.
	for rig, a in rigAudio do
		if a.hrp.Parent then
			local moved = (a.hrp.Position - a.lastPos).Magnitude
			a.lastPos = a.hrp.Position
			if moved / dt > MAX_PLAUSIBLE_SPEED then
				moved = 0 -- teleport frame (rig pivoted home); no spurious footstep at home.
			end
			a.stepAccum += moved
			if a.stepAccum >= MA.FootstepStride then
				a.stepAccum = 0
				a.footstep.PlaybackSpeed = a.mix.Pitch * (0.9 + math.random() * 0.2)
				a.footstep:Play()
			end

			a.occAccum += dt
			if a.occAccum >= OCC.Interval and phrp then
				a.occAccum = 0
				local origin = phrp.Position
				local hit = Workspace:Raycast(origin, a.hrp.Position - origin, occlusionParams(rig))
				local occluded = hit ~= nil
				if occluded ~= a.occluded then
					applyOcclusion(a, occluded)
				end
			end
		end
	end

	-- Global: gated heartbeat + adaptive tension bed, both driven by the nearest hunter --
	-- silenced entirely inside a safe room (the sanctuary should feel safe).
	local bestT = if phrp and not inSafeRoom then threatLevel(phrp) else 0
	heartbeat.Volume = MA.HeartbeatVolume * bestT
	heartbeat.PlaybackSpeed = MA.HeartbeatMinRate + (MA.HeartbeatMaxRate - MA.HeartbeatMinRate) * bestT
	local target = MUS.TensionMaxVolume * bestT
	tension.Volume += (target - tension.Volume) * math.min(dt * MUS.FadeRate, 1)
end)
