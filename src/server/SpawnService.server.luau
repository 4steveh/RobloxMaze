--!nonstrict
-- SpawnService.server.luau
-- The single owner of WHERE a character goes when it spawns -- first spawn and
-- every respawn alike (there is no separate respawn service). Places the
-- character at the player's current checkpoint (recorded by SafeRoomService) or,
-- if they have none yet, at a PlayerStart marker.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Attributes = require(ReplicatedStorage.Attributes)

-- Where this player should spawn: their checkpoint CFrame if SafeRoomService has
-- recorded one, otherwise the first PlayerStart marker. nil if neither exists.
local function spawnCFrame(player)
	-- Honor the Config toggle: when AtCheckpoint is off, ignore any recorded
	-- checkpoint and always fall through to a PlayerStart marker.
	if Config.Respawn.AtCheckpoint then
		local checkpoint = player:GetAttribute(Attributes.Checkpoint)
		if typeof(checkpoint) == "CFrame" then
			return checkpoint
		end
	end
	for _, marker in Discovery.getAll(Tags.PlayerStart) do
		if marker:IsA("BasePart") then
			return marker.CFrame
		end
	end
	return nil
end

local function onCharacterAdded(player, character)
	local target = spawnCFrame(player)
	if not target then
		return -- no checkpoint and no PlayerStart placed yet; leave the default spawn
	end

	-- Placement (not RespawnLocation) is the source of truth here: the markers are
	-- tagged Parts, not SpawnLocations, so we set the CFrame directly. Spawn upright
	-- above the marker so a rotated marker can't tilt the character into the floor.
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		return
	end
	rootPart.CFrame = CFrame.new(target.Position + Vector3.new(0, Config.Respawn.SpawnUpOffset, 0))
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
