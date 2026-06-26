--!nonstrict
-- JumpscareController.client.luau
-- The scare payoff for MonsterCaught: a scream (ducking every other bus), a full
-- ViewportFrame close-up of the actual monster mesh lunging at the screen with a
-- violent shake, a red flash punch, and the "CAUGHT!" headline + respawn countdown.
-- Renders only; the catch is server-authoritative. The mesh is cloned from the live
-- (replicated) rig, so no client-side asset copy is needed.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local AudioGroups = require(ReplicatedStorage.AudioGroups)
local Attributes = require(ReplicatedStorage.Attributes)

local player = Players.LocalPlayer
local caughtRemote = Remotes.get(Remotes.Names.MonsterCaught)

-- Personal comfort/accessibility prefs (LocalPlayer attributes from SettingsController; render-only,
-- client-local), cached + refreshed on change. FxIntensity scales the red flash + the lunge shake;
-- ReduceFlashing swaps the hard flash for a gentle steady dim (photosensitivity). The scream is left
-- to the global master-volume setting, so audio is untouched here.
local fxIntensity = Config.Settings.DefaultFxIntensity
local reduceFlashing = Config.Settings.DefaultReduceFlashing
local function refreshPrefs()
	local fx = player:GetAttribute(Attributes.SettingFxIntensity)
	fxIntensity = if typeof(fx) == "number" then fx else Config.Settings.DefaultFxIntensity
	local rf = player:GetAttribute(Attributes.SettingReduceFlashing)
	reduceFlashing = if typeof(rf) == "boolean" then rf else Config.Settings.DefaultReduceFlashing
end
refreshPrefs()
player:GetAttributeChangedSignal(Attributes.SettingFxIntensity):Connect(refreshPrefs)
player:GetAttributeChangedSignal(Attributes.SettingReduceFlashing):Connect(refreshPrefs)

local gui = Instance.new("ScreenGui")
gui.Name = "JumpscareGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

-- Monster face viewport (the lunge) -------------------------------------------------
local viewport = Instance.new("ViewportFrame")
viewport.Name = "ScareViewport"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundColor3 = Color3.fromRGB(8, 0, 0)
viewport.BackgroundTransparency = 0
viewport.Ambient = Color3.fromRGB(90, 25, 25)
viewport.LightColor = Color3.fromRGB(255, 180, 175)
viewport.LightDirection = Vector3.new(0, -0.25, -1)
viewport.Visible = false
viewport.Parent = gui

local vpCamera = Instance.new("Camera")
vpCamera.Parent = viewport
viewport.CurrentCamera = vpCamera

-- Red flash punch over the face -----------------------------------------------------
local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
flash.BackgroundTransparency = 1
flash.Visible = false
flash.Parent = gui

-- "CAUGHT!" headline + respawn countdown -------------------------------------------
local caughtLabel = Instance.new("TextLabel")
caughtLabel.Name = "Caught"
caughtLabel.AnchorPoint = Vector2.new(0.5, 0.5)
caughtLabel.Position = UDim2.fromScale(0.5, 0.16)
caughtLabel.Size = UDim2.fromOffset(560, 90)
caughtLabel.BackgroundTransparency = 1
caughtLabel.Font = Config.UI.DisplayFont
caughtLabel.TextSize = 76
caughtLabel.TextColor3 = Config.Feedback.CaughtColor
caughtLabel.TextStrokeTransparency = Config.UI.TextStrokeTransparency
caughtLabel.Text = Config.Feedback.CaughtText
caughtLabel.Visible = false
caughtLabel.Parent = gui

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Name = "Countdown"
countdownLabel.AnchorPoint = Vector2.new(0.5, 1)
countdownLabel.Position = UDim2.fromScale(0.5, 0.9)
countdownLabel.Size = UDim2.fromOffset(420, 28)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Font = Config.UI.HeadingFont
countdownLabel.TextSize = 22
countdownLabel.TextColor3 = Config.UI.TextColor
countdownLabel.TextStrokeTransparency = Config.UI.TextStrokeTransparency
countdownLabel.Text = ""
countdownLabel.Visible = false
countdownLabel.Parent = gui

-- Scream (ducks every other bus while it plays) ------------------------------------
local scream = Instance.new("Sound")
scream.Name = "Jumpscare"
scream.SoundId = Config.Audio.Stingers.JumpscareId
scream.Volume = Config.Audio.Stingers.JumpscareVolume
scream.SoundGroup = AudioGroups.get("Master")
scream.Parent = SoundService

-- Find the rig to show in the scare: prefer the SPECIES that actually caught the player (so a
-- bunny catch shows the bunny, a monkey catch shows the monkey), falling back to any built rig.
local function findMonsterRig(species)
	local monsters = Workspace:FindFirstChild(WorldFolders.Monsters)
	if not monsters then
		return nil
	end
	local fallback = nil
	for _, rig in monsters:GetChildren() do
		if rig:FindFirstChild("Body") then
			fallback = fallback or rig
			if species and rig:GetAttribute(Attributes.MonsterSpecies) == species then
				return rig
			end
		end
	end
	return fallback
end

