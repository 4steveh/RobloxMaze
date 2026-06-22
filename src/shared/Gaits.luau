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
	WalkArcScale: number,
	WalkLegScale: number,
	HopPitch: number,
	ForwardSurge: number,
	LegExtend: number,
	ArmSwing: number,
	HeadBob: number,
	IdleBreathHz: number,
	IdleBreathAmp: number,
	FootfallDip: number,
	WalkLean: number,
}

local TAU = math.pi * 2

-- A natural foot STRIDE (the anti-slide fix for "feet skate / it's a skin, not a creature"): the
-- planted foot is held during STANCE and swept BACK to match the body's forward travel (so it does
-- not slide), then SWUNG forward quickly during SWING. `lp` = the limb's phase (0..1); returns the
-- fore/aft angle (positive = forward, matching the rig's -Z). Same amplitude as the old sine, better
-- shape. (Single-part rigid legs can't bend a knee, so this is the best a hip-only joint can do.)
local STANCE = 0.6 -- fraction of the cycle the foot is planted (vs swinging)
local function stride(lp: number, amp: number): number
	lp = lp % 1
	if lp < STANCE then
		-- stance: foot planted, sweeps from forward(+amp) to back(-amp) as the body moves over it
		return amp * (1 - 2 * (lp / STANCE))
	end
	-- swing: foot returns from back(-amp) to forward(+amp), quicker (the step)
	return amp * (2 * ((lp - STANCE) / (1 - STANCE)) - 1)
end

-- The bunny is the corrupted BIPEDAL mascot, so it HOPS as one body: a single hop
-- arc per `phase` cycle (planted at phase 0/1, airborne apex at 0.5). `move` (0..1)
-- fades the whole gait in from the idle pose; `chase` (0..1) flattens + quickens it.
-- `clock` drives only the idle breathing/sway, so when moving the result is a pure
-- function of phase. Returns the `Body` joint's Transform offset.
function Gaits.bunny(phase: number, clock: number, w: Weights, p: BunnyParams): { [string]: CFrame }
	local move = math.clamp(w.move, 0, 1)
	local chase = math.clamp(w.chase, 0, 1)
	local idle = 1 - move
	local walk = 1 - chase

	-- Vertical: the WALK now carries WEIGHT -- the body DROPS on each footfall (2 dips per stride =
	-- mass + impact), instead of floating at a constant height (the "it's a skin gliding" tell). The
	-- CHASE swells into the single committed-lunge HOP arc. A forward LEAN sells it as a creature
	-- pushing into its motion (deeper while hunting).
	local arc = math.sin(phase * math.pi) -- 0 -> 1 -> 0, one hop per stride
	local hopY = arc * p.HopHeight * chase * move -- the committed-lunge hop (chase only)
	local footfall = -p.FootfallDip * (1 - math.cos(phase * 2 * TAU)) * 0.5 * walk * move -- weight, 2/stride
	local surge = -p.ForwardSurge * arc * chase * move
	local hopPitch = p.HopPitch * math.sin(phase * TAU) * chase * move
	local lean = p.WalkLean * (0.6 + 0.4 * chase) * move -- forward lean (positive), deeper hunting
	local breath = math.sin(clock * TAU * p.IdleBreathHz) * p.IdleBreathAmp * idle

	-- Legs: an ANTI-SLIDE stride at the walk (planted foot sweeps back, no skate -- half a cycle
	-- apart) synchronizing into the both-legs HOP (extend at the plant, tuck at the apex) as chase
	-- rises. Arms COUNTER-swing the opposite leg (contralateral, like a real biped) at the walk.
	local legHop = -p.LegExtend * math.cos(phase * TAU) -- both together (the hop)
	local legWalkL = stride(phase, p.LegExtend * p.WalkLegScale)
	local legWalkR = stride(phase + 0.5, p.LegExtend * p.WalkLegScale)
	local legL = (legWalkL * walk + legHop * chase) * move
	local legR = (legWalkR * walk + legHop * chase) * move
	local armHop = p.ArmSwing * math.sin(phase * TAU)
	local armL = (-stride(phase + 0.5, p.ArmSwing) * 0.7 * walk + armHop * chase) * move -- counters LegL
	local armR = (-stride(phase, p.ArmSwing) * 0.7 * walk + armHop * chase) * move -- counters LegR
	local headA = math.sin(phase * TAU + 1.0) * p.HeadBob * move

	return {
		-- Counter the body lean on the head so it stays up and forward (looking where it's going).
		Body = CFrame.new(0, hopY + footfall + breath, surge) * CFrame.Angles(hopPitch + lean, 0, 0),
		CHead = CFrame.Angles(headA - lean * 0.5, 0, 0),
		LegL = CFrame.Angles(legL, 0, 0),
		LegR = CFrame.Angles(legR, 0, 0),
		ArmL = CFrame.Angles(armL, 0, 0),
		ArmR = CFrame.Angles(armR, 0, 0),
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
	FootfallDip: number,
	WalkLean: number,
}

-- The monkey is an articulated primate doing a 4-beat BOUNDING gallop: the front pair
-- (arms) and rear pair (legs) swing a half-cycle apart, with the spine flexing, the head
-- thrusting, and the tail counter-swaying. Each value is an animation DELTA from the
-- rest crouch baked into the rig's joint C0s. Returns one Transform per cosmetic joint.
function Gaits.monkey(phase: number, clock: number, w: Weights, p: MonkeyParams): { [string]: CFrame }
	local move = math.clamp(w.move, 0, 1)
	local chase = math.clamp(w.chase, 0, 1)
	local idle = 1 - move
	local walk = 1 - chase

	-- WALK: a weighted 4-beat walk -- the torso DROPS on each footfall (mass, not a flat glide) and
	-- the limbs use an ANTI-SLIDE stride. CHASE: the single suspension GALLOP arc (the bounding leap,
	-- feet off the floor). A base forward hunch + walk lean sell it as a creature, not a skin.
	local arc = math.sin(phase * math.pi) -- 0 -> 1 -> 0, one suspension per stride
	local gallopH = p.GallopHeight * (1 - chase * (1 - p.GallopChaseScale))
	local bobY = arc * gallopH * chase * move -- the gallop suspension (chase)
	local footfall = -p.FootfallDip * (1 - math.cos(phase * 2 * TAU)) * 0.5 * walk * move -- walk weight
	local surge = -p.GallopSurge * arc * chase * move -- -Z is forward
	local rock = p.GallopPitch * math.sin(phase * TAU) * chase * move -- spine rock fore/aft
	local hunch = (p.GallopHunch * (0.4 + 0.6 * chase) + p.WalkLean * walk) * move
	local roll = math.sin(phase * TAU) * p.GallopRoll * chase * move
	local breath = math.sin(clock * TAU * p.IdleBreathHz) * p.IdleBreathAmp * idle

	-- The four limbs: an ANTI-SLIDE stride at the walk (front pair leads, rear pair a half-cycle
	-- later -- a diagonal-ish walk), swelling into the gallop swing as chase rises. Small L/R desync.
	local armWalkL = stride(phase, p.ArmSwing)
	local armWalkR = stride(phase + p.LimbDesync, p.ArmSwing)
	local legWalkL = stride(phase + 0.5, p.LegSwing)
	local legWalkR = stride(phase + 0.5 + p.LimbDesync, p.LegSwing)
	local armGallL = math.sin(phase * TAU) * p.ArmSwing
	local armGallR = math.sin((phase + p.LimbDesync) * TAU) * p.ArmSwing
	local legPhase = (phase + 0.5) % 1
	local legGallL = math.sin(legPhase * TAU) * p.LegSwing
	local legGallR = math.sin((legPhase + p.LimbDesync) * TAU) * p.LegSwing
	local armL = (armWalkL * walk + armGallL * chase) * move
	local armR = (armWalkR * walk + armGallR * chase) * move
	local legL = (legWalkL * walk + legGallL * chase) * move
	local legR = (legWalkR * walk + legGallR * chase) * move
	local headBob = math.sin(phase * TAU + 1.0) * p.HeadBob * move
	local headThrust = p.HeadThrust * chase
	local scan = math.sin(clock * p.IdleScanSpeed) * p.IdleScanAmp * idle
	local tail = math.sin(phase * TAU) * (p.TailSway + p.TailLash * chase) * move
		+ math.sin(clock * 1.1) * p.TailSway * 0.5 * idle

	return {
		Body = CFrame.new(0, bobY + footfall + breath, surge) * CFrame.Angles(rock + hunch, roll * 0.5, roll),
		CHead = CFrame.Angles(headBob - headThrust, scan, 0),
		ArmL = CFrame.Angles(armL, 0, 0),
		ArmR = CFrame.Angles(armR, 0, 0),
		LegL = CFrame.Angles(legL, 0, 0),
		LegR = CFrame.Angles(legR, 0, 0),
		Tail = CFrame.Angles(0, tail, 0),
	}
end

return Gaits
