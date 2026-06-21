--!nonstrict
-- NoiseService.server.luau
-- Server-authoritative NOISE -- the monkey's prey signal. Each PollInterval it measures
-- every player's actual ground speed from REPLICATED HRP position deltas (unspoofable:
-- the server owns position) and writes a smoothed `NoiseLevel` (0..1) attribute:
-- sprinting is loud, walking sits below the monkey's HearThreshold (so the default
-- state is safe), creeping is near-silent. Noise RISES fast and DECAYS slowly, so
-- shedding the monkey means committing to quiet. Zeroed for players in a SafeRoom /
-- Won / RespawnGrace (sanctuary silences you, so you cannot bait it from safety).
--
-- This is the SprintService-style server poll: it owns one player attribute. No client
-- input -- movement is already server-known, so the monkey needs no new trusted remote.
-- The monkey reads this via MonsterService's per-player effectiveNoise; the HUD renders it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)

local N = Config.Noise

-- Map measured planar speed (studs/s) -> target noise (0..1), piecewise so each tier
-- (sprint / walk / creep / idle) is tunable independently.
local function targetNoise(speed: number): number
	if speed >= N.SprintSpeedRef then
		return N.SprintNoise
	elseif speed >= N.WalkSpeedRef then
		local t = (speed - N.WalkSpeedRef) / (N.SprintSpeedRef - N.WalkSpeedRef)
		return N.WalkNoise + (N.SprintNoise - N.WalkNoise) * t
	elseif speed >= N.CreepSpeedRef then
		local t = (speed - N.CreepSpeedRef) / (N.WalkSpeedRef - N.CreepSpeedRef)
		return N.CreepNoise + (N.WalkNoise - N.CreepNoise) * t
	end
	local t = speed / math.max(N.CreepSpeedRef, 0.001)
	return N.IdleNoise + (N.CreepNoise - N.IdleNoise) * t
end

local lastPos = {} -- [player] = Vector3 last sampled HRP position

local function isSilenced(player: Player): boolean
	return player:GetAttribute(Attributes.InSafeRoom) == true
		or player:GetAttribute(Attributes.GameState) == Enums.GameState.Won
		or player:GetAttribute(Attributes.RespawnGrace) == true
		or player:GetAttribute(Attributes.Downed) == true -- a downed player makes no controllable noise
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Attributes.NoiseLevel, 0)
	-- Drop the stale sample on respawn so the death->respawn position jump is never
	-- read as movement (the next tick re-seeds lastPos from the fresh position).
	player.CharacterAdded:Connect(function()
		lastPos[player] = nil
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	lastPos[player] = nil
end)

-- Per-player noise update, factored out so it can be pcall-isolated (one bad player
-- can't freeze noise -- and thus the monkey's prey signal -- for the whole server).
local function processPlayer(player: Player, dt: number)
	local hrp = PlayerUtil.livingRootPart(player)
	local current = player:GetAttribute(Attributes.NoiseLevel) or 0
	local target
	if not hrp or isSilenced(player) then
		target = 0
		if hrp then
			lastPos[player] = hrp.Position
		end
	else
		local prev = lastPos[player] or hrp.Position
		lastPos[player] = hrp.Position
		local delta = hrp.Position - prev
		local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
		if speed > N.MaxPlausibleSpeed then
			return -- a teleport (respawn jump), not running: leave NoiseLevel untouched this tick
		end
		target = targetNoise(speed)
	end
	-- Asymmetric smoothing: rise fast (instantly loud), decay slow (commit to quiet).
	local rate = if target > current then N.RisePerSecond else N.DecayPerSecond
	local value = current + (target - current) * math.min(dt * rate, 1)
	if value < 0.001 then
		value = 0
	end
	player:SetAttribute(Attributes.NoiseLevel, value)
end

local lastClock = os.clock()
while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	local dt = math.max(now - lastClock, 1e-3)
	lastClock = now

	for _, player in Players:GetPlayers() do
		local ok, err = pcall(processPlayer, player, dt)
		if not ok then
			warn("[NoiseService] tick error for a player (skipped this tick):", err)
		end
	end
end
