--!nonstrict
-- MonsterService.server.luau
-- Owns the bunny: builds a valid procedural placeholder rig at each MonsterSpawn,
-- and (in later steps) senses players, drives PathfindingService movement off the
-- Config.Spatial.PollInterval cadence, ticks the pure BunnyFSM, and routes a catch
-- into the existing SpawnService death/respawn. Server-authoritative; the client
-- only renders the rig and plays the jumpscare via the MonsterCaught remote.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Enums = require(ReplicatedStorage.Enums)
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local Remotes = require(ReplicatedStorage.Remotes)
local BunnyFSM = require(script.Parent.BunnyFSM)

local STATE_ATTRIBUTE = "State" -- on the rig model: current Enums.MonsterState (observability/testing)

local monstersFolder = Instance.new("Folder")
monstersFolder.Name = "Monsters"
monstersFolder.Parent = Workspace

Remotes.init()
local caughtRemote = Remotes.get(Remotes.Names.MonsterCaught)
local stateRemote = Remotes.get(Remotes.Names.MonsterStateChanged)

-- A VALID procedural Humanoid rig: a HumanoidRootPart body + a welded Head (a
-- Humanoid needs a Head to be a living character) + a Humanoid with RequiresNeck
-- off and an explicit HipHeight so it stands on the floor and Humanoid:MoveTo can
-- walk it. No art assets -- Config.Monster.Body* are placeholders.
local function createRig(spawnPart): Model
	local rig = Instance.new("Model")
	rig.Name = Enums.MonsterType.Bunny

	-- Invisible physics root: the collision box pathfinding/movement use. It stays the
	-- BodySize box so AgentRadius and corridor fit are unchanged; the visible body is
	-- the welded mascot mesh below.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Config.Monster.BodySize
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = true
	root.Parent = rig

	-- Invisible Head (a Humanoid needs a Head to count as a living character); also
	-- hosts the eye-glow light at roughly face height.
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1, 1, 1)
	head.Transparency = 1
	head.CanCollide = false
	head.Massless = true -- doesn't affect the Humanoid's balance
	head.Parent = rig

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = head
	weld.C0 = CFrame.new(0, Config.Monster.BodySize.Y / 2 + 0.5, 0)
	weld.Parent = root

	-- Visible body: the corrupted-mascot mesh, welded to the invisible root so it moves
	-- with the physics body but never affects pathfinding (CanCollide off, Massless).
	local body = ServerStorage.Assets.BunnyBody:Clone()
	body.Name = "Body"
	body.Anchored = false
	body.CanCollide = false
	body.CanQuery = false
	body.Massless = true
	body.Parent = rig
	local bodyWeld = Instance.new("Weld")
	bodyWeld.Part0 = root
	bodyWeld.Part1 = body
	bodyWeld.C0 = CFrame.new(0, Config.Monster.ModelYOffset, 0)
		* CFrame.Angles(0, math.rad(Config.Monster.ModelFaceYaw), 0)
	bodyWeld.Parent = root

	-- A faint red eye-glow so it reads as "watching" in the dark.
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = Config.Monster.EyeGlowColor
	glow.Brightness = Config.Monster.EyeGlowBrightness
	glow.Range = Config.Monster.EyeGlowRange
	glow.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false -- single-body placeholder has no Neck joint
	humanoid.HipHeight = Config.Monster.BodySize.Y / 2 -- float the root above the floor so it can walk
	humanoid.AutoRotate = true
	humanoid.Parent = rig

	rig.PrimaryPart = root
	rig:PivotTo(CFrame.new(spawnPart.Position + Vector3.new(0, Config.Monster.BodySize.Y, 0)))
	rig.Parent = monstersFolder
	rig:SetAttribute(STATE_ATTRIBUTE, Enums.MonsterState.Patrol)

	-- Keep physics authority on the server so server-driven MoveTo is honored.
	-- pcall: SetNetworkOwner can raise on an unanchored part mid-construction.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return rig
end

-- Raycast params reused each sense: ignore the rig and all player characters, so
-- only world geometry (walls) can block line of sight.
local function sightParams(rig: Model): RaycastParams
	local filter = { rig }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	return params
end

