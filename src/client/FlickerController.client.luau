--!nonstrict
-- FlickerController.client.luau
-- Client-only atmosphere: every Light tagged FlickerLight flickers like a failing
-- fluorescent -- brightness oscillates around its captured base value with the odd
-- brief blackout. Purely a local visual effect (uncontested, affects no game state
-- and no other player -> allowed client-side per CLAUDE.md). Renders only; the
-- flicker tunables come from Config.Lighting.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)

-- Per-light state: captured base brightness, a random phase + speed jitter (so
-- fixtures don't flicker in lockstep), and a "blacked out until" timestamp.
local lights = {}

local function track(inst)
	if inst:IsA("Light") then
		lights[inst] = {
			base = inst.Brightness,
			phase = math.random() * math.pi * 2,
			speed = Config.Lighting.FlickerSpeed * (0.8 + math.random() * 0.4),
			offUntil = 0,
		}
	end
end

local function untrack(inst)
	lights[inst] = nil
end

-- Fires for fixtures present now and any tagged later; cleanup is unneeded (the
-- controller lives for the whole client session), so the returned disconnector is
-- intentionally ignored.
Discovery.observe(Tags.FlickerLight, track, untrack)

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	for light, s in lights do
		if not light.Parent then
			continue
		end
		if clock < s.offUntil then
			light.Brightness = 0
		elseif math.random() < Config.Lighting.FlickerOffChance then
			s.offUntil = clock + Config.Lighting.FlickerOffTime
			light.Brightness = 0
		else
			local osc = 0.5 + 0.5 * math.sin(clock * s.speed + s.phase)
			local scale = Config.Lighting.FlickerMinScale + (1 - Config.Lighting.FlickerMinScale) * osc
			scale = math.clamp(scale * (0.92 + math.random() * 0.16), 0, 1.2)
			light.Brightness = s.base * scale
		end
	end
end)
