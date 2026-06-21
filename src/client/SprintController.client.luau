--!nonstrict
-- SprintController.client.luau
-- Captures the sprint key and reports its held-state to the server as INTENT. It
-- never changes speed or stamina locally -- SprintService owns both (server-
-- authoritative, per CLAUDE.md). This script only sends a boolean on press/release.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local sprintIntent = Remotes.get(Remotes.Names.SprintIntent)
local sprintKey = Config.Player.SprintKey

local held = false
local function send(isHeld)
	if isHeld == held then
		return -- only fire on an actual transition (the server also rate-limits)
	end
	held = isHeld
	sprintIntent:FireServer(isHeld)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == sprintKey then
		send(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- Release always counts (even if the press was gameProcessed) so we never stick on.
	if input.KeyCode == sprintKey then
		send(false)
	end
end)

-- Alt-tab / focus loss does NOT fire InputEnded for a held key, which would otherwise
-- leave the server believing sprint is held. Release explicitly on focus loss.
UserInputService.WindowFocusReleased:Connect(function()
	send(false)
end)

-- Drop the held-state on respawn so a new character never starts stuck-sprinting.
Players.LocalPlayer.CharacterAdded:Connect(function()
	send(false)
end)
