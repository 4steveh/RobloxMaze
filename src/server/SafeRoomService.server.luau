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

Remotes.init()
local enteredRemote = Remotes.get(Remotes.Names.SafeRoomEntered)
local leftRemote = Remotes.get(Remotes.Names.SafeRoomLeft)

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

while true do
	task.wait(Config.Spatial.PollInterval)

	local safeRooms = Discovery.getAll(Tags.SafeRoom)
	for _, player in Players:GetPlayers() do
		local rootPart = PlayerUtil.livingRootPart(player)
		if rootPart then
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
		-- No living HRP this tick (spawning/dead): skip without erroring.
	end
end
