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
	local SR = Config.SafeRoom

	-- Retire the old full-VOLUME wireframe (a floating green cage that read as debug art): a glowing
	-- FLOOR BORDER traced around the room base instead -- finished, and the green twin of the trap's red
	-- floor pad. Idempotent: rebuild a "SafeTrim" folder of four neon strips each call (clears + refills),
	-- so a re-tag never stacks duplicates. Strips are placed in the room's LOCAL frame (part.CFrame * ...)
	-- so a rotated room is still traced correctly.
	local stale = part:FindFirstChild("SafeOutline")
	if stale then
		stale:Destroy()
	end
	local trim = part:FindFirstChild("SafeTrim")
	if not (trim and trim:IsA("Folder")) then
		if trim then
			trim:Destroy()
		end
		trim = Instance.new("Folder")
		trim.Name = "SafeTrim"
		trim.Parent = part
	else
		trim:ClearAllChildren()
	end
	local s = part.Size
	local floorLocalY = -s.Y / 2 + SR.TrimRaise -- the room's floor, in its own frame, a hair raised
	local t = SR.TrimThickness
	local function strip(name: string, size: Vector3, localPos: Vector3)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = SR.OutlineColor
		p.Transparency = SR.OutlineTransparency
		p.Size = size
		p.CFrame = part.CFrame * CFrame.new(localPos)
		p.Parent = trim
	end
	-- Two strips spanning X (the north/south edges) and two spanning Z (east/west), inset by half their
	-- thickness so the border sits flush inside the footprint.
	strip("TrimN", Vector3.new(s.X, SR.TrimHeight, t), Vector3.new(0, floorLocalY, s.Z / 2 - t / 2))
	strip("TrimS", Vector3.new(s.X, SR.TrimHeight, t), Vector3.new(0, floorLocalY, -s.Z / 2 + t / 2))
	strip("TrimE", Vector3.new(t, SR.TrimHeight, s.Z), Vector3.new(s.X / 2 - t / 2, floorLocalY, 0))
	strip("TrimW", Vector3.new(t, SR.TrimHeight, s.Z), Vector3.new(-s.X / 2 + t / 2, floorLocalY, 0))

	-- Soft inviting glow so the sanctuary self-lights in the dark (kept gentle -- it must not outshine
	-- the keys/exit, which are the objective). Shadows off: it's a wash, not a caster.
	local glow = part:FindFirstChild("SafeGlow")
	if not (glow and glow:IsA("PointLight")) then
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
