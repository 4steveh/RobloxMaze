--!nonstrict
-- ExitService.server.luau
-- Server-authoritative win check AND the physical exit DOOR. On the Config poll
-- interval, if a player is within the exit trigger radius of an ExitDoor (spatial,
-- never Touched -- measured to the door's closest SURFACE so a big gate part can't
-- leave the win unreachable) and holds at least the required keys, it triggers the
-- win: sets GameState = Won, freezes the player briefly, fires the win remote, SLIDES
-- THE GATE OPEN, and announces the escape to the lobby. At the door without enough
-- keys it gives a one-shot "locked" nudge -- nothing punishing.
--
-- The exit is two tagged things: the ExitDoor trigger VOLUME (proximity), and the
-- ExitGate SOLID part(s) that block the corridor. The gate stays shut + visibly LOCKED
-- (red indicator light) until the shared team holds RequiredToWin keys (indicator turns
-- green -- "openable"), then heaves open on a win. It re-closes/re-locks on a round reset.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Enums = require(ReplicatedStorage.Enums)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local ServerSignals = require(script.Parent.ServerSignals)

Remotes.init()
local gameWonRemote = Remotes.get(Remotes.Names.GameWon)
local exitLockedRemote = Remotes.get(Remotes.Names.ExitLocked)
local exitOpenedRemote = Remotes.get(Remotes.Names.ExitOpened)
local alarmRemote = Remotes.get(Remotes.Names.AlarmStateChanged) -- endgame climax: the all-keys alarm

local EXIT = Config.Exit

-- Whether a player has already won is derived from the authoritative GameState
-- attribute (not a private latch), so a RoundService resetting GameState to Playing
-- re-arms the exit naturally -- no separate "clear the win" handshake needed.
local atLockedDoor = {} -- [player] = true while standing at the door without enough keys

-- Exit-gate registry: each ExitGate part -> its closed pose, indicator light, open state.
-- Discovered by tag (never a hardcoded path); a maze with no ExitGate still wins (the
-- proximity check stands alone) -- the gate is the JUICE, not a hard dependency.
local gates = {} -- [part] = { closedCFrame = CFrame, light = PointLight, opened = boolean }
local unlocked = false -- last-applied lock indicator state (so we only repaint on change)
local announcedOpen = false -- ExitOpened fires once per round, even if two players escape together

local function indicatorFor(part: BasePart): PointLight
	local light = part:FindFirstChild("ExitLock")
	if not (light and light:IsA("PointLight")) then
		light = Instance.new("PointLight")
		light.Name = "ExitLock"
		light.Range = EXIT.IndicatorRange
		light.Brightness = EXIT.IndicatorBrightness
		light.Parent = part
	end
	return light
end

Discovery.observe(Tags.ExitGate, function(part)
	if not part:IsA("BasePart") then
		return
	end
	gates[part] = {
		closedCFrame = part.CFrame,
		light = indicatorFor(part),
		opened = false,
	}
	part.Anchored = true
	gates[part].light.Color = if unlocked then EXIT.UnlockedColor else EXIT.LockedColor
end, function(part)
	gates[part] = nil
end)

