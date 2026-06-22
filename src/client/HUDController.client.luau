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
local pipStrokes = {} -- parallel: each pip's UIStroke, flashed on fill
local pipScales = {} -- parallel: each pip's UIScale, popped on fill
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

	-- A UIScale the pickup pop overshoots (the row is center-aligned, so a single pip popping
	-- stays balanced); reset to 1 each round.
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = pip

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
	pipStrokes[i] = stroke
	pipScales[i] = scale
end

local function refreshPips()
	for i, pip in pips do
		pip.BackgroundColor3 = if i <= keyCount then HUD.PipFilledColor else HUD.PipEmptyColor
	end
end

-- Make a just-collected key feel TACTILE: the filled pip overshoots in scale (Back ease) and its
-- stroke flashes bright, then both settle. Render-only juice; the fill colour comes from refreshPips.
local function popPip(i)
	local scale, stroke = pipScales[i], pipStrokes[i]
	if not (scale and stroke) then
		return
	end
	-- Punch up fast, settle back with a Back overshoot.
	scale.Scale = 1
	TweenService
		:Create(scale, TweenInfo.new(HUD.PipPopSeconds * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = HUD.PipPopScale,
		})
		:Play()
	task.delay(HUD.PipPopSeconds * 0.35, function()
		TweenService
			:Create(scale, TweenInfo.new(HUD.PipPopSeconds * 0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			:Play()
	end)
	-- Stroke flash: thicken + brighten, then ease back to the resting stroke.
	stroke.Thickness = HUD.PipPopStrokeThickness
	stroke.Color = HUD.PipPopStrokeColor
	TweenService:Create(stroke, TweenInfo.new(HUD.PipPopSeconds), {
		Thickness = HUD.PipStrokeThickness,
		Color = HUD.PipStrokeColor,
	}):Play()
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

-- Exhaustion flash: a stroke on the gauge (the render loop owns the FILL colour every frame, so a
-- fill-colour flash would be overwritten -- the stroke is ours to flash). Invisible at rest.
local staminaStroke = Instance.new("UIStroke")
staminaStroke.Color = HUD.ExhaustColor
staminaStroke.Thickness = 0
staminaStroke.Transparency = 1
staminaStroke.Parent = staminaBack
local staminaBasePos = staminaBack.Position

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
local winTextBasePos = UDim2.fromScale(0.5, 0.58)
winText.Position = winTextBasePos
winText.Size = UDim2.fromOffset(HUD.WinTextWidth, HUD.WinTextSize + HUD.WinTextPadding)
winText.BackgroundTransparency = 1
winText.Font = Enum.Font.GothamBold
winText.TextSize = HUD.WinTextSize
winText.Text = "ESCAPED"
winText.TextColor3 = HUD.WinIconColor
winText.Parent = winOverlay

-- A full-screen relief BLOOM that washes over the win the instant it lands, then clears -- it sits
-- above the overlay (ZIndex) so the dark panel + icon ease in beneath the fading light.
local winFlash = Instance.new("Frame")
winFlash.Name = "WinFlash"
winFlash.Size = UDim2.fromScale(1, 1)
winFlash.BackgroundColor3 = HUD.WinFlashColor
winFlash.BackgroundTransparency = 1
winFlash.ZIndex = 10
winFlash.Visible = false
winFlash.Parent = gui

-- The escape is the run's PAYOFF, so it arrives as a sequence (bloom -> overlay eases in -> icon
-- pops with an overshoot -> label rises in), not a hard Visible flip. The win jingle already lands
-- via StingerController on the same GameWon remote. Render-only.
local function playWinCelebration()
	winFlash.Visible = true
	winFlash.BackgroundTransparency = 0
	TweenService:Create(
		winFlash,
		TweenInfo.new(HUD.WinFlashSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()

	winOverlay.Visible = true
	winOverlay.BackgroundTransparency = 1
	TweenService:Create(
		winOverlay,
		TweenInfo.new(HUD.WinOverlayFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = HUD.WinBackTransparency }
	):Play()

	winIcon.Size = UDim2.fromOffset(0, 0) -- pop up from nothing (Back overshoot)
	TweenService:Create(
		winIcon,
		TweenInfo.new(HUD.WinIconPopSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(HUD.WinIconSize, HUD.WinIconSize) }
	):Play()

	winText.Position = winTextBasePos + UDim2.fromOffset(0, HUD.WinTextRisePixels)
	winText.TextTransparency = 1
	TweenService:Create(
		winText,
		TweenInfo.new(HUD.WinTextRiseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = winTextBasePos, TextTransparency = 0 }
	):Play()
end

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

-- Sprint EXHAUSTION feedback. When stamina empties mid-chase the server cuts your speed, which can
-- read as "Shift stopped working". A one-shot jolt + "OUT OF BREATH" toast at the moment of
-- exhaustion tells the player WHY they slowed. Fires once per drain; re-arms only after stamina
-- climbs back to usable (the render loop edge-detects). Render-only.
local exhausted = false
local function triggerExhaust()
	showToast(HUD.ExhaustText, HUD.ExhaustColor, HUD.ExhaustToastSeconds)
	staminaStroke.Thickness = 3
	staminaStroke.Transparency = 0
	TweenService:Create(staminaStroke, TweenInfo.new(0.4), { Thickness = 0, Transparency = 1 }):Play()
	task.spawn(function()
		local step = HUD.ExhaustShakeTime / 4
		for _ = 1, 2 do
			staminaBack.Position = staminaBasePos + UDim2.fromOffset(HUD.ExhaustShakePixels, 0)
			task.wait(step)
			staminaBack.Position = staminaBasePos + UDim2.fromOffset(-HUD.ExhaustShakePixels, 0)
			task.wait(step)
		end
		staminaBack.Position = staminaBasePos
	end)
end

-- Cached ExitDoor list (the exit arrow read Discovery.getAll every frame; observe once).
local exitDoors = {}
Discovery.observe(Tags.ExitDoor, function(inst)
	if inst:IsA("BasePart") then
		table.insert(exitDoors, inst)
	end
end, function(inst)
	local i = table.find(exitDoors, inst)
	if i then
		table.remove(exitDoors, i)
	end
end)

-- Remotes ---------------------------------------------------------------------
local keyCollectedRemote = Remotes.get(Remotes.Names.KeyCollected)
local gameWonRemote = Remotes.get(Remotes.Names.GameWon)
local exitLockedRemote = Remotes.get(Remotes.Names.ExitLocked)
local exitOpenedRemote = Remotes.get(Remotes.Names.ExitOpened)

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
	count = count or keyCount
	showToast(string.format("KEY %d/%d", count, requiredKeys), nil, Config.Feedback.KeyToastSeconds)
	popPip(count) -- the pip that just filled (index == the new team total)
end)

gameWonRemote.OnClientEvent:Connect(playWinCelebration)

-- A teammate reached the exit (shared round): the escapee gets the win overlay above;
-- everyone else sees WHO got out, so the round reset reads as their escape, not a yank.
-- Matched by name (not GameState) since the remotes and the attribute replicate together.
exitOpenedRemote.OnClientEvent:Connect(function(escapeeName)
	if escapeeName == player.Name then
		return
	end
	showToast(
		string.format("%s %s", escapeeName or "Someone", Config.Feedback.EscapedSuffix),
		Config.Feedback.EscapedColor,
		Config.Feedback.EscapedToastSeconds
	)
end)

-- A new round (GameState back to Playing) hides the win overlay + bloom.
player:GetAttributeChangedSignal(Attributes.GameState):Connect(function()
	if player:GetAttribute(Attributes.GameState) ~= Enums.GameState.Won then
		winOverlay.Visible = false
		winFlash.Visible = false
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

	-- Exhaustion edge-detect: fire once as stamina bottoms out; re-arm once it recovers to usable.
	if not exhausted and sfrac <= HUD.ExhaustFraction then
		exhausted = true
		triggerExhaust()
	elseif exhausted and sfrac >= HUD.ExhaustRecoverFraction then
		exhausted = false
	end

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
			for _, candidate in exitDoors do
				if candidate.Parent then
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
