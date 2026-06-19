--!nonstrict
-- ExitService.server.luau
-- Server-authoritative win check. On the Config poll interval, if a player is
-- within the exit trigger radius of an ExitDoor (spatial, never Touched) and
-- holds at least the required keys, it triggers the win: sets GameState = Won,
-- freezes the player briefly, and fires the win remote. At the door without
-- enough keys, it gives a one-shot "locked" nudge -- nothing punishing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Enums = require(ReplicatedStorage.Enums)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)

Remotes.init()
local gameWonRemote = Remotes.get(Remotes.Names.GameWon)
local exitLockedRemote = Remotes.get(Remotes.Names.ExitLocked)

local won = {} -- [player] = true once they have won (don't re-trigger)
local atLockedDoor = {} -- [player] = true while standing at the door without enough keys

local function freezePlayer(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local walk, jumpPower, jumpHeight = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	task.delay(Config.Win.FreezeDuration, function()
		if humanoid.Parent then
			humanoid.WalkSpeed = walk
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
	won[player] = nil
	atLockedDoor[player] = nil
end)

while true do
	task.wait(Config.Spatial.PollInterval)

	local doors = Discovery.getAll(Tags.ExitDoor)
	for _, player in Players:GetPlayers() do
		if not won[player] then
			local rootPart = PlayerUtil.livingRootPart(player)
			if rootPart then
				local atDoor = false
				for _, door in doors do
					if
						door:IsA("BasePart")
						and Spatial.withinRange(rootPart.Position, door.Position, Config.Spatial.ExitTriggerRadius)
					then
						atDoor = true
						break
					end
				end

				if atDoor then
					local keys = player:GetAttribute(Attributes.KeyCount) or 0
					if keys >= Config.Keys.RequiredToWin then
						won[player] = true
						player:SetAttribute(Attributes.GameState, Enums.GameState.Won)
						freezePlayer(player.Character)
						gameWonRemote:FireClient(player)
					elseif not atLockedDoor[player] then
						-- One-shot locked feedback on arrival; re-armed when they leave.
						atLockedDoor[player] = true
						exitLockedRemote:FireClient(player)
					end
				else
					atLockedDoor[player] = false
				end
			end
		end
	end
end
