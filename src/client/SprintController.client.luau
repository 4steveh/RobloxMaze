--!nonstrict
-- SprintController.client.luau
-- Captures the sprint key and reports its held-state to the server as INTENT. It
-- never changes speed or stamina locally -- SprintService owns both (server-
-- authoritative, per CLAUDE.md). This script only sends a boolean on press/release.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
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

-- Sprint via ContextActionService: createTouchButton makes a hold-to-sprint "Run" button on
-- touch devices (iPad/iPhone), while the keyboard SprintKey still works on PC -- one handler.
-- Begin -> sprinting; End/Cancel (key release, button lift, OR focus steal) -> released.
local SPRINT_ACTION = "Sprint"
ContextActionService:BindAction(SPRINT_ACTION, function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		send(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		send(false)
	end
	return Enum.ContextActionResult.Sink
end, true, sprintKey)
ContextActionService:SetTitle(SPRINT_ACTION, "Run")
ContextActionService:SetPosition(SPRINT_ACTION, UDim2.new(1, -150, 0.6, 0))

-- Alt-tab / focus loss does NOT fire a release for a held key, which would otherwise
-- leave the server believing sprint is held. Release explicitly on focus loss.
UserInputService.WindowFocusReleased:Connect(function()
	send(false)
end)

-- Drop the held-state on respawn so a new character never starts stuck-sprinting.
Players.LocalPlayer.CharacterAdded:Connect(function()
	send(false)
end)
