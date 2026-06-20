# Monster Roster + Real Locomotion — Design Spec & Phased Build Plan

- **Date:** 2026-06-20
- **Status:** Approved; **Phases 1–7 IMPLEMENTED & verified in Studio.** Bunny (vision stalker,
  whole-mesh hop) + Monkey (noise hunter, articulated bounding gallop) both walk like real
  creatures with opposite counters; reactive chase grade/vignette + HUD noise meter shipped.
  **Deferred polish** (noted, not done): enabling `Lighting.Technology = Future` (a manual Studio
  toggle — scripts can't set it), a distinct monkey screech/audio identity (needs a sourced asset
  id), camera FOV/head-bob, and the chase-only threat-direction arrow.
- **Phase 1 implementation note (adaptation from direct evidence):** the `BunnyBody` mesh is a
  single rigid **bipedal mascot** (person-in-a-bunny-suit: head+ears, collar, arms, pink feet,
  tail), not a quadruped — so adding primitive ears/legs (§2.2) would double the baked ones. The
  bunny instead animates as **one body doing a two-footed HOP** (`Config.MonsterAnim.Bunny`,
  `Gaits.bunny`): the whole mesh arcs up (feet leave the floor), pitches/lunges forward, and plants
  — a real bunny gait and a deeply unsettling read, with cadence locked to ground speed. The
  multi-limb articulation in §2.2/§2.3 still applies to the **monkey** (built from primitives,
  Phase 5). The Phase-1 Config lives at top-level `Config.MonsterAnim` (sibling of the *frozen*
  `Config.Monster`), folding into `Config.Monster.Anim.<Species>` in the Phase 2/4 restructure.
- **Depends on:** the bunny MVP (`MonsterService` + `BunnyFSM` + procedural rig), the
  playability overhaul (sprint/stamina, compass, audio), and the daycare environment pass.
- **Supersedes nothing.** Extends `2026-06-19-monster-bunny-design.md` — the bunny's
  vision-stalker behaviour is preserved verbatim and refactored, not rewritten.

---

## 1. Goal & design pillars

Turn the single gliding bunny into a **roster of two believable predators that walk like
real creatures and pull the player between two opposite failure modes**, while keeping every
hard constraint in CLAUDE.md (server authority, Config-as-truth, tag/spatial discovery,
one-system-per-module, no marketplace inserts).

Three pillars:

1. **Two creatures, two orthogonal counters — the bunny hunts what it SEES, the monkey
   hunts what it HEARS.** The bunny is the established methodical vision stalker (escape by
   breaking line of sight). The monkey is its inverse: a near-blind screecher drawn to
   **noise** (sprint, fast movement, the flashlight), escaped only by **going quiet**. This
   is the deliberate decision over "a second vision stalker" — a second see-you monster just
   doubles the same pressure; an inverse monster makes the *already-built* sprint + flashlight
   systems a live stealth economy. (Research 2's role design; chosen over Research 4's
   "ambush-from-AmbushNode monkey," because noise-vs-sight is a cleaner, learnable contrast
   and reuses three existing systems instead of bolting on a fourth.)

2. **Real locomotion, not a glide.** Both rigs articulate: a cosmetic Motor6D skeleton on top
   of the *unchanged* physics root, animated **client-side** with a procedural gait whose
   stride frequency is derived from actual ground speed (feet move *with* the floor → no
   slide). The physics/pathfinding/LoS contract is provably untouched because every cosmetic
   limb is `Massless`/`CanCollide=false`/`CanQuery=false`.

3. **Top-tier presentation as a measured backlog, not a rewrite.** Future lighting + flashlight
   shadows + reactive chase grade + dynamic audio + haptics, each a small Config-driven,
   render-only client layer hung off signals the server already owns (`MonsterStateChanged`,
   the rig `State`/`Species` attributes, replicated rig positions).

**The locomotion promise (the bar Phase 1 must clear):** stop one rigid mesh from
ice-skating. After Phase 1, a single bunny rig visibly hops — body arc, leg push/tuck, ear
flop — with the hop cadence locked to how fast it is actually travelling, rendered identically
on every client at zero bandwidth, with pathfinding and detection unchanged.

---

## 2. The locomotion system

### 2.1 Chosen method (decided)

**A cosmetic, articulated Motor6D skeleton welded to the existing physics root, animated by a
client controller that writes `Motor6D.Transform` on `RunService.PreSimulation`, computing the
gait locally from the rig's replicated root motion + `State`/`Species` attributes. No Animator
on the rig, ever. Zero replication, zero new remotes.** (Research 1 + Research 5, in agreement.)

Why this method beats the alternatives, in one line each:
- **Client `Transform` writes** > server `Transform` writes (Transform does not replicate —
  server writes render nowhere) and > animating `C0` (C0 replicates → per-joint CFrame
  bandwidth blowout for a purely cosmetic effect, and corrupts the bind pose).
