--!nonstrict
-- SafeRoomService.server.luau
-- Server authority for "is this player safe" and "where is their checkpoint".
-- On the Config poll interval it spatially tests each living player's
-- HumanoidRootPart against every SafeRoom part (no Touched events -- see
-- CLAUDE.md), detects enter/leave transitions vs. the previous tick, records the
-- entered SafeRoom as the player's checkpoint, and fires the enter/leave remotes
-- that the flashlight (and later, audio) consume.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local ServerSignals = require(script.Parent.ServerSignals)

Remotes.init()
local enteredRemote = Remotes.get(Remotes.Names.SafeRoomEntered)
local leftRemote = Remotes.get(Remotes.Names.SafeRoomLeft)

-- Cosmetic sanctuary tell (decides NOTHING -- detection stays the spatial poll below). A SafeRoom
-- was invisible from outside (a trigger volume), so safety wasn't FINDABLE down a corridor. We attach
-- a calm green outline + soft glow per room -- the green half of the red=danger (trap pad) / green=safe
-- language. One-time per part (idempotent find-or-create, so a re-tagged part never doubles up), built
-- here on the server so the marks replicate to every client. Discovery.observe fires for existing rooms
-- AND any tagged later; children die with their part, so onRemoved needs no cleanup.
local function markSafeRoom(part)
	if not part:IsA("BasePart") then
		return -- only solid trigger volumes carry the visual; ignore folders/attachments tagged by mistake
	end

	-- Green wire outline so the room's bounds read at a glance from down a dark hall.
	local outline = part:FindFirstChild("SafeOutline")
	if not outline then
		outline = Instance.new("SelectionBox")
		outline.Name = "SafeOutline"
		outline.Adornee = part
		outline.LineThickness = 0.05 -- a thin calm line, not a thick beacon
		outline.Parent = part
	end
	outline.Color3 = Config.SafeRoom.OutlineColor
	outline.SurfaceColor3 = Config.SafeRoom.OutlineColor
	outline.Transparency = Config.SafeRoom.OutlineTransparency

	-- Soft inviting glow so the sanctuary self-lights in the dark (kept gentle -- it must not outshine
	-- the keys/exit, which are the objective). Shadows off: it's a wash, not a caster.
	local glow = part:FindFirstChild("SafeGlow")
	if not glow then
		glow = Instance.new("PointLight")
		glow.Name = "SafeGlow"
		glow.Shadows = false
		glow.Parent = part
	end
	glow.Color = Config.SafeRoom.GlowColor
	glow.Brightness = Config.SafeRoom.GlowBrightness
	glow.Range = Config.SafeRoom.GlowRange
end

Discovery.observe(Tags.SafeRoom, markSafeRoom)

-- Whether each player was inside any SafeRoom on the previous tick.
local insideLast = {}

-- Reset transition state for a fresh character so a player who respawns inside a
-- SafeRoom correctly re-fires "entered" on the next tick.
local function onPlayerAdded(player)
	insideLast[player] = false
	player:SetAttribute(Attributes.InSafeRoom, false)
	player.CharacterAdded:Connect(function()
		insideLast[player] = false
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	insideLast[player] = nil
end)

-- New round: forget safe-room state and clear checkpoints so everyone restarts at the
-- PlayerStart (a fresh run), not their last safe room.
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	for _, player in Players:GetPlayers() do
		if insideLast[player] then
			leftRemote:FireClient(player) -- so the client clears safe-room reverb/recharge belief
		end
		insideLast[player] = false
		player:SetAttribute(Attributes.InSafeRoom, false)
		player:SetAttribute(Attributes.Checkpoint, nil)
	end
end)

-- Per-player occupancy/transition check, factored out so it can be pcall-isolated:
-- a throw on one player (HRP cleared mid-frame, a room part destroyed) must not
-- freeze safe-room detection (and thus battery recharge + checkpoints) server-wide.
local function processPlayer(player, safeRooms)
	local rootPart = PlayerUtil.livingRootPart(player)
	if not rootPart then
		return -- No living HRP this tick (spawning/dead): skip without erroring.
	end
	local position = rootPart.Position

	-- Which SafeRoom (if any) the player is inside this tick.
	local currentRoom = nil
	for _, room in safeRooms do
		if room:IsA("BasePart") and Spatial.isInsidePart(room, position) then
			currentRoom = room
			break
		end
	end

	local insideNow = currentRoom ~= nil
	local wasInside = insideLast[player] == true

	if insideNow and not wasInside then
		-- Entered: this SafeRoom becomes the checkpoint SpawnService reads.
		player:SetAttribute(Attributes.Checkpoint, currentRoom.CFrame)
		player:SetAttribute(Attributes.InSafeRoom, true)
		enteredRemote:FireClient(player)
	elseif wasInside and not insideNow then
		-- Left: checkpoint persists; only the "safe" flag clears.
		player:SetAttribute(Attributes.InSafeRoom, false)
		leftRemote:FireClient(player)
	end

	insideLast[player] = insideNow
end

while true do
	task.wait(Config.Spatial.PollInterval)

	local safeRooms = Discovery.getAll(Tags.SafeRoom)
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(processPlayer, player, safeRooms)
		if not ok then
			warn("[SafeRoomService] tick error for a player (skipped this tick):", err)
		end
	end
end
