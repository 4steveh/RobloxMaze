--!nonstrict
-- FlickerController.client.luau
-- Client-only atmosphere: every Light tagged FlickerLight flickers like a failing fluorescent --
-- brightness oscillates around its captured base value with the odd brief stutter, and the fixture's
-- emissive PANEL (and any light-shaft Beam) dims in lockstep so the visible tube and its pool fail
-- together. Purely a local visual effect (uncontested, affects no game state and no other player ->
-- allowed client-side per CLAUDE.md). Renders only; tunables come from Config.Lighting.
--
-- Accessibility: this used to be a deep, frequent, blackout-heavy strobe across ~24 fixtures, which
-- read as a "flashing walls" glitch. It now (a) flickers gentler + rarer (Config.Lighting), (b) honours
-- the REDUCE-FLASHING pref -- a shallow STEADY shimmer with NO blackouts -- and (c) scales the flicker
-- DEPTH by the FX-intensity pref (0 = lights hold perfectly steady).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Attributes = require(ReplicatedStorage.Attributes)

local L = Config.Lighting
local player = Players.LocalPlayer

-- Comfort prefs (client-local attributes the SettingsController writes), cached + refreshed on change
-- so we never read attributes per-frame. ReduceFlashing => steady shimmer, no cuts; FxIntensity scales
-- how DEEP the flicker dips (1 = full character, 0 = lights stay put).
local reduceFlashing = Config.Settings.DefaultReduceFlashing
local fxIntensity = Config.Settings.DefaultFxIntensity
local function refreshPrefs()
	local rf = player:GetAttribute(Attributes.SettingReduceFlashing)
	reduceFlashing = if typeof(rf) == "boolean" then rf else Config.Settings.DefaultReduceFlashing
	local fx = player:GetAttribute(Attributes.SettingFxIntensity)
	fxIntensity = if typeof(fx) == "number" then math.clamp(fx, 0, 1) else Config.Settings.DefaultFxIntensity
end
refreshPrefs()
player:GetAttributeChangedSignal(Attributes.SettingReduceFlashing):Connect(refreshPrefs)
player:GetAttributeChangedSignal(Attributes.SettingFxIntensity):Connect(refreshPrefs)

-- Per-light state: captured base brightness, a random phase + speed jitter (so fixtures don't flicker
-- in lockstep), a "blacked out until" timestamp, and the sibling visuals it drives (the emissive ceiling
-- Panel + any ShaftBeam) so the glow and its pool stutter together.
local lights = {}

local function track(inst)
	if inst:IsA("Light") then
		local parent = inst.Parent
		local panel = (parent and parent:IsA("BasePart") and parent.Material == Enum.Material.Neon) and parent or nil
		lights[inst] = {
			base = inst.Brightness,
			phase = math.random() * math.pi * 2,
			speed = L.FlickerSpeed * (0.8 + math.random() * 0.4),
			offUntil = 0,
			-- The fixture's light-shaft Beam (if any) flickers in lockstep with the light.
			beam = parent and parent:FindFirstChild("ShaftBeam"),
			-- The fixture's emissive PANEL (the maze ceiling tubes): fade it toward clear as the light dies.
			panel = panel,
		}
	end
end

local function untrack(inst)
	lights[inst] = nil
end

-- Fires for fixtures present now and any tagged later; cleanup is unneeded (the controller lives for
-- the whole client session), so the returned disconnector is intentionally ignored.
Discovery.observe(Tags.FlickerLight, track, untrack)

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	for light, s in lights do
		if not light.Parent then
			continue
		end

		-- scale: a 0..1 fraction of the fixture's base brightness for this frame.
		local scale
		if reduceFlashing then
			-- Photosensitivity-safe: a shallow STEADY shimmer between ReduceFlashingMinScale and 1.0,
			-- no random blackouts (and FxIntensity still flattens it toward steady).
			local osc = 0.5 + 0.5 * math.sin(clock * s.speed + s.phase)
			local depth = (1 - L.ReduceFlashingMinScale) * fxIntensity
			scale = 1 - depth * osc
		elseif clock < s.offUntil then
			scale = 0
		elseif math.random() < L.FlickerOffChance then
			s.offUntil = clock + L.FlickerOffTime
			scale = 0
		else
			local osc = 0.5 + 0.5 * math.sin(clock * s.speed + s.phase)
			local flick = L.FlickerMinScale + (1 - L.FlickerMinScale) * osc
			flick = math.clamp(flick * (0.94 + math.random() * 0.12), 0, 1.15)
			-- FxIntensity lerps between perfectly steady (1.0) and the full flicker.
			scale = 1 - (1 - flick) * fxIntensity
		end

		light.Brightness = s.base * scale

		-- Sync the emissive panel: fully lit at scale 1, fading toward (but never fully) clear at a cut,
		-- so the visible tube tracks its pool instead of staying a constant-bright slab over a dark floor.
		if s.panel then
			s.panel.Transparency = L.PanelDimMax * (1 - scale)
		end

		-- Flicker the fixture's light shaft with it: hide it on a blackout, otherwise fade its opacity
		-- with the light's current brightness.
		if s.beam then
			if scale <= 0 then
				s.beam.Enabled = false
			else
				s.beam.Enabled = true
				s.beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1 - 0.45 * scale),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		end
	end
end)
