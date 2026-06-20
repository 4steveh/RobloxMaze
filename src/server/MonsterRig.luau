--!nonstrict
-- MonsterRig.luau
-- Builds a monster rig for ANY species from its resolved Config slice. The PHYSICAL
-- contract is identical across species (so MonsterService's mover/FSM/catch code is
-- species-agnostic): an invisible `HumanoidRootPart` collision box (`BodySize`), an
-- invisible `Head` (a Humanoid needs one), a `Humanoid` (RequiresNeck off, explicit
-- HipHeight, AutoRotate), and `SetNetworkOwner(nil)` so server MoveTo is honoured.
--
-- The VISIBLE body is one of two shapes, both animated by the client MonsterAnimController
-- writing cosmetic `Motor6D.Transform` (CanCollide/CanQuery/CanTouch off + Massless, so
-- it never touches collision / LoS rays / Humanoid balance):
--   * a single mesh `Body` on a `BodyJoint` (the bunny -- the whole mesh hops), OR
--   * an ARTICULATED primitive skeleton when no mesh asset exists (the monkey -- a
--     hunched primate whose limbs actually step): torso ("Body") + CHead + ArmL/ArmR +
--     LegL/LegR + Tail, each on its own Motor6D the gait recipe drives by name.
-- World mutation only -- no AI here (MonsterService owns decisions + the State attribute).

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Attributes)

local MonsterRig = {}

-- A cosmetic segment: out of collision/queries/balance, ready to be Motor6D-animated.
local function cosmeticPart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	return p
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	return m
end

-- Single rigid mesh body on one BodyJoint (the bunny). The whole mesh is animated.
local function buildMeshBody(rig: Model, root: BasePart, source: BasePart, cfg)
	local body = source:Clone()
	body.Name = "Body"
	body.Anchored = false
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Massless = true
	body.Parent = rig
	joint(
		"BodyJoint",
		root,
		body,
		CFrame.new(0, cfg.ModelYOffset, 0) * CFrame.Angles(0, math.rad(cfg.ModelFaceYaw), 0),
		CFrame.new()
	)
	return body -- the eye-glow host
end

-- Articulated primitive primate (the monkey). A hunched knuckle-walker: torso "Body",
-- a forward-jutting head, long ground-reaching arms, bent legs, and a tail -- each on a
-- Motor6D named for the gait recipe. Rest pose (Transform identity) is the standing
-- crouch baked into the C0/C1; the gait adds the swing/bob on top. (Segment geometry is
-- rig-construction detail, like the existing invisible Head size -- gait TUNABLES live in
-- Config.Monster.Anim.Monkey.)
local function buildPrimate(rig: Model, root: BasePart, cfg): BasePart
	local dark = cfg.BodyColor
	local rad = math.rad

	-- Torso (the animatable trunk). Slight forward hunch baked into the BodyJoint rest.
	local torso = cosmeticPart("Body", Vector3.new(1.7, 1.5, 2.3), dark)
	torso.Parent = rig
	joint("BodyJoint", root, torso, CFrame.new(0, cfg.ModelYOffset, 0) * CFrame.Angles(rad(12), 0, 0), CFrame.new())

	-- Head, jutting forward and a little down (hosts the eye-glow).
	local head = cosmeticPart("CHead", Vector3.new(1.2, 1.1, 1.2), dark)
	head.Shape = Enum.PartType.Ball
	head.Parent = rig
	joint("CHead", torso, head, CFrame.new(0, 0.45, -1.45), CFrame.new())
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = cfg.EyeGlowColor
	glow.Brightness = cfg.EyeGlowBrightness
	glow.Range = cfg.EyeGlowRange
	glow.Parent = head

	-- A limb segment pivoting at one end: C0 places the joint on the torso (with a rest
	-- angle), C1 puts the pivot at the limb's TOP so it swings from there (not its centre).
	local function limb(name: string, size: Vector3, c0: CFrame, pivotFromCentre: number)
		local part = cosmeticPart(name, size, dark)
		part.Parent = rig
		joint(name, torso, part, c0, CFrame.new(0, pivotFromCentre, 0))
	end

	-- Long arms reaching toward the ground (forward rest angle = the knuckle-reach).
	local armSize = Vector3.new(0.5, 2.2, 0.5)
	limb("ArmL", armSize, CFrame.new(-0.85, 0.35, -0.95) * CFrame.Angles(rad(38), 0, 0), 1.05)
	limb("ArmR", armSize, CFrame.new(0.85, 0.35, -0.95) * CFrame.Angles(rad(38), 0, 0), 1.05)

	-- Bent rear legs (shorter), pivoting at the hip.
	local legSize = Vector3.new(0.6, 1.6, 0.6)
	limb("LegL", legSize, CFrame.new(-0.6, -0.45, 0.85) * CFrame.Angles(rad(-18), 0, 0), 0.8)
	limb("LegR", legSize, CFrame.new(0.6, -0.45, 0.85) * CFrame.Angles(rad(-18), 0, 0), 0.8)

	-- Tail (pivot at the base near the torso rear).
	local tail = cosmeticPart("Tail", Vector3.new(0.35, 0.35, 1.7), dark)
	tail.Parent = rig
	joint("Tail", torso, tail, CFrame.new(0, 0.25, 1.15) * CFrame.Angles(rad(22), 0, 0), CFrame.new(0, 0, -0.85))

	return torso -- the "Body" the jumpscare clones / the eye-glow host
