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
	LandDip: number,
	ForwardSurge: number,
	LeanInto: number,
	IdleBreathHz: number,
	IdleBreathAmp: number,
	IdleSwayAmp: number,
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

	-- Vertical hop arc -- the body leaves the floor (the anti-glide). Flatter in a chase.
	local arc = math.sin(phase * math.pi) -- 0 -> 1 -> 0
	local hopHeight = p.HopHeight * (1 - chase * (1 - p.ChaseHopScale))
	local hopY = arc * hopHeight * move

	-- Landing compression: a short downward dip as the feet plant (phase near 0 and 1).
	local landWeight = (math.cos(phase * TAU) + 1) * 0.5 -- 1 at 0/1, 0 at .5
	local dip = -p.LandDip * landWeight * move

	-- Forward lunge through the air (peaks mid-hop, settles at the plant). -Z is forward.
	local surge = -p.ForwardSurge * arc * move

	-- Pitch: nose up on takeoff, nose down on the descent; plus a forward crouch-lean
	-- that deepens with speed and especially in a chase.
	local pitch = p.HopPitch * math.sin(phase * TAU) * move
	local lean = p.LeanInto * move * (0.5 + 0.5 * chase)

	-- Idle life so a stopped rig still breathes and shifts its weight (never a statue).
	local breath = math.sin(clock * TAU * p.IdleBreathHz) * p.IdleBreathAmp * idle
	local sway = math.sin(clock * 1.3) * p.IdleSwayAmp * idle

	local body = CFrame.new(0, hopY + dip + breath, surge) * CFrame.Angles(pitch + lean, sway, 0)
	return { Body = body }
end

-- Shape of Config.Monster.Anim.Monkey.
export type MonkeyParams = {
	RefSpeed: number,
	SpeedSmoothing: number,
	WeightSmoothing: number,
	MinMoveSpeed: number,
	StrideDistance: number,
	ChaseStrideScale: number,
	ArmSwing: number,
	LegSwing: number,
	LimbDesync: number,
	BodyBob: number,
	BodyPitchFlex: number,
	BodyRoll: number,
	ChaseHunch: number,
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

	-- Bound: arms lead, legs follow a half-cycle later. A small L/R desync adds life.
	local armL = math.sin(phase * TAU) * p.ArmSwing * move
	local armR = math.sin((phase + p.LimbDesync) * TAU) * p.ArmSwing * move
	local legPhase = (phase + 0.5) % 1
	local legL = math.sin(legPhase * TAU) * p.LegSwing * move
	local legR = math.sin((legPhase + p.LimbDesync) * TAU) * p.LegSwing * move

	-- Torso: vertical bob twice a cycle (one per plant), a flexing spine, a slight roll,
	-- and a deeper hunch while hunting.
	local bob = -math.abs(math.sin(phase * TAU)) * p.BodyBob * move
	local flex = math.sin(phase * TAU) * p.BodyPitchFlex * move
	local roll = math.sin(phase * TAU) * p.BodyRoll * move
	local hunch = p.ChaseHunch * chase
	local breath = math.sin(clock * TAU * p.IdleBreathHz) * p.IdleBreathAmp * idle

	-- Head: bob with the gait, thrust forward while hunting, slow scan when idle.
	local headBob = math.sin(phase * TAU + 1.0) * p.HeadBob * move
	local headThrust = p.HeadThrust * chase
	local scan = math.sin(clock * p.IdleScanSpeed) * p.IdleScanAmp * idle

	-- Tail: side-sway with the gait, lashing while hunting, idle drift when stopped.
	local tail = math.sin(phase * TAU) * (p.TailSway + p.TailLash * chase) * move
		+ math.sin(clock * 1.1) * p.TailSway * 0.5 * idle

	return {
		Body = CFrame.new(0, bob + breath, 0) * CFrame.Angles(flex + hunch, roll * 0.5, roll),
		CHead = CFrame.Angles(headBob - headThrust, scan, 0),
		ArmL = CFrame.Angles(armL, 0, 0),
		ArmR = CFrame.Angles(armR, 0, 0),
		LegL = CFrame.Angles(legL, 0, 0),
		LegR = CFrame.Angles(legR, 0, 0),
		Tail = CFrame.Angles(0, tail, 0),
	}
end

return Gaits