- **No Animator:** an Animator overwrites `Motor6D.Transform` every frame even with zero tracks
  playing (the classic gotcha) — the rig's `Humanoid` must stay Animator-free.
- **`PreSimulation` not `RenderStepped`:** PreSimulation runs *after* the Animator overwrite
  window and before physics, so writes survive even if a future Animator sneaks in, and limbs
  render in lockstep with the body. Its `dt` drives the phase accumulator.

This is architecturally blessed: limbs are **uncontested** (they decide nothing) and
**non-exploitable** (a cheater desyncing their own monster's legs gains nothing) — the same
class as `FlickerController`/dust, which CLAUDE.md explicitly permits client-side.

### 2.2 Rig articulation (server, in the rig builder)

Keep **everything physical** exactly as-is: the invisible `HumanoidRootPart` (`BodySize` box,
`CanCollide=true`, `SetNetworkOwner(nil)`), the invisible `Head`, the `Humanoid`
(`RequiresNeck=false`, `HipHeight`, `AutoRotate=true`), `Humanoid:MoveTo`, the FSM, sensing.

Replace the single rigid welded `Body` with a small skeleton:
- The torso stays named **`Body`** and stays **Weld**'d to the root (the one joint that must
  not animate; `JumpscareController` clones the part named `Body`, so the name is load-bearing).
- Every other segment (`Head` cosmetic, `EarL`, `EarR`, `LegFrontL/R`, `LegHindL/R`, `Tail` for
  the bunny; `ShoulderL/R`, `ArmL/R`, `LegL/R`, `Tail` for the monkey) is a primitive part (or a
  slice of the existing mesh) joined to the torso by a **`Motor6D`** (`Part0`=torso,
  `Part1`=segment), rest pose set via `C0`.
- **Mandatory flags on every cosmetic segment:** `CanCollide=false`, `CanQuery=false`,
  `CanTouch=false`, `Massless=true`, `Anchored=false`. These keep the skeleton out of the
  collision solver, out of the LoS/pathfinding raycasts (CanQuery), and out of the Humanoid's
  balance (Massless) — so AgentRadius/AgentHeight/HipHeight and the vision cone are provably
  unaffected. **This is the #1 locomotion bug to guard:** any limb left `Massless=false` or
  `CanCollide=true` makes the Humanoid fight to balance and the rig jitters/falls.
- Parent every segment **under the rig `Model`** (beside the root), never under the HRP — keeps
  `GetBoundingBox`/`PivotTo`/the catch-repel working and the Jumpscare clone shallow.
- Set a server `Species` attribute on the rig — the client reads it to pick the gait recipe.

### 2.3 Gait math (pure module, client applies it)

Pure recipes live in a `--!strict` module `Gaits` (`Gaits.bunny(...)`, `Gaits.monkey(...)`
→ `{ jointName: CFrame }`); the controller applies the returned offsets to `Transform`. The
**anti-glide link** is stride frequency derived from planar speed:

```
planarSpeed = magnitude(XZ of (root.Position - lastPos)/dt)   -- replicated motion, exploit-safe
moveWeight  = clamp(speedSmooth / RefSpeed, 0, 1)
strideHz    = BaseStrideHz * (speedSmooth/RefSpeed) * (1 + chaseWeight*ChaseStrideBoost)
phase       = (phase + strideHz*dt) % 1
```

- **Bunny:** one hop per phase cycle — whole-body vertical arc (`HopHeight`) + nose-down/up
  pitch (`HopPitch`), hind legs extend on push / tuck at apex, front paws reach to plant on
  landing, ears flop lagging body vertical velocity, small head bob. Idle (`moveWeight→0`):
  breathing on the torso + periodic ear twitch + slow head scan, `:Lerp`'d in by `(1-moveWeight)`.
- **Monkey:** a 4-beat knuckle-walk/gallop — per-limb phase offsets, lift+forward swing per
  limb, torso bob (2× stride) + lateral roll (1× stride), tail counter-sway, head thrust. Idle:
  hunched static pitch + shoulder sway + head scan.
- **State modulation** off the replicated `State` attribute: `Chase` lerps params toward
  faster/flatter/aggressive (ears pinned, head thrust); `Search` boosts the head-scan sweep
  ("looking for you"). All three weights are critically damped (`x += (target-x)*min(dt*k,1)`)
  so transitions never snap.
- **Turning polish (render-only):** keep server `AutoRotate=true`; smooth the *cosmetic* torso
  yaw with a damped lean-into-turns so AutoRotate corner-snaps don't read as a snap.
- **Foot-lock:** the speed-derived `strideHz` already reads as "planted." Optional later polish:
  a per-foot downward raycast ground-stick during the plant window. Real 2-bone IK is a stretch.

