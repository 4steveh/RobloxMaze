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
- `Spatial.withinRange(position, target, radius)` — distance check.

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
| `Attributes`    | Canonical Instance attribute-name constants (per-player `Checkpoint`, `InSafeRoom`, `KeyCount`, `GameState`, `FlashlightBattery`, `RespawnGrace`, `Stamina`, `FlashlightOn`, `NoiseLevel`; per-rig `Species`) — the `Tags` discipline applied to attributes. |
| `Config`        | Single source of truth for every tunable number (frozen sections). |
| `Enums`         | Enum-like constant tables (`GameState`; `MonsterType.{Bunny,Monkey}`; `MonsterState.{Patrol,Chase,Search,Alert,Investigate}`). |
| `Types`         | Shared Luau `export type` definitions. |
| `MonsterTypes`  | The FSM contract both monster brains share: `PlayerSense` (incl. `noise`), `Sensed`, `TickResult` (incl. `faceTarget`), and the common `FSMState` head (`name`, `targetUserId`) `MonsterService` reads. No shared base class — sibling pure FSMs behind one boundary, each taking its own `cfg`. |
| `Discovery`     | Thin `CollectionService` wrapper — `getAll`, `observe`. |
| `Spatial`       | Pure geometry — `isInsidePart`, `withinRange`. |
| `Remotes`       | RemoteEvent registry under one ReplicatedStorage folder; fetch by name. Server→client cues plus `MonsterStateChanged`, and the one **client→server** remote `SprintIntent` (validated + rate-limited server-side). |
| `PlayerUtil`    | Player-character helpers (e.g. `livingRootPart`) shared by the polling services. |
| `AudioGroups`   | Builds the SoundService `SoundGroup` bus tree (Master > Music/Ambient/Monster/SFX/UI) from `Config.Audio.Groups`; `get(name)` routes a Sound to a bus, `duck(name, …)` ducks one. The single home for audio routing/mix. |
| `Gaits`         | Pure procedural-gait recipes (one per monster species) → a map of joint (Part1) name to the `Motor6D.Transform` CFrame the client should write. No Instance work, no global time read (`clock` is passed in) — deterministic and unit-testable. The anti-glide math lives here. |

## Systems (`src/server/`, `src/client/`)

