--!nonstrict
-- CameraShakeController.client.luau
-- The threat you FEEL. Two layers, both render-only and exploit-safe:
--   * a continuous tremble scaled by the nearest monster actively hunting THIS player and how
--     close it is (the same replicated rig State + position model as ChaseFXController), and
--   * sharp one-shot impulses on discrete scares -- a trap firing near you, being caught --
--     off the existing server cue remotes.
-- It binds AFTER the camera update (RenderPriority.Camera + 1) and POST-multiplies the camera
-- CFrame, so it layers cleanly on top of whatever camera mode is active and never fights it.
-- Kept deliberately small (Config.CameraShake): enough to feel, never enough to nauseate or
-- hurt navigation. Decides nothing -- the FlickerController-class client cosmetic.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Enums = require(ReplicatedStorage.Enums)
local Attributes = require(ReplicatedStorage.Attributes)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local Remotes = require(ReplicatedStorage.Remotes)

local C = Config.CameraShake
if not C.Enabled then
	return
end

local STATE = Attributes.MonsterState
local player = Players.LocalPlayer

-- Personal FX-strength pref (LocalPlayer attribute from SettingsController; render-only, client-local):
-- scales the whole shake so motion-sensitive players can damp or kill it (0 == no shake). Cached +
-- refreshed on change rather than read every frame. ReduceFlashing doesn't apply -- shake isn't a flash.
local fxIntensity = Config.Settings.DefaultFxIntensity
local function refreshFxIntensity()
	local fx = player:GetAttribute(Attributes.SettingFxIntensity)
	fxIntensity = if typeof(fx) == "number" then fx else Config.Settings.DefaultFxIntensity
end
refreshFxIntensity()
player:GetAttributeChangedSignal(Attributes.SettingFxIntensity):Connect(refreshFxIntensity)

local current = 0 -- smoothed continuous threat tremble (0..1)
local impulse = 0 -- decaying one-shot impulse magnitude (in offset/tilt units)

-- Discrete impulses (a scare you should physically jolt at).
local function bump(magnitude: number)
	if magnitude > impulse then
		impulse = magnitude
	end
end

Remotes.get(Remotes.Names.MonsterCaught).OnClientEvent:Connect(function()
	bump(C.CaughtImpulse)
end)

Remotes.get(Remotes.Names.TrapTriggered).OnClientEvent:Connect(function(trapPart, phase)
	if phase ~= "fire" or typeof(trapPart) ~= "Instance" or not trapPart:IsA("BasePart") then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local d = (trapPart.Position - hrp.Position).Magnitude
	if d < C.TrapImpulseRadius then
		bump(C.TrapImpulse * (1 - d / C.TrapImpulseRadius)) -- nearer = harder
	end
end)

-- Nearest hunting monster's proximity -> continuous tremble target (exploit-safe; replicated).
local function threatTarget(): number
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)
	if not (hrp and monsters) then
		return 0
	end
	local span = math.max(C.ThreatStartDistance - C.ThreatMaxDistance, 1e-3)
	local target = 0
	for _, rig in monsters:GetChildren() do
		local rRoot = rig:FindFirstChild("HumanoidRootPart")
		local st = rig:GetAttribute(STATE)
		if rRoot then
			local aggressive = st == Enums.MonsterState.Chase or st == Enums.MonsterState.Investigate
			local alert = st == Enums.MonsterState.Alert
			if aggressive or alert then
				local d = (rRoot.Position - hrp.Position).Magnitude
				local prox = math.clamp((C.ThreatStartDistance - d) / span, 0, 1)
				local t = if aggressive then prox else prox * C.AlertScale
				if t > target then
					target = t
				end
			end
		end
	end
	return target
end

local TWO_PI = math.pi * 2
RunService:BindToRenderStep("CameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	current += (threatTarget() - current) * math.min(dt * C.FadeRate, 1)
	impulse *= math.exp(-C.ImpulseDecay * dt)

	-- Below perceptible -> leave the camera untouched (no constant micro-jitter at rest).
	if current < 0.01 and impulse < 0.01 then
		return
	end

	local t = os.clock()
	local fc = C.Frequency * TWO_PI
	local posAmp = current * C.MaxOffset
	local rotAmp = current * C.MaxTilt
	-- Continuous tremble: incommensurate frequencies per axis so it never reads as a clean sine.
	local ox = math.sin(t * fc) * posAmp
	local oy = math.sin(t * fc * 1.3 + 1.7) * posAmp
	local roll = math.sin(t * fc * 0.9 + 0.5) * rotAmp
	local pitch = math.sin(t * fc * 1.1 + 2.3) * rotAmp * 0.6

	-- Impulse layer (snappier, decaying): adds positional + rotational rattle on top.
	if impulse > 0.01 then
		local fi = C.ImpulseFrequency * TWO_PI
		ox += math.sin(t * fi) * impulse * 0.12
		oy += math.cos(t * fi * 1.2) * impulse * 0.12
		roll += math.sin(t * fi * 1.1) * impulse * 0.7
		pitch += math.cos(t * fi) * impulse * 0.42
	end

	-- The FX-strength pref scales both layers (tremble + impulse are already folded into the offsets).
	camera.CFrame = camera.CFrame
		* CFrame.new(ox * fxIntensity, oy * fxIntensity, 0)
		* CFrame.Angles(math.rad(pitch * fxIntensity), 0, math.rad(roll * fxIntensity))
end)
