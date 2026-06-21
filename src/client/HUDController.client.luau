--!nonstrict
-- HUDController.client.luau
-- Icon-forward HUD (minimal text): a row of key pips, a battery gauge, an exit
-- arrow that appears only once all keys are collected, and a win overlay. The
-- client only RENDERS state pushed by the server (remotes) and reads Config --
-- it never decides pickups or the win. Visuals are no-asset placeholders (shapes
-- + glyphs) with clearly-named empty Sound/ImageLabel slots to fill with real art.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)

local HUD = Config.HUD
local requiredKeys = Config.Keys.RequiredToWin

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local keyCount = 0

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Placeholder feedback sounds: no asset IDs -- set SoundId to your own SFX.
local function placeholderSound(name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "" -- TODO: drop in an asset id, e.g. "rbxassetid://..."
	sound.Parent = gui
	return sound
end
local keyCollectSound = placeholderSound("KeyCollectSound")
local exitLockedSound = placeholderSound("ExitLockedSound")

-- Key pips --------------------------------------------------------------------
local pipsBasePosition = UDim2.new(0.5, 0, 0, HUD.PipTopOffset)
local pipsRow = Instance.new("Frame")
pipsRow.Name = "KeyPips"
pipsRow.AnchorPoint = Vector2.new(0.5, 0)
pipsRow.Position = pipsBasePosition
pipsRow.Size = UDim2.fromOffset(requiredKeys * HUD.PipSize + (requiredKeys - 1) * HUD.PipGap, HUD.PipSize)
pipsRow.BackgroundTransparency = 1
pipsRow.Parent = gui

local pipsLayout = Instance.new("UIListLayout")
pipsLayout.FillDirection = Enum.FillDirection.Horizontal
pipsLayout.Padding = UDim.new(0, HUD.PipGap)
pipsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pipsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pipsLayout.Parent = pipsRow

local pips = {}
for i = 1, requiredKeys do
	local pip = Instance.new("Frame")
	pip.Name = "Pip" .. i
	pip.LayoutOrder = i
	pip.Size = UDim2.fromOffset(HUD.PipSize, HUD.PipSize)
	pip.BackgroundColor3 = HUD.PipEmptyColor

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- circle
	corner.Parent = pip

	local stroke = Instance.new("UIStroke")
	stroke.Color = HUD.PipStrokeColor
	stroke.Thickness = HUD.PipStrokeThickness
	stroke.Parent = pip

	-- Art hook: drop a key/collectible icon image here later.
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(HUD.PipIconScale, HUD.PipIconScale)
	icon.Image = "" -- TODO: key icon asset id
	icon.Parent = pip

	pip.Parent = pipsRow
	pips[i] = pip
end

local function refreshPips()
	for i, pip in pips do
		pip.BackgroundColor3 = if i <= keyCount then HUD.PipFilledColor else HUD.PipEmptyColor
	end
end

-- Battery gauge ---------------------------------------------------------------
local batteryBack = Instance.new("Frame")
batteryBack.Name = "BatteryGauge"
batteryBack.AnchorPoint = Vector2.new(0, 1)
batteryBack.Position = UDim2.new(0, HUD.BatteryMargin, 1, -HUD.BatteryMargin)
batteryBack.Size = UDim2.fromOffset(HUD.BatteryWidth, HUD.BatteryHeight)
batteryBack.BackgroundColor3 = HUD.BatteryBackColor
local batteryBackCorner = Instance.new("UICorner")
batteryBackCorner.CornerRadius = UDim.new(0, HUD.CornerRadius)
batteryBackCorner.Parent = batteryBack
batteryBack.Parent = gui

local batteryFill = Instance.new("Frame")
batteryFill.Name = "Fill"
batteryFill.AnchorPoint = Vector2.new(0, 0.5)
batteryFill.Position = UDim2.fromScale(0, 0.5)
batteryFill.Size = UDim2.fromScale(1, 1)
batteryFill.BackgroundColor3 = HUD.BatteryFillColor
local batteryFillCorner = Instance.new("UICorner")
batteryFillCorner.CornerRadius = UDim.new(0, HUD.CornerRadius)
batteryFillCorner.Parent = batteryFill
batteryFill.Parent = batteryBack

-- Stamina gauge (sits just above the battery gauge) ----------------------------
local staminaBack = Instance.new("Frame")
staminaBack.Name = "StaminaGauge"
staminaBack.AnchorPoint = Vector2.new(0, 1)
staminaBack.Position = UDim2.new(0, HUD.BatteryMargin, 1, -(HUD.BatteryMargin + HUD.BatteryHeight + HUD.StaminaGap))
staminaBack.Size = UDim2.fromOffset(HUD.BatteryWidth, HUD.BatteryHeight)
staminaBack.BackgroundColor3 = HUD.BatteryBackColor
local staminaBackCorner = Instance.new("UICorner")
staminaBackCorner.CornerRadius = UDim.new(0, HUD.CornerRadius)
staminaBackCorner.Parent = staminaBack
staminaBack.Parent = gui

local staminaFill = Instance.new("Frame")
staminaFill.Name = "Fill"
staminaFill.AnchorPoint = Vector2.new(0, 0.5)
staminaFill.Position = UDim2.fromScale(0, 0.5)
staminaFill.Size = UDim2.fromScale(1, 1)
staminaFill.BackgroundColor3 = HUD.StaminaFillColor
local staminaFillCorner = Instance.new("UICorner")
staminaFillCorner.CornerRadius = UDim.new(0, HUD.CornerRadius)
staminaFillCorner.Parent = staminaFill
staminaFill.Parent = staminaBack

-- Exit arrow (placeholder glyph; swap for an arrow image later) ----------------
local arrow = Instance.new("TextLabel")
arrow.Name = "ExitArrow"
arrow.AnchorPoint = Vector2.new(0.5, 1)
arrow.Position = UDim2.new(0.5, 0, 1, -HUD.ArrowBottomOffset)
arrow.Size = UDim2.fromOffset(HUD.ArrowSize, HUD.ArrowSize)
arrow.BackgroundTransparency = 1
arrow.Font = Enum.Font.GothamBold
arrow.Text = "\u{25B2}" -- up-pointing triangle = "ahead"
arrow.TextScaled = true
arrow.TextColor3 = HUD.ArrowColor
arrow.Visible = false
arrow.Parent = gui

-- Win overlay (icon-led; minimal text) ----------------------------------------
local winOverlay = Instance.new("Frame")
winOverlay.Name = "WinOverlay"
winOverlay.Size = UDim2.fromScale(1, 1)
winOverlay.BackgroundColor3 = HUD.WinBackColor
winOverlay.BackgroundTransparency = HUD.WinBackTransparency
winOverlay.Visible = false
winOverlay.Parent = gui

local winIcon = Instance.new("TextLabel")
winIcon.Name = "Icon"
winIcon.AnchorPoint = Vector2.new(0.5, 0.5)
winIcon.Position = UDim2.fromScale(0.5, 0.45)
winIcon.Size = UDim2.fromOffset(HUD.WinIconSize, HUD.WinIconSize)
winIcon.BackgroundTransparency = 1
winIcon.Font = Enum.Font.GothamBold
winIcon.Text = "\u{2713}" -- checkmark placeholder; swap for an "escaped" graphic
winIcon.TextScaled = true
winIcon.TextColor3 = HUD.WinIconColor
winIcon.Parent = winOverlay

local winText = Instance.new("TextLabel")
winText.Name = "Label"
winText.AnchorPoint = Vector2.new(0.5, 0)
winText.Position = UDim2.fromScale(0.5, 0.58)
winText.Size = UDim2.fromOffset(HUD.WinTextWidth, HUD.WinTextSize + HUD.WinTextPadding)
winText.BackgroundTransparency = 1
winText.Font = Enum.Font.GothamBold
winText.TextSize = HUD.WinTextSize
winText.Text = "ESCAPED"
winText.TextColor3 = HUD.WinIconColor
winText.Parent = winOverlay

-- Transient feedback toast (key pickup / locked door) --------------------------
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0.5)
toast.Position = UDim2.fromScale(0.5, HUD.ToastYScale)
toast.Size = UDim2.fromOffset(HUD.ToastWidth, HUD.ToastHeight)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamBold
toast.TextSize = HUD.ToastTextSize
toast.TextColor3 = Config.Feedback.ToastColor
toast.TextStrokeTransparency = 0.4
toast.TextTransparency = 1
toast.Text = ""
toast.Parent = gui