end

-- Build, position, and parent a rig for `species` at `spawnPart`, under `parent`. The
-- visible body is the species mesh if present, else the articulated primate. Returns the
-- Model. MonsterService sets the `State` attribute and owns it from there.
function MonsterRig.build(species: string, cfg, spawnPart: BasePart, parent: Instance): Model
	local rig = Instance.new("Model")
	rig.Name = species

	-- Invisible physics root: the collision box pathfinding/movement use.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = cfg.BodySize
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = true
	root.Parent = rig

	-- Invisible Head (a Humanoid needs a Head to count as a living character). Distinct
	-- from any cosmetic head (the monkey's visible head is "CHead").
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1, 1, 1)
	head.Transparency = 1
	head.CanCollide = false
	head.Massless = true
	head.Parent = rig
	local headWeld = Instance.new("Weld")
	headWeld.Part0 = root
	headWeld.Part1 = head
	headWeld.C0 = CFrame.new(0, cfg.BodySize.Y / 2 + 0.5, 0)
	headWeld.Parent = root

	-- Visible body: the species mesh, or the articulated primate when no mesh exists.
	local assets = ServerStorage:FindFirstChild("Assets")
	local meshSource = assets and cfg.BodyAssetName and assets:FindFirstChild(cfg.BodyAssetName)
	if meshSource and meshSource:IsA("BasePart") then
		local body = buildMeshBody(rig, root, meshSource, cfg)
		local glow = Instance.new("PointLight")
		glow.Name = "EyeGlow"
		glow.Color = cfg.EyeGlowColor
		glow.Brightness = cfg.EyeGlowBrightness
		glow.Range = cfg.EyeGlowRange
		glow.Parent = body
	else
		buildPrimate(rig, root, cfg) -- creates "Body" + limbs + its own eye-glow
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.HipHeight = cfg.BodySize.Y / 2 -- float the root above the floor so it can walk
	humanoid.AutoRotate = true
	humanoid.Parent = rig

	rig.PrimaryPart = root
	rig:PivotTo(CFrame.new(spawnPart.Position + Vector3.new(0, cfg.BodySize.Y, 0)))
	rig:SetAttribute(Attributes.MonsterSpecies, species)
	rig.Parent = parent

	-- Keep physics authority on the server so server-driven MoveTo is honoured.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return rig
end

return MonsterRig
