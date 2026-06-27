--!nonstrict
-- MonsterAnimController.client.luau
-- Procedural creature locomotion -- the fix for "the monster just glides along the
-- floor". Each monster rig carries a cosmetic Motor6D skeleton on top of its UNCHANGED
-- physics root; this controller animates those joints' `Transform` every simulation
-- step so the body moves like a real creature (the bunny HOPS), with the gait cadence
-- derived from the rig's actual replicated ground speed -- so motion and animation can
-- never desync. Render-only and exploit-safe: it reads only replicated positions/state,
-- writes only the non-replicated `Transform` channel (no Animator, zero bandwidth), and
-- decides nothing -- the same client-cosmetic class as FlickerController/dust that
-- CLAUDE.md permits. Mirrors MonsterAudioController's rig observation.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Enums = require(ReplicatedStorage.Enums)
local Gaits = require(ReplicatedStorage.Gaits)
local Attributes = require(ReplicatedStorage.Attributes)
local WorldFolders = require(ReplicatedStorage.WorldFolders)

local STATE_ATTRIBUTE = Attributes.MonsterState -- matches the rig attribute MonsterService writes

-- [rig] = { root, joints = { [Part1Name] = Motor6D }, species, lastPos, speed, phase, moveW, chaseW, speciesConn }
local rigs = {}

-- A catch/round-reset teleports the rig home (PivotTo); that one-frame jump reads as a huge
-- instantaneous speed. Real creature locomotion stays well under this, so any planar speed
-- above it is a teleport frame to reject -- not motion to animate (which would twitch the gait).
local MAX_PLAUSIBLE_SPEED = 80 -- studs/s

-- Every cosmetic joint, keyed by the segment (Part1) name the gait recipe returns.
local function collectJoints(rig)
	local joints = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			joints[d.Part1.Name] = d
		end
	end
	return joints
end

local function addRig(rig)
	if not rig:IsA("Model") or rigs[rig] then
		return
	end
	task.spawn(function()
		local root = rig:WaitForChild("HumanoidRootPart", 5)
		if not root or rigs[rig] then
			return
		end
		-- Descendants can replicate slightly after the model arrives; retry until the
		-- cosmetic joints are present (bounded so a malformed rig never spins forever).
		local joints
		for _ = 1, 20 do
			joints = collectJoints(rig)
			if next(joints) ~= nil then
				break
			end
			task.wait(0.05)
		end
		if rigs[rig] then
			return
		end
		local s = {
			root = root,
			joints = joints or {},
			species = rig:GetAttribute(Attributes.MonsterSpecies) or Enums.MonsterType.Bunny,
			lastPos = root.Position,
			speed = 0,
			phase = 0,
			moveW = 0,
			chaseW = 0,
		}
		rigs[rig] = s
		-- Species can replicate slightly after the model arrives; re-read it on change so a monkey
		-- rig can't be stranded on the bunny gait (same late-replication guard the rig audio uses).
		s.speciesConn = rig:GetAttributeChangedSignal(Attributes.MonsterSpecies):Connect(function()
			if rigs[rig] == s then -- still the live entry (not removed/replaced)
				s.species = rig:GetAttribute(Attributes.MonsterSpecies) or Enums.MonsterType.Bunny
			end
		end)
	end)
end

local function removeRig(rig)
	local s = rigs[rig]
	if s and s.speciesConn then
		s.speciesConn:Disconnect()
	end
	rigs[rig] = nil
end

-- Bounded wait: if MonsterService errors before parenting the folder, don't yield forever
-- (which would silently disable the gait) -- warn and bail. Connect ChildAdded BEFORE the
-- initial sweep so a rig parented mid-sweep can't be missed (addRig is idempotent).
local monstersFolder = Workspace:FindFirstChild(WorldFolders.Monsters)
	or Workspace:WaitForChild(WorldFolders.Monsters, 30)
if not monstersFolder then
	warn("MonsterAnimController: Monsters folder never appeared; gait disabled")
	return
end
monstersFolder.ChildAdded:Connect(addRig)
monstersFolder.ChildRemoved:Connect(removeRig)
for _, rig in monstersFolder:GetChildren() do
	addRig(rig)
end

-- Critically-damped approach (frame-rate independent), so weights never snap.
local function approach(current, target, rate, dt)
	return current + (target - current) * math.min(dt * rate, 1)
end

-- Per-species gait recipe + its Config.Monster.Anim params. Adding a species is a row.
local GAIT = {
	[Enums.MonsterType.Bunny] = Gaits.bunny,
	[Enums.MonsterType.Monkey] = Gaits.monkey,
}
local ANIM = {
	[Enums.MonsterType.Bunny] = Config.Monster.Anim.Bunny,
	[Enums.MonsterType.Monkey] = Config.Monster.Anim.Monkey,
}

-- A rig in an aggressive pursuit state -> the gait flattens/quickens/hunches.
local function isAggressive(rig): boolean
	local st = rig:GetAttribute(STATE_ATTRIBUTE)
	return st == Enums.MonsterState.Chase or st == Enums.MonsterState.Investigate
end

RunService.PreSimulation:Connect(function(dt)
	if dt <= 0 then
		return
	end
	local now = os.clock()
	for rig, s in rigs do
		local root = s.root
		local p = ANIM[s.species]
		local gait = GAIT[s.species]
		if root and root.Parent and p and gait then
			-- Measured planar (XZ) ground speed from REPLICATED motion -- exploit-safe.
			local delta = root.Position - s.lastPos
			s.lastPos = root.Position
			local planar = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
			if planar > MAX_PLAUSIBLE_SPEED then
				planar = 0 -- teleport frame (rig pivoted home); measure cleanly next frame.
			end
			s.speed = approach(s.speed, planar, p.SpeedSmoothing, dt)

			-- Blend weights: move (fade the gait in) and chase (flatten/quicken/hunch it).
			local moveTarget = math.clamp(s.speed / p.RefSpeed, 0, 1)
			s.moveW = approach(s.moveW, moveTarget, p.WeightSmoothing, dt)
			local chaseTarget = isAggressive(rig) and 1 or 0
			s.chaseW = approach(s.chaseW, chaseTarget, p.WeightSmoothing, dt)

			-- Advance the gait phase from real speed: one stride per StrideDistance studs
			-- travelled (shorter/faster when hunting). Idle freezes it so the rig settles.
			if s.speed >= p.MinMoveSpeed then
				local stride = p.StrideDistance * (1 - s.chaseW * (1 - p.ChaseStrideScale))
				s.phase = (s.phase + (s.speed / math.max(stride, 0.1)) * dt) % 1
			end

			local offsets = gait(s.phase, now, { move = s.moveW, chase = s.chaseW }, p)
			for name, cf in offsets do
				local m = s.joints[name]
				if m then
					m.Transform = cf
				end
			end
		end
	end
end)
