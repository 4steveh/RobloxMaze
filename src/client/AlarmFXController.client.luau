--!nonstrict
-- AlarmFXController.client.luau
-- The ENDGAME climax made felt. When the team grabs the last key the exit heaves open and it's a
-- sprint for the door -- this turns that moment into an emergency: a full-screen pulsing RED wash
-- blooms in, a one-shot alarm sting hits, and a low pitched-up bed loops under it all until the
-- round ends. Driven purely by the server-authoritative AlarmStateChanged remote (the client never
-- decides "all keys are in"), and it owns its OWN ScreenGui + Sounds, so nothing else is touched.
-- Render-only -- the FlickerController-class cosmetic, the loud twin of SafeRoomFXController's relief.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)
local Attributes = require(ReplicatedStorage.Attributes)

local EG = Config.Endgame
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Personal comfort/accessibility prefs (LocalPlayer attributes from SettingsController; client-local),
-- cached + refreshed on change so we don't read attributes every frame -- consistent with ChaseFX.
-- FxIntensity scales the wash amplitude (0 == invisible); ReduceFlashing holds a STEADY dim red (no strobe).
local fxIntensity = Config.Settings.DefaultFxIntensity
local reduceFlashing = Config.Settings.DefaultReduceFlashing
local function refreshPrefs()
	local fx = player:GetAttribute(Attributes.SettingFxIntensity)
	fxIntensity = if typeof(fx) == "number" then fx else Config.Settings.DefaultFxIntensity
	local rf = player:GetAttribute(Attributes.SettingReduceFlashing)
	reduceFlashing = if typeof(rf) == "boolean" then rf else Config.Settings.DefaultReduceFlashing
end
refreshPrefs()
player:GetAttributeChangedSignal(Attributes.SettingFxIntensity):Connect(refreshPrefs)
player:GetAttributeChangedSignal(Attributes.SettingReduceFlashing):Connect(refreshPrefs)

-- The emergency wash: one full-screen red Frame on a high-DisplayOrder GUI (over the chase vignette),
-- its transparency pulsed around WashMaxTransparency. Its own ScreenGui so no other HUD is disturbed.
local gui = Instance.new("ScreenGui")
gui.Name = "AlarmFX"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 60 -- above the chase vignette (50) -- the endgame trumps the ambient hunt mood
gui.Parent = playerGui

local wash = Instance.new("Frame")
wash.Name = "AlarmWash"
wash.BackgroundColor3 = EG.WashColor
wash.BorderSizePixel = 0
wash.Position = UDim2.fromScale(0, 0)
wash.Size = UDim2.fromScale(1, 1)
wash.BackgroundTransparency = 1 -- fully clear until the alarm sounds
wash.Parent = gui

-- One-shot alarm sting (on the Monster bus -- the threat channel) + the low looping bed (Music bus,
-- pitched up so the dread drone reads as an alarm, not the ambient bed). Both built once, reused.
local sting = Instance.new("Sound")
sting.SoundId = EG.StingId
sting.Volume = EG.StingVolume
sting.SoundGroup = AudioGroups.get("Monster")
sting.Parent = SoundService

local bed = Instance.new("Sound")
bed.SoundId = EG.BedId
bed.Volume = EG.BedVolume
bed.PlaybackSpeed = EG.BedPitch
bed.Looped = true
bed.SoundGroup = AudioGroups.get("Music")
bed.Parent = SoundService

-- State: `active` is the server-driven on/off; `level` is the eased 0..1 fade so the wash blooms in
-- on alarm-on and fades out on alarm-off (FadeSeconds), instead of snapping.
local active = false
local level = 0

Remotes.get(Remotes.Names.AlarmStateChanged).OnClientEvent:Connect(function(on)
	local now = on == true
	if now == active then
		return -- ignore repeats; only act on a real on/off transition
	end
	active = now
	if active then
		sting:Play()
		bed:Play()
	else
		bed:Stop()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	-- Ease toward the alarm state over FadeSeconds (shared in/out time -- a bloom on, a fade off).
	level += ((if active then 1 else 0) - level) * math.min(dt / math.max(EG.FadeSeconds, 1e-3), 1)

	-- Pulse the wash around its peak alpha. ReduceFlashing holds a STEADY dim red (the wash at half its
	-- amplitude, no strobe); otherwise it throbs at PulseHz. FxIntensity scales the whole amplitude.
	local amount = level * fxIntensity
	local pulse = if reduceFlashing then 0.5 else (math.sin(os.clock() * math.pi * 2 * EG.PulseHz) * 0.5 + 0.5)
	local opaque = (1 - EG.WashMaxTransparency) * amount * pulse
	wash.BackgroundTransparency = 1 - opaque
end)
