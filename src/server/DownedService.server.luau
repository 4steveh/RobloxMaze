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
-- A KILL (not the co-op down) emits this so KeyService can apply the drop-a-key stake,
-- without coupling KeyService to monster/life logic (it just reacts to the signal).
local killedSignal = ServerSignals.get(ServerSignals.Names.PlayerKilled)

-- [player] = { progress = number, jumpPower = number, jumpHeight = number }
local downedState = {}

local function setAttrs(player, downed, progress)
	player:SetAttribute(Attributes.Downed, downed)
	player:SetAttribute(Attributes.ReviveProgress, progress)
end

-- Immobilize by ANCHORING the root, NOT PlatformStand. PlatformStand ragdolls the body:
-- it drops the HRP ~2 studs and can clip through the floor, which players read as "fell
-- through the map" (black screen) while being unable to move. Anchoring freezes the
-- character exactly in place, collapsed, with no physics, so it can never clip or fall.
-- WalkSpeed/Jump are also zeroed (SprintService skips downed players, so it never fights this).
local function down(player, species)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	downedState[player] = { progress = 0, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight }
	setAttrs(player, true, 0)
	player:SetAttribute(Attributes.DownedUntil, Workspace:GetServerTimeNow() + D.BleedoutSeconds)
	if hrp then
		-- Slump the body into a collapsed kneel BEFORE anchoring: lower it by DownDrop and
		-- pitch it forward by DownPitch (keeping yaw), so a downed player reads as collapsed
		-- rather than a frozen standing mannequin. Still ANCHOR (never PlatformStand — see above).
		hrp.CFrame = (hrp.CFrame - Vector3.new(0, D.DownDrop, 0)) * CFrame.Angles(-D.DownPitch, 0, 0)
		hrp.Anchored = true
	end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	caughtRemote:FireClient(player, true, species) -- the grab scare (downed variant — no respawn countdown); species drives which monster lunges
end

-- The classic death path (solo / disabled / full wipe): scare + checkpoint respawn.
local function kill(player, species)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	caughtRemote:FireClient(player, false, species) -- species → the jumpscare shows the monster that caught you
	if humanoid then
		humanoid.Health = 0 -- SpawnService.Died → RespawnDelay → checkpoint respawn
	end
	killedSignal:Fire(player) -- a kill resolved → KeyService applies the drop-a-key stake (if Config.Keys.DropOnCatch)
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
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = false
	end
	if humanoid then
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
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = false -- unanchor so the death + respawn isn't frozen in place
	end
	if humanoid then
		humanoid.Health = 0
	end
end

-- A monster reached a player: pick the outcome. `species` (which monster) is forwarded to the
-- client so the jumpscare shows the creature that actually caught you.
ServerSignals.get(ServerSignals.Names.PlayerCaught).Event:Connect(function(player, species)
	if player:GetAttribute(Attributes.Downed) == true then
		return -- already down; ignore a re-trigger
	end
	if D.Enabled and rescuerExists(player) then
		down(player, species)
	else
		kill(player, species)
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
	-- Clamp the upper bound too: a server hitch must not advance revive progress past its
	-- threshold in one tick (MonsterService + NoiseService clamp their dt for the same reason).
	local dt = math.clamp(now - lastClock, 1e-3, Config.Spatial.PollInterval * D.MaxTickDtFactor)
	lastClock = now
	local serverTime = Workspace:GetServerTimeNow()

	for player, st in downedState do
		-- Per-player isolation: one bad player can't freeze rescue for everyone.
		local ok, err = pcall(function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then
				-- Body gone while downed (shouldn't happen now we anchor instead of ragdoll, but
				-- NEVER leave a player stuck-downed): clear the flag so they recover. SpawnService
				-- respawns the character; its CharacterAdded handler re-cleans this anyway.
				downedState[player] = nil
				setAttrs(player, false, 0)
				player:SetAttribute(Attributes.DownedUntil, nil)
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
