--!nonstrict
-- HidingService.server.luau
-- The genre's missing last-resort escape: a tagged HidingSpot (a locker/cabinet) you DUCK INTO when
-- you're cornered -- out of stamina, decoy on cooldown. While hidden a monster can neither see nor
-- hear you (MonsterService leaves you out of the sensed set, exactly like a SafeRoom), so it's the
-- final "I have to lose them NOW" button. It is NOT god-mode: a HUNTING monster (Chase/Investigate)
-- that lingers within DiscoverRadius of your spot for DiscoverSeconds FLUSHES you back out, so you
-- must break line of sight BEFORE you hide -- ducking in while still seen only delays the grab.
--
-- Server-authoritative throughout, mirroring SafeRoomService/SprintService: the client sends only
-- the HideIntent (no payload, treated as hostile -- type-free but rate-limited per player). The server
-- alone decides eligibility + range from the player's OWN known HRP position (never a client position),
-- owns the Hidden attribute, anchors/teleports the body, and runs the discover poll by spatial check.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local ServerSignals = require(script.Parent.ServerSignals)

local H = Config.Hiding

-- Inert when the feature is off: bind nothing (a stray HideIntent from the client harmlessly no-ops,
-- since the remote is never connected here). Mirrors the "inert until placed" intent of Config.Hiding.
if not H.Enabled then
	return
end

Remotes.init()
local hideIntent = Remotes.get(Remotes.Names.HideIntent)

-- [player] = { spot = BasePart, prePos = Vector3, discoverTime = number }
local hideState = {}
local lastIntent = {} -- [player] = os.clock() of the last ACCEPTED HideIntent (per-player rate limit)

-- Self-heal the placed locker geometry: the Locker_<spot> models were authored FLOATING ~4 studs off
-- the floor, so a hiding player (placed at the floor) had their head clip the cabinet while their feet
-- stuck out below it ("head in, feet out"). Rather than depend on the unsaved place content being
-- corrected by hand, SNAP each locker down so its base rests on the maze floor at boot -- reproducible,
-- git-durable, and harmless if a locker is already seated (the <0.05 dy guard skips it). World-space
-- translate (pre-multiply) so a rotated locker still moves straight DOWN in Y.
local function normalizeLockers()
	if not H.FloorSnap then
		return
	end
	local floorY = Config.Maze.FloorY -- top surface of the maze floor (walls/props stand on it)
	for _, spot in Discovery.getAll(Tags.HidingSpot) do
		if spot:IsA("BasePart") then
			local locker = spot.Parent and spot.Parent:FindFirstChild("Locker_" .. spot.Name)
			if not (locker and locker:IsA("Model")) then
				-- Structural fallback: some places nest the HidingSpot UNDER its Locker model rather than
				-- as a named sibling -- find the enclosing Model instead (defensive; the sibling lookup is
				-- what THIS place uses).
				locker = spot:FindFirstAncestorWhichIsA("Model")
			end
			if locker and locker:IsA("Model") then
				local cf, size = locker:GetBoundingBox()
				local dy = floorY - (cf.Position.Y - size.Y / 2)
				if math.abs(dy) > 0.05 then
					locker:PivotTo(CFrame.new(0, dy, 0) * locker:GetPivot())
				end
			else
				warn("[HidingService] no Locker model for tagged HidingSpot:", spot:GetFullName())
			end
		end
	end
end
task.defer(normalizeLockers) -- after CollectionService tags settle (HidingSpot discovery)

-- A monster that is actively HUNTING (Chase/Investigate -- not a calm patrol/search) within
-- DiscoverRadius of a hidden body. Reads the rigs' replicated State attribute off the Monsters
-- folder; Alert is excluded (it's the monkey's stationary "it heard you" tell, not a closing hunt).
local function hunterNearPosition(position: Vector3): boolean
	local folder = Workspace:FindFirstChild(WorldFolders.Monsters)
	if not folder then
		return false
	end
	for _, rig in folder:GetChildren() do
		local state = rig:GetAttribute(Attributes.MonsterState)
		if state == Enums.MonsterState.Chase or state == Enums.MonsterState.Investigate then
			local root = rig.PrimaryPart
			if root and Spatial.withinRange(root.Position, position, H.DiscoverRadius) then
				return true
			end
		end
	end
	return false
