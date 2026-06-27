--!nonstrict
-- HideController.client.luau
-- Captures the HIDE input and reports it to the server as INTENT (no payload). HidingService owns the
-- whole act -- it validates range from your authoritative position, anchors/teleports you, and runs the
-- discover poll -- so this script only sends the toggle and renders two render-only tells: a "press to
-- HIDE" affordance when you're near a usable spot, and a "HIDDEN" overlay while you're tucked away. The
-- proximity check here is COSMETIC (it just hints "you can duck in"); the server does the real range gate.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)

local H = Config.Hiding
local TC = Config.TouchControls
local UI = Config.UI
local hideIntent = Remotes.get(Remotes.Names.HideIntent)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function fireHide()
	hideIntent:FireServer() -- no payload: the server confirms range + toggles in/out
end

-- Keyboard (PC) + a gamepad button bound to the same action. createTouchButton=false: touch devices
-- get the custom button below instead of CAS's small generic auto-button.
ContextActionService:BindAction("Hide", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		fireHide()
	end
	return Enum.ContextActionResult.Sink
end, false, H.HideKey, H.GamepadHideKey)

local gui = Instance.new("ScreenGui")
gui.Name = "HideHud"
gui.ResetOnSpawn = false
gui.Parent = playerGui

-- "press to HIDE" affordance, shown only near a usable spot. On touch there's no key to name.
local prompt = Instance.new("TextLabel")
prompt.Name = "HidePrompt"
prompt.AnchorPoint = Vector2.new(0.5, 1)
prompt.Position = UDim2.fromScale(0.5, 0.8) -- just below screen centre, clear of the bottom gauges
prompt.Size = UDim2.fromOffset(220, 34)
prompt.BackgroundColor3 = TC.BackgroundColor
prompt.BackgroundTransparency = TC.BackgroundTransparency
prompt.Font = UI.SubheadingFont
prompt.TextSize = 20
prompt.TextColor3 = H.PromptColor
prompt.TextStrokeTransparency = UI.TextStrokeTransparency
prompt.Text = UserInputService.TouchEnabled and H.PromptText or (H.PromptText .. "  [" .. H.HideKey.Name .. "]")
prompt.Visible = false
local promptCorner = Instance.new("UICorner")
promptCorner.CornerRadius = UDim.new(0, UI.ChipCornerRadius)
promptCorner.Parent = prompt
prompt.Parent = gui

-- The "HIDDEN" overlay while you're tucked away (display weight, centred).
local hidden = Instance.new("TextLabel")
hidden.Name = "HiddenOverlay"
hidden.AnchorPoint = Vector2.new(0.5, 0.5)
hidden.Position = UDim2.fromScale(0.5, 0.5)
hidden.Size = UDim2.fromOffset(380, 46)
hidden.BackgroundTransparency = 1
hidden.Font = UI.HeadingFont
hidden.TextSize = 30
hidden.TextColor3 = H.PromptColor
hidden.TextStrokeColor3 = UI.TextStrokeColor
hidden.TextStrokeTransparency = UI.TextStrokeTransparency
hidden.Text = H.HiddenText
hidden.Visible = false
hidden.Parent = gui

-- Custom circular tap button for touch devices, in the bottom-right stack above the DECOY button.
if UserInputService.TouchEnabled then
	local btn = Instance.new("TextButton")
	btn.Name = "HideButton"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -TC.EdgeMargin, 1, -H.TouchBottomOffset)
	btn.Size = UDim2.fromOffset(TC.ButtonSize, TC.ButtonSize)
	btn.BackgroundColor3 = TC.BackgroundColor
	btn.BackgroundTransparency = TC.BackgroundTransparency
	btn.AutoButtonColor = true
	btn.Active = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = TC.TextSize
	btn.TextColor3 = TC.TextColor
	btn.Text = H.TouchLabel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- circular
	corner.Parent = btn
	local ring = Instance.new("UIStroke")
	ring.Color = H.TouchColor
	ring.Thickness = TC.RingThickness
	ring.Parent = btn
	-- Tap-punch: a quick scale pop on every press (springs back via Back/Out) -- tactile feedback kids can SEE.
	local scale = Instance.new("UIScale")
	scale.Parent = btn
	local function punch()
		scale.Scale = TC.PressScale
		TweenService:Create(
			scale,
			TweenInfo.new(TC.PressReturnSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
	btn.Activated:Connect(function()
		fireHide()
		punch()
	end)
	btn.Parent = gui
end

-- Drive the two tells each frame. The HIDDEN overlay takes over while hidden; otherwise the prompt
-- appears whenever a HidingSpot is within EnterRadius (cosmetic proximity -- the server re-validates).
RunService.RenderStepped:Connect(function()
	local isHidden = player:GetAttribute(Attributes.Hidden) == true
	hidden.Visible = isHidden
	if isHidden then
		prompt.Visible = false
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		prompt.Visible = false
		return
	end
	local near = false
	for _, spot in Discovery.getAll(Tags.HidingSpot) do
		if spot:IsA("BasePart") and (spot.Position - hrp.Position).Magnitude <= H.EnterRadius then
			near = true
			break
		end
	end
	prompt.Visible = near
end)
