--!strict
-- Gaits.luau
-- Pure procedural-gait recipes for the monsters (one per species). Each recipe is a
-- function of a phase accumulator (advanced by the rig's real ground speed) plus
-- blend weights and Config params, returning a map of joint (Part1) name -> the
-- `Motor6D.Transform` CFrame the client should write. NO Instance work and NO global
-- time read -- `clock` is passed in -- so this module is deterministic and unit-
-- testable, and the client `MonsterAnimController` owns all world mutation.
--
-- The anti-glide guarantee lives here: vertical motion (a hop arc / leg cycle) means
-- the body leaves the floor and plants instead of ice-skating, and stride cadence is
-- driven by actual travel speed by the caller, so the gait never desyncs from motion.

local Gaits = {}

export type Weights = { move: number, chase: number }

-- Shape of Config.Monster.Anim.Bunny (the caller passes that frozen table).
export type BunnyParams = {
	RefSpeed: number,
	SpeedSmoothing: number,
	WeightSmoothing: number,
	MinMoveSpeed: number,
	StrideDistance: number,
	ChaseStrideScale: number,
	HopHeight: number,
	ChaseHopScale: number,
	HopPitch: number,
	ForwardSurge: number,
	LegExtend: number,
	ArmSwing: number,
	HeadBob: number,
	IdleBreathHz: number,
	IdleBreathAmp: number,
}

local TAU = math.pi * 2

-- The bunny is the corrupted BIPEDAL mascot, so it HOPS as one body: a single hop
-- arc per `phase` cycle (planted at phase 0/1, airborne apex at 0.5). `move` (0..1)
-- fades the whole gait in from the idle pose; `chase` (0..1) flattens + quickens it.
-- `clock` drives only the idle breathing/sway, so when moving the result is a pure
-- function of phase. Returns the `Body` joint's Transform offset.
function Gaits.bunny(phase: number, clock: number, w: Weights, p: BunnyParams): { [string]: CFrame }
	local move = math.clamp(w.move, 0, 1)
	local chase = math.clamp(w.chase, 0, 1)
	local idle = 1 - move

	-- Body: a (reduced) hop arc + forward lunge + pitch. The articulated LEGS do most of
	-- the work now, so the torso arc is gentler than the old whole-mesh hop.
	local arc = math.sin(phase * math.pi) -- 0 -> 1 -> 0
	local hopHeight = p.HopHeight * (1 - chase * (1 - p.ChaseHopScale))
	local hopY = arc * hopHeight * move
	local surge = -p.ForwardSurge * arc * move -- -Z forward
	local pitch = p.HopPitch * math.sin(phase * TAU) * move
	local breath = math.sin(clock * TAU * p.IdleBreathHz) * p.IdleBreathAmp * idle

	-- A bunny HOP drives BOTH legs together: they extend/push down at the plant (phase
	-- 0/1) and tuck up at the airborne apex (phase 0.5). Arms reach/swing through the hop;
	-- the head bobs. These swing real mesh limbs on the articulated rig.
	local legA = -p.LegExtend * math.cos(phase * TAU) * move -- extend at plant, tuck at apex
	local armA = p.ArmSwing * math.sin(phase * TAU) * move
	local headA = math.sin(phase * TAU + 1.0) * p.HeadBob * move

	return {
		Body = CFrame.new(0, hopY + breath, surge) * CFrame.Angles(pitch, 0, 0),
		CHead = CFrame.Angles(headA, 0, 0),
		LegL = CFrame.Angles(legA, 0, 0),
		LegR = CFrame.Angles(legA, 0, 0), -- both together (a hop, not an alternating walk)
		ArmL = CFrame.Angles(armA, 0, 0),
		ArmR = CFrame.Angles(armA, 0, 0),
	}
end

-- Shape of Config.Monster.Anim.Monkey.
export type MonkeyParams = {
	RefSpeed: number,
	SpeedSmoothing: number,
	WeightSmoothing: number,
	MinMoveSpeed: number,
	StrideDistance: number,
	ChaseStrideScale: number,
	GallopHeight: number,
	GallopChaseScale: number,
	GallopSurge: number,
	GallopPitch: number,
	GallopRoll: number,
	GallopHunch: number,
	ArmSwing: number,
	LegSwing: number,
	LimbDesync: number,
	HeadBob: number,
	HeadThrust: number,
	TailSway: number,
	TailLash: number,
	IdleBreathHz: number,
	IdleBreathAmp: number,
	IdleScanSpeed: number,
	IdleScanAmp: number,
}

-- The monkey is an articulated primate doing a 4-beat BOUNDING gallop: the front pair
-- (arms) and rear pair (legs) swing a half-cycle apart, with the spine flexing, the head
-- thrusting, and the tail counter-swaying. Each value is an animation DELTA from the
-- rest crouch baked into the rig's joint C0s. Returns one Transform per cosmetic joint.
function Gaits.monkey(phase: number, clock: number, w: Weights, p: MonkeyParams): { [string]: CFrame }
	local move = math.clamp(w.move, 0, 1)
	local chase = math.clamp(w.chase, 0, 1)
	local idle = 1 - move

	-- WHOLE-BODY GALLOP (the live path -- the monkey is the gorilla mesh on one `Body`
	-- joint). One suspension arc per stride: the body leaps up + forward (feet off the
	-- floor = the anti-glide), the spine rocks fore/aft, with a loping roll and a hunch
	-- that deepens while hunting. Flatter + more horizontal in a chase.
	local arc = math.sin(phase * math.pi) -- 0 -> 1 -> 0, one suspension per stride
	local gallopH = p.GallopHeight * (1 - chase * (1 - p.GallopChaseScale))
	local bobY = arc * gallopH * move
	local surge = -p.GallopSurge * arc * move -- -Z is forward
	local rock = p.GallopPitch * math.sin(phase * TAU) * move -- spine rock fore/aft
	local hunch = p.GallopHunch * (0.4 + 0.6 * chase) * move
	local roll = math.sin(phase * TAU) * p.GallopRoll * move
	local breath = math.sin(clock * TAU * p.IdleBreathHz) * p.IdleBreathAmp * idle

	-- Articulated-limb fallback (no-mesh primate): arms lead, legs follow half a cycle,
	-- a small L/R desync; head bob/thrust + scan; tail sway/lash. Ignored on the mesh rig
	-- (those joints don't exist there), so it's free to keep for the proxy.
	local armL = math.sin(phase * TAU) * p.ArmSwing * move
	local armR = math.sin((phase + p.LimbDesync) * TAU) * p.ArmSwing * move
	local legPhase = (phase + 0.5) % 1
	local legL = math.sin(legPhase * TAU) * p.LegSwing * move
	local legR = math.sin((legPhase + p.LimbDesync) * TAU) * p.LegSwing * move
	local headBob = math.sin(phase * TAU + 1.0) * p.HeadBob * move
	local headThrust = p.HeadThrust * chase
	local scan = math.sin(clock * p.IdleScanSpeed) * p.IdleScanAmp * idle
	local tail = math.sin(phase * TAU) * (p.TailSway + p.TailLash * chase) * move
		+ math.sin(clock * 1.1) * p.TailSway * 0.5 * idle

	return {
		Body = CFrame.new(0, bobY + breath, surge) * CFrame.Angles(rock + hunch, roll * 0.5, roll),
		CHead = CFrame.Angles(headBob - headThrust, scan, 0),
		ArmL = CFrame.Angles(armL, 0, 0),
		ArmR = CFrame.Angles(armR, 0, 0),
		LegL = CFrame.Angles(legL, 0, 0),
		LegR = CFrame.Angles(legR, 0, 0),
		Tail = CFrame.Angles(0, tail, 0),
	}
end

return Gaits