end

-- Duck IN: the toggle's hide branch. Confirms the player is eligible (a living HRP, not already
-- safe/won/downed/graced) and within EnterRadius of a real HidingSpot from the SERVER's known
-- position, then teleports + ANCHORS them into the spot (like DownedService.down freezes the body --
-- NOT PlatformStand, whose ragdoll clipped players through the floor) and raises the Hidden flag.
local function hide(player: Player)
	-- Eligibility: you can't duck in while already safe, escaped, downed, or mid-respawn-grace.
	if
		player:GetAttribute(Attributes.InSafeRoom) == true
		or player:GetAttribute(Attributes.GameState) == Enums.GameState.Won
		or player:GetAttribute(Attributes.Downed) == true
		or player:GetAttribute(Attributes.RespawnGrace) == true
	then
		return
	end
	local hrp = PlayerUtil.livingRootPart(player)
	if not hrp then
		return
	end

	-- Nearest HidingSpot in reach, by SURFACE distance (distanceToPart, not center -- a locker has
	-- volume; the surface trigger is what CLAUDE.md prescribes for proximity to a thick part).
	local nearest, nearestDist = nil, math.huge
	for _, spot in Discovery.getAll(Tags.HidingSpot) do
		if spot:IsA("BasePart") then
			local d = Spatial.distanceToPart(hrp.Position, spot)
			if d < nearestDist then
				nearest, nearestDist = spot, d
			end
		end
	end
	if not nearest or nearestDist > H.EnterRadius then
		return -- no usable spot within reach: reject the intent (the client only HINTED you were near one)
	end

	-- Keep the player's current (standing) Y so the body never clips into the floor or floats; only
	-- slide them onto the spot in the XZ plane. Remember the spot + where they came from (prePos) so we
	-- can climb them back out in front of it (or, if the spot has no clear facing, back toward prePos).
	local prePos = hrp.Position
	-- Preserve the player's CURRENT horizontal facing so ducking in doesn't snap them to face world +Z
	-- (identity rotation did): derive yaw from their HRP look and re-apply it at the hide spot.
	local hidePos = Vector3.new(nearest.Position.X, prePos.Y, nearest.Position.Z)
	local look = hrp.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then
		flatLook = Vector3.new(0, 0, 1) -- degenerate (looking straight up/down) -> default facing
	end
	hrp.CFrame = CFrame.new(hidePos, hidePos + flatLook.Unit)
	hrp.Anchored = true
	hideState[player] = { spot = nearest, prePos = prePos, discoverTime = 0 }
	player:SetAttribute(Attributes.Hidden, true)
end

