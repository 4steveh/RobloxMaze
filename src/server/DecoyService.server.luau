--!nonstrict
-- DecoyService.server.luau
-- Noise as a WEAPON (the Granny lesson): a player tosses a rattling decoy that fires
-- ServerSignals.NoiseEvent at its landing point, so the near-blind NOISE monkey investigates
-- the WRONG spot and you slip past -- turning the monkey from pure punishment into a puzzle.
--
-- Server-authoritative + exploit-safe: the client sends ONLY intent (no payload). The server
-- computes the landing point from the player's OWN replicated position + facing (never a client
-- position) and clamps it to the first wall along the throw, so it can't be aimed through geometry
-- or spoofed. A per-player cooldown (+ a light rate-limit on the hostile remote) stops spam. The
-- decoy is a real server-spawned part (replicated -> every client sees/hears it rattle). Reuses the
-- exact NoiseEvent path the sprung-trap lure already uses; only the deaf bunny ignores it.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local AudioGroups = require(ReplicatedStorage.AudioGroups)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local ServerSignals = require(script.Parent.ServerSignals)

local C = Config.Decoy

Remotes.init()
local throwRemote = Remotes.get(Remotes.Names.ThrowDecoy)
local noiseSignal = ServerSignals.get(ServerSignals.Names.NoiseEvent)

local decoyFolder = Instance.new("Folder")
decoyFolder.Name = "Decoys"
decoyFolder.Parent = Workspace

local lastThrow = {} -- [player] = os.clock() of the last accepted throw (cooldown)
local lastMsg = {} -- [player] = os.clock() of the last message (rate-limit)

-- A player may throw while alive and playing (not Won, not Downed). A SafeRoom throw is fine --
-- luring the monkey away BEFORE you leave is exactly the intended play.
local function eligible(player: Player): boolean
	return player:GetAttribute(Attributes.GameState) ~= Enums.GameState.Won
		and player:GetAttribute(Attributes.Downed) ~= true
end

-- Where the decoy lands: ThrowDistance ahead along the player's flat facing, CLAMPED to the first
-- wall (so it can't be thrown through geometry), then dropped to the floor. All server-known.
local function landingPoint(player: Player): Vector3?
	local hrp = PlayerUtil.livingRootPart(player)
	if not hrp then
		return nil
	end
	local origin = hrp.Position
	local facing = hrp.CFrame.LookVector
	local flat = Vector3.new(facing.X, 0, facing.Z)
	flat = if flat.Magnitude < 0.01 then Vector3.new(0, 0, -1) else flat.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { decoyFolder }
	if player.Character then
		table.insert(filter, player.Character)
	end
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)
	if monsters then
		table.insert(filter, monsters)
	end
	params.FilterDescendantsInstances = filter

	local up = Vector3.new(0, 2.5, 0)
	local dist = C.ThrowDistance
	local fwdHit = Workspace:Raycast(origin + up, flat * C.ThrowDistance, params)
	if fwdHit then
		dist = math.max(2, (fwdHit.Position - (origin + up)).Magnitude - C.WallPadding)
	end
	local restXZ = origin + up + flat * dist
	local downHit = Workspace:Raycast(restXZ, Vector3.new(0, -40, 0), params)
	if downHit then
		return downHit.Position + Vector3.new(0, C.LandingHeight, 0)
	end
	return origin + flat * dist + Vector3.new(0, C.LandingHeight, 0)
end

local function spawnDecoy(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "Decoy"
	part.Shape = Enum.PartType.Ball
	part.Size = C.Size
	part.Color = C.Color
	part.Material = C.Material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Position = position
	part.Parent = decoyFolder

	local light = Instance.new("PointLight")
	light.Color = C.LightColor
	light.Brightness = C.LightBrightness
	light.Range = C.LightRange
	light.Parent = part

	local sound = Instance.new("Sound")
	sound.SoundId = C.RattleSoundId
	sound.Volume = C.RattleVolume
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.Audio.RollOffMin
	sound.RollOffMaxDistance = C.RattleRange
	sound.SoundGroup = AudioGroups.get("SFX")
	sound.Parent = part
	sound:Play()

	-- Pulse the world-noise event a few times so the monkey keeps homing to the spot while it
	-- rattles (each pulse is a fresh one-shot it investigates), then despawn.
	task.spawn(function()
		for _ = 1, C.NoisePulses do
			noiseSignal:Fire(position)
			task.wait(C.PulseInterval)
		end
	end)
	task.delay(C.LifeSeconds, function()
		part:Destroy()
	end)
end

throwRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	-- Hostile input: rate-limit first (drop floods cheaply), then the real cooldown.
	if now - (lastMsg[player] or -math.huge) < C.IntentRateLimit then
		return
	end
	lastMsg[player] = now
	if not eligible(player) then
		return
	end
	if now - (lastThrow[player] or -math.huge) < C.Cooldown then
		return
	end
	local landing = landingPoint(player)
	if not landing then
		return
	end
	lastThrow[player] = now
	spawnDecoy(landing)
end)

Players.PlayerRemoving:Connect(function(player)
	lastThrow[player] = nil
	lastMsg[player] = nil
end)
