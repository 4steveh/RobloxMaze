--!nonstrict
-- AtmosphereFXController.client.luau
-- Ambient dust drifting in the air -- the cheapest, highest-impact horror-atmosphere tell the
-- maze was missing. A single ParticleEmitter lives in an invisible volume that follows the
-- camera, so motes always surround the player; with LightInfluence on, they're only really
-- visible where a light touches them -- i.e. they GLINT IN THE FLASHLIGHT BEAM as it sweeps a
-- dark corridor, the moment that sells "this place is real". Particles are world-locked
-- (LockedToPart off), so they hang in the air and you walk THROUGH them.
--
-- Render-only, client-side, decides nothing and touches no contested state -- the same
-- FlickerController/MonsterAnimController cosmetic class CLAUDE.md explicitly permits.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local A = Config.AtmosphereFX
if not A.Enabled then
	return
end

-- The invisible emitter volume. A Block emits particles throughout its bounding box, so a big
-- cube around the camera fills the surrounding air rather than spraying from a point.
local volume = Instance.new("Part")
volume.Name = "AtmosphereDust"
volume.Size = Vector3.new(A.VolumeSize, A.VolumeSize, A.VolumeSize)
volume.Transparency = 1
volume.Anchored = true
volume.CanCollide = false
volume.CanQuery = false
volume.CanTouch = false
volume.CastShadow = false
volume.Locked = true
volume.Parent = Workspace

local dust = Instance.new("ParticleEmitter")
dust.Texture = A.DustTexture
dust.Color = ColorSequence.new(A.DustColor)
-- Scale in then out so motes never pop in/out of existence.
dust.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.15, A.SizeMax),
	NumberSequenceKeypoint.new(0.85, A.SizeMin),
	NumberSequenceKeypoint.new(1, 0),
})
-- Fade from invisible -> faint -> invisible (the flashlight does the real revealing).
dust.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.25, A.TransparencyMin),
	NumberSequenceKeypoint.new(0.75, A.TransparencyMax),
	NumberSequenceKeypoint.new(1, 1),
})
dust.Lifetime = NumberRange.new(A.LifetimeMin, A.LifetimeMax)
dust.Rate = A.Rate
dust.Speed = NumberRange.new(0, A.Speed)
dust.SpreadAngle = Vector2.new(180, 180) -- motes drift every which way
dust.Acceleration = Vector3.new(0, A.DriftRise, 0) -- a faint upward bias (warm air)
dust.Rotation = NumberRange.new(-180, 180)
dust.RotSpeed = NumberRange.new(-A.SpinDeg, A.SpinDeg)
dust.LightInfluence = A.LightInfluence -- lit by lights -> glows in the beam, invisible in the dark
dust.LightEmission = A.LightEmission
dust.LockedToPart = false -- world-locked: motes hang in the air as you move through them
dust.Parent = volume

-- Follow the camera so the surrounding air is always populated. Axis-aligned (we move only the
-- position, never the rotation) so the world-locked motes never appear to swirl with the camera.
RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if camera then
		volume.CFrame = CFrame.new(camera.CFrame.Position)
	end
end)
