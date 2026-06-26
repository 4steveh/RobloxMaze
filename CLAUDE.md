# RobloxMaze — Conventions

A maze **horror** game built with Rojo + Luau. This file is the contract every
change must follow. The architecture is deliberate — read this before editing,
and keep it accurate as systems grow.

---

## TL;DR — the rules that matter most

1. **Server-authoritative.** All contested / game-deciding state lives and is
   validated on the server. The client renders, captures input, plays local
   effects, and draws UI — nothing more.
2. **Detection is spatial, not touch-based.** The server decides occupancy and
   proximity by polling positions with `Spatial` helpers — never `Touched`.
3. **Tag-based discovery.** Find level objects via `Tags` + `Discovery`. Never
   hardcode instance paths or names.
4. **`Config` is the single source of truth.** No magic numbers live anywhere
   else — not in logic, not in UI.
5. **One system per module**, mapped per the layout below.
6. **Run StyLua and Selene before any change is considered done.**

---

## Toolchain (Rokit)

Tool versions are pinned in [`rokit.toml`](rokit.toml) and managed by
[Rokit](https://github.com/rojo-rbx/rokit) (the current official manager —
aftman/foreman are retired). Pinned here: `rojo`, `stylua`, `selene`.

```sh
rokit install        # install the exact pinned tool versions (run after cloning)
rokit add owner/repo # add a new tool at latest stable, pinning the resolved version
rokit update         # move pins forward to latest stable
```

`rokit` puts tool shims on your PATH (`~/.rokit/bin`); after `rokit install` the
commands below "just work" from the repo root.

---

## Everyday commands

```sh
rojo serve                                   # serve to the Studio plugin (this project: :34873 via servePort)
rojo build --output build.rbxlx              # build a place file (gitignored)
rojo sourcemap --include-non-scripts -o sourcemap.json   # refresh LSP sourcemap

stylua .                                     # format (writes changes)
stylua --check .                             # verify formatting (CI / pre-commit)
selene .                                     # lint
```

**Before considering ANY change done:** run `stylua .` and `selene .`. Both must
be clean (Selene: `0 errors, 0 warnings`). Regenerate `sourcemap.json` whenever
the instance tree changes so the Luau language server stays accurate.

A [`Makefile`](Makefile) wraps these (zero external deps — just the Rokit shims):
`make install` (tools + git hooks), `make fmt` / `make lint` / `make check`
(format + lint + build gate), `make serve` / `make build` / `make sourcemap`. A
versioned **pre-commit hook** ([`.githooks/pre-commit`](.githooks/pre-commit),
enabled by `make hooks`) blocks any commit that isn't StyLua-clean + Selene-clean.

**Code-sync fallback (when the Rojo plugin isn't connected):** `make serve-files`
serves the repo over `http://127.0.0.1:8777`, then paste
[`scripts/studio-sync.luau`](scripts/studio-sync.luau) into the Studio command bar
(Edit mode) to pull every `src/*.luau` into the place via `HttpService`. This is a
stopgap; the supported path is `rojo serve` + the plugin's **Connect**.

---

## Architecture

### Server-authoritative
All contested or game-deciding state — keys, win/lose, checkpoints, monster AI,
damage — lives and is validated on the **server**. The client only renders,
captures input, plays local effects, and draws UI.

In particular, **the server detects pickups and zone entry by spatial check**
(see below). The client never reports *"I collected this"* or *"I'm in the safe
room"* — that would be trivially exploitable. The client sends *intent* (e.g.
"I pressed the use key"); the server decides outcomes.

### The one deliberate client-side exception: flashlight battery
Flashlight battery is tracked **client-side**, because it is a single player's
personal, uncontested, latency-sensitive resource that no other player or server
system depends on. Draining it locally feels responsive, and cheating the battery
only hurts the cheater (less fear) — it cannot affect other players or the outcome.

