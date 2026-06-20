--!nonstrict
-- StingerController.client.luau
-- One-shot event stingers wired to the EXISTING server remotes: a key-pickup chime, a
-- locked-door thunk, and the win jingle (which ducks the ambient/monster beds so it
-- lands). The jumpscare scream lives in JumpscareController (it owns MonsterCaught).
-- Renders only -- the server decides every one of these events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)

local ST = Config.Audio.Stingers

local function stinger(id, volume, busName)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.SoundGroup = AudioGroups.get(busName)
	s.Parent = SoundService
	return s
end

local keyChime = stinger(ST.KeyChimeId, ST.KeyChimeVolume, "UI")
local lockedThunk = stinger(ST.LockedThunkId, ST.LockedThunkVolume, "SFX")
local winJingle = stinger(ST.WinJingleId, ST.WinJingleVolume, "Music")

Remotes.get(Remotes.Names.KeyCollected).OnClientEvent:Connect(function()
	keyChime:Play()
end)

Remotes.get(Remotes.Names.ExitLocked).OnClientEvent:Connect(function()
	lockedThunk:Play()
end)

Remotes.get(Remotes.Names.GameWon).OnClientEvent:Connect(function()
	-- Duck the dread beds under the celebration.
	AudioGroups.duck("Ambient", 0.15, Config.Win.FreezeDuration)
	AudioGroups.duck("Monster", 0.0, Config.Win.FreezeDuration)
	winJingle:Play()
end)