-- Does the shared team hold every key? (Counts are mirrored across players, so any
-- player's KeyCount answers it; max-scan stays correct even if that ever changes.)
local function teamHasKeys(): boolean
	for _, player in Players:GetPlayers() do
		if (player:GetAttribute(Attributes.KeyCount) or 0) >= Config.Keys.RequiredToWin then
			return true
		end
	end
	return false
end

-- Repaint the lock indicators when the team crosses the "all keys in" line (cheap; only
-- on a transition). Opened gates keep their green -- they read as "this way out".
local function refreshIndicators()
	local now = teamHasKeys()
	if now == unlocked then
		return
	end
	unlocked = now
	for _, gate in gates do
		if not gate.opened then
			gate.light.Color = if unlocked then EXIT.UnlockedColor else EXIT.LockedColor
		end
	end
	-- Same crossing drives the lobby-wide ALARM (the climax made felt): on at all-keys, off if
	-- the team drops back below (a key respawn). One fire per transition (this only runs on change).
	if Config.Endgame.AlarmEnabled then
		alarmRemote:FireAllClients(unlocked)
	end
end

local function openGates()
	for part, gate in gates do
		if not gate.opened then
			gate.opened = true
			part.CanCollide = false -- stop the heaving door from shoving the escapee
			gate.light.Color = EXIT.UnlockedColor
			local up = part.CFrame.UpVector * EXIT.OpenLiftStuds
			TweenService:Create(
				part,
				TweenInfo.new(EXIT.OpenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = gate.closedCFrame + up }
			):Play()
		end
	end
end

local function closeGates()
	for part, gate in gates do
		gate.opened = false
		part.CFrame = gate.closedCFrame -- snap shut (no one is watching during the reset blackout)
		part.CanCollide = true
		gate.light.Color = EXIT.LockedColor
	end
	unlocked = false
end

local function freezePlayer(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local jumpPower, jumpHeight = humanoid.JumpPower, humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	task.delay(Config.Win.FreezeDuration, function()
		if humanoid.Parent then
			-- Restore to the canonical base WalkSpeed, not the captured live speed: the
			-- player may have been sprinting at the win instant, and SprintService leaves
			-- Won players' WalkSpeed alone, so a captured SprintSpeed would otherwise stick.
			humanoid.WalkSpeed = Config.Player.WalkSpeed
			humanoid.JumpPower = jumpPower
			humanoid.JumpHeight = jumpHeight
		end
	end)
end

local function onPlayerAdded(player)
	player:SetAttribute(Attributes.GameState, Enums.GameState.Playing)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	atLockedDoor[player] = nil
end)

-- New round: clear the win so the exit re-arms (processPlayer reads GameState), and
-- shut + re-lock the gate so the next round starts behind a closed door.
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	announcedOpen = false
	closeGates()
	if Config.Endgame.AlarmEnabled then
		alarmRemote:FireAllClients(false) -- silence the endgame alarm for the fresh round
	end
	for _, player in Players:GetPlayers() do
		atLockedDoor[player] = nil
		player:SetAttribute(Attributes.GameState, Enums.GameState.Playing)
	end
end)

-- Per-player exit check, factored out so it can be pcall-isolated: a throw on one
-- player must not freeze win detection for the whole server.
local function processPlayer(player, doors)
	if player:GetAttribute(Attributes.GameState) == Enums.GameState.Won then
		return -- already won; don't re-trigger (re-armed when RoundService resets GameState)
	end
	if player:GetAttribute(Attributes.Downed) == true then
		return -- collapsed at the exit doesn't count as escaping
	end
	local rootPart = PlayerUtil.livingRootPart(player)
	if not rootPart then
		return
	end

	local atDoor = false
	for _, door in doors do
		if
			door:IsA("BasePart")
			and Spatial.distanceToPart(rootPart.Position, door) <= Config.Spatial.ExitTriggerRadius
		then
			atDoor = true
			break
		end
	end

	if atDoor then
		local keys = player:GetAttribute(Attributes.KeyCount) or 0
		if keys >= Config.Keys.RequiredToWin then
			player:SetAttribute(Attributes.GameState, Enums.GameState.Won)
			freezePlayer(player.Character)
			gameWonRemote:FireClient(player)
			openGates()
			if not announcedOpen then
				announcedOpen = true
				exitOpenedRemote:FireAllClients(player.Name) -- door-open SFX + "X ESCAPED!" for the others
			end
		elseif not atLockedDoor[player] then
			-- One-shot locked feedback on arrival; re-armed when they leave.
			atLockedDoor[player] = true
			exitLockedRemote:FireClient(player)
		end
	else
		atLockedDoor[player] = false
	end
end

while true do
	task.wait(Config.Spatial.PollInterval)

	refreshIndicators()
	local doors = Discovery.getAll(Tags.ExitDoor)
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(processPlayer, player, doors)
		if not ok then
			warn("[ExitService] tick error for a player (skipped this tick):", err)
		end
	end
end
