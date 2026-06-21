--!nonstrict
-- ChaseFXController.client.luau
-- The hunt as a VISUAL event. Render-only and exploit-safe: each frame it finds the
-- nearest monster actively hunting THIS player (rig `State` == Chase/Investigate, or a
-- softer dread when merely Alert) and how close it is -- all from REPLICATED rig State +
-- position -- then drives a DEDICATED ColorCorrection (desaturate + red wash), a closing
-- vignette, a heartbeat pulse, and a flare of that monster's eye-glow. Its own
-- ColorCorrection instance, so the static place grade is never touched. Decides nothing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Enums = require(ReplicatedStorage.Enums)
local Attributes = require(ReplicatedStorage.Attributes)
local WorldFolders = require(ReplicatedStorage.WorldFolders)

local C = Config.Chase
local STATE = Attributes.MonsterState
local player = Players.LocalPlayer

-- Dedicated grade (composes over the place's static ColorGrading/ColorCorrection).
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "ChaseGrade"
cc.Enabled = true
cc.Parent = Lighting

local function setGrade(intensity: number)
	cc.Saturation = C.Saturation * intensity
	cc.Contrast = C.Contrast * intensity
	cc.Brightness = C.BrightnessDrop * intensity
	cc.TintColor = Color3.new(1, 1, 1):Lerp(C.TintColor, intensity)
end
setGrade(0)

-- Vignette: four edge bands, each opaque at the screen edge and fading to clear toward
-- the centre (UIGradient transparency), the whole set faded in by threat intensity.
local gui = Instance.new("ScreenGui")
gui.Name = "ChaseVignette"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local bands = {}
local function makeBand(pos: UDim2, size: UDim2, gradientRotation: number)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = C.VignetteColor
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundTransparency = 1
	f.ZIndex = 1
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
local th = C.VignetteThickness
makeBand(UDim2.fromScale(0, 0), UDim2.fromScale(1, th), 90) -- top (opaque at top edge)
makeBand(UDim2.fromScale(0, 1 - th), UDim2.fromScale(1, th), 270) -- bottom
makeBand(UDim2.fromScale(0, 0), UDim2.fromScale(th, 1), 0) -- left
makeBand(UDim2.fromScale(1 - th, 0), UDim2.fromScale(th, 1), 180) -- right

-- Cache each eye-glow's base so we can restore it when the monster stops hunting.
local glowBase = {} -- [PointLight] = { b = Brightness, r = Range }
local glowByRig = {} -- [rig] = PointLight, cached so we don't recurse the rig every frame
local function glowOf(rig)
	local g = glowByRig[rig]
	if not (g and g.Parent) then
		g = rig:FindFirstChild("EyeGlow", true)
		glowByRig[rig] = g
	end
	if g and g:IsA("PointLight") then
		if not glowBase[g] then
			glowBase[g] = { b = g.Brightness, r = g.Range }
		end
		return g
	end
	return nil
end

local current = 0
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)

	local target = 0
	local nearestAggro, nearestDist, nearestProx = nil, math.huge, 0
	if hrp and monsters then
		local span = C.ThreatStartDistance - C.ThreatMaxDistance
		for _, rig in monsters:GetChildren() do
			local rRoot = rig:FindFirstChild("HumanoidRootPart")
			local st = rig:GetAttribute(STATE)
			-- Default any monster's glow back to base; the active hunter is flared below.
			local g = glowOf(rig)
			if g then
				g.Brightness = glowBase[g].b
				g.Range = glowBase[g].r
			end
			if rRoot then
				local aggressive = st == Enums.MonsterState.Chase or st == Enums.MonsterState.Investigate
				local alert = st == Enums.MonsterState.Alert
				if aggressive or alert then
					local d = (rRoot.Position - hrp.Position).Magnitude
					local prox = math.clamp((C.ThreatStartDistance - d) / span, 0, 1)
					local t = if aggressive then prox else prox * C.AlertScale
					if t > target then
						target = t
					end
					if aggressive and d < nearestDist then
						nearestDist, nearestAggro, nearestProx = d, rig, prox
					end
				end
			end
		end
	end

	-- Smoothly approach the target, then pulse with the threat (a visual heartbeat).
	current += (target - current) * math.min(dt * C.FadeRate, 1)
	local pulse = if current > 0.01
		then 1 + math.sin(os.clock() * math.pi * 2 * C.PulseHz) * C.PulseAmp * current
		else 1
	local intensity = math.clamp(current * pulse, 0, 1)

	setGrade(intensity)
	local bandAlpha = 1 - intensity * (1 - C.VignetteMinTransparency)
	for _, f in bands do
		f.BackgroundTransparency = bandAlpha
	end

	-- Flare the nearest hunting monster's eyes by its proximity.
	if nearestAggro then
		local g = glowOf(nearestAggro)
		if g then
			g.Brightness = glowBase[g].b + (C.EyeGlowBrightness - glowBase[g].b) * nearestProx
			g.Range = glowBase[g].r + (C.EyeGlowRange - glowBase[g].r) * nearestProx
		end
	end
end)
