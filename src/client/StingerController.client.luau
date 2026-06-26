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
local exitHeave = stinger(Config.Exit.OpenSoundId, Config.Exit.OpenSoundVolume, "SFX") -- the gate sliding open
local huntBegins = stinger(ST.HuntBeginsId, ST.HuntBeginsVolume, "Monster") -- the peace window ended
local keyComplete = stinger(ST.KeyCompleteId, ST.KeyCompleteVolume, "UI") -- the all-keys flourish
keyComplete.PlaybackSpeed = ST.KeyCompletePitch
local safeRoomRelief = stinger(ST.SafeRoomReliefId, ST.SafeRoomReliefVolume, "Ambient") -- the "you're safe" exhale
safeRoomRelief.PlaybackSpeed = ST.SafeRoomReliefPitch
-- A TEAMMATE got hunted: a quiet, low warning on a 2D bus -- deliberately softer/lower than the
-- target's OWN ChaseSting (MonsterAudioController) so it never reads as "I'm being hunted".
local huntedAlert = stinger(ST.HuntedAlertId, ST.HuntedAlertVolume, "Monster")
huntedAlert.PlaybackSpeed = ST.HuntedAlertPitch
local achievementChime = stinger(ST.AchievementId, ST.AchievementVolume, "UI") -- a bright unlock chime
achievementChime.PlaybackSpeed = ST.AchievementPitch
local roundSummary = stinger(ST.RoundSummaryId, ST.RoundSummaryVolume, "UI") -- a soft results tone
roundSummary.PlaybackSpeed = ST.RoundSummaryPitch

local requiredKeys = Config.Keys.RequiredToWin

Remotes.get(Remotes.Names.KeyCollected).OnClientEvent:Connect(function(count)
	keyChime:Play()
	-- The FINAL key is the run's turning point ("now run for the exit") -- layer the triumphant
	-- flourish over the chime and briefly lift the dread beds so the moment lands.
	if count and count >= requiredKeys then
		AudioGroups.duck("Ambient", 0.4, 1.0)
		keyComplete:Play()
	end
end)

-- Entering a SafeRoom: a warm low bell, the audible companion to the visual "SAFE" bloom.
Remotes.get(Remotes.Names.SafeRoomEntered).OnClientEvent:Connect(function()
	safeRoomRelief:Play()
end)

Remotes.get(Remotes.Names.ExitLocked).OnClientEvent:Connect(function()
	lockedThunk:Play()
end)

-- The hunt begins (peace window ended): a dread sting, ducking the ambient bed briefly so it lands.
Remotes.get(Remotes.Names.HuntBegins).OnClientEvent:Connect(function()
	AudioGroups.duck("Ambient", 0.25, 1.5)
	huntBegins:Play()
end)

-- The exit gate heaving open (heard by the whole lobby when anyone escapes).
Remotes.get(Remotes.Names.ExitOpened).OnClientEvent:Connect(function()
	exitHeave:Play()
end)

Remotes.get(Remotes.Names.GameWon).OnClientEvent:Connect(function()
	-- Duck the dread beds under the celebration.
	AudioGroups.duck("Ambient", 0.15, Config.Win.FreezeDuration)
	AudioGroups.duck("Monster", 0.0, Config.Win.FreezeDuration)
	winJingle:Play()
end)

-- A teammate just got hunted: the quiet team-awareness warning (the payload name reads in the HUD).
Remotes.get(Remotes.Names.HuntingAlert).OnClientEvent:Connect(function()
	huntedAlert:Play()
end)

-- A lifetime-stat milestone earned: a bright unlock chime under the toast.
Remotes.get(Remotes.Names.AchievementUnlocked).OnClientEvent:Connect(function()
	achievementChime:Play()
end)

-- The end-of-round results card appears: a soft results tone (per round, escape or not).
Remotes.get(Remotes.Names.RoundSummary).OnClientEvent:Connect(function()
	roundSummary:Play()
end)