-- Build the FSM's player list: every eligible living player with a visible flag.
-- Eligible = living HRP, NOT in a SafeRoom, NOT won. (A brand-new player whose
-- InSafeRoom/GameState attributes are still nil is intentionally treated as
-- eligible -- not-safe / not-won.) Visible = within DetectRange of the root,
-- inside the DetectHalfAngle cone, and unobstructed by walls.
local function sensePlayers(rig: Model): { any }
	local root = rig.PrimaryPart
	local eyePos = root.Position + Vector3.new(0, Config.Monster.EyeHeight, 0)
	local facing = root.CFrame.LookVector
	local params = sightParams(rig)

	local result = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(Attributes.InSafeRoom) == true then
			continue
		end
		if player:GetAttribute(Attributes.GameState) == Enums.GameState.Won then
			continue
		end
		-- Respawn invulnerability: a freshly (re)spawned player is invisible to the
		-- bunny for Config.Respawn.InvulnSeconds, so it can never instantly re-catch
		-- at the spawn point. The root anti-spawn-camp guard (see SpawnService).
		if player:GetAttribute(Attributes.RespawnGrace) == true then
			continue
		end
		local hrp = PlayerUtil.livingRootPart(player)
		if not hrp then
			continue
		end

		-- Range/cone from the root (consistent with the FSM's flat proximity).
		local toPlayer = hrp.Position - root.Position
		local distance = toPlayer.Magnitude
		local visible = false
		if distance <= Config.Monster.DetectRange and distance > 0 then
			local angle = math.deg(math.acos(math.clamp(facing:Dot(toPlayer.Unit), -1, 1)))
			if angle <= Config.Monster.DetectHalfAngle then
				-- LoS ray from the raised eye to the player's HRP; hit == nil => clear.
				local ray = hrp.Position - eyePos
				local hit = Workspace:Raycast(eyePos, ray, params)
				visible = hit == nil
			end
		end
		table.insert(result, { player = player, position = hrp.Position, visible = visible })
	end
	return result
end

-- Per-rig movement: walks the Humanoid along a PathfindingService path toward a
-- target, recomputing at most every RepathInterval (ComputeAsync yields). Detects
-- stalls (wedged on a corner) and forces a repath, and falls back to steering
-- straight at the target when no path is available.
local function createMover(rig: Model)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local path = PathfindingService:CreatePath({
		AgentRadius = Config.Monster.AgentRadius,
		AgentHeight = Config.Monster.AgentHeight,
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
		if lastPos and (root.Position - lastPos).Magnitude < Config.Monster.StallEpsilon then
			stalledTicks += 1
		else
			stalledTicks = 0
		end
		lastPos = root.Position
		if stalledTicks >= Config.Monster.StallTicks then
			sinceRepath = math.huge
			stalledTicks = 0
		end

		sinceRepath += dt
		if sinceRepath >= Config.Monster.RepathInterval then
			repath(target)
		end

		if #waypoints == 0 then
			humanoid:MoveTo(target) -- direct fallback
			return
		end
		while waypointIndex <= #waypoints do
			local wp = waypoints[waypointIndex].Position
			if
				(Vector3.new(wp.X, root.Position.Y, wp.Z) - root.Position).Magnitude
				< Config.Monster.WaypointReachedDistance
			then
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

local warnedNoPatrol = false
local function patrolNodePositions(): { Vector3 }
	local nodes = {}
	for _, m in Discovery.getAll(Tags.PatrolPoint) do
		if m:IsA("BasePart") then
			table.insert(nodes, m.Position)
		end
	end
	if #nodes == 0 and not warnedNoPatrol then
		warnedNoPatrol = true
		warn("[MonsterService] No PatrolPoint markers found; the bunny will idle near its spawn.")
	end
	return nodes
end

local instances = {} -- { { rig = Model, state = FSMState, mover = Mover } }

local warnedNoSpawn = false
local function spawnBunnies()
	local spawns = Discovery.getAll(Tags.MonsterSpawn)
	if #spawns == 0 then
		if not warnedNoSpawn then
			warnedNoSpawn = true
			warn("[MonsterService] No MonsterSpawn marker found; no bunny spawned.")
		end
		return
	end
	for _, spawnPart in spawns do
		if spawnPart:IsA("BasePart") then
			local rig = createRig(spawnPart)
			table.insert(instances, {
				rig = rig,
				state = BunnyFSM.newState(),
				mover = createMover(rig),
				spawnPart = spawnPart, -- home to repel the rig to on a catch
				dormantUntil = 0, -- os.clock() until which this rig senses nothing (post-catch)
				prevState = Enums.MonsterState.Patrol, -- last state we fired MonsterStateChanged for
				prevTargetUserId = nil, -- the player it was chasing last tick (so a fade fires to them)
			})
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
local function catch(inst, player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return
	end
	humanoid.Health = 0
	caughtRemote:FireClient(player)

	if Config.Monster.ResetToPatrolOnCatch then
		inst.state = BunnyFSM.newState()
		local spawnPart = inst.spawnPart
		if spawnPart and inst.rig.PrimaryPart then
			inst.rig:PivotTo(CFrame.new(spawnPart.Position + Vector3.new(0, Config.Monster.BodySize.Y, 0)))
		end
		inst.dormantUntil = os.clock() + Config.Monster.PostCatchDormantSeconds
	end
end

spawnBunnies()

-- Server-authoritative tick on the shared poll cadence (never Touched). dt comes
-- from os.clock deltas so FSM timers stay accurate even when ComputeAsync yields.
local lastClock = os.clock()
while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	-- Clamp dt: a server hitch (ComputeAsync yields, GC pause) must not let a single
	-- tick advance the FSM past LoseSightSeconds / SearchDuration in one jump.
	local dt = math.min(now - lastClock, Config.Spatial.PollInterval * Config.Monster.MaxTickDtFactor)
	lastClock = now
	local nodes = patrolNodePositions()
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
			-- Dormant after a catch: sense nothing, so the (freshly reset) FSM just
			-- patrols home instead of re-acquiring the player at the kill/respawn site.
			local dormant = now < (inst.dormantUntil or 0)
			local sensed = {
				dt = dt,
				rigPosition = root.Position,
				patrolNodes = nodes,
				players = if dormant then {} else sensePlayers(rig),
			}
			local result = BunnyFSM.tick(inst.state, sensed)
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = result.speed
			end
			inst.mover.update(result.moveTarget, dt)
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
