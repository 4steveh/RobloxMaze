--!nonstrict
-- MonsterPresenceFXController.client.luau
-- Makes the creatures feel PHYSICAL instead of ghostly. On each rig it attaches two client-only
-- cosmetic emitters:
--   * foot dust -- kicked up under the body, its rate scaled by the rig's actual replicated
--     ground speed, so a sprinting hunter leaves a churned-up trail and a still one leaves none;
--   * breath fog -- a faint puff drifting from the head, panting faster while it's hunting.
-- Together with MonsterAnimController's gait, a creature you glimpse in the dark now disturbs the
-- ground and breathes. Render-only and exploit-safe: it reads only replicated position/state and
-- creates only LOCAL instances (never replicated, never touched by the server) -- the same
-- MonsterAnimController cosmetic class CLAUDE.md permits. Mirrors its rig observation.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Enums = require(ReplicatedStorage.Enums)
local Attributes = require(ReplicatedStorage.Attributes)
local WorldFolders = require(ReplicatedStorage.WorldFolders)

local M = Config.MonsterFX
if not M.Enabled then
	return
end

local STATE = Attributes.MonsterState
local rigs = {} -- [rig] = { root, dust, breath, lastPos, speed }

-- The head that hosts the breath: the visible CHead if present, else the (invisible) Head, else
-- the root -- the emitter just needs a point near the face. Forward is host-local -Z (matches
-- the rig's eye placement convention in MonsterRig).
local function breathHost(rig, root)
	return rig:FindFirstChild("CHead") or rig:FindFirstChild("Head") or root
end

local function makeFootDust(root): ParticleEmitter
	local att = Instance.new("Attachment")
	att.Name = "FXFoot"
	att.Position = Vector3.new(0, -root.Size.Y / 2 + 0.2, 0) -- at the base of the collision box
	att.Parent = root

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = M.DustTexture
	dust.Color = ColorSequence.new(M.DustColor)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, M.DustSize * 0.4),
		NumberSequenceKeypoint.new(1, M.DustSize),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(M.DustLifetime * 0.7, M.DustLifetime)
	dust.Rate = 0 -- driven by speed below
	dust.Speed = NumberRange.new(0.4, 1.4)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Acceleration = Vector3.new(0, M.DustRise, 0)
	dust.LightInfluence = 1
	dust.LockedToPart = false -- the dust stays where it was kicked up, the creature moves on
	dust.Parent = att
	return dust
end

local function makeBreath(host): ParticleEmitter
	local att = Instance.new("Attachment")
	att.Name = "FXBreath"
	att.Position = Vector3.new(0, 0, -host.Size.Z * 0.5) -- just in front of the face (host -Z)
	att.Parent = host

	local breath = Instance.new("ParticleEmitter")
	breath.Texture = M.BreathTexture
	breath.Color = ColorSequence.new(M.BreathColor)
	breath.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, M.BreathSize * 0.5),
		NumberSequenceKeypoint.new(1, M.BreathSize),
	})
	breath.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, M.BreathTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	breath.Lifetime = NumberRange.new(M.BreathLifetime * 0.7, M.BreathLifetime)
	breath.Rate = M.BreathRate
	breath.Speed = NumberRange.new(M.BreathSpeed * 0.5, M.BreathSpeed)
	breath.SpreadAngle = Vector2.new(28, 28)
	breath.Acceleration = Vector3.new(0, 0.6, 0) -- breath rises as it dissipates
	breath.LightInfluence = 1
	breath.LockedToPart = false
	breath.Parent = att
	return breath
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
		rigs[rig] = {
			root = root,
			dust = makeFootDust(root),
			breath = makeBreath(breathHost(rig, root)),
			lastPos = root.Position,
			speed = 0,
		}
	end)
end

local function removeRig(rig)
	rigs[rig] = nil
end

local monstersFolder = Workspace:WaitForChild(WorldFolders.Monsters)
for _, rig in monstersFolder:GetChildren() do
	addRig(rig)
end
monstersFolder.ChildAdded:Connect(addRig)
monstersFolder.ChildRemoved:Connect(removeRig)

local span = M.DustFullSpeed - M.DustMoveSpeed
RunService.Heartbeat:Connect(function(dt)
	if dt <= 0 then
		return
	end
	for rig, s in rigs do
		local root = s.root
		if root and root.Parent then
			-- Planar ground speed from REPLICATED motion (exploit-safe), lightly smoothed.
			local delta = root.Position - s.lastPos
			s.lastPos = root.Position
			local planar = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
			s.speed += (planar - s.speed) * math.min(dt * 8, 1)

			-- Foot dust scales from nothing (still) to full (sprinting).
			local moveFrac = math.clamp((s.speed - M.DustMoveSpeed) / span, 0, 1)
			s.dust.Rate = moveFrac * M.DustMaxRate

			-- Breath pants faster while hunting (Chase/Investigate).
			local st = rig:GetAttribute(STATE)
			local hunting = st == Enums.MonsterState.Chase or st == Enums.MonsterState.Investigate
			s.breath.Rate = M.BreathRate * (if hunting then 2.2 else 1)
		else
			rigs[rig] = nil
		end
	end
end)
