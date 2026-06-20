--!nonstrict
-- MonsterAudioController.client.luau
-- The highest-tension audio: 3D breathing + footsteps parented to each monster rig
-- (auto-attenuating with distance), a non-spatial heartbeat the client scales by the
-- nearest rig's distance, and a Patrol->Chase sting keyed off the server's per-player
-- MonsterStateChanged remote. All rendering; the rig State + the remote are the
-- server-authoritative truth. Reads only the replicated rig position (exploit-safe).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Enums = require(ReplicatedStorage.Enums)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local MA = Config.Audio.Monster
local player = Players.LocalPlayer
local monsterBus = AudioGroups.get("Monster")

-- Non-spatial heartbeat (volume + rate ramp with nearest-rig closeness).
local heartbeat = Instance.new("Sound")
heartbeat.Name = "Heartbeat"
heartbeat.SoundId = MA.HeartbeatId
heartbeat.Looped = true
heartbeat.Volume = 0
heartbeat.SoundGroup = monsterBus
heartbeat.Parent = SoundService
heartbeat:Play()

-- One-shot chase sting, fired when a rig chasing THIS player enters Chase.
local sting = Instance.new("Sound")
sting.Name = "ChaseSting"
sting.SoundId = MA.ChaseStingId
sting.Volume = MA.ChaseStingVolume
sting.SoundGroup = monsterBus
sting.Parent = SoundService

local stateRemote = Remotes.get(Remotes.Names.MonsterStateChanged)
stateRemote.OnClientEvent:Connect(function(state)
	if state == Enums.MonsterState.Chase then
		sting:Play()
	end
end)

-- Per-rig 3D sounds (breathing loop + footstep one-shots) on the rig's HRP.
local rigAudio = {} -- [rig] = { hrp, breathing, footstep, lastPos, stepAccum }

local function makeSpatial(id, volume, range, looped)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = Config.Audio.RollOffMin
	s.RollOffMaxDistance = range
	s.SoundGroup = monsterBus
	return s
end

local function addRig(rig)
	if not rig:IsA("Model") or rigAudio[rig] then
		return
	end
	task.spawn(function()
		local hrp = rig:FindFirstChild("HumanoidRootPart") or rig:WaitForChild("HumanoidRootPart", 5)
		if not hrp or rigAudio[rig] then
			return
		end
		local breathing = makeSpatial(MA.BreathingId, MA.BreathingVolume, MA.BreathingRange, true)
		breathing.Name = "Breathing"
		breathing.Parent = hrp
		breathing:Play()
		local footstep = makeSpatial(MA.FootstepId, MA.FootstepVolume, MA.FootstepRange, false)
		footstep.Name = "Footstep"
		footstep.Parent = hrp
		rigAudio[rig] = { hrp = hrp, breathing = breathing, footstep = footstep, lastPos = hrp.Position, stepAccum = 0 }
	end)
end

local function removeRig(rig)
	local a = rigAudio[rig]
	if a then
		a.breathing:Destroy()
		a.footstep:Destroy()
		rigAudio[rig] = nil
	end
end

local monstersFolder = Workspace:WaitForChild("Monsters")
for _, rig in monstersFolder:GetChildren() do
	addRig(rig)
end
monstersFolder.ChildAdded:Connect(addRig)
monstersFolder.ChildRemoved:Connect(removeRig)

RunService.RenderStepped:Connect(function()
	-- Footsteps: a step every FootstepStride studs the rig travels.
	for _, a in rigAudio do
		if a.hrp.Parent then
			local moved = (a.hrp.Position - a.lastPos).Magnitude
			a.lastPos = a.hrp.Position
			a.stepAccum += moved
			if a.stepAccum >= MA.FootstepStride then
				a.stepAccum = 0
				a.footstep.PlaybackSpeed = 0.9 + math.random() * 0.2
				a.footstep:Play()
			end
		end
	end

	-- Heartbeat: ramp by the nearest rig's distance to the local character.
	local character = player.Character
	local phrp = character and character:FindFirstChild("HumanoidRootPart")
	local nearest = math.huge
	if phrp then
		for _, a in rigAudio do
			if a.hrp.Parent then
				nearest = math.min(nearest, (a.hrp.Position - phrp.Position).Magnitude)
			end
		end
	end
	if phrp and nearest <= MA.HeartbeatStartDistance then
		local span = MA.HeartbeatStartDistance - MA.HeartbeatMaxDistance
		local t = math.clamp((MA.HeartbeatStartDistance - nearest) / span, 0, 1)
		heartbeat.Volume = MA.HeartbeatVolume * t
		heartbeat.PlaybackSpeed = MA.HeartbeatMinRate + (MA.HeartbeatMaxRate - MA.HeartbeatMinRate) * t
	else
		heartbeat.Volume = 0
	end
end)
