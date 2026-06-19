# The Bunny — Monster MVP Design

- **Date:** 2026-06-19
- **Status:** Approved (design); pending implementation plan
- **Depends on:** the deterministic SpawnLocation respawn (commit `0cd961e`) — the catch cashes in that loop.

---

## 1. Goal

Introduce the game's first monster — "the bunny" — turning the walkable slice into a
horror loop: a server-authoritative stalker that hunts the player through the maze,
and on catching them triggers the death → jumpscare → respawn-at-checkpoint loop that
was just hardened. Catch-and-respawn becomes the core gameplay.

This is an **MVP**: one bunny, one monster type, a procedural placeholder rig, built and
tested in a throwaway greybox maze. The architecture must not preclude multiple monsters
or types later, but we ship exactly one.

---

## 2. Gameplay design (the four pillars)

Decided during brainstorming:

1. **Behaviour: patrol → chase → search → give up.** A classic stalker FSM. It wanders
   fixed patrol routes; on detecting the player it chases; if it loses them it searches
   the last-seen area, then gives up and resumes patrolling. Rewards hiding and breaking
   line of sight.
2. **Detection: vision cone + line of sight.** It sees the player only inside a
   forward-facing cone, within range, with no wall blocking the ray. You can sneak behind
   it or duck behind a wall to escape. Positioning and maze geometry are the gameplay.
3. **Chase: faster than the player — escape only by breaking sight.** It outpaces you in a
   straight line, so you cannot simply outrun it; you must round corners and break its
   line of sight to drop it into Search, then hide.
4. **Catch: instant → respawn.** Closing within catch range kills the player on the spot.
   The death fires the jumpscare during `Config.Respawn.RespawnDelay`, then the player
   respawns at their last SafeRoom checkpoint with keys intact. No health/damage system.

### SafeRoom sanctuary rule

SafeRooms are refuges during a hunt. **Detection skips any player whose `InSafeRoom`
attribute is `true`** (that attribute already exists, server-set by `SafeRoomService`) —
such a player is removed from the bunny's sensed set entirely. Because the chased target
then *vanishes from the sensed set* (as opposed to merely going out of sight behind a wall,
where it is still sensed with `visible = false`), the bunny **drops to Search immediately**
— no grace window. That is the difference that makes a SafeRoom an instant sanctuary while
rounding a corner only buys you the `LoseSightSeconds` grace. For the MVP we do **not** add
navmesh no-go zones: the bunny may physically wander into a SafeRoom but cannot see or catch
a player there, and leaves once it has no target. Barring it from SafeRoom volumes entirely
is deferred.

---

## 3. Build order

PathfindingService needs walkable geometry before any AI can be built or tested, and there
is no hunt-and-hide in a void. So:

1. **Greybox test maze** (Studio content) — first.
2. **The bunny** (code) — second.

---

## 4. The greybox maze

Throwaway scaffolding whose only jobs are to give the navmesh something to path around and
make hunt-and-hide real. Gray boxes only — no art, no meshes.

- A single floor, roughly **120×120 studs**, with perimeter walls and internal walls forming
  a **simple branching layout: a few corridors, 2–3 dead ends, and at least one loop**. The
  loop is required — breaking line of sight and circling back is the core counterplay.
- All parts anchored; walls `CanCollide = true` so they block both the player and the navmesh.
- The existing markers are **repositioned out of the current void into the maze**:
  `PlayerStart` near one corner, `SafeRoom` off a corridor, the 5 `KeySpot`s spread down
  corridors and dead ends, `ExitDoor` at the far end.
- Add **~4–6 `PatrolPoint` markers** along the corridors and **one `MonsterSpawn`** deeper in.
- Generated programmatically via the Studio MCP (`execute_luau`) for reproducibility, then the
  place is **saved** (Workspace is not Rojo-synced).

When the real maze is built later, the same markers drop into it and no bunny code changes.

---

## 5. Architecture & components

Server-authoritative; one FSM per monster type, per CLAUDE.md. The client only renders and
plays the local jumpscare effect.

### `MonsterService.server.luau` (owner / entry point)

- Discovers `MonsterSpawn` markers via `Discovery`; spawns one bunny rig per marker (MVP
  expects one).
- Owns each instance's runtime state and runs the tick loop on **`Config.Spatial.PollInterval`**
  — the same server-poll discipline as `SafeRoomService` / `KeyService`.
- Each tick: gathers sensed inputs (living player positions, line-of-sight raycasts, patrol
  nodes, dt), calls `BunnyFSM.tick`, then **applies** the result — moves the rig along a
  `PathfindingService` path toward the returned target, writes the rig's `State` attribute,
  and on a catch sets the target's `Humanoid.Health = 0` (handing off to the existing
  SpawnService death → `RespawnDelay` → respawn loop) and fires the `MonsterCaught` remote.
- Owns all `PathfindingService` use (`CreatePath`, `ComputeAsync`, waypoint following).

### `BunnyFSM.luau` (server module — pure decision logic)

- One `tick(state, sensed)` function returning: next state, a movement intent (target
  position to path toward), and whether a catch occurred.
