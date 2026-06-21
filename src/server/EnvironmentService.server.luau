--!nonstrict
-- EnvironmentService.server.luau
-- Rebuilds the horror MOOD from code on boot, so a fresh `rojo build` of this repo looks
-- like the game (not a flat, bright, fogless box) and the flashlight/monster shadows
-- actually work. The whole atmosphere -- Lighting model, darkness, Atmosphere haze,
-- Bloom/DOF, and a base ColorCorrection grade -- used to live only in unsaved Studio
-- place content; this service makes it deterministic and version-controlled.
--
-- Server-side: Lighting and effects parented under Lighting replicate to every client
-- (a late joiner inherits the applied state). It is idempotent -- each effect is found
-- by name or created -- so it never duplicates whatever a place already has, and it
-- NEVER touches the client-only "ChaseGrade" ColorCorrection (it owns "BaseGrade").

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local E = Config.Environment

-- Find an existing child of Lighting by name+class, or create one. Keeps the service
-- idempotent and lets it adopt (rather than duplicate) anything already in the place.
local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

-- Core Lighting -------------------------------------------------------------------
Lighting.Technology = E.Technology -- Future: real-time shadows -> the flashlight throws creatures' shadows
Lighting.ClockTime = E.ClockTime
Lighting.GeographicLatitude = E.GeographicLatitude
Lighting.Brightness = E.Brightness
Lighting.ExposureCompensation = E.ExposureCompensation
Lighting.Ambient = E.Ambient
Lighting.OutdoorAmbient = E.OutdoorAmbient
Lighting.EnvironmentDiffuseScale = E.EnvironmentDiffuseScale
Lighting.EnvironmentSpecularScale = E.EnvironmentSpecularScale
Lighting.GlobalShadows = E.GlobalShadows
Lighting.ShadowSoftness = E.ShadowSoftness

-- Atmosphere (volumetric haze) ----------------------------------------------------
local atmos = ensure("Atmosphere", "Atmosphere")
atmos.Density = E.Atmosphere.Density
atmos.Offset = E.Atmosphere.Offset
atmos.Color = E.Atmosphere.Color
atmos.Decay = E.Atmosphere.Decay
atmos.Glare = E.Atmosphere.Glare
atmos.Haze = E.Atmosphere.Haze

-- Bloom ---------------------------------------------------------------------------
local bloom = ensure("BloomEffect", "Bloom")
bloom.Intensity = E.Bloom.Intensity
bloom.Size = E.Bloom.Size
bloom.Threshold = E.Bloom.Threshold
bloom.Enabled = true

-- Depth of field ------------------------------------------------------------------
local dof = ensure("DepthOfFieldEffect", "DepthOfField")
dof.FarIntensity = E.DepthOfField.FarIntensity
dof.FocusDistance = E.DepthOfField.FocusDistance
dof.InFocusRadius = E.DepthOfField.InFocusRadius
dof.NearIntensity = E.DepthOfField.NearIntensity
dof.Enabled = true

-- Base colour grade (the client ChaseFX "ChaseGrade" composes on top of this) ------
local grade = ensure("ColorCorrectionEffect", "BaseGrade")
grade.Brightness = E.BaseGrade.Brightness
grade.Contrast = E.BaseGrade.Contrast
grade.Saturation = E.BaseGrade.Saturation
grade.TintColor = E.BaseGrade.TintColor
grade.Enabled = true
