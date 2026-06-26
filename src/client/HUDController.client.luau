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

-- Event audio (key chime, locked-door thunk, win jingle, etc.) is owned ENTIRELY by
-- StingerController, the single source for one-shot event SFX wired to the same remotes
-- this HUD reads. The HUD renders visuals only -- no Sound instances live here.

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

-- A caption laid over a gauge bar (left-aligned, strong stroke so it reads even over a full
-- fill), so the two left-corner bars are self-labelling (BATTERY / STAMINA) the way the NOISE
-- meter labels itself on the right -- a new player no longer has to guess what they are.
local function makeGaugeLabel(parent, text)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.AnchorPoint = Vector2.new(0, 0.5)
	lbl.Position = UDim2.new(0, 6, 0.5, 0)
	lbl.Size = UDim2.new(1, -12, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Config.UI.SubheadingFont
	lbl.TextSize = HUD.GaugeLabelSize
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Config.UI.TextColor
	lbl.TextStrokeColor3 = Config.UI.TextStrokeColor
	lbl.TextStrokeTransparency = 0.15
	lbl.Text = text
	lbl.ZIndex = 5
	lbl.Parent = parent
	return lbl
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
makeGaugeLabel(batteryBack, HUD.BatteryLabel)

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
makeGaugeLabel(staminaBack, HUD.StaminaLabel)

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
arrow.Font = Config.UI.HeadingFont
arrow.Text = "\u{25B2}" -- up-pointing triangle = "ahead"
arrow.TextScaled = true
arrow.TextColor3 = HUD.ArrowColor
arrow.Visible = false
arrow.Parent = gui

-- "EXIT" caption under the gold arrow, so its glyph is never confused with the green KEY arrow
-- (CompassController) that points to keys during the hunt -- the two now read as distinct goals.
local arrowLabel = Instance.new("TextLabel")
arrowLabel.Name = "ExitArrowLabel"
arrowLabel.AnchorPoint = Vector2.new(0.5, 0) -- top-anchored just under the arrow's bottom edge
arrowLabel.Position = UDim2.new(0.5, 0, 1, -HUD.ArrowBottomOffset)
arrowLabel.Size = UDim2.fromOffset(140, HUD.ArrowLabelSize + 4)
arrowLabel.BackgroundTransparency = 1
arrowLabel.Font = Config.UI.SubheadingFont
arrowLabel.TextSize = HUD.ArrowLabelSize
arrowLabel.TextColor3 = HUD.ArrowColor
arrowLabel.TextStrokeColor3 = Config.UI.TextStrokeColor
arrowLabel.TextStrokeTransparency = Config.UI.TextStrokeTransparency
arrowLabel.Text = HUD.ArrowLabel
arrowLabel.Visible = false
arrowLabel.Parent = gui

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
winIcon.Font = Config.UI.HeadingFont
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
winText.Font = Config.UI.DisplayFont
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

-- Key-pickup SCREEN PULSE: a brief gold wash on every pickup, so a key grabbed mid-chase (when
-- your eyes are on the monster, not the pip row) still registers as progress. Render-only juice.
local pickupPulse = Instance.new("Frame")
pickupPulse.Name = "PickupPulse"
pickupPulse.Size = UDim2.fromScale(1, 1)
pickupPulse.BackgroundColor3 = HUD.PickupPulseColor
pickupPulse.BackgroundTransparency = 1
pickupPulse.ZIndex = 9
pickupPulse.Visible = false
pickupPulse.Parent = gui

local function playPickupPulse()
	pickupPulse.Visible = true
	pickupPulse.BackgroundTransparency = HUD.PickupPulseTransparency
	TweenService:Create(
		pickupPulse,
		TweenInfo.new(HUD.PickupPulseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
end

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

-- Transient feedback toasts (key pickup / locked door / hunt alerts / achievements) ---------
-- A FIFO STACK, not one reused label: in a busy co-op moment several events land together (a
-- teammate's key + a hunt alert + an achievement), and a single shared label silently clobbered
-- all but the last (a new message instantly overwrote the previous via a shared token). Each
-- showToast now spawns its OWN short-lived label that fades and removes itself after its hold
-- time; the container shows up to ToastStackMax at once, newest at the TOP (the canonical toast
-- spot), and evicts the oldest when a further one arrives. Render-only -- the HUD decides nothing.
local ToastStackMax = 3 -- most toasts on screen at once; a 4th evicts the oldest (a fixed render-only layout cap)
local toastFadeSeconds = 0.5 -- seconds each toast takes to fade out before it removes itself

local toastStack = Instance.new("Frame")
toastStack.Name = "ToastStack"
toastStack.AnchorPoint = Vector2.new(0.5, 0)
-- Top-anchored half a toast above ToastYScale so a LONE toast's centre still lands exactly where
-- the old single toast sat; extras then grow DOWNWARD, away from the key pips up top.
toastStack.Position = UDim2.new(0.5, 0, HUD.ToastYScale, -HUD.ToastHeight / 2)
toastStack.Size =
	UDim2.fromOffset(HUD.ToastWidth, HUD.ToastHeight * ToastStackMax + Config.UI.ChipCornerRadius * (ToastStackMax - 1))
toastStack.BackgroundTransparency = 1
toastStack.Parent = gui

local toastLayout = Instance.new("UIListLayout")
toastLayout.FillDirection = Enum.FillDirection.Vertical
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder -- newest gets the smallest order -> sits at the top
toastLayout.Padding = UDim.new(0, Config.UI.ChipCornerRadius) -- the standard small UI spacing unit, so stacked chips never touch
toastLayout.Parent = toastStack

-- One stacked toast label, styled exactly like the former single toast (panel + stroke fade IN
-- with the text -- hidden at rest, not a persistent box). Returned hidden; showToast reveals it.
local function makeToast()
	local label = Instance.new("TextLabel")
	label.Name = "Toast"
	label.Size = UDim2.fromOffset(HUD.ToastWidth, HUD.ToastHeight)
	label.BackgroundColor3 = Config.UI.PanelColor
	label.BackgroundTransparency = 1
	label.Font = Config.UI.SubheadingFont
	label.TextSize = HUD.ToastTextSize
	label.TextColor3 = Config.Feedback.ToastColor
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.Text = ""

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.UI.StrokeColor
	stroke.Transparency = 1 -- fades in/out with the panel
	stroke.Thickness = Config.UI.StrokeThickness
	stroke.Parent = label

	return label, stroke
end

local activeToasts = {} -- FIFO of live labels: [1] = oldest, [#] = newest
local toastOrder = 0 -- decremented per toast so a newer label SORTS ABOVE older ones (top of the stack)

local function removeToast(label)
	local i = table.find(activeToasts, label)
	if i then
		table.remove(activeToasts, i)
	end
	label:Destroy()
end

local function showToast(text, color, seconds)
	local label, stroke = makeToast()
	label.Text = text
	label.TextColor3 = color or Config.Feedback.ToastColor
	toastOrder -= 1
	label.LayoutOrder = toastOrder
	label.Parent = toastStack
	table.insert(activeToasts, label)

	-- Cap the stack: each arrival evicts the OLDEST, so the freshest events are never crowded out.
	while #activeToasts > ToastStackMax do
		removeToast(activeToasts[1])
	end

	-- Reveal: panel + stroke + text fade in together (matches the former single-toast look).
	label.TextTransparency = 0
	label.TextStrokeTransparency = Config.UI.TextStrokeTransparency
	label.BackgroundTransparency = Config.UI.PanelTransparency
	stroke.Transparency = Config.UI.StrokeTransparency

	-- Each label owns its OWN lifetime (no shared token): after its hold time it fades out and then
	-- removes itself, so concurrent toasts never overwrite one another.
	task.delay(seconds, function()
		if not label.Parent then
			return -- already evicted by a later toast hitting the cap
		end
		TweenService:Create(
			label,
			TweenInfo.new(toastFadeSeconds),
			{ TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }
		):Play()
		TweenService:Create(stroke, TweenInfo.new(toastFadeSeconds), { Transparency = 1 }):Play()
		task.delay(toastFadeSeconds, function()
			if label.Parent then
				removeToast(label)
			end
		end)
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
local huntingAlertRemote = Remotes.get(Remotes.Names.HuntingAlert)

-- Co-op situational awareness: a monster just started hunting a TEAMMATE. The hunted player
-- already feels it (chase sting/grade), so only show the alert to OTHERS -- "Steve is being HUNTED!"
huntingAlertRemote.OnClientEvent:Connect(function(huntedName)
	if not huntedName or huntedName == player.Name then
		return
	end
	showToast(
		string.format("%s %s", huntedName, Config.Feedback.HuntedSuffix),
		Config.Feedback.HuntedColor,
		Config.Feedback.HuntedToastSeconds
	)
end)

-- Achievement unlocked: a lifetime-stat milestone earned -> a gold toast "ACHIEVEMENT — NAME  (+N)".
local achievementRemote = Remotes.get(Remotes.Names.AchievementUnlocked)
achievementRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	local A = Config.Achievements
	showToast(
		string.format("%s — %s  (+%d)", A.ToastPrefix, data.name or "", data.reward or 0),
		Config.UI.WarnColor,
		A.ToastSeconds
	)
	playPickupPulse() -- a positive flash to match the milestone
end)

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

-- Optional gold BONUS key grabbed (team count rises): a brief gold toast. Read off the server-
-- mirrored BonusKeyCount attribute (no new remote) -- the coins themselves land at round end.
local lastBonusKeys = player:GetAttribute(Attributes.BonusKeyCount) or 0
player:GetAttributeChangedSignal(Attributes.BonusKeyCount):Connect(function()
	local n = player:GetAttribute(Attributes.BonusKeyCount) or 0
	if n > lastBonusKeys then
		showToast("BONUS KEY!", HUD.ArrowColor, Config.Feedback.KeyToastSeconds)
		playPickupPulse()
	end
	lastBonusKeys = n
end)

keyCollectedRemote.OnClientEvent:Connect(function(count, pickerName)
	count = count or keyCount
	-- A teammate's pickup is ATTRIBUTED ("Steve got a key 2/3"); your own stays the plain "KEY n/3".
	local text
	if pickerName and pickerName ~= player.Name then
		text = string.format("%s %s  %d/%d", pickerName, Config.Feedback.KeyBySuffix, count, requiredKeys)
	else
		text = string.format("KEY %d/%d", count, requiredKeys)
	end
	showToast(text, nil, Config.Feedback.KeyToastSeconds)
	popPip(count) -- the pip that just filled (index == the new team total)
	playPickupPulse() -- a screen-wide flash so a mid-chase pickup is never missed
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
	-- Show the REMAINING delta ("NEED 1 MORE KEY") rather than the raw target, so a player at the
	-- locked door instantly knows how much further to go (with correct singular/plural).
	local missing = math.max(requiredKeys - keyCount, 0)
	local needText = if missing == 1 then "NEED 1 MORE KEY" else string.format("NEED %d MORE KEYS", missing)
	showToast(
		string.format("%s — %s", Config.Feedback.LockedTextPrefix, needText),
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
	arrowLabel.Visible = showArrow
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