local toastToken = 0
local function showToast(text, color, seconds)
	toastToken += 1
	local mine = toastToken
	toast.Text = text
	toast.TextColor3 = color or Config.Feedback.ToastColor
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.4
	task.delay(seconds, function()
		if mine == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- Remotes ---------------------------------------------------------------------
local keyCollectedRemote = Remotes.get(Remotes.Names.KeyCollected)
local gameWonRemote = Remotes.get(Remotes.Names.GameWon)
local exitLockedRemote = Remotes.get(Remotes.Names.ExitLocked)

-- Pip count syncs from the server-authoritative KeyCount attribute, so it is correct on
-- pickup AND on a round reset to 0 (the remote below only drives the chime/toast juice).
local function setKeyCount(count)
	keyCount = count or 0
	refreshPips()
end
setKeyCount(player:GetAttribute(Attributes.KeyCount) or 0)
player:GetAttributeChangedSignal(Attributes.KeyCount):Connect(function()
	setKeyCount(player:GetAttribute(Attributes.KeyCount) or 0)
end)

keyCollectedRemote.OnClientEvent:Connect(function(count)
	keyCollectSound:Play()
	showToast(string.format("KEY %d/%d", count or keyCount, requiredKeys), nil, Config.Feedback.KeyToastSeconds)
end)

gameWonRemote.OnClientEvent:Connect(function()
	winOverlay.Visible = true
end)

-- A new round (GameState back to Playing) hides the win overlay.
player:GetAttributeChangedSignal(Attributes.GameState):Connect(function()
	if player:GetAttribute(Attributes.GameState) ~= Enums.GameState.Won then
		winOverlay.Visible = false
	end
end)

exitLockedRemote.OnClientEvent:Connect(function()
	exitLockedSound:Play()
	showToast(
		string.format("%s — NEED %d KEYS (have %d)", Config.Feedback.LockedTextPrefix, requiredKeys, keyCount),
		HUD.BatteryLowColor,
		Config.Feedback.LockedToastSeconds
	)
	-- A small rattle of the pip row -- nothing punishing.
	local step = HUD.LockedShakeTime / 4
	for _ = 1, 2 do
		pipsRow.Position = pipsBasePosition + UDim2.fromOffset(HUD.LockedShakePixels, 0)
		task.wait(step)
		pipsRow.Position = pipsBasePosition + UDim2.fromOffset(-HUD.LockedShakePixels, 0)
		task.wait(step)
	end
	pipsRow.Position = pipsBasePosition
end)

-- Per-frame: battery gauge + exit-arrow direction -----------------------------
RunService.RenderStepped:Connect(function()
	-- Battery gauge reads the client-set battery attribute (FlashlightController).
	local battery = player:GetAttribute(Attributes.FlashlightBattery)
	if battery == nil then
		battery = Config.Flashlight.BatteryMax
	end
	local frac = math.clamp(battery / Config.Flashlight.BatteryMax, 0, 1)
	batteryFill.Size = UDim2.fromScale(frac, 1)
	batteryFill.BackgroundColor3 = if battery <= Config.Flashlight.LowBatteryThreshold
		then HUD.BatteryLowColor
		else HUD.BatteryFillColor

	-- Stamina gauge reads the server-authoritative Stamina attribute (SprintService).
	local stamina = player:GetAttribute(Attributes.Stamina)
	if stamina == nil then
		stamina = Config.Player.StaminaMax
	end
	local sfrac = math.clamp(stamina / Config.Player.StaminaMax, 0, 1)
	staminaFill.Size = UDim2.fromScale(sfrac, 1)
	staminaFill.BackgroundColor3 = if sfrac <= 0.25 then HUD.StaminaLowColor else HUD.StaminaFillColor

	-- Exit arrow: only once every key is collected; points toward the ExitDoor.
	local showArrow = keyCount >= requiredKeys
	arrow.Visible = showArrow
	if showArrow then
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera
		-- Nearest ExitDoor, matching ExitService's any-door win trigger.
		local door = nil
		if rootPart then
			local nearest = math.huge
			for _, candidate in Discovery.getAll(Tags.ExitDoor) do
				if candidate:IsA("BasePart") then
					local dist = (candidate.Position - rootPart.Position).Magnitude
					if dist < nearest then
						nearest, door = dist, candidate
					end
				end
			end
		end
		if rootPart and door and camera then
			local toDoor = door.Position - rootPart.Position
			local camCF = camera.CFrame
			local forward = camCF.LookVector
			local right = camCF.RightVector
			-- Bearing on the horizontal plane, relative to where the camera faces.
			local f = forward.X * toDoor.X + forward.Z * toDoor.Z
			local r = right.X * toDoor.X + right.Z * toDoor.Z
			arrow.Rotation = math.deg(math.atan2(r, f))
		end
	end
end)