-- Climb back OUT (the toggle's unhide branch + the discover flush): place the player ExitNudge studs
-- in FRONT of the spot, un-anchor, drop the flag. Degenerate spot facing (a square locker) falls back
-- to nudging toward prePos -- the open floor they walked in from.
local function unhide(player: Player)
	local st = hideState[player]
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and st and st.spot and st.spot.Parent then
		local spot = st.spot
		-- PRIMARY: drop them back onto prePos -- the known-walkable floor they stepped in from, so the
		-- climb-out never shoves them THROUGH a wall the locker happens to face. The LookVector nudge is
		-- only the fallback when prePos is missing or sits basically on top of the spot (degenerate).
		local out
		if st.prePos then
			local back = st.prePos - spot.Position
			if Vector3.new(back.X, 0, back.Z).Magnitude >= 1e-3 then
				out = st.prePos
			end
		end
		if not out then
			local look = spot.CFrame.LookVector
			local dir = Vector3.new(look.X, 0, look.Z) -- the spot's flat facing = "in front"
			if dir.Magnitude < 1e-3 then
				dir = Vector3.new(0, 0, 1) -- last resort so the Unit below never divides by zero
			end
			out = spot.Position + dir.Unit * H.ExitNudge
		end
		hrp.CFrame = CFrame.new(Vector3.new(out.X, hrp.Position.Y, out.Z)) -- keep the anchored (standing) Y
	end
	if hrp then
		hrp.Anchored = false
	end
	hideState[player] = nil
	player:SetAttribute(Attributes.Hidden, false)
end

-- Found out: a hunter sat on the spot too long. Climb the player out and grant a brief beat of
-- RespawnGrace so being discovered isn't an instant grab the same frame they pop into the open.
-- Reuse RespawnGrace (MonsterService already skips graced players); clear it guarded on the SAME
-- character and only if they haven't re-hidden, mirroring DownedService.revive's grace handling.
local function flush(player: Player)
	local character = player.Character
	unhide(player)
	player:SetAttribute(Attributes.RespawnGrace, true)
	task.delay(H.FlushGraceSeconds, function()
		if player.Character == character and player:GetAttribute(Attributes.Hidden) ~= true then
			player:SetAttribute(Attributes.RespawnGrace, false)
		end
	end)
end

-- Lifecycle cleanup: a fresh or dead body is NEVER hidden. Drop the state, clear the flag, and make
-- sure no HRP is left anchored (mirrors DownedService's CharacterAdded reset).
local function clearHidden(player: Player)
	hideState[player] = nil
	player:SetAttribute(Attributes.Hidden, false)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp.Anchored then
		hrp.Anchored = false
	end
end

-- Hostile input: no payload, so there's nothing to type-check -- just rate-limit per player (anti-spam),
-- then TOGGLE. All the validation (eligibility, range, position) lives in hide() and runs server-side.
hideIntent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastIntent[player] or 0) < H.IntentRateLimit then
		return -- spam -> throttle
	end
	lastIntent[player] = now
	-- Per-player isolation: a throw on one player's hide/unhide must not break the remote for everyone.
	local ok, err = pcall(function()
		if player:GetAttribute(Attributes.Hidden) == true then
			unhide(player)
		else
			hide(player)
		end
	end)
	if not ok then
		warn("[HidingService] hide-intent error for a player:", err)
	end
end)

-- A fresh character is never hidden, and dying while tucked away clears the flag + un-anchors so the
-- death/respawn isn't frozen inside the locker (mirrors DownedService.bleedout's pre-kill unanchor).
local function onPlayerAdded(player: Player)
	player:SetAttribute(Attributes.Hidden, false)
	local function onCharacter(character)
		hideState[player] = nil
		player:SetAttribute(Attributes.Hidden, false)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				clearHidden(player)
			end)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	hideState[player] = nil
	lastIntent[player] = nil
end)

-- New round: nobody stays tucked away across the boundary (the maze re-carves; everyone restarts).
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	for _, player in Players:GetPlayers() do
		clearHidden(player)
	end
end)

-- Discover poll (server cadence, never Touched): for each hidden player, accumulate the time a hunter
-- spends within DiscoverRadius of their spot. Cross DiscoverSeconds and they're flushed out; the timer
-- resets the moment no hunter is near (the search "loses interest"), so a hunter only PASSING by is safe.
local lastClock = os.clock()
while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	-- Clamp the upper bound too: a server hitch must not jump discoverTime past DiscoverSeconds
	-- in one tick (MonsterService + NoiseService clamp their dt for the same reason).
	local dt = math.clamp(now - lastClock, 1e-3, Config.Spatial.PollInterval * H.MaxTickDtFactor)
	lastClock = now

	for player, st in hideState do
		-- Per-player isolation: one bad player can't freeze discovery for everyone hiding.
		local ok, err = pcall(function()
			local hrp = PlayerUtil.livingRootPart(player)
			if not hrp then
				return -- body gone while hidden; the death/CharacterAdded cleanup clears the flag
			end
			if hunterNearPosition(hrp.Position) then
				st.discoverTime += dt
				if st.discoverTime >= H.DiscoverSeconds then
					flush(player)
				end
			else
				st.discoverTime = 0 -- no hunter near: the spot's cover holds, the search resets
			end
		end)
		if not ok then
			warn("[HidingService] discover-poll error for a player (skipped this tick):", err)
		end
	end
end
