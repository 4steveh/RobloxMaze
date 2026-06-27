--!nonstrict
-- AmbientController.client.luau
-- The room's voice: a looped HVAC/drone bed, plus the signature daycare scare -- an
-- intermittent 3D music-box motif drifting in from the mascot statue (any part tagged
-- MusicBoxEmitter). Also switches global reverb by re-deriving it from the
-- server-authoritative InSafeRoom attribute (the client never detects occupancy itself).
-- All client-side and uncontested (allowed per CLAUDE.md).

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local player = Players.LocalPlayer

local AM = Config.Audio.Ambient
local ambientBus = AudioGroups.get("Ambient")
local rng = Random.new()

-- Looped 2D beds.
local function bed(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = true
	s.SoundGroup = ambientBus
	s.Parent = SoundService
	s:Play()
	return s
end
bed(AM.DroneId, AM.DroneVolume)
bed(AM.RoomToneId, AM.RoomToneVolume)

-- 3D music box on each tagged emitter (the mascot statue).
local boxes = {} -- [part] = Sound
local boxBase = {} -- [Sound] = per-drift-in base PlaybackSpeed (the wobble rides on top); set at each play
Discovery.observe(Tags.MusicBoxEmitter, function(part)
	if not part:IsA("BasePart") or boxes[part] then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "MusicBox"
	s.SoundId = AM.MusicBoxId
	s.Volume = AM.MusicBoxVolume
	s.Looped = false
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = Config.Audio.RollOffMin
	s.RollOffMaxDistance = AM.MusicBoxRange
	s.SoundGroup = ambientBus
	s.Parent = part
	boxes[part] = s
end, function(part)
	if boxes[part] then
		boxBase[boxes[part]] = nil
		boxes[part]:Destroy()
		boxes[part] = nil
	end
end)

-- A continuous detune wobble while a box plays: a music box that is winding down / haunted,
-- never a clean loop. Cheap (only touches currently-playing boxes).
local boxClock = 0
RunService.Heartbeat:Connect(function(dt)
	boxClock += dt
	local wobble = math.sin(boxClock * AM.MusicBoxWobbleHz * math.pi * 2) * AM.MusicBoxPitchWobble
	for _, s in boxes do
		if s.IsPlaying then
			s.PlaybackSpeed = (boxBase[s] or 1) + wobble
		end
	end
end)

-- Drift the music box in and out on a randomized gap: each drift-in starts at a random point
-- in the (long) clip and FADES out (rather than cutting), so no two are quite the same.
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(AM.MusicBoxMinGap, AM.MusicBoxMaxGap))
		for _, s in boxes do
			if s.Parent and not s.IsPlaying then
				s.Volume = AM.MusicBoxVolume
				s.TimePosition = rng:NextNumber(0, AM.MusicBoxStartRange)
				-- A fresh random base pitch for this drift-in, so no two are quite the same.
				boxBase[s] = 1 + rng:NextNumber(-AM.MusicBoxTransposeRange, AM.MusicBoxTransposeRange)
				s:Play()
				task.delay(AM.MusicBoxPlaySeconds, function()
					if s.Parent and s.IsPlaying then
						TweenService:Create(s, TweenInfo.new(AM.MusicBoxFadeSeconds), { Volume = 0 }):Play()
						task.delay(AM.MusicBoxFadeSeconds, function()
							if s.Parent then
								s:Stop()
								s.Volume = AM.MusicBoxVolume
							end
						end)
					end
				end)
			end
		end
	end
end)

-- Reverb follows safe-room occupancy, re-derived from the authoritative InSafeRoom
-- attribute (self-healing: overlapping zones / an in-flight respawn can't strand it).
local function applyReverb()
	SoundService.AmbientReverb = if player:GetAttribute(Attributes.InSafeRoom) == true
		then Config.Audio.Reverb.SafeRoom
		else Config.Audio.Reverb.Maze
end
applyReverb()
player:GetAttributeChangedSignal(Attributes.InSafeRoom):Connect(applyReverb)
-- A respawn can't inherit a stale reverb: re-derive it from the authoritative InSafeRoom
-- attribute (don't force Maze) -- respawning INSIDE a safe room doesn't re-transition InSafeRoom,
-- so a forced Maze would strand the reverb wrong; deriving keeps the maze case unchanged and the
-- in-safe-room case correct.
player.CharacterAdded:Connect(applyReverb)
