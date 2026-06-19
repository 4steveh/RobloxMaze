--!nonstrict
-- MonsterService.server.luau
-- Owns the bunny: builds a valid procedural placeholder rig at each MonsterSpawn,
-- and (in later steps) senses players, drives PathfindingService movement off the
-- Config.Spatial.PollInterval cadence, ticks the pure BunnyFSM, and routes a catch
-- into the existing SpawnService death/respawn. Server-authoritative; the client
-- only renders the rig and plays the jumpscare via the MonsterCaught remote.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Enums = require(ReplicatedStorage.Enums)
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)

local STATE_ATTRIBUTE = "State" -- on the rig model: current Enums.MonsterState (observability/testing)

local monstersFolder = Instance.new("Folder")
monstersFolder.Name = "Monsters"
monstersFolder.Parent = Workspace

-- A VALID procedural Humanoid rig: a HumanoidRootPart body + a welded Head (a
-- Humanoid needs a Head to be a living character) + a Humanoid with RequiresNeck
-- off and an explicit HipHeight so it stands on the floor and Humanoid:MoveTo can
-- walk it. No art assets -- Config.Monster.Body* are placeholders.
local function createRig(spawnPart): Model
	local rig = Instance.new("Model")
	rig.Name = Enums.MonsterType.Bunny

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Config.Monster.BodySize
	root.Color = Config.Monster.BodyColor
	root.Anchored = false
	root.CanCollide = true
	root.Parent = rig

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1, 1, 1)
	head.Color = Config.Monster.BodyColor
	head.CanCollide = false
	head.Massless = true -- doesn't affect the Humanoid's balance
	head.Parent = rig

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = head
	weld.C0 = CFrame.new(0, Config.Monster.BodySize.Y / 2 + 0.5, 0)
	weld.Parent = root

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
	root:SetNetworkOwner(nil)
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

-- Debug seam (server-only) so the Task 7 playtest can call the real function.
-- Not read by any game logic. shared[] is truly cross-script on the server
-- (unlike _G which is per-environment); the test reads it via execute_luau Server.
-- selene: allow(global_usage)
_G.__MonsterSensePlayers = sensePlayers
-- selene: allow(global_usage)
shared.__MonsterSensePlayers = sensePlayers

-- One bunny per MonsterSpawn marker (MVP expects one). Warn once if none exist.
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
			createRig(spawnPart)
		end
	end
end

spawnBunnies()
