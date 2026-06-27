--!nonstrict
-- FlareService.server.luau
-- Light as a WEAPON (the dark-vs-light theme made a player VERB): a throwable road-flare whose bright
-- burst FREEZES any monster caught in its glow for a beat. It's the universal "get it off me NOW" tool
-- that works on BOTH monsters -- the defensive complement to the decoy (the decoy PULLS the near-blind
-- monkey to a wrong spot via noise; the flare PUSHES both monsters off you via light). A shared, lobby-
-- visible "safe for a beat" beat (so you can also flare a chaser off a downed teammate to revive them).
--
-- Server-authoritative + exploit-safe, modeled on DecoyService: the client sends ONLY intent (no
-- payload, treated as hostile -- rate-limited + cooldown + per-round charge-gated server-side). The
-- server computes the landing from the player's OWN known position+facing (never a client position),
-- clamps it to the first wall, spawns a REAL replicated burning flare (every client sees/hears it), and
-- blinds every rig within BlindRadius by writing the EXISTING MonsterStunnedUntil seam -- the SAME
-- attribute TrapService writes and MonsterService already honors (freeze + skip the contact-catch). So
-- this needs ZERO MonsterService changes. The only trusted value is the per-round charge count, which
-- the SERVER owns (FlareCharges is a read-only HUD mirror); no client position/aim is ever trusted.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local AudioGroups = require(ReplicatedStorage.AudioGroups)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local ServerSignals = require(script.Parent.ServerSignals)

local C = Config.Flare

-- Inert when the feature is off: bind nothing (a stray ThrowFlare from the client harmlessly no-ops,
-- since the remote is never connected here). Mirrors the Hiding/Decoy "inert when disabled" intent.
if not C.Enabled then
	return
end

Remotes.init()
local throwRemote = Remotes.get(Remotes.Names.ThrowFlare)

local flareFolder = Instance.new("Folder")
flareFolder.Name = "Flares"
flareFolder.Parent = Workspace

local lastThrow = {} -- [player] = os.clock() of the last accepted throw (cooldown)
local lastMsg = {} -- [player] = os.clock() of the last message (rate-limit)

-- Charges are server-authoritative: the handler checks the server's OWN attribute, the client only
-- mirrors it for the HUD. Set on join; refilled (NOT per-respawn -- a death never refunds) each round.
local function grantCharges(player: Player)
	player:SetAttribute(Attributes.FlareCharges, C.Charges)
end

-- A player may throw while alive and playing (not Won, not Downed). A SafeRoom throw is fine.
local function eligible(player: Player): boolean
	return player:GetAttribute(Attributes.GameState) ~= Enums.GameState.Won
		and player:GetAttribute(Attributes.Downed) ~= true
		and player:GetAttribute(Attributes.Hidden) ~= true -- can't throw from inside a locker (would betray the hiding spot)
end