### 2.4 The in-Studio confirmation test (run FIRST, before any gait math)

**Two-client Play Solo** (Test → Clients and Servers → 2 players) to verify *cross-client*
rendering, not just the local one:

1. Build one rig: torso `Weld`'d to HRP, one `EarL` `Motor6D`'d to the torso (§2.2 flags),
   **no Animator**.
2. In a LocalScript, on `RunService.PreSimulation` write
   `earMotor.Transform = CFrame.Angles(math.sin(os.clock()*3)*0.6, 0, 0)`.
3. **PASS:** the ear rocks on **both** client windows while the server walks the rig via
   `MoveTo`. → Method confirmed; proceed to gait math.
4. **FAIL (ear frozen):** delete any Animator on the Humanoid and retry; if still frozen,
   switch the write to `earMotor.C0 = restC0 * CFrame.Angles(...)` — if *that* animates, adopt
   the **fallback** (animate cached-rest `C0` client-side instead of `Transform`; same gait
   math, immune to the Animator gotcha).
5. Sanity-check physics is untouched: the rig still pathfinds identically and a player hidden
   behind the *torso/limbs* is still detected (CanQuery=false means cosmetic parts never block
   the sense ray).

### 2.5 New modules

| Module | Side | Type | Role |
| --- | --- | --- | --- |
| `src/shared/Gaits.luau` | shared | `--!strict` | Pure gait recipes (`bunny`/`monkey`) → joint-offset CFrames. Unit-testable, no Instance work. |
| `src/client/MonsterAnimController.client.luau` | client | `--!nonstrict` | Observes `Workspace.Monsters` (mirrors `MonsterAudioController`); per rig resolves joints + reads `Species`; one `PreSimulation` connection drives all rigs' `Transform`. Render-only. |

---

## 3. The monster roster

### 3.1 The Bunny — *the methodical stalker who hunts what it SEES* (refined, behaviour-preserved)

Unchanged in behaviour: tours `PatrolPoint`s, sweeps a forward vision cone + LoS raycast, and
on detection commits to a `ChaseSpeed` pursuit you cannot outrun at base `WalkSpeed`. **Deaf and
oblivious to noise** — sprint flat-out behind its back and it won't care unless you enter its
cone with a clear ray. Counter: spatial/visual — manage facing, use walls, sprint to break sight.
The refactor (Phase 4) moves its numbers from `Config.Monster` flat fields into
`Config.Monster.Species.Bunny` and injects them as `cfg` — **values copied verbatim, zero
behaviour change.**

### 3.2 The Monkey — *the blind screecher who hunts what it HEARS* (new)

Near-blind ambusher drawn to **noise**: sprinting, fast movement, an on flashlight raise a
server-computed **noise** level it can hear *through walls*, falling off with distance and
decaying when you go quiet. On hearing enough it **erratically rushes** the noise source; eyes
on you at close range → **screech + lunge** (the fastest thing in the game, in short windows).
Beaten by the one thing the bunny ignores: **going quiet** (walk, kill the flashlight).

The squeeze (the headline emergent moment): sprint to break the bunny's sight → you spike noise
→ the monkey converges → go quiet to shed the monkey → you slow back into the bunny's reach. The
SafeRoom is the only place safe from sight **and** sound at once.

One-line contrast: **the bunny makes you afraid to be seen; the monkey makes you afraid to be
heard.**

### 3.3 FSMs — siblings behind a shared contract (not a shared base)

One FSM module per type (`BunnyFSM`, `MonkeyFSM`), both `--!strict`, both pure
(`newState`/`tick(state, sensed, cfg)`, no Instance work), both behind a shared
`MonsterTypes` contract. Sharing a base class would over-couple two deliberately different
brains; the small duplicated helpers (`flatDistance`, nearest-node) are cheap.

**`cfg` injection (decided):** `tick` takes a `cfg` param (the per-species `Config.Monster`
slice) instead of reading `Config.Monster.*` directly — this is what lets two FSMs coexist
without sharing one config namespace. The bunny's signature changes from `tick(state, sensed)`
to `tick(state, sensed, cfg)`; its only caller is `MonsterService`, so it migrates in one commit.

