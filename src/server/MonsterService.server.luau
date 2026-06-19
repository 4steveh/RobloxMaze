--!nonstrict
-- MonsterService.server.luau
-- Owns the bunny: builds a valid procedural placeholder rig at each MonsterSpawn,
-- and (in later steps) senses players, drives PathfindingService movement off the
-- Config.Spatial.PollInterval cadence, ticks the pure BunnyFSM, and routes a catch
-- into the existing SpawnService death/respawn. Server-authoritative; the client
-- only renders the rig and plays the jumpscare via the MonsterCaught remote.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Enums = require(ReplicatedStorage.Enums)

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