-- Where the flare lands: ThrowDistance ahead along the player's flat facing, CLAMPED to the first wall
-- (so it can't be thrown through geometry), then dropped to the floor. All server-known (copy of
-- DecoyService.landingPoint with the flare's own throw geometry).
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
	local filter = { flareFolder }
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

-- The blind: freeze every rig within BlindRadius of the flare by writing MonsterStunnedUntil in the
-- server clock (the exact write TrapService.fireOnMonster does, generalized to a radius). Blinds ALL
-- rigs in range -- a patroller frozen for a beat is harmless; it only matters when one is chasing you.
local function blindMonstersNear(position: Vector3)
	local folder = Workspace:FindFirstChild(WorldFolders.Monsters)
	if not folder then
		return
	end
	local deadline = Workspace:GetServerTimeNow() + C.BlindSeconds
	for _, rig in folder:GetChildren() do
		if rig:IsA("Model") then
			local root = rig.PrimaryPart
			if root and (root.Position - position).Magnitude <= C.BlindRadius then
				-- The later deadline wins, so a flare on an already-trap-stunned rig just extends it.
				local existing = rig:GetAttribute(Attributes.MonsterStunnedUntil)
				if not existing or existing < deadline then
					rig:SetAttribute(Attributes.MonsterStunnedUntil, deadline)
				end
			end
		end
	end
end

local function spawnFlare(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "Flare"
	part.Size = C.Size
	part.Color = C.Color
	part.Material = C.Material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)) -- lie the stick flat on the floor
	part.Parent = flareFolder

	local light = Instance.new("PointLight")
	light.Color = C.LightColor
	light.Brightness = C.IgniteFlashBrightness -- spikes at ignition, eased down below
	light.Range = C.LightRange
	light.Shadows = false
	light.Parent = part

	local spark = Instance.new("ParticleEmitter")
	spark.Texture = C.SparkTexture
	spark.Color = ColorSequence.new(C.SparkColor)
	spark.Rate = C.SparkRate
	spark.Lifetime = NumberRange.new(C.SparkLifetime * 0.6, C.SparkLifetime)
	spark.Size = NumberSequence.new(C.SparkSize, 0)
	spark.Speed = NumberRange.new(2, 5)
	spark.SpreadAngle = Vector2.new(40, 40)
	spark.LightEmission = 1
	spark.Parent = part

	local ignite = Instance.new("Sound")
	ignite.SoundId = C.IgniteSoundId
	ignite.Volume = C.IgniteVolume
	ignite.RollOffMode = Enum.RollOffMode.InverseTapered
	ignite.RollOffMinDistance = Config.Audio.RollOffMin
	ignite.RollOffMaxDistance = C.BurnRange
	ignite.SoundGroup = AudioGroups.get("SFX")
	ignite.Parent = part
	ignite:Play()

	local burn = Instance.new("Sound")
	burn.SoundId = C.BurnSoundId
	burn.Volume = C.BurnVolume
	burn.PlaybackSpeed = C.BurnPitch
	burn.Looped = true
	burn.RollOffMode = Enum.RollOffMode.InverseTapered
	burn.RollOffMinDistance = Config.Audio.RollOffMin
	burn.RollOffMaxDistance = C.BurnRange
	burn.SoundGroup = AudioGroups.get("SFX")
	burn.Parent = part
	burn:Play()

	-- Ease the ignite flash back to the steady burn brightness over IgniteFlashSeconds (a per-Heartbeat
	-- lerp, no Tween instance to clean up), guarded so it stops the instant the part despawns -- mirrors
	-- DecoyService's light handling.
	task.spawn(function()
		local elapsed = 0
		while elapsed < C.IgniteFlashSeconds do
			if not part.Parent then
				return
			end
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			local alpha = math.clamp(elapsed / C.IgniteFlashSeconds, 0, 1)
			light.Brightness = C.IgniteFlashBrightness + (C.LightBrightness - C.IgniteFlashBrightness) * alpha
		end
		if part.Parent then
			light.Brightness = C.LightBrightness
		end
	end)

	-- After a short travel beat, blind on ignition, then re-apply every interval while it burns (so a
	-- monster wandering INTO the still-burning pool is also caught -- covers the poll cadence). Stops the
	-- instant the part despawns.
	task.spawn(function()
		task.wait(C.IgniteDelay)
		local elapsed = C.IgniteDelay
		while part.Parent and elapsed < C.LifeSeconds do
			blindMonstersNear(position)
			task.wait(C.RepeatBlindInterval)
			elapsed += C.RepeatBlindInterval
		end
	end)

	task.delay(C.LifeSeconds, function()
		part:Destroy()
	end)
end

throwRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	-- Hostile input: rate-limit first (drop floods cheaply), then the real checks.
	if now - (lastMsg[player] or -math.huge) < C.IntentRateLimit then
		return
	end
	lastMsg[player] = now
	if not eligible(player) then
		return
	end
	if (player:GetAttribute(Attributes.FlareCharges) or 0) <= 0 then
		return -- out of flares this round
	end
	if now - (lastThrow[player] or -math.huge) < C.Cooldown then
		return
	end
	local landing = landingPoint(player)
	if not landing then
		return -- no valid landing (no living HRP): don't consume a charge
	end
	-- Only a successful spawn consumes a charge + arms the cooldown.
	lastThrow[player] = now
	player:SetAttribute(Attributes.FlareCharges, (player:GetAttribute(Attributes.FlareCharges) or C.Charges) - 1)
	spawnFlare(landing)
end)

local function onPlayerAdded(player: Player)
	grantCharges(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	lastThrow[player] = nil
	lastMsg[player] = nil
end)

-- New round: everyone's flares are restocked (a fresh hunt, a fresh defensive kit).
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	-- Destroy any flare still burning across the boundary FIRST -- otherwise its .Parent-guarded re-blind
	-- loop could write a fresh MonsterStunnedUntil into the NEW round, freezing a rig at the start of the
	-- next hunt (MazeService re-carves + repelHome already reset the rigs). Destroying the part severs the
	-- loop via its .Parent guard.
	for _, flare in flareFolder:GetChildren() do
		flare:Destroy()
	end
	for _, player in Players:GetPlayers() do
		grantCharges(player)
	end
end)
