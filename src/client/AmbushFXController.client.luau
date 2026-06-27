--!nonstrict
-- AmbushFXController.client.luau
-- Renders the AmbushNode micro-scare off the server's AmbushTriggered remote (server-
-- authoritative -- the client never self-detects the node). At the node position it plays a
-- localized 3D skitter (parented to a temporary part so it spatializes -- a distant scare
-- barely whispers) routed through the Monster bus, and briefly cuts the nearest FlickerLight
-- fixture so a corridor blinks dark for a beat ("something just moved"). Render-only (the
-- FlickerController-class cosmetic) -- it decides nothing.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)
local Attributes = require(ReplicatedStorage.Attributes)
local Tags = require(ReplicatedStorage.Tags)

local player = Players.LocalPlayer
local ambushRemote = Remotes.get(Remotes.Names.AmbushTriggered)
local monsterBus = AudioGroups.get("Monster") -- a skitter is a creature sound, not generic SFX
local C = Config.Ambush

-- Personal comfort prefs (client-local attributes from SettingsController; render-only, no server
-- trust), cached + refreshed on change. A light cut is a brief flash, so ReduceFlashing suppresses
-- the cut; the spatialized skitter still plays (audio is left to the master-volume setting).
-- FxIntensity at 0 means "no FX" -- it suppresses the cut entirely (the skitter still plays).
local reduceFlashing = Config.Settings.DefaultReduceFlashing
local fxIntensity = Config.Settings.DefaultFxIntensity
local function refreshPrefs()
	local rf = player:GetAttribute(Attributes.SettingReduceFlashing)
	reduceFlashing = if typeof(rf) == "boolean" then rf else Config.Settings.DefaultReduceFlashing
	local fx = player:GetAttribute(Attributes.SettingFxIntensity)
	fxIntensity = if typeof(fx) == "number" then fx else Config.Settings.DefaultFxIntensity
end
refreshPrefs()
player:GetAttributeChangedSignal(Attributes.SettingReduceFlashing):Connect(refreshPrefs)
player:GetAttributeChangedSignal(Attributes.SettingFxIntensity):Connect(refreshPrefs)

-- The 3D skitter: parent the Sound to a temporary anchored invisible part at the node so it
-- distance-attenuates (spatializes) instead of thunking at full volume in every ear. The carrier
-- (and its Sound) is Debris-collected after the clip has had time to finish; the part is inert
-- (no collision/query/touch) so it can never affect the world.
local function skitter(position: Vector3)
	local carrier = Instance.new("Part")
	carrier.Name = "AmbushSkitter"
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.Transparency = 1
	carrier.Size = Vector3.one
	carrier.CFrame = CFrame.new(position)
	carrier.Parent = Workspace

	local s = Instance.new("Sound")
	s.SoundId = C.SkitterId
	s.Volume = C.SkitterVolume
	s.PlaybackSpeed = C.SkitterPitch -- pitched up so it reads as a fast scuttle, not a footstep
	s.SoundGroup = monsterBus
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = Config.Audio.RollOffMin
	s.RollOffMaxDistance = C.SkitterRange
	s.Parent = carrier
	s:Play()
	Debris:AddItem(carrier, 3) -- a quick scuttle finishes well within this; takes the Sound with it
end

-- Briefly cut the nearest FlickerLight fixture to the scare. FlickerLight is tagged on the LIGHT
-- itself (see FlickerController), so GetTagged returns Lights -- we measure distance via each
-- light's parent BasePart, kill the winner's Enabled, then restore it after the cut window.
-- FlickerController only writes Brightness, so toggling Enabled never fights it. The cut is BOUND
-- to SkitterRange (same radius as the audible scare) so an off-screen fixture across the map can
-- never black out -- only a fixture near the node (the player's own corridor) blinks.
local function cutNearestLight(position: Vector3)
	if reduceFlashing or fxIntensity <= 0 then
		return -- a cut is a flash -- honour the comfort settings
	end
	local nearestLight, nearestDist = nil, math.huge
	for _, light in CollectionService:GetTagged(Tags.FlickerLight) do
		local fixture = light:IsA("Light") and light.Parent
		if fixture and fixture:IsA("BasePart") then
			local d = (fixture.Position - position).Magnitude
			if d < nearestDist then
				nearestDist = d
				nearestLight = light
			end
		end
	end
	if nearestLight and nearestDist <= C.SkitterRange then
		nearestLight.Enabled = false
		task.delay(C.LightCutSeconds, function()
			if nearestLight.Parent then
				nearestLight.Enabled = true
			end
		end)
	end
end

ambushRemote.OnClientEvent:Connect(function(position)
	if typeof(position) ~= "Vector3" then
		return -- defensive: the remote payload is the node position
	end
	skitter(position)
	cutNearestLight(position)
end)
