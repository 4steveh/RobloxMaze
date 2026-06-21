--!nonstrict
-- SprintFXController.client.luau
-- Sprint FOV kick: the camera widens as the player actually sprints, so a server-
-- authoritative sprint (SprintService owns WalkSpeed via the SprintIntent remote -- a
-- network round-trip away) FEELS immediate and fast. It reads the character's REAL
-- horizontal ground speed, so the kick scales with how fast you are truly moving and
-- never lies when you're out of stamina or wedged on a wall. Pure client cosmetic --
-- uncontested, render-only, nothing else depends on it: the FlickerController-class
-- exception CLAUDE.md permits.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local P = Config.Player
local player = Players.LocalPlayer

-- The kick rides ON TOP of whatever the base camera FOV is, captured on the first frame
-- the camera exists (before any kick, which starts at 0) so we restore to it exactly.
local baseFov = nil

RunService.RenderStepped:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if baseFov == nil then
		baseFov = camera.FieldOfView
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	-- Horizontal ground speed only (vertical ignored, so jumping/falling never kicks FOV).
	-- Ramps from 0 at walk speed to 1 at sprint speed.
	local kickFraction = 0
	if hrp then
		local v = hrp.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		kickFraction = math.clamp((speed - P.WalkSpeed) / math.max(P.SprintSpeed - P.WalkSpeed, 1), 0, 1)
	end

	local target = baseFov + P.SprintFovKick * kickFraction
	local alpha = math.clamp(P.SprintFovSmoothing * dt, 0, 1)
	camera.FieldOfView = camera.FieldOfView + (target - camera.FieldOfView) * alpha
end)
