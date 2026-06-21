--!nonstrict
-- PlayerSFXController.client.luau
-- The local player's presence: footsteps timed to movement (3D on the character so
-- others localize you), a flashlight toggle click (off the FlashlightOn attribute the
-- FlashlightController publishes), and a low-battery beep when the battery first drops
-- below the threshold. All client-side and uncontested (allowed per CLAUDE.md).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local PS = Config.Audio.Player
local player = Players.LocalPlayer
local sfxBus = AudioGroups.get("SFX")
local uiBus = AudioGroups.get("UI")
local rng = Random.new()

-- One reusable 3D footstep Sound parented to the current character's HRP.
local footstep = nil
local function setupCharacter(character)
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then
		return
	end
	footstep = Instance.new("Sound")
	footstep.Name = "Footstep"
	footstep.Volume = PS.FootstepVolume
	footstep.RollOffMode = Enum.RollOffMode.InverseTapered
	footstep.RollOffMinDistance = Config.Audio.RollOffMin
	footstep.RollOffMaxDistance = PS.FootstepRange
	footstep.SoundGroup = sfxBus
	footstep.Parent = hrp
end
if player.Character then
	setupCharacter(player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

-- Footstep loudness scales with the movement TIER, so your ears confirm the NoiseMeter:
-- creeping near-silent, walking normal, sprinting loud (and quicker cadence, below).
local function footstepVolumeScale(speed)
	local W = Config.Player.WalkSpeed
	if speed <= PS.FootstepCreepSpeed then
		return PS.FootstepCreepVolumeScale
	elseif speed < W then
		local t = (speed - PS.FootstepCreepSpeed) / math.max(W - PS.FootstepCreepSpeed, 0.001)
		return PS.FootstepCreepVolumeScale + (1 - PS.FootstepCreepVolumeScale) * t
	elseif speed <= PS.FootstepSprintSpeed then
		local t = (speed - W) / math.max(PS.FootstepSprintSpeed - W, 0.001)
		return 1 + (PS.FootstepSprintVolumeScale - 1) * t
	end
	return PS.FootstepSprintVolumeScale
end

local function playFootstep(speed)
	if not (footstep and footstep.Parent) then
		return
	end
	footstep.SoundId = PS.FootstepIds[rng:NextInteger(1, #PS.FootstepIds)]
	footstep.PlaybackSpeed = 0.9 + rng:NextNumber(0, 0.2)
	footstep.Volume = PS.FootstepVolume * footstepVolumeScale(speed)
	footstep:Play()
end

local function playBeep(volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = PS.LowBatteryBeepId
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.SoundGroup = uiBus
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)
end

-- Footsteps + the low-battery countdown, on one render loop.
local stepClock = 0
local beepClock = 0
local wasDead = false
RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 then
		local v = if hrp then hrp.AssemblyLinearVelocity else Vector3.zero
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if moving and grounded then
			stepClock -= dt
			if stepClock <= 0 then
				playFootstep(speed)
				local rate = math.max(0.5, speed / Config.Player.WalkSpeed)
				stepClock = PS.FootstepWalkInterval / rate
			end
		else
			stepClock = 0 -- step immediately when movement resumes
		end
	end

	-- Low battery: the beep QUICKENS as the battery empties (a countdown to dark), then a
	-- single pitched-down beep when the light "dies" at zero.
	local battery = player:GetAttribute(Attributes.FlashlightBattery)
	if battery == nil then
		battery = Config.Flashlight.BatteryMax
	end
	if battery <= Config.Flashlight.LowBatteryThreshold and battery > 0 then
		beepClock -= dt
		if beepClock <= 0 then
			playBeep(PS.LowBatteryBeepVolume, 1)
			local frac = math.clamp(battery / Config.Flashlight.LowBatteryThreshold, 0, 1) -- 1 at threshold -> 0 empty
			beepClock = PS.LowBatteryBeepMinInterval
				+ (PS.LowBatteryBeepMaxInterval - PS.LowBatteryBeepMinInterval) * frac
		end
	else
		beepClock = 0
	end
	local dead = battery <= 0
	if dead and not wasDead then
		playBeep(PS.LowBatteryBeepVolume * 1.2, PS.LightDiesPitch)
	end
	wasDead = dead
end)

-- Flashlight toggle click (the attribute flips only on an actual toggle).
player:GetAttributeChangedSignal(Attributes.FlashlightOn):Connect(function()
	local s = Instance.new("Sound")
	s.SoundId = PS.FlashlightClickId
	s.Volume = PS.FlashlightClickVolume
	s.SoundGroup = sfxBus
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 1)
end)
