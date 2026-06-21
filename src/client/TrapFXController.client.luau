--!nonstrict
-- TrapFXController.client.luau
-- Renders trap telegraph + fire FX off the server's TrapTriggered remote. The static
-- red-arrow telegraph is placed geometry (always visible -- the fair "watch the floor"
-- tell); this adds the WIND-UP pulse (the arrow + glow flash bright red + a click, the
-- reaction window) and the FIRE effect (a dart streaks along the trap's facing + a thunk
-- + impact flash). Render-only; the trap arming/firing/kill is all server-authoritative.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local AudioGroups = require(ReplicatedStorage.AudioGroups)
local Discovery = require(ReplicatedStorage.Discovery)
local Tags = require(ReplicatedStorage.Tags)

local C = Config.Traps
local trapRemote = Remotes.get(Remotes.Names.TrapTriggered)
local sfxBus = AudioGroups.get("SFX")

-- Continuous gentle "danger breathing" of each trap's glow so a trap reads as a LIVE HAZARD,
-- not floor decoration. A trap mid wind-up/fire is in `flashing` and the pulse leaves its glow
-- alone (the flash owns the brightness then).
local traps = {}
Discovery.observe(Tags.Trap, function(part)
	if part:IsA("BasePart") then
		traps[part] = true
	end
end, function(part)
	traps[part] = nil
end)
local flashing = {} -- [part] = true while a wind-up / fire flash owns the glow
RunService.Heartbeat:Connect(function()
	local wave = 0.5 + 0.5 * math.sin(os.clock() * C.GlowPulseHz * math.pi * 2)
	for part in traps do
		if part.Parent and not flashing[part] then
			local glow = part:FindFirstChild("TrapGlow")
			if glow then
				glow.Brightness = C.GlowBrightness * (1 - C.GlowPulseDepth * wave)
			end
		end
	end
end)

-- Recolour the trap's arrow parts + glow (used for the wind-up pulse and fire flash).
local function setTrapColor(part, color, glowMul)
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, 5) == "Arrow" then
			d.Color = color
		elseif d:IsA("PointLight") then
			d.Color = color
			d.Brightness = C.GlowBrightness * glowMul
		end
	end
end

local function play(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.SoundGroup = sfxBus
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 3)
end

local function windup(part)
	play(C.ClickId, 0.5)
	flashing[part] = true
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < C.WindupSeconds and part.Parent do
			local pulse = 0.5 + 0.5 * math.sin((os.clock() - t0) * 32)
			setTrapColor(part, C.ArrowColor:Lerp(C.ArrowFlashColor, pulse), 1 + 4 * pulse)
			RunService.RenderStepped:Wait()
		end
		if part.Parent then
			setTrapColor(part, C.ArrowColor, 1)
		end
		flashing[part] = nil -- hand the glow back to the breathing pulse
	end)
end

local function fire(part)
	play(C.FireId, C.FireVolume)
	flashing[part] = true
	setTrapColor(part, C.ArrowFlashColor, 5)
	task.delay(0.15, function()
		if part.Parent then
			setTrapColor(part, C.ArrowColor, 1)
		end
		flashing[part] = nil
	end)
	-- A dart streaks across the corridor along the trap's facing (-Z).
	local dir = part.CFrame.LookVector
	local origin = part.Position + Vector3.new(0, 1.6, 0) - dir * 4
	local dart = Instance.new("Part")
	dart.Anchored = true
	dart.CanCollide = false
	dart.CanQuery = false
	dart.Size = Vector3.new(0.2, 0.2, C.DartLength)
	dart.Color = C.DartColor
	dart.Material = Enum.Material.Neon
	dart.CFrame = CFrame.lookAt(origin, origin + dir)
	dart.Parent = Workspace
	Debris:AddItem(dart, 0.6)
	task.spawn(function()
		local travelled = 0
		while travelled < 22 and dart.Parent do
			local dt = RunService.RenderStepped:Wait()
			local step = C.DartSpeed * dt
			dart.CFrame = dart.CFrame + dir * step
			travelled += step
		end
	end)
end

trapRemote.OnClientEvent:Connect(function(part, phase)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part.Parent then
		return
	end
	if phase == "windup" then
		windup(part)
	elseif phase == "fire" then
		fire(part)
	end
end)
