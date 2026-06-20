--!nonstrict
-- AmbientController.client.luau
-- The room's voice: a looped HVAC/drone bed, plus the signature daycare scare -- an
-- intermittent 3D music-box motif drifting in from the mascot statue (any part tagged
-- MusicBoxEmitter). Also switches global reverb on SafeRoom enter/leave using the
-- server-authoritative SafeRoom remotes (the client never detects occupancy itself).
-- All client-side and uncontested (allowed per CLAUDE.md).

local SoundService = game:GetService("SoundService")
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

-- Drift the music box in and out on a randomized gap.
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(AM.MusicBoxMinGap, AM.MusicBoxMaxGap))
		for _, s in boxes do
			if s.Parent and not s.IsPlaying then
				s.TimePosition = 0
				s:Play()
				task.delay(AM.MusicBoxPlaySeconds, function()
					if s.Parent then
						s:Stop()
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
