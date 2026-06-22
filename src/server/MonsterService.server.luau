--!nonstrict
-- MonsterService.server.luau
-- Owns the monster ROSTER: builds a rig per species at its spawn markers, senses each
-- player (vision cone + LoS for sight; server-computed noise for hearing) off the
-- Config.Spatial.PollInterval cadence, ticks that rig's pure FSM with its resolved cfg,
-- drives PathfindingService movement, and routes a catch into the SpawnService
-- death/respawn. Species-agnostic: a `SPECIES` dispatch table maps each Enums.MonsterType
-- to its { fsm, cfg, spawnTag }, and each rig stores its own fsm/cfg, so the bunny
-- (vision stalker) and monkey (noise hunter) run side by side through one loop.
-- Server-authoritative; the client only renders the rig and plays the jumpscare cue.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Enums = require(ReplicatedStorage.Enums)
local Attributes = require(ReplicatedStorage.Attributes)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local Remotes = require(ReplicatedStorage.Remotes)
local BunnyFSM = require(script.Parent.BunnyFSM)
local MonkeyFSM = require(script.Parent.MonkeyFSM)
local MonsterRig = require(script.Parent.MonsterRig)
local ServerSignals = require(script.Parent.ServerSignals)

local STATE_ATTRIBUTE = Attributes.MonsterState -- on the rig model: current Enums.MonsterState

local monstersFolder = Instance.new("Folder")
monstersFolder.Name = WorldFolders.Monsters
monstersFolder.Parent = Workspace

Remotes.init()
local stateRemote = Remotes.get(Remotes.Names.MonsterStateChanged)
-- A catch hands the OUTCOME to DownedService (down vs kill) via this signal; MonsterService
-- stays out of player-life logic (it only repels its rig home so it never camps the body).
local playerCaughtSignal = ServerSignals.get(ServerSignals.Names.PlayerCaught)

-- Resolve a species' Config slice: the Shared cross-species plumbing overlaid with
-- the species' own behaviour/rig fields (the species wins on any overlap). This is
-- the `cfg` we inject into the FSM (BunnyFSM.tick(state, sensed, cfg)) and read for
-- the rig/mover, so multiple species coexist without one flat config namespace.
local function resolveSpecies(name: string)
	local M = Config.Monster
	local cfg = table.clone(M.Shared) -- mutable shallow copy of the frozen Shared slice
	for k, v in M.Species[name] do
		cfg[k] = v
	end
	return cfg
end

-- Cross-species constants the tick loop reads directly (not per-rig).
local SHARED = Config.Monster.Shared
local AGGRO = Config.Aggression

-- World NOISE events (a sprung trap, via ServerSignals.NoiseEvent): the near-blind monkey
-- investigates the loudest recent one. We store only the LATEST; the tick loop hands it to each
-- eligible (hearing, in-range, not-dormant) rig exactly ONCE (tracked by event id), so it reads as
-- a single fresh transition rather than re-firing every tick. The deaf bunny ignores it (no HearRange).
local latestNoise = nil -- { pos = Vector3, id = number, expiresAt = os.clock() }
local noiseIdCounter = 0
ServerSignals.get(ServerSignals.Names.NoiseEvent).Event:Connect(function(pos)
	if typeof(pos) ~= "Vector3" then
		return
	end
	noiseIdCounter += 1
	latestNoise = { pos = pos, id = noiseIdCounter, expiresAt = os.clock() + SHARED.NoiseEventReactSeconds }
end)

-- The maze's current aggression (0..1): how close the closest player is to winning
-- (best KeyCount / RequiredToWin, server-read). Scales monster speed + sense range so the
-- hunt tightens as the round nears its end. 0 when aggression is disabled.
local function currentAggression(): number
	if not AGGRO.Enabled then
		return 0
	end
	local best = 0
	for _, player in Players:GetPlayers() do
		local kc = player:GetAttribute(Attributes.KeyCount) or 0
		if kc > best then
			best = kc
		end
	end
	return math.clamp(best / math.max(Config.Keys.RequiredToWin, 1), 0, 1)
end