**Monkey detection model — hearing-primary, vision-secondary:**
- **Heard** when `effectiveNoise = NoiseLevel × falloff(distance, HearRange) ≥ HearThreshold`.
  **No LoS raycast for hearing** — it hears through walls (that's the point).
- **Seen** (lunge/catch confirm only) reuses the existing cone+LoS machinery with the monkey's
  own short/wide params.
- Same eligibility gate as the bunny: skip `InSafeRoom`/`Won`/`RespawnGrace` players entirely,
  **and** force their `NoiseLevel` to 0 (a SafeRoom silences you so you can't bait it).

**Monkey states** (reuses `Patrol`/`Chase`/`Search`; adds `Alert`/`Investigate`):

| State | Behaviour |
| --- | --- |
| `Patrol` | Perches near its `MonkeySpawn` nest, short slow tours of nearby `PatrolPoint`s; scans every player's `effectiveNoise`. |
| `Alert` *(new)* | Heard something — snaps to face the loudest source and holds `AlertDuration` (the fair "it heard you" tell). Noise persists → `Investigate`; decays → `Patrol`. |
| `Investigate` *(new)* | Erratic fast rush (`InvestigateSpeed`) toward the last-heard point with a random lateral `InvestigateJitter` per repath (weaves, slightly dodgeable). Re-hears louder → re-aims; close-range sight → `Chase`; noise below `LoseHearThreshold` for `LoseHearSeconds` → `Search`. |
| `Chase` | Triggered only with **eyes on a heard player at close range**: committed `LungeSpeed` burst. Within `CatchRadius` → catch. Lost sight + quiet → `Search`. |
| `Search` | Pokes the last point for `SearchDuration`, hearing-only. Re-hears → `Investigate`; re-sees → `Chase`; expires → `Patrol` (climbs home). |

### 3.4 Interactions (coexist and stay winnable)

Separate spawns (bunny `MonsterSpawn`, monkey `MonkeySpawn` placed in a different region, near
the key-dense middle), shared `PatrolPoint` graph (bunny tours it, monkey only dips in to
investigate). Both run independently and can split targets in co-op. Three guardrails keep a
solo pincer survivable:
1. **Anti-spawn-camp applies to both** (`ResetToPatrolOnCatch` + `PostCatchDormantSeconds` +
   `RespawnGrace` skip).
2. **SafeRooms are a hard sanctuary from both** (removed from both sensed sets + noise zeroed).
3. **Fairness budget:** walking with the flashlight off sits **below** `HearThreshold` (the
   default state is genuinely safe from the monkey); the lunge needs LoS so ducking a wall mid-
   Chase denies the kill; `AlertDuration` gives a ~1.2 s reaction beat; the monkey mostly
   perches, so it must *travel* — that travel time is your escape window.

### 3.5 Concrete numbers

**`Config.Monster.Species.Bunny`** = current `Config.Monster` values verbatim (`PatrolSpeed=10`,
`ChaseSpeed=19`, `DetectRange=50`, `DetectHalfAngle=45`, `LoseSightSeconds=4`, `SearchDuration=6`,
`SearchWanderRadius=12`, `CatchRadius=5`, `PatrolMemory=2`, `BodySize=2.5×3.5×2.5`,
`BodyColor=(220,218,225)`, `ModelYOffset=0.75`, `ModelFaceYaw=0`, `EyeGlowColor=(210,40,40)`,
`EyeGlowBrightness=0.7`, `EyeGlowRange=7`, `BodyAssetName="BunnyBody"`).

**`Config.Monster.Species.Monkey`** (grounded vs `WalkSpeed 16`, `SprintSpeed 22`, bunny
`ChaseSpeed 19`):

```lua
PatrolSpeed = 11,            -- ambling near its nest
InvestigateSpeed = 18,       -- > WalkSpeed 16 (runs down a walker who stays loud), < SprintSpeed 22 (a sprinter can still gain)
LungeSpeed = 24,             -- > 22: unoutrunnable BY DESIGN, but sight-gated + short -> counter is "break sight", never "panic-sprint"
HearRange = 90,              -- studs to zero noise (longer than bunny sight 50: sound travels)
HearThreshold = 0.45,        -- effectiveNoise to commit to Alert (walking+light-off sits below this)
LoseHearThreshold = 0.25,
LoseHearSeconds = 3,
SightRange = 14, SightHalfAngle = 70, EyeHeight = 2,   -- short, wide cone: confirms a lunge only
AlertDuration = 1.2,         -- the fair "it heard you" tell
SearchDuration = 6, SearchWanderRadius = 12, InvestigateJitter = 6,
CatchRadius = 5,
BodySize = Vector3.new(2.5, 3.5, 2.5),                 -- <= bunny so corridor fit is identical (do NOT exceed)
BodyColor = Color3.fromRGB(60, 48, 44),                -- dark/matted: distinct silhouette from the pale bunny
BodyAssetName = "MonkeyBody",                          -- falls back to a primitive proxy if absent
ModelYOffset = 0.75, ModelFaceYaw = 0,
EyeGlowColor = Color3.fromRGB(250, 210, 60),           -- sickly yellow (vs bunny red): instant species read in the dark
EyeGlowBrightness = 0.7, EyeGlowRange = 7,
```

**`Config.Monster.Shared`** (cross-species plumbing, lifted out of the flat `Config.Monster`):
`RepathInterval=0.4`, `AgentRadius=2`, `AgentHeight=5`, `WaypointReachedDistance=4`,
`StallEpsilon=0.5`, `StallTicks=10`, `MaxTickDtFactor=4`, `ResetToPatrolOnCatch=true`,
`PostCatchDormantSeconds=4`, `NoKeySpawnRadius=30`. (Monkey may set `RepathInterval=0.35` in its
slice to weave faster — slice overrides shared where present.)

**`Config.Noise`** (server-computed from signals the server already owns — unspoofable):
```lua
SprintNoise = 1.0,           -- validated SprintIntent engaged = max noise
FastMoveNoise = 0.55,        -- moving at/above WalkSpeed without sprinting
SlowMoveNoise = 0.15, IdleNoise = 0.0,
FlashlightNoise = 0.30,      -- OPTIONAL additive (deferred; only if FlashlightStateIntent ships; capped < HearThreshold)
MoveSpeedRef = 16,
DecayPerSecond = 1.5,        -- noise lingers then fades (you must COMMIT to being quiet)
RisePerSecond = 4.0,         -- near-instant: sprinting is immediately loud
MaxNoise = 1.0,
```

**`Config.Monster.Anim`** (per-species, render-only client params; in Config because they are
numbers, per the single-source rule). Bunny: `RefSpeed=16`, `SpeedSmoothing=10`,
`BaseStrideHz=1.6`, `ChaseBlend=6`, `ChaseStrideBoost=0.6`, `HopHeight=1.1`, `HopPitch=0.35`,
`HindExtend=0.7`, `FrontReach=0.6`, `EarFollow=0.6`, `EarStiffness=8`, `EarSway=0.25`,
`EarSplay=0.2`, `HeadBob=0.15`, `IdleBreathHz=0.4`, `IdleBreathAmp=0.08`, `ScanSpeed=2`,
`SquashAmp=0.12`, `LeanGain=0.3`, `HeadLead=0.5`, `MaxLean=0.4`. Monkey: `MonkeyStep=0.6`,
`MonkeyStride=0.5`, `MonkeyBob=0.25`, `MonkeyRoll=0.12`, `TailCounter=1.0`, `TailSway=0.4`,
`MonkeyGaitOffsets={LegHindL=0.0,LegHindR=0.1,LegFrontL=0.5,LegFrontR=0.6}`. All tuned in Studio.

---

## 4. Graphics + audio + interactivity (selected items by phase)

Curated from Research 3 (graphics) and Research 4 (audio/feel) — only items with the best
impact/effort that hang off existing server signals (render-only, exploit-safe) or deepen the
core loop with no new client authority. Everything not listed is §7 future.

### Presentation Pack A — "real horror game" base look (Phase 6)
- **Future lighting + flashlight shadows** (S, very high). `Lighting.Technology=Future`;
  `Shadows=true` on the flashlight `SpotLight` + hero FlickerLights; tighten flashlight
  Angle/Brightness/Range so the monster throws a shadow down a corridor before you see it. Gate
  shadow-caster count via `Config.Perf`.
- **Monster material pass** (S, high). Swap the `Body` mesh `Material`/`Color` to a wet/matted
  "wrong mascot" read; per-species `BodyColor` already distinguishes them.
- **Jumpscare eye-glow restore + emissive** (S, high). The viewport `ClearAllChildren()`
  strips the eyes — re-add `PointLight`s at eye height + red uplight `LightDirection`. New
  `Config.Jumpscare` section.

### Presentation Pack B — the chase as an event (Phase 6, off `MonsterStateChanged`)
- **Reactive ColorCorrection + vignette on Chase** (M, very high). New
  `ChaseFXController.client.luau`: desaturate/crush/red-tint + vignette in on `Chase`, tween
  back on `Search`/`Patrol`. Use a *separate* CC instance so the static place grade isn't
  corrupted. `Config.Chase`.
- **Reactive eye-glow wash** (M, high). Client reads each rig's `State` and scales that rig's
  `EyeGlow` brightness/range up in Chase (`Config.Monster.EyeGlowChaseBrightness/Range`).
- **Camera FOV kick + head-bob** (S–M, high). New `CameraController.client.luau`: FOV punch on
  sprint (gated on authoritative `Stamina`), speed-coupled head-bob, closing-danger vignette off
  replicated nearest-rig distance. `Config.Camera`.

### Audio Pack (Phase 6, one PR over `MonsterAudioController` + `Config.Audio`)
- **Dynamic chase music bed + near-catch stab** (S, high). Looped bed fades in on `Chase`
  (Music bus, ducks under the scream), stab when nearest rig crosses `CatchRadius*NearCatchFactor`.
- **Occlusion lowpass** (S–M, high). Client LoS ray rig→player; `LowPassFilter` on that rig's 3D
  sounds when blocked (muffled-then-clear when it rounds the corner). Render-only.
- **Behind-you near-catch breathing** (S, high). Dry panicked breath swells when the nearest
  chasing rig is inside an inner radius **and** behind the camera (dot test).
- **Per-monster-type audio table** (S, prerequisite for the monkey's identity). Reshape
  `Config.Audio.Monster` into `{Bunny={...}, Monkey={...}}`, keyed by the rig `Species` attribute;
  bunny values just nest unchanged.
- **Haptics + screen punch on catch/key** (S, high on gamepad/mobile). `HapticService` rumble +
  red flash off the existing `MonsterCaught`/`KeyCollected` remotes. `Config.Feedback`.

### Interactivity / readability (Phase 7, deepens the loop)
- **Threat indicator** (S–M, high). New `ThreatIndicatorController.client.luau`: an edge arrow
  toward the nearest *chasing* rig, shown only while `MonsterStateChanged` says you're hunted
  (leaks nothing new; the patrol monster stays hidden). `Config.Compass.Danger*`.
- **HUD noise meter** (S, medium). Render the server-authoritative `NoiseLevel` attribute as a
  gauge — a fair "you are being loud" tell that teaches the monkey's counter. Render-only.
- **Stamina/heartbeat tightening** (S, medium). Heartbeat + ragged breath rise with low
  `Stamina`; HUD stamina pulses near empty.

---

## 5. Exact registry additions

**`Enums.MonsterType`** → add `Monkey = "Monkey"`.

**`Enums.MonsterState`** → add `Alert = "Alert"`, `Investigate = "Investigate"` (the existing
three stay; the bunny never enters the new two).

**`Tags`** → add `MonkeySpawn = "MonkeySpawn"`. *(Decision: a dedicated tag, not a shared
`MonsterSpawn` + `Species` attribute. Research 2 and Research 5 disagreed here; chosen Research 2's
separate tag because it keeps discovery a trivial per-species `Discovery.getAll(...)` matching the
existing pattern, lets designers place nests unambiguously, and the `Species`-attribute pooling
payoff only matters with many types sharing one spawn pool — which this design doesn't have. The
rig still carries a `Species` **attribute** for the client gait/audio lookup; that's a different
concern from spawn discovery.)*

**`Attributes`** → add two:
- `MonsterSpecies = "Species"` — string on a **rig Model**: which `Enums.MonsterType` it is;
  read by the client `MonsterAnimController` (gait) and per-type audio. Server-set.
- `NoiseLevel = "NoiseLevel"` — number 0..1 on a **Player**: server-computed audible noise
  (sprint + movement). Drives the monkey's hearing; never client-set; the HUD may render it.

**`Remotes`** → **none new.** Movement + the validated `SprintIntent` give the full noise model
server-side; per-player monster feedback rides the existing `MonsterStateChanged`; the catch rides
`MonsterCaught`. (Optional, deferred: one validated rate-limited `FlashlightStateIntent` only if
flashlight-noise is added later.)

**`Config`** new/changed sections:
- `Config.Monster` restructured into `Config.Monster.Shared` + `Config.Monster.Species.{Bunny,
  Monkey}` + `Config.Monster.Anim.{Bunny,Monkey}` (each `table.freeze`d; bunny values verbatim).
  Add `EyeGlowChaseBrightness`/`EyeGlowChaseRange` to each species slice.
- New `Config.Noise` (§3.5).
- Presentation sections, added in Phase 6 as their packs land: `Config.Jumpscare`, `Config.Chase`,
  `Config.Camera`, `Config.Perf` (`MaxShadowLights`, `ShadowCullDistance`), `Config.Audio.Monster`
  reshaped per-type (+ `ChaseBedId/Volume/FadeIn/Out`, `NearCatchStabId/Factor/Volume`,
  `OccludedCutoff`, `BehindBreathId/Radius/DotThreshold`), `Config.Flashlight.Shadows`,
  `Config.Compass.Danger*`, `Config.Feedback.Haptic*`.

**New `--!strict` contract module `src/shared/MonsterTypes.luau`** holding the FSM contract
(`PlayerSense`, `Sensed`, `TickResult`, an `FSMState` common head of `{name, targetUserId?}`,
`SpeciesConfig`, `MonsterFSM`) — moved out of `BunnyFSM` so both FSMs and `MonsterService` share
one definition. Each FSM keeps its own concrete superset state internally (no `::` casts at the
boundary, because `MonsterService` only reads `.name`/`.targetUserId`).

---

## 6. Phased build plan

Ordered so each phase is independently shippable, verifiable in Studio, and low-risk. **Phase 1
is the vertical slice: prove the locomotion method on ONE bunny rig and kill the glide before any
generalization.** Phases 2–5 generalize and add the monkey; Phase 6–7 are presentation/feel.

> Every phase ends with: `stylua .` + `selene .` clean (`0 errors, 0 warnings`), regenerate
> `sourcemap.json` (the instance tree changed), and **File→Save in Studio** (Workspace content
> is not Rojo-synced). Use the Studio MCP with `set_active_studio` confirmed on the right place
> before any mutating call.

### Phase 1 — Prove procedural locomotion on one bunny rig (kill the glide)

The smallest thing that delivers the headline win. No monkey, no Config refactor, no roster.

**What changes (files):**
- `src/server/MonsterService.server.luau` `createRig`: replace the single rigid `Body` weld with
  the articulated skeleton — keep `Body` (torso) Weld'd to root, add `EarL/EarR`, `LegFrontL/R`,
  `LegHindL/R`, `Tail` as primitives `Motor6D`'d to the torso (all `Massless`/`CanCollide=false`/
  `CanQuery=false`/`CanTouch=false`), set rest `C0`s. Set `rig:SetAttribute(Attributes.MonsterSpecies,
  Enums.MonsterType.Bunny)`. **Do not add an Animator.** Everything else untouched.
- `src/shared/Attributes.luau`: add `MonsterSpecies = "Species"`.
- `src/shared/Config.luau`: add `Config.Monster.Anim` (bunny block only for now — temporary
  sibling of the flat `Config.Monster`; folds into the Phase 4 restructure).
- New `src/shared/Gaits.luau` (`--!strict`): `Gaits.bunny(phase, weights, params)` only.
- New `src/client/MonsterAnimController.client.luau` (`--!nonstrict`): observe `Workspace.Monsters`
  (mirror `MonsterAudioController`), resolve joints per rig, one `PreSimulation` loop applying
  `Gaits.bunny` to `Transform`, reading replicated root motion + `State`.

**Verify (Studio):**
1. **Run the §2.4 two-client test first** (a throwaway `EarL` write) to confirm Method 1 vs the
   C0 fallback — adopt whichever passes before writing real gait math.
2. `start_stop_play` + `screen_capture` mid-walk: the bunny **hops** — body arc + leg push/tuck
   + ear flop — with hop cadence matching travel speed (no foot-slide). Idle breathing when stopped.
3. **Pathfinding-unchanged gate:** re-run the existing all-pairs PatrolPoint reach check; the rig
   reaches every node exactly as before. A player hidden behind the torso/limbs is still detected
   only by real walls (CanQuery proof).
4. `JumpscareController` still renders the `Body` close-up on a catch.

**Definition of done:** one bunny rig visibly walks (no glide), rendered on both clients at zero
bandwidth; pathfinding/LoS/jumpscare unchanged; StyLua/Selene clean; place saved; capture evidence.

### Phase 2 — Contract + Config refactor (behaviour-preserving)

Load-bearing refactor that must be one commit (the `BunnyFSM.tick` signature changes and its only
caller is `MonsterService`).

**What changes:** new `src/shared/MonsterTypes.luau` (move the four types out of `BunnyFSM`, add
`FSMState` head + `SpeciesConfig` + `MonsterFSM`); `Config.Monster` → `Shared` + `Species.Bunny`
+ fold in `Config.Monster.Anim` (bunny values **verbatim**); `BunnyFSM` imports the contract and
takes `cfg`, replacing every `Config.Monster.X` with `cfg.X`; `MonsterService` passes `cfg` and
reads the Bunny slice (incl. `sensePlayers` reading `cfg.DetectRange/DetectHalfAngle`).

**Verify:** full playtest — bunny patrols/detects(cone+LoS)/chases/searches/gives-up/catches →
jumpscare → respawn at checkpoint; `State` cycles; all-pairs pathfinding gate unchanged. **Grep
for any residual flat `Config.Monster.` field read** (a missed `sensePlayers` migration silently
breaks vision).

**Definition of done:** bunny behaviour bit-identical to pre-refactor; no orphan flat
`Config.Monster` fields; lint/format clean; saved.

### Phase 3 — Extract the rig builder (behaviour-preserving)

**What changes:** extract `createRig` → new `src/server/MonsterRig.luau` (`--!nonstrict`),
`MonsterRig.build(species, cfg, spawnPart): Model`, still building the exact articulated bunny
from Phase 1. `MonsterService` calls it. Falls back to a primitive proxy if
`ServerStorage.Assets:FindFirstChild(cfg.BodyAssetName)` is absent (so a missing monkey mesh never
errors the server).

**Verify:** visual/audio/jumpscare identical; rig still walks. **Definition of done:** no
behaviour change; lint clean; saved.

### Phase 4 — The monkey species (FSM + noise, no new locomotion)

**What changes:** `Enums` (+`Monkey`, +`Alert`/`Investigate`); `Tags` (+`MonkeySpawn`);
`Attributes` (+`NoiseLevel`); `Config` (+`Config.Monster.Species.Monkey`, +`Config.Monster.Anim.
Monkey`, +`Config.Noise`); new `src/server/MonkeyFSM.luau` (`--!strict`, same contract,
hearing-primary detection per §3.3); new `src/server/NoiseService.server.luau` (`--!nonstrict` —
owns `NoiseLevel` on the `PollInterval`, exactly like `SprintService` owns `Stamina`, from actual
HRP velocity + authoritative sprint state; zeroes it for `InSafeRoom`/`Won`/`RespawnGrace`);
`MonsterService` becomes a `SPECIES` dispatch table (`{fsm, cfg}` per type), discovers
`MonkeySpawn`, stores `fsm`/`cfg`/`species` per rig, attaches each player's `NoiseLevel` +
`effectiveNoise` to the monkey's sensed set, reuses the mover/catch/anti-camp paths. Rig builder
handles the monkey body (primitives, or one `generate_mesh` — **never `insert_asset`**).
**Studio content:** place ≥1 `MonkeySpawn` marker in a different region than `MonsterSpawn`.

**Verify:** set a `MonkeySpawn` and play — the monkey perches (`Patrol`), wakes to `Alert` when
you sprint (facing you), `Investigate`-rushes the noise, lunges to `Chase`+catch with eyes on you
at close range; **going quiet drops it back**; walking+light-off never wakes it (below threshold);
SafeRoom silences you. Bunny untouched. Re-run the pathfinding gate (monkey `BodySize`/`AgentRadius`
≤ bunny → corridor fit identical). Capture the bunny+monkey pincer.

**Definition of done:** both monsters run independently with their counters working; the noise
model is unspoofable (server-owned inputs only); lint clean; saved.

### Phase 5 — Monkey locomotion

**What changes:** `Gaits.monkey` (the 4-beat gait, §2.3); `MonsterRig` builds the monkey's
jointed limbs; `MonsterAnimController` already dispatches on `Species` → applies `Gaits.monkey`.

**Verify:** mid-chase capture — the monkey knuckle-walks/gallops (limbs cycle, stride matches
travel, torso bob+roll, tail counter-sway), idle hunch when perched, faster gait in `Chase`. Rig
doesn't tip (Massless/CanCollide asserted on every limb).

**Definition of done:** both species walk like real creatures; physics unchanged; lint clean; saved.

### Phase 6 — Presentation packs (graphics + audio)

Ship as small PRs in this order: **Pack A** (Future + flashlight shadows + monster material +
jumpscare eyes), **Pack B** (`ChaseFXController` + eye-glow wash + `CameraController` FOV/bob),
**Audio Pack** (chase bed + occlusion + behind-breath + per-type audio table + haptics). Add
`Config.Perf` shadow/particle budget *with* Future (Future demands the budget). All render-only
off existing signals.

**Verify:** `inspect_instance` confirms `Technology=Future`; flashlight casts a corridor shadow;
chase grade tweens in and **back to neutral** on give-up; chase bed ducks under the scream;
occluded monster audio muffles then clears on the corner; framerate holds with the shadow budget.

**Definition of done:** each pack visibly elevates without touching authority; grade restores on
give-up; perf holds; lint clean; saved.

### Phase 7 — Readability + interactivity

`ThreatIndicatorController` (chase-only danger arrow), HUD `NoiseLevel` meter,
stamina/heartbeat tightening. **Verify:** danger arrow appears only while hunted and never reveals
a patrolling monster; the noise meter tracks sprint/quiet; heartbeat rises at low stamina.
**Definition of done:** the monkey's counter is teachable from the HUD; lint clean; saved.

---

## 7. Out of scope / future

- **Hiding spots, closeable/barricadable doors, throwable noise lures, hold-to-grab keys,
  AmbushNode scares, flashlight-as-deterrent** — each a strong loop-deepener (Research 4 Tier
  2–3) but each needs a new validated client→server remote and its own spatial service; deferred
  to a later interactivity milestone, applying the `SprintIntent` hardening discipline each time.
- **Flashlight-noise contribution** (`FlashlightStateIntent` + `Config.Noise.FlashlightNoise`) —
  the monkey ships on movement+sprint noise first (fully server-authoritative, zero remotes); add
  flashlight noise as a tuning pass only if the risk/reward needs more teeth.
- **AI-generated limbed hero meshes** (`generate_mesh`) replacing the primitive limbs — only after
  the procedural channel proves out; quality-checked, never `insert_asset`.
- **Real 2-bone IK foot-lock, squash/stretch via mesh-size**, per-species jumpscare framing,
  spectate-while-dead + co-op distant-scream, round-seed/replay determinism — polish backlog.
- **A third monster, navmesh no-go zones around SafeRooms, difficulty ramping** — later.
