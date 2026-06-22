--!nonstrict
-- RoundService.server.luau
-- Owns the round lifecycle so the game LOOPS. Before this, keys spawned once (KeyService)
-- and a win latched forever (a player who reached the exit was Won with nothing left to do
-- and the server never recovered a playable state). RoundService closes the loop:
--
--   detect a win (any player's GameState -> Won) -> hold a brief celebration ->
--   fire ServerSignals.RoundReset, which each system reacts to by resetting ONLY its own
--   state: KeyService re-randomizes the keys, ExitService clears the win, SafeRoomService
--   clears checkpoints, SpawnService respawns everyone at the start, MonsterService resets
--   the rigs. The round is SHARED (the first escape ends it for the lobby), which fits a
--   short arcade-horror loop and is exactly the replay the single-player case needs.
--
-- No direct cross-script calls (per CLAUDE.md): the win is observed via the GameState
-- attribute and the new round announced via the ServerSignals bus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local ServerSignals = require(script.Parent.ServerSignals)

local R = Config.Round
local roundReset = ServerSignals.get(ServerSignals.Names.RoundReset)
local roundEnded = ServerSignals.get(ServerSignals.Names.RoundEnded)

local resetting = false
local roundGen = 0 -- bumped each reset, so a straggler win from an older round can't re-reset
local roundStartClock = os.clock() -- when the current round began
-- When each player's survival-for-THIS-round clock started: their join time, or the round start --
-- whichever is LATER. So a mid-round joiner is credited only the time they were actually present,
-- not the whole round (the survival-coin floor is per-second; full-round credit over-pays joiners).
local joinClock = {} -- [player] = os.clock()

local function beginNewRound()
	if resetting then
		return -- a reset is already in flight (another player won in the same window)
	end
	resetting = true
	roundGen += 1

	-- Award coins for the round that just ended, BEFORE roundReset clears KeyCount / GameState.
	-- EconomyService listens; the summary captures end-of-round state.
	-- An ARRAY with `player` as a VALUE (not a table keyed by the Player Instance): a BindableEvent
	-- deep-copies its table args and does NOT preserve Instance KEYS, but Instance VALUES survive.
	local summaries = {}
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local started = math.max(roundStartClock, joinClock[player] or roundStartClock)
		table.insert(summaries, {
			player = player,
			keys = player:GetAttribute(Attributes.KeyCount) or 0,
			escaped = player:GetAttribute(Attributes.GameState) == Enums.GameState.Won,
			survivalSeconds = now - started,
		})
	end
	roundEnded:Fire(summaries)

	roundReset:Fire() -- each system resets its own state (keys, win, checkpoints, spawns, monsters)
	roundStartClock = os.clock()
	task.wait(R.ResetSettleSeconds)
	resetting = false
end

local function onWin()
	-- Shared round: let the winner's celebration play, then loop everyone into a fresh round.
	-- Capture the round we won in: if a SECOND player also won during this celebration and
	-- their reset already fired, our generation is stale -- don't reset the fresh round again.
	local myGen = roundGen
	task.wait(R.WinCelebrationSeconds)
	if myGen ~= roundGen then
		return
	end
	beginNewRound()
end

local function watch(player: Player)
	joinClock[player] = os.clock()
	player:GetAttributeChangedSignal(Attributes.GameState):Connect(function()
		if player:GetAttribute(Attributes.GameState) == Enums.GameState.Won and not resetting then
			task.spawn(onWin)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player)
	joinClock[player] = nil
end)
for _, player in Players:GetPlayers() do
	watch(player)
end

-- A round nobody escapes still ENDS: after MaxRoundSeconds with no win, force a fresh round so the
-- maze re-carves and coins pay out (the never-worth-zero floor). beginNewRound guards re-entry, and
-- the summaries carry escaped=false. 0 disables the safety net.
if R.MaxRoundSeconds and R.MaxRoundSeconds > 0 then
	task.spawn(function()
		while true do
			task.wait(1)
			if not resetting and os.clock() - roundStartClock >= R.MaxRoundSeconds then
				beginNewRound()
			end
		end
	end)
end
