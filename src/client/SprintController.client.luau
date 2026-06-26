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
local gamepadSprintKey = Config.Player.GamepadSprintKey

local held = false
local function send(isHeld)
	if isHeld == held then
		return -- only fire on an actual transition (the server also rate-limits)
	end
	held = isHeld
	sprintIntent:FireServer(isHeld)
end

-- Keyboard sprint (PC) + a gamepad stick-click bound to the same action -- CAS reports the same
-- Begin/End for either input, so the held-state logic is unchanged. createTouchButton=false: touch
-- devices get the custom hold button below instead of CAS's small generic auto-button.
local SPRINT_ACTION = "Sprint"
ContextActionService:BindAction(SPRINT_ACTION, function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		send(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		send(false)
	end
	return Enum.ContextActionResult.Sink
end, false, sprintKey, gamepadSprintKey)

-- Custom on-screen HOLD-to-sprint button for touch devices (iPad/iPhone), below the flashlight
-- button. Active=true keeps camera panning usable. Render-only; hidden on PC.
if UserInputService.TouchEnabled then
	local TC = Config.TouchControls
	local touchGui = Instance.new("ScreenGui")
	touchGui.Name = "SprintTouch"
	touchGui.ResetOnSpawn = false
	touchGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.Name = "SprintButton"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -TC.EdgeMargin, 1, -TC.SprintBottomOffset)
	btn.Size = UDim2.fromOffset(TC.ButtonSize, TC.ButtonSize)
	btn.BackgroundColor3 = TC.BackgroundColor
	btn.BackgroundTransparency = TC.BackgroundTransparency
	btn.AutoButtonColor = true
	btn.Active = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = TC.TextSize
	btn.TextColor3 = TC.TextColor
	btn.Text = TC.SprintLabel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- circular
	corner.Parent = btn
	local ring = Instance.new("UIStroke")
	ring.Color = TC.SprintColor
	ring.Thickness = 3
	ring.Parent = btn
	if TC.SprintIconImage ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.6, 0.6)
		icon.Image = TC.SprintIconImage
		icon.Parent = btn
		btn.Text = ""
	end
	-- Hold: press anywhere on the button -> sprint; lift/leave -> stop.
	btn.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			send(true)
		end
	end)
	btn.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			send(false)
		end
	end)
	btn.Parent = touchGui
end

-- Alt-tab / focus loss does NOT fire a release for a held key, which would otherwise
-- leave the server believing sprint is held. Release explicitly on focus loss.
UserInputService.WindowFocusReleased:Connect(function()
	send(false)
end)

-- Drop the held-state on respawn so a new character never starts stuck-sprinting.
Players.LocalPlayer.CharacterAdded:Connect(function()
	send(false)
end)