local function populateViewport(species)
	local old = viewport:FindFirstChild("ScareModel")
	if old then
		old:Destroy()
	end
	local rig = findMonsterRig(species)
	if not rig then
		return false
	end
	-- The rigs are MULTI-PART now: centre on the cosmetic head (the face) and clone every
	-- visible cosmetic part, so the whole creature lunges at the camera (not just a torso).
	local head = rig:FindFirstChild("CHead") or rig:FindFirstChild("Body")
	if not (head and head:IsA("BasePart")) then
		return false
	end
	-- Capture the species eye-glow colour BEFORE the clone loop strips it: it's what makes
	-- the climax unmistakably red-bunny vs yellow-monkey and it dominates the viewport light.
	local liveGlow = rig:FindFirstChild("EyeGlow", true)
	local glowColor = (liveGlow and liveGlow:IsA("PointLight") and liveGlow.Color) or Color3.fromRGB(255, 90, 80)

	local headCF = head.CFrame
	local container = Instance.new("Model")
	container.Name = "ScareModel"
	local clonedHead = nil
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "HumanoidRootPart" then
			local c = part:Clone()
			c:ClearAllChildren()
			c.Anchored = true
			c.CanCollide = false
			c.CFrame = headCF:ToObjectSpace(part.CFrame) -- head at the origin, facing -Z
			c.Parent = container
			if part == head then
				clonedHead = c
			end
		end
	end

	-- Restore a punchy eye-glow on the cloned face (ClearAllChildren stripped the original),
	-- and bias the viewport lighting toward that hue so the glow -- not flat fill -- reads.
	local glowHost = clonedHead or container:FindFirstChildWhichIsA("BasePart")
	if glowHost then
		local glow = Instance.new("PointLight")
		glow.Color = glowColor
		glow.Brightness = 6
		glow.Range = 12
		glow.Parent = glowHost
	end
	viewport.LightColor = Color3.new(1, 1, 1):Lerp(glowColor, 0.5)
	viewport.Ambient = Color3.fromRGB(20, 12, 12)

	container.Parent = viewport
	return true
end

local scareToken = 0

-- Payload `downed`: true = grabbed into the revivable DOWNED state (the DownedController
-- HUD takes over — show only a SHORT scare, no "CAUGHT!"/countdown); false/nil = killed
-- (the classic CAUGHT headline + respawn countdown).
caughtRemote.OnClientEvent:Connect(function(downed, species)
	scareToken += 1
	local mine = scareToken
	local killed = not downed
	-- How long the scare holds the screen: the full respawn window if killed, a short
	-- punch if downed (so the bleedout/revive HUD is readable underneath).
	local total = if killed then Config.Respawn.RespawnDelay else 1.3

	-- Audio: scream over a hard duck of every bed.
	scream:Play()
	for _, bus in { "Ambient", "Monster", "Music", "SFX" } do
		AudioGroups.duck(bus, 0.0, total)
	end

	local hasFace = populateViewport(species)
	viewport.Visible = hasFace
	flash.Visible = true
	-- The red overlay: the FX-strength pref scales how strong it reads (0 == none). ReduceFlashing
	-- holds a gentle STEADY red (no strobe) for the whole window; otherwise it's a hard punch.
	flash.BackgroundTransparency = if reduceFlashing then 1 - 0.18 * fxIntensity else 1 - 0.95 * fxIntensity
	caughtLabel.Visible = killed
	countdownLabel.Visible = killed

	-- Flash punch out fast (reveals the face) -- skipped under ReduceFlashing, where the gentle red holds.
	if not reduceFlashing then
		TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	end

	-- Lunge + shake for the first ~0.55s, then hold the face for the rest of the window.
	task.spawn(function()
		local faceY = 0.2 -- the cloned creature is centred on its head at the viewport origin
		local elapsed = 0
		local lunge = 0.55
		while elapsed < lunge and mine == scareToken do
			local dt = RunService.RenderStepped:Wait()
			elapsed += dt
			local t = math.clamp(elapsed / lunge, 0, 1)
			local dist = 3.4 - 1.8 * t -- dolly in
			local shake = (1 - t) * 0.28 * fxIntensity
			local jx = (math.random() - 0.5) * shake
			local jy = (math.random() - 0.5) * shake
			vpCamera.CFrame = CFrame.new(Vector3.new(jx, faceY + jy, -dist), Vector3.new(0, faceY, 0))
		end
		if mine == scareToken then
			vpCamera.CFrame = CFrame.new(Vector3.new(0, faceY, -1.6), Vector3.new(0, faceY, 0))
		end
	end)

	-- Hold for the window (killed: a respawn countdown; downed: a short scare hold), then clear
	-- so the DownedController bleedout/revive HUD is readable underneath.
	task.spawn(function()
		local remaining = total
		while remaining > 0 and mine == scareToken do
			if killed then
				countdownLabel.Text = string.format("Respawning in %.0f...", math.ceil(remaining))
			end
			task.wait(0.1)
			remaining -= 0.1
		end
		if mine == scareToken then
			viewport.Visible = false
			flash.Visible = false
			caughtLabel.Visible = false
			countdownLabel.Visible = false
		end
	end)
end)
