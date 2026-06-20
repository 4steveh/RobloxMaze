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

local function playFootstep()
	if not (footstep and footstep.Parent) then
		return
	end
	footstep.SoundId = PS.FootstepIds[rng:NextInteger(1, #PS.FootstepIds)]
	footstep.PlaybackSpeed = 0.9 + rng:NextNumber(0, 0.2)
	footstep:Play()
end

-- Footsteps + low-battery edge, on one render loop.
local stepClock = 0
local wasLow = false
RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if moving and grounded then
			stepClock -= dt
			if stepClock <= 0 then
				playFootstep()
				local rate = math.max(0.5, humanoid.WalkSpeed / Config.Player.WalkSpeed)
				stepClock = PS.FootstepWalkInterval / rate
			end
		else
			stepClock = 0 -- step immediately when movement resumes
		end
	end

	-- Low-battery beep on the downward crossing of the threshold.
	local battery = player:GetAttribute(Attributes.FlashlightBattery)
	if battery == nil then
		battery = Config.Flashlight.BatteryMax
	end
	local low = battery <= Config.Flashlight.LowBatteryThreshold
	if low and not wasLow then
		local s = Instance.new("Sound")
		s.SoundId = PS.LowBatteryBeepId
		s.Volume = PS.LowBatteryBeepVolume
		s.SoundGroup = uiBus
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 1)
	end
	wasLow = low
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