| System | Side | Role |
| ------ | ---- | ---- |
| `GameBootstrap` | server | Skeleton sanity check: prints discovered marker counts on start. |
| `SafeRoomService` | server | Authority on "is this player safe" + their checkpoint. Polls each living HRP against `SafeRoom` parts with `Spatial`, fires `SafeRoomEntered`/`SafeRoomLeft`, and writes the `Checkpoint` attribute. |
| `SpawnService` | server | Single owner of the character lifecycle. Sets `Players.CharacterAutoLoads = false` and calls `LoadCharacter` itself. Gives each player a personal hidden `SpawnLocation` (their `RespawnLocation`, `Duration = 0` so no forcefield), moves it to the `Checkpoint` attribute, else a `PlayerStart` marker, and only then loads — so the character spawns deterministically *on* the pad with no origin flash, no Heartbeat reassert. On `Humanoid.Died` it waits `Config.Respawn.RespawnDelay`, then respawns the same way. Each spawn also grants `Config.Respawn.InvulnSeconds` of `RespawnGrace` (a visible ForceField; the monster ignores graced players) so a fresh character can't be instantly re-caught. |
| `KeyService` | server | Spawns the round's keys at a random subset of `KeySpot` markers; detects pickups by `Spatial.withinRange`; tracks each player's `KeyCount` (survives respawn); fires `KeyCollected`. |
| `ExitService` | server | Win check: at an `ExitDoor` with enough keys → sets `GameState=Won`, freezes the player, fires `GameWon`; at the door without enough → one-shot `ExitLocked`. |
| `MonsterService` | server | The monster ROSTER's owner. A `SPECIES` dispatch table maps each `Enums.MonsterType` → its `{ fsm, cfg, spawnTag }`; it builds a rig (via `MonsterRig`) at each species' spawn marker (`MonsterSpawn` for the bunny, `MonkeySpawn` for the monkey), stores each rig's `fsm`/`cfg`/`species`, and runs one species-agnostic loop. Each `Config.Spatial.PollInterval` it senses players (vision cone + LoS for SIGHT; per-player `effectiveNoise` = `NoiseLevel` × distance-falloff for HEARING; skipping `InSafeRoom`/`RespawnGrace`/`Won`), ticks that rig's pure FSM with its resolved `cfg`, drives `PathfindingService` movement (incl. a face-while-standing yaw for the monkey's Alert), writes the rig `State`, fires `MonsterStateChanged` to the hunted player, and per-rig `pcall`-isolates the tick. On a catch: `Humanoid.Health = 0`, fires `MonsterCaught`, then **resets the FSM + repels the rig home + goes dormant** (anti-spawn-camp, both species). |
| `MonsterRig` | server | The species-agnostic rig builder. `build(species, cfg, spawnPart, parent)` makes the identical PHYSICAL contract (invisible `HumanoidRootPart` `BodySize` box + invisible `Head` + `Humanoid` + `SetNetworkOwner(nil)`) plus the visible body: a single mesh `Body` on a `BodyJoint` (the bunny) **or** an articulated primitive skeleton when no mesh exists (the monkey — torso `Body` + `CHead` + `ArmL/ArmR` + `LegL/LegR` + `Tail`, each on its own cosmetic `Motor6D`). All cosmetic parts `Massless`/`CanCollide`/`CanQuery`/`CanTouch`-off. |
| `SprintService` | server | Server-authoritative sprint/stamina — the escape tool. Owns `Humanoid.WalkSpeed` and the `Stamina` attribute; the client sends only `SprintIntent` (the one client→server remote, **validated + rate-limited**). Skips `Won` players so it never fights the win-freeze. |
| `NoiseService` | server | Server-authoritative NOISE — the monkey's prey signal. Each `PollInterval` measures every player's ground speed from REPLICATED HRP position deltas (unspoofable) and writes a smoothed `NoiseLevel` (0..1): sprinting is loud, walking sits below the monkey's `HearThreshold` (safe), creeping is near-silent. Rises fast, decays slow (you must COMMIT to quiet). Zeroed in a SafeRoom/Won/RespawnGrace. No client input. |
| `BunnyFSM` | server | Pure FSM (`newState`/`tick(state, sensed, cfg)`) for the bunny — the VISION stalker: Patrol (touring) → Chase → Search → give up, off the cone+LoS sense. No Instance side-effects (`MonsterService` applies it); the `cfg` slice is injected so species coexist. |
| `MonkeyFSM` | server | Pure FSM for the monkey — the near-blind NOISE hunter (inverse of the bunny). Patrol → **Alert** (heard you: freeze + face — the fair tell) → **Investigate** (erratic rush at the noise) → Chase (eyes-on lunge) → catch; Search on losing the trail. Hears `effectiveNoise` through walls; sees only at short range to confirm a lunge. Counter: go QUIET. Same contract/`cfg`-injection as `BunnyFSM`. |
| `FlashlightController` | client | Head-parented `SpotLight` (Config-driven) toggled with `Config.Flashlight.ToggleKey`; client-side battery that drains while lit outside a safe room and recharges inside one (gate from server remotes). Publishes battery via `FlashlightBattery` and on/off via `FlashlightOn` for the HUD/SFX. |
| `HUDController` | client | Icon-forward HUD: key pips (count = `Config.Keys.RequiredToWin`), battery + stamina gauges, an exit arrow shown only once all keys are in, transient feedback toasts (`KEY n/3`, `EXIT LOCKED`), and a win overlay. Renders only. |
| `ObjectiveController` | client | Direction layer: spawn intro banner, a controls hint, and a persistent `KEYS n/3 → reach the EXIT` objective tracker (off `KeyCollected`). |
| `CompassController` | client | Wayfinding: a through-wall beacon over every live key (tag `ActiveKey`) plus an edge arrow to the nearest one. |
| `SprintController` | client | Captures the sprint key and sends the held-state to `SprintService` as `SprintIntent`. Changes no speed/stamina locally. |
| `FlickerController` | client | Makes `FlickerLight` fixtures (and their `ShaftBeam` light shafts) flicker like failing fluorescents. Renders only. |
| `MonsterAudioController` | client | 3D breathing/footsteps on each rig, a distance-scaled heartbeat, and a Patrol→Chase sting (off `MonsterStateChanged`). |
| `MonsterAnimController` | client | **Procedural creature locomotion (the no-glide fix).** Observes `Workspace.Monsters`; per rig reads the replicated root speed + `State`/`Species` and, on `RunService.PreSimulation`, writes each cosmetic `Motor6D.Transform` from that species' `Gaits` recipe so the body moves like a real creature — the **bunny hops** (whole-mesh arc + lunge), the **monkey bounds** (4-beat gallop: limbs cycle, spine flexes, tail sways) — with cadence locked to actual ground speed. No Animator, render-only, zero bandwidth — the FlickerController-class client cosmetic CLAUDE.md permits. |
| `ChaseFXController` | client | **The hunt as a visual event.** Each frame finds the nearest monster hunting THIS player (rig `State` Chase/Investigate, softer on Alert) + its distance (replicated, exploit-safe) and drives a DEDICATED `ColorCorrectionEffect` (desaturate + red wash), a closing edge vignette, a heartbeat pulse, and a flare of that monster's eye-glow. Fades back to neutral on escape. Its own CC instance, so the static place grade is untouched. |
| `NoiseMeterController` | client | HUD noise meter — teaches the monkey's counter. Renders the server-authoritative `NoiseLevel` as a bar with a fixed marker at the monkey's `HearThreshold`: below it you're inaudible (green), cross it (sprint/run) and it flips red + pulses ("the monkey can hear you"). Render-only. |
| `AmbientController` | client | Looped drone/room-tone beds, the intermittent 3D music-box motif on the `MusicBoxEmitter` statue, and reverb switched by SafeRoom occupancy. |
| `PlayerSFXController` | client | Footsteps timed to movement, the flashlight toggle click (off `FlashlightOn`), and a low-battery beep. |
| `StingerController` | client | One-shot stingers wired to existing remotes: key chime, locked-door thunk, win jingle (ducks the beds). |
| `JumpscareController` | client | On `MonsterCaught`: a scream (ducking every bus), a full-screen `ViewportFrame` close-up of the live monster mesh lunging with shake, a red flash, and the `CAUGHT!` headline + respawn countdown. |

**Cross-script state:** server systems share per-player state through Player
attributes named in `Attributes` (e.g. the checkpoint `CFrame`) — never globals
or direct script-to-script calls. The client learns safe-room state only from the
`SafeRoomService` remotes; it never detects safe rooms itself.

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