-- The roster: each species -> its FSM module, resolved cfg slice, and spawn tag. Adding
-- a species is one row here (+ its Config slice + FSM module + a placed spawn marker).
local SPECIES = {
	[Enums.MonsterType.Bunny] = {
		fsm = BunnyFSM,
		cfg = resolveSpecies(Enums.MonsterType.Bunny),
		spawnTag = Tags.MonsterSpawn,
	},
	[Enums.MonsterType.Monkey] = {
		fsm = MonkeyFSM,
		cfg = resolveSpecies(Enums.MonsterType.Monkey),
		spawnTag = Tags.MonkeySpawn,
	},
}

-- One sight RaycastParams built ONCE per tick (not per rig): exclude every monster rig
-- (the whole Monsters folder) and all player characters, so only world geometry (walls)
-- blocks line of sight. Excluding all rigs also means one monster never hides a player
-- from another's vision -- desirable, and it lets every rig share one params object.
local function buildSightParams(playerChars: { Instance }): RaycastParams
	local filter = { monstersFolder }
	for _, character in playerChars do
		table.insert(filter, character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	return params
end

-- Build a rig's sensed player list: each eligible living player with a `visible` flag
-- (the species' sight cone + LoS) and a `noise` value (effectiveNoise = the player's
-- server-computed NoiseLevel x distance falloff over cfg.HearRange -- only for a species
-- that hears, i.e. cfg.HearRange set; nil for the deaf bunny). Eligible = living HRP, NOT
-- in a SafeRoom / Won / RespawnGrace (a brand-new player whose attributes are still nil
-- is treated as eligible). SafeRoom/Won/Grace also silences the monkey (those players
-- leave the sensed set entirely, so it can neither see nor hear them).
local function sensePlayers(rig: Model, cfg, rangeMul: number, params: RaycastParams): { any }
	local root = rig.PrimaryPart
	local eyePos = root.Position + Vector3.new(0, cfg.EyeHeight, 0)
	local facing = root.CFrame.LookVector
	-- Aggression widens the senses as the round nears its end (rangeMul >= 1).
	local detectRange = cfg.DetectRange * rangeMul

	local result = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(Attributes.InSafeRoom) == true then
			continue
		end
		if player:GetAttribute(Attributes.GameState) == Enums.GameState.Won then
			continue
		end
		-- Respawn invulnerability: a freshly (re)spawned player is invisible to every
		-- monster for Config.Respawn.InvulnSeconds (the root anti-spawn-camp guard).
		if player:GetAttribute(Attributes.RespawnGrace) == true then
			continue
		end
		-- A DOWNED player is already caught — the monster moves on (no camping the body),
		-- so it can't instantly re-grab them at zero or interrupt a revive.
		if player:GetAttribute(Attributes.Downed) == true then
			continue
		end
		local hrp = PlayerUtil.livingRootPart(player)
		if not hrp then
			continue
		end

		local toPlayer = hrp.Position - root.Position
		local distance = toPlayer.Magnitude

		-- Sight: within the (aggression-scaled) detect range, inside the cone, unobstructed.
		local visible = false
		if distance <= detectRange and distance > 0 then
			local angle = math.deg(math.acos(math.clamp(facing:Dot(toPlayer.Unit), -1, 1)))
			if angle <= cfg.DetectHalfAngle then
				local ray = hrp.Position - eyePos
				visible = Workspace:Raycast(eyePos, ray, params) == nil
			end
		end

		-- Hearing (species with cfg.HearRange only): effectiveNoise = NoiseLevel x linear
		-- distance falloff. NO line of sight -- it hears straight through walls.
		local noise = nil
		if cfg.HearRange then
			local level = player:GetAttribute(Attributes.NoiseLevel) or 0
			noise = level * math.clamp(1 - distance / (cfg.HearRange * rangeMul), 0, 1)
		end

		table.insert(result, { player = player, position = hrp.Position, visible = visible, noise = noise })
	end
	return result
end

-- Per-rig movement: walks the Humanoid along a PathfindingService path toward a
-- target, recomputing at most every RepathInterval (ComputeAsync yields). Detects
-- stalls (wedged on a corner) and forces a repath, and falls back to steering
-- straight at the target when no path is available.
local function createMover(rig: Model, cfg)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local path = PathfindingService:CreatePath({
		AgentRadius = cfg.AgentRadius,
		AgentHeight = cfg.AgentHeight,
		AgentCanJump = false,
	})
	local waypoints = {}
	local waypointIndex = 1
	local sinceRepath = math.huge -- force a path on the first update
	local lastPos = nil
	local stalledTicks = 0

	local function repath(target: Vector3)
		local root = rig.PrimaryPart
		local ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
			waypointIndex = 1
		else
			waypoints = {} -- fall back to direct steering
		end
		sinceRepath = 0
	end

	local mover = {}
	function mover.update(target: Vector3?, dt: number)
		local root = rig.PrimaryPart
		if not root then
			return
		end
		if target == nil then
			humanoid:MoveTo(root.Position) -- stand still at the current spot
			lastPos = root.Position
			stalledTicks = 0
			return
		end

		-- Stall recovery: barely moving toward a real target -> force a repath.
		if lastPos and (root.Position - lastPos).Magnitude < cfg.StallEpsilon then
			stalledTicks += 1
		else
			stalledTicks = 0
		end
		lastPos = root.Position
		if stalledTicks >= cfg.StallTicks then
			sinceRepath = math.huge
			stalledTicks = 0
		end

		sinceRepath += dt
		if sinceRepath >= cfg.RepathInterval then
			repath(target)
		end

		if #waypoints == 0 then
			humanoid:MoveTo(target) -- direct fallback
			return
		end
		while waypointIndex <= #waypoints do
			local wp = waypoints[waypointIndex].Position
			if (Vector3.new(wp.X, root.Position.Y, wp.Z) - root.Position).Magnitude < cfg.WaypointReachedDistance then
				waypointIndex += 1
			else
				break
			end
		end
		if waypointIndex <= #waypoints then
			humanoid:MoveTo(waypoints[waypointIndex].Position)
		else
			humanoid:MoveTo(target)
		end
	end

	return mover
end

-- The monkey's nest(s) -- the bunny's patrol graph excludes nodes within NestExclusionRadius of
-- these so the two species own distinct turf (the monkey GUARDS its nest/exit; the bunny roams
-- the rest), instead of both pacing the same central corridor. Markers don't move, so cache once.
local cachedMonkeyNests: { Vector3 }? = nil
local function monkeyNestPositions(): { Vector3 }
	if cachedMonkeyNests then
		return cachedMonkeyNests
	end
	local nests = {}
	for _, m in Discovery.getAll(Tags.MonkeySpawn) do
		if m:IsA("BasePart") then
			table.insert(nests, m.Position)
		end
	end
	cachedMonkeyNests = nests
	return nests
end

local warnedNoPatrol = false
local function patrolNodePositions(): { Vector3 }
	local nests = monkeyNestPositions()
	local exclSq = SHARED.NestExclusionRadius * SHARED.NestExclusionRadius
	local nodes = {}
	for _, m in Discovery.getAll(Tags.PatrolPoint) do
		if m:IsA("BasePart") then
			local pos = m.Position
			local nearNest = false
			for _, nest in nests do
				local dx, dz = pos.X - nest.X, pos.Z - nest.Z
				if dx * dx + dz * dz <= exclSq then
					nearNest = true
					break
				end
			end
			if not nearNest then
				table.insert(nodes, pos)
			end
		end
	end
	if #nodes == 0 and not warnedNoPatrol then
		warnedNoPatrol = true
		warn(
			"[MonsterService] No usable PatrolPoint markers (after monkey-nest exclusion); the bunny will idle near its spawn."
		)
	end
	return nodes
end

local instances = {} -- { { rig = Model, state = FSMState, mover = Mover } }

local warnedNoSpawn = {} -- [species] = true once we've warned about a missing spawn marker
local function spawnMonsters()
	for speciesName, def in SPECIES do
		local spawns = Discovery.getAll(def.spawnTag)
		if #spawns == 0 then
			if not warnedNoSpawn[speciesName] then
				warnedNoSpawn[speciesName] = true
				warn(`[MonsterService] No {def.spawnTag} marker found; no {speciesName} spawned.`)
			end
			continue
		end
		for _, spawnPart in spawns do
			if spawnPart:IsA("BasePart") then
				local rig = MonsterRig.build(speciesName, def.cfg, spawnPart, monstersFolder)
				rig:SetAttribute(STATE_ATTRIBUTE, Enums.MonsterState.Patrol) -- MonsterService owns State from here
				table.insert(instances, {
					rig = rig,
					fsm = def.fsm, -- this rig's brain (BunnyFSM / MonkeyFSM)
					cfg = def.cfg, -- this rig's resolved Config slice
					species = speciesName,
					state = def.fsm.newState(),
					mover = createMover(rig, def.cfg),
					spawnPart = spawnPart, -- home to repel the rig to on a catch
					dormantUntil = 0, -- os.clock() until which this rig senses nothing (post-catch)
					lastNoiseId = 0, -- id of the last world NoiseEvent this rig consumed (deliver-once)
					prevState = Enums.MonsterState.Patrol, -- last state we fired MonsterStateChanged for
					prevTargetUserId = nil, -- the player it was chasing last tick (so a fade fires to them)
				})
			end
		end
	end
end

-- A catch reuses the hardened death/respawn: kill the player and cue the client
-- jumpscare. SpawnService handles RespawnDelay -> respawn at the checkpoint.
--
-- It ALSO breaks the spawn-camp at its root (the #1 player complaint): clearing the
-- FSM drops Chase/lastSeen so the bunny stops loitering on the kill site, the rig is
-- sent home to its MonsterSpawn, and it goes dormant (senses nothing) through the
-- respawn window -- so it can't already be on top of the player when they reappear.
-- Clear a rig's FSM, send it home to its spawn, and make it dormant for the post-catch
-- window. Shared by a catch (anti-spawn-camp) and a round reset (fresh start, no rig left
-- loitering on a player from the previous round).
local function repelHome(inst)
	inst.state = inst.fsm.newState()
	local spawnPart = inst.spawnPart
	if spawnPart and inst.rig.PrimaryPart then
		inst.rig:PivotTo(CFrame.new(spawnPart.Position + Vector3.new(0, inst.cfg.BodySize.Y, 0)))
	end
	inst.dormantUntil = os.clock() + inst.cfg.PostCatchDormantSeconds
	inst.rig:SetAttribute(Attributes.MonsterStunnedUntil, 0) -- a fresh start is never mid-stun
	inst.rig:SetAttribute(STATE_ATTRIBUTE, inst.state.name)
	inst.prevState = inst.state.name
	inst.prevTargetUserId = nil
end

local function catch(inst, player: Player)
	if player:GetAttribute(Attributes.Downed) == true then
		return -- already down; don't re-trigger the outcome
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return
	end
	-- Hand the outcome to DownedService (down vs kill); MonsterService doesn't own player life.
	-- Pass the SPECIES so the jumpscare shows the monster that actually caught you (not whichever
	-- rig the client happened to find first).
	playerCaughtSignal:Fire(player, inst.species)

	if inst.cfg.ResetToPatrolOnCatch then
		repelHome(inst)
	end
end

spawnMonsters()

-- New round: reset every rig (clear the FSM, send it home, brief dormancy) so no monster
-- is left chasing a player from the round that just ended.
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	for _, inst in instances do
		pcall(repelHome, inst)
	end
end)

-- Server-authoritative tick on the shared poll cadence (never Touched). dt comes
-- from os.clock deltas so FSM timers stay accurate even when ComputeAsync yields.
local lastClock = os.clock()
while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	-- Server clock for trap-stun deadlines (TrapService writes StunnedUntil in this clock).
	local serverNow = Workspace:GetServerTimeNow()
	-- Clamp dt: a server hitch (ComputeAsync yields, GC pause) must not let a single
	-- tick advance an FSM past its timers in one jump.
	local dt = math.min(now - lastClock, Config.Spatial.PollInterval * SHARED.MaxTickDtFactor)
	lastClock = now
	local nodes = patrolNodePositions()
	-- The hunt tightens as the round nears its end (computed once per tick, applied to
	-- every rig's sense range and move speed).
	local aggro = currentAggression()
	local rangeMul = 1 + aggro * AGGRO.MaxRangeBonus
	local speedMul = 1 + aggro * AGGRO.MaxSpeedBonus
	-- Player-character list + the shared sight params, built ONCE per tick (not per rig).
	local playerChars = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(playerChars, player.Character)
		end
	end
	local sightParams = buildSightParams(playerChars)
	for _, inst in instances do
		-- Per-rig isolation: a throw on one rig (PrimaryPart cleared mid-frame, MoveTo
		-- on a destroyed Humanoid, a raycast edge case) must NOT kill the loop and
		-- freeze every monster forever. Warn and carry on.
		local ok, err = pcall(function()
			local rig = inst.rig
			local root = rig.PrimaryPart
			if not (root and rig.Parent) then
				return
			end
			-- Trap stun: a rig that ran over an armed floor trap (TrapService wrote StunnedUntil)
			-- stands FROZEN -- WalkSpeed 0, no move -- so a player who baited it across the trap
			-- gets a real escape gap. It keeps its FSM state and resumes the hunt when the stun
			-- expires (skip sensing + the FSM tick this frame; the dart/thunk FX already played).
			local stunnedUntil = rig:GetAttribute(Attributes.MonsterStunnedUntil)
			if stunnedUntil and serverNow < stunnedUntil then
				local stunnedHum = rig:FindFirstChildOfClass("Humanoid")
				if stunnedHum then
					stunnedHum.WalkSpeed = 0
				end
				inst.mover.update(nil, dt)
				return
			end
			-- Dormant after a catch: sense nothing, so the (freshly reset) FSM just
			-- patrols home instead of re-acquiring the player at the kill/respawn site.
			local dormant = now < (inst.dormantUntil or 0)
			-- Deliver a world noise event to this rig ONCE: only a HEARING rig (cfg.HearRange =
			-- the monkey), awake, in range of a still-fresh event it hasn't already consumed.
			local noiseEvent = nil
			if not dormant and inst.cfg.HearRange and latestNoise and now < latestNoise.expiresAt then
				if
					inst.lastNoiseId ~= latestNoise.id
					and (latestNoise.pos - root.Position).Magnitude <= inst.cfg.HearRange
				then
					noiseEvent = latestNoise.pos
					inst.lastNoiseId = latestNoise.id
				end
			end
			local sensed = {
				dt = dt,
				rigPosition = root.Position,
				patrolNodes = nodes,
				homePosition = (inst.spawnPart and inst.spawnPart.Position) or root.Position, -- the nest/spawn
				players = if dormant then {} else sensePlayers(rig, inst.cfg, rangeMul, sightParams),
				noiseEvent = noiseEvent,
			}
			local result = inst.fsm.tick(inst.state, sensed, inst.cfg)
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = result.speed * speedMul
			end
			inst.mover.update(result.moveTarget, dt)

			-- Face-while-standing (the monkey's Alert "it heard you" snap): when an FSM
			-- returns a faceTarget and no movement, smoothly yaw the rig toward it.
			if result.moveTarget == nil and result.faceTarget then
				local from = root.Position
				local look = Vector3.new(result.faceTarget.X, from.Y, result.faceTarget.Z)
				if (look - from).Magnitude > 0.1 then
					root.CFrame = root.CFrame:Lerp(CFrame.lookAt(from, look), 0.35)
				end
			end
			rig:SetAttribute(STATE_ATTRIBUTE, inst.state.name)

			-- Per-player chase signal: when this rig's FSM state changes, tell the chased
			-- player (or the one it just stopped chasing) so their MonsterAudioController
			-- can hit or clear the chase sting -- correct even with multiple players.
			if inst.state.name ~= inst.prevState then
				local uid = inst.state.targetUserId or inst.prevTargetUserId
				local target = uid and Players:GetPlayerByUserId(uid)
				if target then
					stateRemote:FireClient(target, inst.state.name)
				end
				inst.prevState = inst.state.name
			end
			inst.prevTargetUserId = inst.state.targetUserId

			if result.caught then
				catch(inst, result.caught)
			end
		end)
		if not ok then
			warn("[MonsterService] tick error on a rig (skipped this tick):", err)
		end
	end
end
