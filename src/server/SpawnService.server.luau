--!nonstrict
-- SpawnService.server.luau
-- The single owner of WHERE a character goes when it spawns -- first spawn and
-- every respawn alike (there is no separate respawn service). Places the
-- character at the player's current checkpoint (recorded by SafeRoomService) or,
-- if they have none yet, at a PlayerStart marker.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		return
	end

	-- Place upright above the marker (CFrame, not RespawnLocation: the markers are
	-- tagged Parts, not SpawnLocations). With no SpawnLocation the engine applies
	-- its own default spawn position around CharacterAdded, which can override a
	-- single CFrame write -- so assert ours across the next few frames so it wins.
	local goal = CFrame.new(target.Position + Vector3.new(0, Config.Respawn.SpawnUpOffset, 0))
	character:PivotTo(goal)
	for _ = 1, 4 do
		RunService.Heartbeat:Wait()
		if not rootPart.Parent then
			return
		end
		character:PivotTo(goal)
	end
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