- **No Instance side-effects inside** — it reads sensed inputs and returns decisions;
  `MonsterService` performs all world mutation. This keeps the AI isolated and testable and
  respects "one system per module".

### The rig (procedural placeholder — no art assets)

- A **valid** procedural `Humanoid` rig — the minimum that actually walks: a `HumanoidRootPart`
  body part, a welded `Head` part, and a `Humanoid` with `RequiresNeck = false` and an explicit
  `HipHeight` (a bare 1-part rig with no `Head`/`HipHeight` spawns dead and won't `MoveTo`). It
  is moved along `PathfindingService` waypoints via `Humanoid:MoveTo`, and its `PrimaryPart`
  network ownership is pinned to the server (`SetNetworkOwner(nil)`) so server-driven movement
  isn't handed to a client. No art assets — `Config.Monster.Body*` placeholders, swapped later.
- Carries its current FSM `State` as an **attribute**, purely so the playtest can read what it
  is doing.

---

## 6. FSM states & transitions

States map to `Enums.MonsterState.{Patrol, Chase, Search}`. Ticked each poll interval.

- **Patrol** — pathfinds between `PatrolPoint` nodes; on reaching one it picks the nearest
  node it has **not** visited in the last `PatrolMemory` hops (falling back to the nearest
  other node if all are recent), so it tours the maze instead of ping-ponging between two
  points. Runs detection against each living player every tick. Any detected → **Chase**
  (target = closest detected player).
- **Chase** — while the target is in sight, paths to the player's *live* position at
  `ChaseSpeed`. Each tick re-checks sight and catch range:
  - within `CatchRadius` of the target → **catch** (see §8);
  - target **gone from the sensed set** (entered a SafeRoom, died, won, or left) →
    **Search immediately** (no grace);
  - target still sensed but **not visible** (behind a wall) → keep heading to the
    **last-seen position**; if it stays broken for `LoseSightSeconds` → **Search**.
- **Search** — moves to the last-seen position, then wanders/looks around within
  `SearchWanderRadius` for `SearchDuration`. Re-detects a player → **Chase**; timer expires →
  **Patrol** (resume nearest node).

---

## 7. Detection model (vision cone + line of sight)

Per tick, per living player — **all three** must hold for the player to be "detected":

1. **Range:** distance(rig, player) ≤ `DetectRange`.
2. **Cone:** angle between the rig's facing (`HumanoidRootPart.CFrame.LookVector`) and the
   direction to the player ≤ `DetectHalfAngle`.
3. **Line of sight:** a raycast from the rig's eye (`HumanoidRootPart.Position + EyeHeight`
   studs up) toward the player's `HumanoidRootPart`, with length equal to that distance and a
   filter excluding the rig's own model and **all** player characters. If the ray hits nothing
   over that distance, line of sight is clear; only world geometry remains in the filter, so any
   hit means a wall is blocking. (Excluding the players keeps the target's own body from
   registering as the "blocker" at the ray's end.)

Players with `InSafeRoom == true` or `GameState == "Won"` are skipped entirely (never
detected, never caught). When multiple players are detected, the **closest** is the target
(co-op-ready).

---

## 8. Catch → respawn handoff

A catch occurs when the rig is within `CatchRadius` of its current target. On catch,
`MonsterService`:

1. Sets the target's `Humanoid.Health = 0`. This fires `Humanoid.Died`, which the existing
   `SpawnService` handles: wait `Config.Respawn.RespawnDelay`, then respawn at the player's
   checkpoint (last SafeRoom) with `KeyCount` intact.
2. Fires `Remotes.Names.MonsterCaught` to that client so the client plays the local jumpscare
   effect during the `RespawnDelay` window.

No new death/respawn logic — the catch reuses the deterministic loop verified in the prior
milestone. The client jumpscare rendering is a client-only effect (placeholder for now;
asset/sound wiring is a later pass).

---

## 9. Shared registry additions

Everything slots into the existing single-source registries — no stray strings or numbers.

- **`Enums.MonsterType`:** add `Bunny = "Bunny"`.
- **`Enums.MonsterState`:** add `Patrol`, `Chase`, `Search`.
- **`Tags`:** reuse the existing `MonsterSpawn` and `PatrolPoint` stubs (no new tags).
- **`Remotes`:** add `MonsterCaught` (server → client: this player was caught; play the
  jumpscare). Registered in `Names` and `REMOTE_EVENTS`.
- **`Attributes`:** none new required for the MVP. The rig's observability attributes
  (`State`, etc.) live on the rig instance, not on players, and are set with literal names
  local to `MonsterService` (they are debug/observability, not cross-system contracts). If a
  cross-system per-player flag is later needed (e.g. a "being chased" HUD state), it gets a
  named constant in `Attributes` then.
- **`Config.Monster`:** new frozen section (values in §10).

---

## 10. `Config.Monster` values

Indicative starting values (all tunable), grounded in the player default `WalkSpeed = 16`:

| Field | Value | Meaning |
| --- | --- | --- |
| `PatrolSpeed` | 10 | studs/s while patrolling (slower, wandering) |
| `ChaseSpeed` | 21 | studs/s while chasing (faster than the player) |
| `DetectRange` | 50 | studs: max distance it can see |
| `DetectHalfAngle` | 45 | degrees: half the vision cone (→ 90° cone) |
| `EyeHeight` | 2 | studs above HRP: LoS ray origin |
| `LoseSightSeconds` | 3 | seconds of broken sight before giving up the live trail → Search |
| `SearchDuration` | 6 | seconds spent searching last-seen before giving up → Patrol |
| `SearchWanderRadius` | 12 | studs it pokes around the last-seen point |
| `CatchRadius` | 5 | studs: distance to the target that counts as a catch |
| `RepathInterval` | 0.4 | seconds between path recomputations during a chase |
| `AgentRadius` | 2 | `CreatePath` agent radius (fit corridors) |
| `AgentHeight` | 5 | `CreatePath` agent height |
| `WaypointReachedDistance` | 4 | studs: advance to the next path waypoint |
| `PatrolMemory` | 2 | patrol nodes remembered as "recently visited" (so it tours, not ping-pongs) |
| `StallEpsilon` | 0.5 | studs: movement below this per tick counts as "not moving" |
| `StallTicks` | 10 | consecutive stalled ticks (with a target) that force a repath |
| `BodySize` | `Vector3.new(2.5, 3.5, 2.5)` | placeholder rig body dimensions, studs |
| `BodyColor` | `Color3.fromRGB(220, 218, 225)` | placeholder rig tone (pale, faintly sickly) |

(`BodySize`/`BodyColor` follow the same spirit as the existing `Config.KeyModel` placeholders —
a simple block in a desaturated tone, no asset IDs; swapped for a real model/mesh later.)

---

## 11. Edge cases / error handling

Mirrors the warn-once discipline already in `SpawnService`:

- **No `MonsterSpawn` marker** → no bunny spawns; warn once.
- **No `PatrolPoint` markers** → the bunny idles / wanders near its spawn; warn once.
- **`PathfindingService` failure / no path** (target in an unreachable nook) → fall back to
  steering directly toward the target for that tick; retry on the next repath; never error the
  tick loop.
- **Target dies / respawns / leaves / wins / enters a SafeRoom mid-chase** → it drops out of
  the sensed set, so the bunny gives up **immediately** → Search → Patrol. This is distinct
  from breaking line of sight behind a wall (target still sensed, `visible = false`), which
  only burns the `LoseSightSeconds` grace. New `InSafeRoom`/`GameState` attributes that are
  `nil` for a brand-new player are intentionally treated as eligible (not-safe / not-won).
- **Rig stalls** (moves < `StallEpsilon` for `StallTicks` consecutive ticks while it has a
  movement target) → force a repath, so a bunny wedged on a corner recovers.

---

## 12. Server authority & data flow

- All AI, detection, movement, and the catch decision are **server-side**, on the poll cadence.
- The client receives the rig via normal replication (it is a model in Workspace) and the
  single `MonsterCaught` remote; it renders the rig and plays the local jumpscare. It never
  decides detection or catches.
- The catch routes through `Humanoid.Health = 0` → `SpawnService` → the verified respawn loop.

---

## 13. Testing plan

Driven via the Studio MCP in the greybox, with the same per-run-evidence rigor used for the
respawn test — read the rig's `State` attribute and positions, plus screen captures:

1. **Patrol:** rig cycles `PatrolPoint`s; `State = Patrol`.
2. **Detect → chase:** drive the player into the cone with LoS → `State = Chase`; it closes on
   the player; observed speed > player speed.
3. **Cone works:** approach from behind (outside the cone) → not detected.
4. **LoS works:** stand close but behind a wall → not detected.
5. **Break sight:** interpose a wall mid-chase → after `LoseSightSeconds`, `State = Search` at
   last-seen → `Patrol` after `SearchDuration`.
6. **Catch:** let it reach the player → `Health = 0` → `MonsterCaught` fires → respawn at the
   checkpoint with keys intact.
7. **SafeRoom sanctuary:** get chased, dive into the SafeRoom → it loses the target and cannot
   catch while `InSafeRoom = true`.

---

## 14. Out of scope (YAGNI for the MVP)

Clean later additions; deliberately excluded now:

- Multiple bunnies / additional monster types (the architecture allows them; ship one).
- Navmesh no-go zones around SafeRooms.
- Audio / music stings and a "being chased" HUD state (a later `Config.Audio` / HUD pass).
- Rig art, meshes, and animation (procedural placeholder only).
- Difficulty ramping, multiple/branching patrol routes, monster memory beyond last-seen.

---

## 15. Definition of done

- Greybox maze exists, is walkable, holds the repositioned markers + `PatrolPoint`s +
  `MonsterSpawn`, and the place is saved.
- `MonsterService` + `BunnyFSM` + the procedural rig implemented; `Enums`, `Remotes`,
  `Config.Monster` extended; CLAUDE.md updated with the new systems and shared additions.
- StyLua and Selene clean.
- All 7 test-plan checks pass in the greybox via the Studio MCP, with per-run evidence.
