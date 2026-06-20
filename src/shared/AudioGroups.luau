--!nonstrict
-- AudioGroups.luau
-- The single home for the SoundService SoundGroup bus tree (Master > Music, Ambient,
-- Monster, SFX, UI). Every audio controller routes its Sounds through a bus via
-- AudioGroups.get(name), so per-bus volume (and future ducking) lives in one
-- Config-driven place -- mirroring how Remotes/Tags centralize their concern.
--
-- Built lazily and idempotently on whichever side asks first. In practice the client
-- builds its own local tree (audio is client-rendered); volumes come from Config.Audio.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local AudioGroups = {}
local groups = {}
local initialized = false

local function ensureGroup(name: string, volume: number, parent: Instance): SoundGroup
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		existing.Volume = volume
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = parent
	return g
end

function AudioGroups.init()
	if initialized then
		return
	end
	initialized = true
	local vols = Config.Audio.Groups
	-- SoundGroups nest by parenting; volumes cascade Master -> child bus -> Sound.
	groups.Master = ensureGroup("Master", vols.Master, SoundService)
	for _, name in { "Music", "Ambient", "Monster", "SFX", "UI" } do
		groups[name] = ensureGroup(name, vols[name], groups.Master)
	end
end

-- Fetch a bus by name (Master/Music/Ambient/Monster/SFX/UI). Falls back to Master.
function AudioGroups.get(name: string): SoundGroup
	AudioGroups.init()
	return groups[name] or groups.Master
end

-- Duck a bus to `factor` of its Config volume for `seconds`, then restore -- so a win
-- jingle or a jumpscare scream can punch through the ambient/monster beds.
function AudioGroups.duck(name: string, factor: number, seconds: number)
	local g = AudioGroups.get(name)
	local base = Config.Audio.Groups[name] or g.Volume
	TweenService:Create(g, TweenInfo.new(0.12), { Volume = base * factor }):Play()
	task.delay(seconds, function()
		TweenService:Create(g, TweenInfo.new(0.5), { Volume = base }):Play()
	end)
end

return AudioGroups
