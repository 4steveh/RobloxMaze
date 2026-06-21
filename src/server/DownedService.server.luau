--!nonstrict
-- DownedService.server.luau
-- Co-op rescue: turns a monster catch into a DOWNED state (collapsed, immobilized,
-- bleeding out) that a teammate can reverse — instead of an instant respawn. This is the
-- genre's strongest co-op beat (Flee the Facility / Survive the Killer): your life depends
-- on a friend risking the monster to reach you, and "save myself vs save them" becomes a
-- real decision.
--
-- Server-authoritative throughout: it owns the Downed / DownedUntil / ReviveProgress
-- attributes, decides down-vs-kill on a catch, and validates revives by SPATIAL proximity
-- (a living teammate staying within ReviveRadius for ReviveSeconds — no client input, just
-- like SafeRoom occupancy). MonsterService stays out of player-life logic: it fires
-- ServerSignals.PlayerCaught and repels its rig home (anti-camp); THIS service picks the
-- outcome. SOLO, or a full wipe (no possible rescuer), goes straight to the normal
-- checkpoint respawn, so single-player is unchanged.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)
local Remotes = require(ReplicatedStorage.Remotes)
local Spatial = require(ReplicatedStorage.Spatial)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local ServerSignals = require(script.Parent.ServerSignals)

local D = Config.Downed

Remotes.init()
local caughtRemote = Remotes.get(Remotes.Names.MonsterCaught)

-- [player] = { progress = number, jumpPower = number, jumpHeight = number }
local downedState = {}

local function setAttrs(player, downed, progress)
	player:SetAttribute(Attributes.Downed, downed)
	player:SetAttribute(Attributes.ReviveProgress, progress)
end

-- Collapse + immobilize. WalkSpeed/Jump are zeroed (SprintService also skips downed players,
-- so it never fights this) and PlatformStand ragdolls the body so teammates SEE who is down.
local function down(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return
	end
	downedState[player] = { progress = 0, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight }
	setAttrs(player, true, 0)
	player:SetAttribute(Attributes.DownedUntil, Workspace:GetServerTimeNow() + D.BleedoutSeconds)
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	caughtRemote:FireClient(player, true) -- the grab scare (downed variant — no respawn countdown)
end

-- The classic death path (solo / disabled / full wipe): scare + checkpoint respawn.
local function kill(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	caughtRemote:FireClient(player, false)
	if humanoid then
		humanoid.Health = 0 -- SpawnService.Died → RespawnDelay → checkpoint respawn
	end
end

-- Any OTHER living, non-downed player who could come save this one? (Existence, not range:
-- they get a chance as long as someone could plausibly run over.)
local function rescuerExists(downedPlayer)
	for _, other in Players:GetPlayers() do
		if
			other ~= downedPlayer
			and other:GetAttribute(Attributes.Downed) ~= true
			and PlayerUtil.livingRootPart(other)
		then
			return true
		end
	end
	return false
end

-- Is a living, non-downed teammate currently within ReviveRadius of the downed player?
local function rescuerInRange(downedPlayer, downedPos)
	for _, other in Players:GetPlayers() do
		if other ~= downedPlayer and other:GetAttribute(Attributes.Downed) ~= true then
			local hrp = PlayerUtil.livingRootPart(other)
			if hrp and Spatial.withinRange(hrp.Position, downedPos, D.ReviveRadius) then
				return true
			end
		end
	end
	return false
end

local function revive(player)
	local st = downedState[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = Config.Player.WalkSpeed -- SprintService resumes ownership next frame
		if st then
			humanoid.JumpPower = st.jumpPower
			humanoid.JumpHeight = st.jumpHeight
		end
	end
	downedState[player] = nil
	setAttrs(player, false, 0)
	player:SetAttribute(Attributes.DownedUntil, nil)

	-- A brief monster-ignore grace so you're not instantly re-grabbed. Reuse RespawnGrace
	-- (MonsterService already skips graced players); guard the clear on the SAME character
	-- so a later respawn's own grace is never stripped early by this timer.
	player:SetAttribute(Attributes.RespawnGrace, true)
	task.delay(D.ReviveGraceSeconds, function()
		if player.Character == character and player:GetAttribute(Attributes.Downed) ~= true then
			player:SetAttribute(Attributes.RespawnGrace, false)
		end
	end)
end

-- Not rescued in time → the normal checkpoint death (NO second scare — the grab already played).
local function bleedout(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	downedState[player] = nil
	setAttrs(player, false, 0)
	player:SetAttribute(Attributes.DownedUntil, nil)
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.Health = 0
	end
end

-- A monster reached a player: pick the outcome.
ServerSignals.get(ServerSignals.Names.PlayerCaught).Event:Connect(function(player)
	if player:GetAttribute(Attributes.Downed) == true then
		return -- already down; ignore a re-trigger
	end
	if D.Enabled and rescuerExists(player) then
		down(player)
	else
		kill(player)
	end
end)

-- A fresh character is NEVER downed — clears the state across a bleedout-respawn AND a
-- round reset (both go through CharacterAdded), so the Downed attribute can't stick.
local function onPlayerAdded(player)
	setAttrs(player, false, 0)
	player.CharacterAdded:Connect(function()
		downedState[player] = nil
		setAttrs(player, false, 0)
		player:SetAttribute(Attributes.DownedUntil, nil)
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	downedState[player] = nil
end)

-- Poll: advance every downed player's bleedout + revive (server poll cadence, never Touched).
local lastClock = os.clock()
while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	local dt = math.max(now - lastClock, 1e-3)
	lastClock = now
	local serverTime = Workspace:GetServerTimeNow()

	for player, st in downedState do
		-- Per-player isolation: one bad player can't freeze rescue for everyone.
		local ok, err = pcall(function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then
				return
			end
			local deadline = player:GetAttribute(Attributes.DownedUntil)
			if deadline and serverTime >= deadline then
				bleedout(player)
				return
			end
			if rescuerInRange(player, hrp.Position) then
				st.progress = math.min(1, st.progress + dt / D.ReviveSeconds)
			else
				st.progress = math.max(0, st.progress - (dt / D.ReviveSeconds) * D.ReviveDecayScale)
			end
			player:SetAttribute(Attributes.ReviveProgress, st.progress)
			if st.progress >= 1 then
				revive(player)
			end
		end)
		if not ok then
			warn("[DownedService] tick error for a player (skipped this tick):", err)
		end
	end
end