**One seam to respect when you build it:** *drain* is fully local, but *recharge*
happens only inside a `SafeRoom`, and **SafeRoom occupancy is server-authoritative**
(decided by spatial check — the client must never self-report "I'm in the safe
room", per the rules below; otherwise it's free infinite light). So the battery
*value* stays on the client, while the recharge *gate* is authorized by the server
(it tells the client when occupancy is active / validates it). Keep that split:
local value, server-gated recharge.

**Rule for any future client-side state:** allow it *only if* it is **both**
(a) uncontested **and** (b) not exploitable in a way that affects other players
or the game outcome. If either fails, it belongs on the server.

### Detection is spatial, not touch-based
Occupancy ("is the player in this safe room?") and proximity ("is the player
close enough to this key / exit?") are decided by the **server** running
`Spatial` helpers against each player's `HumanoidRootPart.Position`, on the
`Config.Spatial.PollInterval` cadence:

- `Spatial.isInsidePart(part, position)` — point-in-oriented-box (handles rotation).
- `Spatial.withinRange(position, target, radius)` — distance to a point (center).
- `Spatial.distanceToPart(position, part)` — distance to the closest point on a part's
  oriented box (0 inside). Use this over `withinRange`-to-center for proximity to a
  large/thick part (e.g. the exit gate) so the trigger fires at the SURFACE, not at an
  unreachable center buried behind the part.

**Do not use `Touched` / `TouchEnded`** for occupancy or proximity — they are
unreliable (miss fast movers, fire spuriously, depend on physics ownership).

### Tag-based discovery
Never hardcode instance paths or names for level objects. Markers are placed in
Studio and found at runtime via `CollectionService` through `Discovery` + `Tags`:

- `Discovery.getAll(tag)` — every instance currently carrying `tag`.
- `Discovery.observe(tag, onAdded, onRemoved?)` — fires for existing instances
  and for any added/removed later; returns a cleanup function.

Code adapts to wherever the markers live. Every tag name comes from
[`Tags`](src/shared/Tags.luau) — never a raw string literal.

### `Config` is the single source of truth
Every tunable number lives in [`Config`](src/shared/Config.luau), grouped into
namespaced, frozen sections. **No magic numbers in logic.** UI that depends on a
count (e.g. key pips) reads the count from `Config` (`Config.Keys.RequiredToWin`)
rather than hardcoding it. New tunables get a named field and a comment.

---

## Project layout & naming

Rojo v7 mapping ([`default.project.json`](default.project.json)):

| Folder        | Roblox location                          | Holds            |
| ------------- | ---------------------------------------- | ---------------- |
| `src/server/` | `ServerScriptService`                    | server systems   |
| `src/client/` | `StarterPlayer.StarterPlayerScripts`     | client systems   |
| `src/shared/` | `ReplicatedStorage`                      | shared modules   |

File-extension → instance-class rules (Rojo):

| Extension       | Becomes       | Use for                |
| --------------- | ------------- | ---------------------- |
| `*.server.luau` | `Script`      | server entry points    |
| `*.client.luau` | `LocalScript` | client entry points    |
| `*.luau`        | `ModuleScript`| everything else (logic)|

**One system per module.** A module does one thing and exposes a small API.

---

## Shared module index (`src/shared/`)

| Module          | Purpose |
| --------------- | ------- |
| `Tags`          | Canonical CollectionService tag-name constants. The only place tag strings exist. |
| `Attributes`    | Canonical Instance attribute-name constants (per-player `Checkpoint`, `InSafeRoom`, `KeyCount`, `GameState`, `FlashlightBattery`, `RespawnGrace`, `Stamina`, `FlashlightOn`, `NoiseLevel`, `Downed`, `DownedUntil`, `ReviveProgress`; per-rig `Species`, `State`) — the `Tags` discipline applied to attributes. |
| `WorldFolders`  | Canonical names of the runtime Workspace container folders (`Monsters`, `Keys`, `PlayerSpawns`) the server builds and the client reads — the `Tags`/`Attributes` discipline applied to the folders that cross the server→client boundary. |
| `Config`        | Single source of truth for every tunable number (frozen sections). |
| `Enums`         | Enum-like constant tables (`GameState`; `MonsterType.{Bunny,Monkey}`; `MonsterState.{Patrol,Chase,Search,Alert,Investigate}`). |
| `Types`         | Shared Luau `export type` definitions. |
| `MonsterTypes`  | The FSM contract both monster brains share: `PlayerSense` (incl. `noise`), `Sensed`, `TickResult` (incl. `faceTarget`), and the common `FSMState` head (`name`, `targetUserId`) `MonsterService` reads. No shared base class — sibling pure FSMs behind one boundary, each taking its own `cfg`. |
| `Discovery`     | Thin `CollectionService` wrapper — `getAll`, `observe`. |
| `Spatial`       | Pure geometry — `isInsidePart`, `withinRange`, `distanceToPart`. |
| `Remotes`       | RemoteEvent registry under one ReplicatedStorage folder; fetch by name. Server→client cues (incl. `MonsterStateChanged`, `TrapTriggered`, `ExitOpened`), and the **client→server** remotes `SprintIntent` / `ShopAction` / `ThrowDecoy` (each validated + rate-limited server-side; payloads treated as hostile). |
| `PlayerUtil`    | Player-character helpers (e.g. `livingRootPart`) shared by the polling services. |
| `AudioGroups`   | Builds the SoundService `SoundGroup` bus tree (Master > Music/Ambient/Monster/SFX/UI) from `Config.Audio.Groups`; `get(name)` routes a Sound to a bus, `duck(name, …)` ducks one. The single home for audio routing/mix. |
| `Gaits`         | Pure procedural-gait recipes (one per monster species) → a map of joint (Part1) name to the `Motor6D.Transform` CFrame the client should write. No Instance work, no global time read (`clock` is passed in) — deterministic and unit-testable. The anti-glide math lives here. |
| `Maze`          | Pure runtime-maze generator: an iterative recursive-backtracker over a Cols×Rows grid → a SPANNING TREE of OPEN edges (connectivity guaranteed by construction). `generate`/`braid`/`floodReachable`/`allReachable`/`allEdges`. Edge ids (`V_c_r`/`H_c_r`) map to physical walls; the caller passes a seeded `Random` (deterministic, unit-testable like `Gaits`). No Instance work. |
| `Progression`   | Pure end-of-round coin math (`computeAward`): a round is never worth zero — participation floor + per-key + per-bonus-key + capped survival + escape (+ co-op-escape) bonus. No Instance/clock reads; weights from `Config.Economy` (unit-testable like `Spatial`). |
| `Cosmetics`     | The frozen cosmetic CATALOG (the only place cosmetic items are defined — the `Tags` discipline for shop items). Cosmetic-ONLY (never affect battery/range/detection), so the shop is never pay-to-win. Stable `id`s the DataStore remembers forever. |
| `Achievements`  | Pure milestone logic (`newlyEarned(stats, earned)` → the achievements a player just satisfied). No Instance/clock reads; thresholds/rewards from `Config.Achievements` (unit-testable like `Progression`). `StatsService` applies the result. |

## Systems (`src/server/`, `src/client/`)

| System | Side | Role |
| ------ | ---- | ---- |
| `GameBootstrap` | server | Skeleton sanity check: prints discovered marker counts on start. |
| `ServerSignals` | server | Server-only BindableEvent registry (the `Remotes` discipline for *in-server* events): one system broadcasts, others react, with no direct script-to-script calls. Carries `RoundReset` and `PlayerCaught` (a monster reached a player → `DownedService` decides down-vs-kill, keeping `MonsterService` out of player-life logic). |
| `MazeService` | server | Owns the RUNTIME MAZE (replayability): builds a permanent wall SUPERSTRUCTURE from code (one anchored wall per potential interior edge of the `Config.Maze` grid + the grid perimeter with the daycare-entrance and exit-gate gaps), then carves a fresh random spanning tree (`Maze.generate`) each round by SLIDING the "open" edges' walls into a well below the floor (CanCollide off) and raising the rest. **NEVER destroys a wall at runtime** — moving anchored parts re-rasterizes the navmesh reliably; destroying/creating them is the confirmed engine bug that strands the AI. Verifies each carve two ways (graph flood-fill + a real `PathfindingService:ComputeAsync` entrance→gate smoke test, retrying on failure), then fires `ServerSignals.MazeRebuilt`. Markers sit at CELL CENTRES (always open floor), so nothing is ever walled in; MonsterService's peace window covers the navmesh settle. `Config.Maze`. |
| `RoundService` | server | Owns the round lifecycle so the game LOOPS (it was single-shot: keys spawned once, a win latched forever). Watches for a win (a player's `GameState`→`Won`), holds `Config.Round.WinCelebrationSeconds`, then fires `ServerSignals.RoundReset`; Key/Exit/SafeRoom/Spawn/Monster services each react by resetting ONLY their own state (re-randomize keys, clear the win, clear checkpoints, respawn everyone at the start, reset the rigs). Shared round (first escape ends it for the lobby). Fires `ServerSignals.RoundEnded` first with each player's `{keys, escaped, survivalSeconds, coopEscapers, bonusKeys}` summary (EconomyService + StatsService consume it BEFORE the reset clears state). |
| `StatsService` | server | The lifetime-STATS + ACHIEVEMENTS owner. Reacts to `ServerSignals.RoundEnded` (same summaries EconomyService awards coins from): folds each into the player's persistent stats (`PlayerData.recordRound` → roundsPlayed/escapes/bonusKeys/fastest-escape/longest-survival; Escapes also mirrors to the `leaderstats` player-list), then runs the pure `Achievements.newlyEarned` — each newly-crossed `Config.Achievements` milestone is granted once (`grantAchievement`), paid a one-time coin reward (`PlayerData.award`, same economy path), and announced via the `AchievementUnlocked` remote. Stays out of the round COINS (EconomyService owns those). |
| `EnvironmentService` | server | Rebuilds the horror MOOD from code on boot (so a fresh build isn't flat/bright/fogless and the place content stays reproducible): sets `Lighting.Technology = Future` (real-time shadows → the flashlight throws creatures' shadows), the dark Ambient/exposure, and idempotently find-or-creates the `Atmosphere` haze + `Bloom` + `DepthOfField` + a base `ColorCorrection` ("BaseGrade") from `Config.Environment`. Never touches the client's "ChaseGrade". |
| `SafeRoomService` | server | Authority on "is this player safe" + their checkpoint. Polls each living HRP against `SafeRoom` parts with `Spatial`, fires `SafeRoomEntered`/`SafeRoomLeft`, and writes the `Checkpoint` attribute. |
| `SpawnService` | server | Single owner of the character lifecycle. Sets `Players.CharacterAutoLoads = false` and calls `LoadCharacter` itself. Gives each player a personal hidden `SpawnLocation` (their `RespawnLocation`, `Duration = 0` so no forcefield), moves it to the `Checkpoint` attribute, else a `PlayerStart` marker, and only then loads — so the character spawns deterministically *on* the pad with no origin flash, no Heartbeat reassert. On `Humanoid.Died` it waits `Config.Respawn.RespawnDelay`, then respawns the same way. Each spawn also grants `Config.Respawn.InvulnSeconds` of `RespawnGrace` (a visible ForceField; the monster ignores graced players) so a fresh character can't be instantly re-caught. |
| `KeyService` | server | Spawns the round's keys at a random subset of `KeySpot` markers; detects pickups by `Spatial.withinRange`. Keys are a **shared TEAM objective** (co-op): a pickup advances ONE team count mirrored onto every player's `KeyCount` (survives respawn) and fires `KeyCollected` to the whole lobby — so 2+ players can all reach `RequiredToWin` (per-player counts on a fixed shared pool locked everyone but one out). |
| `ExitService` | server | Win check **and the physical exit door**. Proximity to an `ExitDoor` is measured to its SURFACE (`Spatial.distanceToPart`, not center — a large gate can't make the win unreachable). With enough keys at the door → `GameState=Won`, freezes the player, fires `GameWon`, **slides the `ExitGate` open** + fires `ExitOpened` (lobby-wide door SFX + "X ESCAPED!" toast for non-winners); without enough → one-shot `ExitLocked`. Each `ExitGate` part stays shut + visibly LOCKED (red indicator light) until the team holds every key (indicator → green), and re-closes/re-locks on `RoundReset`. `Config.Exit`. |
| `MonsterService` | server | The monster ROSTER's owner. A `SPECIES` dispatch table maps each `Enums.MonsterType` → its `{ fsm, cfg, spawnTag }`; it builds a rig (via `MonsterRig`) at each species' spawn marker (`MonsterSpawn` for the bunny, `MonkeySpawn` for the monkey), stores each rig's `fsm`/`cfg`/`species`, and runs one species-agnostic loop. Each `Config.Spatial.PollInterval` it senses players (vision cone + LoS for SIGHT; per-player `effectiveNoise` = `NoiseLevel` × distance-falloff for HEARING; skipping `InSafeRoom`/`RespawnGrace`/`Won`), ticks that rig's pure FSM with its resolved `cfg`, drives `PathfindingService` movement (incl. a face-while-standing yaw for the monkey's Alert), writes the rig `State`, fires `MonsterStateChanged` to the hunted player, and per-rig `pcall`-isolates the tick. On a catch it stays OUT of player-life logic: it fires `ServerSignals.PlayerCaught` (DownedService decides down-vs-kill) and **resets the FSM + repels the rig home + goes dormant** (anti-spawn-camp, both species; the same `repelHome` runs on `RoundReset`). It also skips `Downed` players when sensing (no camping a downed body). Also applies an **aggression ramp** (`Config.Aggression`): monster speed + sense range scale up with how close any player is to winning (best `KeyCount`/`RequiredToWin`), so the hunt tightens as the round nears its end. |
| `MonsterRig` | server | The species-agnostic rig builder. `build(species, cfg, spawnPart, parent)` makes the identical PHYSICAL contract (invisible `HumanoidRootPart` `BodySize` box + invisible `Head` + `Humanoid` + `SetNetworkOwner(nil)`) plus the visible body, chosen by what `Assets.<BodyAssetName>` is: **(a) a multi-part mesh `Model`** (the AI-generated creature split into named parts: `Body`[torso] + `CHead` + `ArmL/ArmR` + `LegL/LegR`) → `buildPartsRig` AUTO-RIGS it — each limb gets a `Motor6D` pivoting at its shoulder/hip/neck (`partPivot` heuristic; rest pose = the generated pose), so the gait swings REAL mesh limbs (both the bunny mascot and the gorilla are this now); **(b) a single mesh** → one rigid `Body` on a `BodyJoint`; **(c) nothing** → the primitive-skeleton fallback. All cosmetic parts `Massless`/`CanCollide`/`CanQuery`/`CanTouch`-off. |
| `SprintService` | server | Server-authoritative sprint/stamina — the escape tool. Owns `Humanoid.WalkSpeed` and the `Stamina` attribute; the client sends only `SprintIntent` (the one client→server remote, **validated + rate-limited**). Skips `Won` players so it never fights the win-freeze. |
| `DecoyService` | server | Server-authoritative noise DECOY — noise as a WEAPON (not just a liability). On the `ThrowDecoy` intent (no payload) it computes the landing point from the player's OWN known position+facing (never a client position), clamps it to the first wall, spawns a rattling decoy part, and fires `ServerSignals.NoiseEvent` there so the near-blind monkey investigates the WRONG spot. Per-player cooldown + rate-limit. `Config.Decoy`. |
| `NoiseService` | server | Server-authoritative NOISE — the monkey's prey signal. Each `PollInterval` measures every player's ground speed from REPLICATED HRP position deltas (unspoofable) and writes a smoothed `NoiseLevel` (0..1): sprinting is loud, walking sits below the monkey's `HearThreshold` (safe), creeping is near-silent. Rises fast, decays slow (you must COMMIT to quiet). Zeroed in a SafeRoom/Won/RespawnGrace. No client input. |
| `TrapService` | server | Server-authoritative floor TRAPS (spatial poll, never Touched). Each `Tags.Trap` marker is FAIR: an always-visible red-arrow telegraph + a short **wind-up** after you enter it (you can back off in time), then it FIRES → `Humanoid.Health=0` (the checkpoint respawn, no jumpscare) AND spikes the victim's `NoiseLevel` (a sprung trap is loud → can draw the monkey). Skips InSafeRoom/Won/RespawnGrace; rearms after a cooldown. Fires `TrapTriggered` for the client FX. `Config.Traps`. |
| `DownedService` | server | Co-op rescue: turns a catch into a revivable **DOWNED** state (immobilized + bleeding out) instead of an instant respawn. **Gated by `Config.Downed.Enabled` (default FALSE → a catch is a reliable instant checkpoint respawn; flip on for the co-op revive flow once playtested with 2+ players).** Reacts to `ServerSignals.PlayerCaught`: if enabled and a teammate could save them → `down` (sets `Downed`/`DownedUntil`, **ANCHORS the HRP** so it freezes in place — NOT PlatformStand, whose ragdoll dropped/clipped players through the floor — fires `MonsterCaught` with `downed=true`); else (solo / full wipe / disabled) → the classic kill → checkpoint respawn. Each poll it bleeds out (→ death respawn) or, if a living teammate STAYS within `Config.Downed.ReviveRadius` for `ReviveSeconds` (spatial, server-authoritative — no client input), **revives** them with a brief grace. A fresh character clears the state. Single-player is unchanged (no rescuer → kill). `Config.Downed`. |
| `BunnyFSM` | server | Pure FSM (`newState`/`tick(state, sensed, cfg)`) for the bunny — the VISION stalker: Patrol (touring) → Chase → Search → give up, off the cone+LoS sense. No Instance side-effects (`MonsterService` applies it); the `cfg` slice is injected so species coexist. |
| `MonkeyFSM` | server | Pure FSM for the monkey — the near-blind NOISE hunter (inverse of the bunny). **Territorial: in Patrol it PACES within `NestWanderRadius` of its `sensed.homePosition` (the `MonkeySpawn` nest) -- it does NOT roam the maze like the bunny, so the two have different jobs and never shadow each other.** (Patrol/Investigate re-pick a fresh wander point on arrival OR after `WanderRepickSeconds` — a random point that lands inside a wall can never be "reached", so the timeout stops it wedging against the wall forever.) Patrol → **Alert** (heard you: freeze + face — the fair tell) → **Investigate** (erratic rush at the noise; leaves the nest) → Chase (eyes-on lunge) → catch; Search on losing the trail, then back to nest-pacing. Hears `effectiveNoise` through walls; sees only at short range to confirm a lunge. Counter: go QUIET. Same contract/`cfg`-injection as `BunnyFSM`. |
| `FlashlightController` | client | Camera-aimed `SpotLight` (Config-driven) toggled with `Config.Flashlight.ToggleKey` — bound via `ContextActionService` (`createTouchButton`) so touch devices get an on-screen **Light** button; client-side battery that drains while lit outside a safe room and recharges inside one (gate from server remotes). Publishes battery via `FlashlightBattery` and on/off via `FlashlightOn` for the HUD/SFX. |
| `HUDController` | client | Icon-forward HUD: key pips (count = `Config.Keys.RequiredToWin`), battery + stamina gauges, an exit arrow shown only once all keys are in, transient feedback toasts (`KEY n/3`, `EXIT LOCKED`), and a win overlay. Renders only. |
| `ObjectiveController` | client | Direction layer: spawn intro banner, a controls hint, and a persistent `KEYS n/3 → reach the EXIT` objective tracker (off `KeyCollected`). |
| `CompassController` | client | Wayfinding: a through-wall beacon over every live key (tag `ActiveKey`) plus an edge arrow to the nearest one. |
| `SprintController` | client | Sends the sprint held-state to `SprintService` as `SprintIntent` (changes no speed/stamina locally). Bound via `ContextActionService` with `createTouchButton`, so touch devices get an on-screen hold-to-sprint **Run** button while the keyboard key still works. |
| `DecoyController` | client | Sends the `ThrowDecoy` intent (no payload) on the decoy key + an on-screen **Decoy** touch button, and renders a local cooldown chip. `DecoyService` owns the throw entirely; this only captures input + shows cooldown. `Config.Decoy`. |
| `SprintFXController` | client | Sprint FOV kick: widens the camera FOV scaled by the character's REAL horizontal ground speed (0 at walk, full at sprint), so a server-authoritative sprint FEELS instant and fast and never lies when out of stamina. Render-only client cosmetic (the FlickerController-class exception); `Config.Player.SprintFovKick`. |
| `FlickerController` | client | Makes `FlickerLight` fixtures (and their `ShaftBeam` light shafts) flicker like failing fluorescents. Renders only. |
| `MonsterAudioController` | client | 3D breathing/footsteps on each rig, a distance-scaled heartbeat, and a Patrol→Chase sting (off `MonsterStateChanged`). |
| `MonsterAnimController` | client | **Procedural creature locomotion (the no-glide fix).** Observes `Workspace.Monsters`; per rig reads the replicated root speed + `State`/`Species` and, on `RunService.PreSimulation`, writes each cosmetic `Motor6D.Transform` from that species' `Gaits` recipe so the creatures move with REAL articulated mesh limbs — the **bunny** does a bipedal hop (both legs extend/tuck, arms swing, head bob, gentle torso arc), the **monkey** a quadruped gallop (front/rear limb pairs swing a half-cycle apart, subtle torso bob/roll) — with cadence locked to actual ground speed. No Animator, render-only, zero bandwidth — the FlickerController-class client cosmetic CLAUDE.md permits. |
| `ChaseFXController` | client | **The hunt as a visual event.** Each frame finds the nearest monster hunting THIS player (rig `State` Chase/Investigate, softer on Alert) + its distance (replicated, exploit-safe) and drives a DEDICATED `ColorCorrectionEffect` (desaturate + red wash), a closing edge vignette, a heartbeat pulse, and a flare of that monster's eye-glow. Fades back to neutral on escape. Its own CC instance, so the static place grade is untouched. |
| `NoiseMeterController` | client | HUD noise meter — teaches the monkey's counter. Renders the server-authoritative `NoiseLevel` as a bar with a fixed marker at the monkey's `HearThreshold`: below it you're inaudible (green), cross it (sprint/run) and it flips red + pulses ("the monkey can hear you"). Render-only. |
| `TrapFXController` | client | Trap telegraph + fire FX off `TrapTriggered`: the wind-up pulse (the red arrow + glow flash bright + a click — the reaction window) and the fire effect (a dart streaks along the trap's facing + a thunk + impact flash). The static red-arrow telegraph itself is placed geometry. Render-only. |
| `AmbientController` | client | Looped drone/room-tone beds, the intermittent 3D music-box motif on the `MusicBoxEmitter` statue, and reverb switched by SafeRoom occupancy. |
| `PlayerSFXController` | client | Footsteps timed to movement, the flashlight toggle click (off `FlashlightOn`), and a low-battery beep. |
| `StingerController` | client | One-shot stingers wired to existing remotes: key chime, locked-door thunk, win jingle (ducks the beds). |
| `JumpscareController` | client | On `MonsterCaught`: a scream (ducking every bus), a full-screen `ViewportFrame` close-up of the live monster mesh lunging with shake, a red flash. Branches on the `downed` payload: killed → the `CAUGHT!` headline + respawn countdown; grabbed-into-downed → a SHORT scare only (no countdown), so `DownedController`'s bleedout/revive HUD reads underneath. |
| `DownedController` | client | The downed/revive HUD (render-only off the `Downed`/`DownedUntil`/`ReviveProgress` attributes): when YOU are downed, a wash + `DOWNED` + a shrinking bleedout bar + a filling revive bar; when a TEAMMATE is downed, a world-space `REVIVE` beacon over them with a revive bar. No input — revive is server-authoritative spatial. |
| `TutorialController` | client | Just-in-time onboarding: the first time a monster CHASES you it teaches sprint + breaking line of sight; the first time one is ALERT (the monkey heard you) it teaches going quiet. Each tip fires once, driven by `MonsterStateChanged`. Render-only; `Config.Onboarding`. |
| `AtmosphereFXController` | client | **Ambient dust** drifting in the air — the cheapest, highest-impact horror-atmosphere tell. One world-locked `ParticleEmitter` in an invisible volume that follows the camera; with `LightInfluence` on, the motes only really read where a light touches them, so they GLINT IN THE FLASHLIGHT BEAM down a dark corridor. Render-only, decides nothing — the FlickerController-class cosmetic; `Config.AtmosphereFX`. |
| `MonsterPresenceFXController` | client | **Makes the creatures feel physical.** Per rig (observes `Workspace.Monsters` like `MonsterAnimController`) attaches two client-only emitters: foot dust whose rate scales with the rig's replicated ground speed (a sprinting hunter churns up a trail), and breath fog from the head that pants faster while hunting. Reads only replicated position/`State`; creates only LOCAL instances. Render-only; `Config.MonsterFX`. |
| `CameraShakeController` | client | **The threat you FEEL.** A continuous tremble scaled by the nearest hunting monster's proximity (same exploit-safe threat model as `ChaseFXController`) plus sharp one-shot impulses on discrete scares (a trap firing near you off `TrapTriggered`, being caught off `MonsterCaught`). Binds AFTER the camera update (`RenderPriority.Camera + 1`) and post-multiplies the camera CFrame so it layers on any camera mode. Kept small — felt, never nauseating. Render-only; `Config.CameraShake`. |

**Cross-script state:** server systems share per-player state through Player
attributes named in `Attributes` (e.g. the checkpoint `CFrame`) — never globals
or direct script-to-script calls. Server→server *events* (e.g. the round lifecycle)
go through `ServerSignals` (a server-only BindableEvent registry, the `Remotes`
discipline applied in-server) — a broadcast others react to, still not a direct call.
The client learns safe-room state only from the `SafeRoomService` remotes; it never
detects safe rooms itself.

---

## Type-checking policy

Set the mode on the **first line** of every script.

- `--!strict` for self-contained logic with little/no Instance API surface:
  `Config`, `Enums`, `Types`, `Spatial`, `Discovery`.
- `--!nonstrict` where code is heavy on Roblox Instance APIs (instance creation,
  service plumbing, RemoteEvents) and strict mode would mostly produce false
  positives: `Remotes`, `*.server.luau` / `*.client.luau` entry points.

**Do not litter `:: SomeType` casts to silence the checker.** If strict mode
fights you on genuine Instance-API code, that module belongs in `--!nonstrict`.

---

## Linting notes (Selene)

`selene.toml` uses `std = "roblox"` with `roblox-std-source = "pinned"`, reading
the committed [`roblox.yml`](roblox.yml). This makes linting deterministic and
network-free (clean checkouts, CI). When you start using a newly-added Roblox
API that Selene flags as undefined, refresh and commit the std:

```sh
selene generate-roblox-std   # rewrites roblox.yml; commit it
```

---

## Forward patterns (decided now, built later)

- **Monsters are finite state machines**, each implemented as a module (one FSM
  per monster type). `Enums.MonsterType` / `Enums.MonsterState` are the stubs.
- **RemoteEvents are validated server-side and used sparingly.** Register names
  in `Remotes`, never create ad-hoc remotes. Treat every client→server payload
  as hostile: validate it on the server.
- **`Config` grows by section** (`Config.Monster`, `Config.Audio`, …), never by
  scattering numbers into systems.
## Roblox workflow (machine-wide skill: ~/.claude/skills/roblox-workflow)
This repo follows the roblox-workflow personal skill for source-of-truth, verify, and build-loop rules.
Filesystem (via Rojo) is the source of truth for scripts; do not hand-edit scripts in Studio while Rojo serves.
TARGET CHECK: multiple Studios may be open on one shared proxy — confirm set_active_studio is the intended game
before any mutating call (execute_luau, multi_edit, insert_asset, upload_image, generate_*).
SECURITY TRIPWIRE: never insert_asset (marketplace asset by ID) without first script_read-ing and scanning every
contained script for obfuscation, remote require(), HttpService, loadstring, getfenv — then get explicit approval.
Never run execute_luau touching credentials, real DataStores, or publishing APIs without confirmation.
