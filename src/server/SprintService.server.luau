--!nonstrict
-- SprintService.server.luau
-- Server-authoritative sprint + stamina -- the player's escape tool that makes a
-- chase winnable (base WalkSpeed loses to the bunny's ChaseSpeed; a stamina-limited
-- sprint burst beats it long enough to break line of sight).
--
-- The client sends only INTENT (the sprint key's held-state) over the SprintIntent
-- remote -- the FIRST and only client->server remote in the game. Per CLAUDE.md the
-- payload is treated as hostile: the server validates its type, rate-limits it, and
-- alone owns the stamina value and the Humanoid.WalkSpeed it produces. A cheating
-- client can spam intent but can never grant itself extra stamina or speed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)

local P = Config.Player

Remotes.init()
local sprintIntent = Remotes.get(Remotes.Names.SprintIntent)

-- Per-player runtime state (never trusted from the client beyond the boolean intent).
local state = {} -- [player] = { stamina, held, lastIntent, lastSprint }

local function ensure(player)
	if not state[player] then
		state[player] = { stamina = P.StaminaMax, held = false, lastIntent = 0, lastSprint = 0 }
		player:SetAttribute(Attributes.Stamina, P.StaminaMax)
	end
	return state[player]
end

local function onPlayerAdded(player)
	ensure(player)
	player.CharacterAdded:Connect(function(character)
		-- Reset the moment a fresh body exists so a respawn starts at base speed.
		local s = ensure(player)
		s.held = false
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.WalkSpeed = P.WalkSpeed
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
end)

-- Hostile input: accept only a boolean, and only at the configured rate.
sprintIntent.OnServerEvent:Connect(function(player, held)
	if typeof(held) ~= "boolean" then
		return -- malformed payload -> ignore
	end
	local s = ensure(player)
	-- Coalesce the intent so a transition can never be lost: the client only sends on
	-- a state CHANGE, so a quick tap-release whose release lands inside the rate limit
	-- would otherwise strand s.held=true (involuntary sprint + stamina drain). Always
	-- converge to the latest held-state, then throttle only the heavier bookkeeping.
	s.held = held
	local now = os.clock()
	if now - s.lastIntent < P.IntentRateLimit then
		return -- spam -> throttle (the held-state above already converged)
	end
	s.lastIntent = now
end)

-- The server alone advances stamina and sets WalkSpeed, every frame.
RunService.Heartbeat:Connect(function(dt)
	for player, s in state do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- Don't fight ExitService's win-freeze or DownedService's immobilization: leave Won
		-- and Downed players' WalkSpeed alone.
		if
			not humanoid
			or humanoid.Health <= 0
			or player:GetAttribute(Attributes.GameState) == Enums.GameState.Won
			or player:GetAttribute(Attributes.Downed) == true
			or player:GetAttribute(Attributes.Hidden) == true -- tucked in a locker (anchored): don't drain stamina or touch WalkSpeed
		then
			continue
		end

		local moving = humanoid.MoveDirection.Magnitude > 0.05
		local sprinting = s.held and moving and s.stamina > 0

		if sprinting then
			humanoid.WalkSpeed = P.SprintSpeed
			s.stamina = math.max(0, s.stamina - P.StaminaDrain * dt)
			s.lastSprint = os.clock()
		else
			humanoid.WalkSpeed = P.WalkSpeed
			-- Regen only after a short delay since the last sprint frame.
			if os.clock() - s.lastSprint >= P.StaminaRegenDelay then
				s.stamina = math.min(P.StaminaMax, s.stamina + P.StaminaRegen * dt)
			end
		end

		player:SetAttribute(Attributes.Stamina, s.stamina)
	end
end)
