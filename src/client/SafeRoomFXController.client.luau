--!nonstrict
-- SafeRoomFXController.client.luau
-- The relief counterpart to ChaseFXController. A safe room is the only sanctuary, but entering one
-- was nearly invisible (just a reverb swap in AmbientController). This gives crossing the threshold a
-- FELT arrival: a warm grade BLOOMS in then settles to a gentle steady warmth while you're inside, a
-- one-shot "SAFE" cue appears, and a soft warm screen-edge glow is held -- all fading on leaving.
--
-- Render-only and exploit-safe: driven purely by the server-authoritative SafeRoom enter/leave
-- remotes (the client never detects occupancy itself, per CLAUDE.md). It owns its OWN ColorCorrection,
-- so the place's static grade and the ChaseGrade are untouched. The FlickerController-class cosmetic.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local SR = Config.SafeRoomFX
local WHITE = Color3.new(1, 1, 1)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Dedicated grade (composes over the place grade + the ChaseGrade; never touches them).
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "SafeGrade"
cc.Enabled = true
cc.Parent = Lighting

-- Warm edge glow: four bands, opaque-at-edge fading to clear toward centre (the inverse-mood twin of
-- the chase vignette). Held subtly while inside so the sanctuary reads even with the grade settled low.
local gui = Instance.new("ScreenGui")
gui.Name = "SafeRoomFX"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 49 -- just under the chase vignette (50)
gui.Parent = playerGui

local bands = {}
local function makeBand(pos: UDim2, size: UDim2, gradientRotation: number)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = SR.GlowColor
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundTransparency = 1
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = gradientRotation
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), -- opaque at the edge
		NumberSequenceKeypoint.new(1, 1), -- clear toward the centre
	})
	g.Parent = f
	table.insert(bands, f)
end
local th = SR.GlowThickness
makeBand(UDim2.fromScale(0, 0), UDim2.fromScale(1, th), 90) -- top
makeBand(UDim2.fromScale(0, 1 - th), UDim2.fromScale(1, th), 270) -- bottom
makeBand(UDim2.fromScale(0, 0), UDim2.fromScale(th, 1), 0) -- left
makeBand(UDim2.fromScale(1 - th, 0), UDim2.fromScale(th, 1), 180) -- right

-- One-shot "SAFE" toast (its own label, independent of the HUD's toast).
local toast = Instance.new("TextLabel")
toast.Name = "SafeToast"
toast.AnchorPoint = Vector2.new(0.5, 0.5)
toast.Position = UDim2.fromScale(0.5, SR.ToastYScale)
toast.Size = UDim2.fromOffset(280, 40)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamBold
toast.TextSize = 28
toast.Text = SR.ToastText
toast.TextColor3 = SR.ToastColor
toast.TextStrokeTransparency = 0.5
toast.TextTransparency = 1
toast.Parent = gui

local toastToken = 0
local function showSafeToast()
	toastToken += 1
	local mine = toastToken
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.5
	task.delay(SR.ToastSeconds, function()
		if mine == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- State: `warmth` is the eased steady "inside" amount (0..1); `bloom` is the transient entry
-- overshoot that decays to 0 (the brightness/saturation lift -- the "lights come up" exhale).
local inside = false
local warmth = 0
local bloom = 0

Remotes.get(Remotes.Names.SafeRoomEntered).OnClientEvent:Connect(function()
	inside = true
	bloom = 1
	showSafeToast()
end)
Remotes.get(Remotes.Names.SafeRoomLeft).OnClientEvent:Connect(function()
	inside = false
end)

RunService.RenderStepped:Connect(function(dt)
	local easeTime = if inside then SR.BloomSeconds else SR.FadeSeconds
	warmth += ((if inside then 1 else 0) - warmth) * math.min(dt / math.max(easeTime, 1e-3), 1)
	bloom = math.max(0, bloom - dt / math.max(SR.SettleSeconds, 1e-3))

	-- Warm tint settles to HoldTint while inside; the bloom adds the extra tint + brightness/saturation
	-- lift at the entry peak, then decays. On leave, warmth eases to 0 -> neutral.
	local tintWeight = math.clamp(warmth * SR.HoldTint + bloom * (SR.BloomTint - SR.HoldTint), 0, 1)
	cc.TintColor = WHITE:Lerp(SR.TintColor, tintWeight)
	cc.Brightness = SR.Brightness * bloom
	cc.Saturation = SR.Saturation * bloom

	local glowAlpha = 1 - warmth * (1 - SR.GlowHoldTransparency)
	for _, band in bands do
		band.BackgroundTransparency = glowAlpha
	end
end)
