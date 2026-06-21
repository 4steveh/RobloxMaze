--!nonstrict
-- AmbientController.client.luau
-- The room's voice: a looped HVAC/drone bed, plus the signature daycare scare -- an
-- intermittent 3D music-box motif drifting in from the mascot statue (any part tagged
-- MusicBoxEmitter). Also switches global reverb on SafeRoom enter/leave using the
-- server-authoritative SafeRoom remotes (the client never detects occupancy itself).
-- All client-side and uncontested (allowed per CLAUDE.md).

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

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
			s.PlaybackSpeed = 1 + wobble
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

-- Reverb follows safe-room occupancy (off the authoritative remotes).
SoundService.AmbientReverb = Config.Audio.Reverb.Maze
Remotes.get(Remotes.Names.SafeRoomEntered).OnClientEvent:Connect(function()
	SoundService.AmbientReverb = Config.Audio.Reverb.SafeRoom
end)
Remotes.get(Remotes.Names.SafeRoomLeft).OnClientEvent:Connect(function()
	SoundService.AmbientReverb = Config.Audio.Reverb.Maze
end)
