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
*(The single exception is a throwaway `KillBrick` test in Prompt 2, which is
temporary and will be removed.)*

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
| `Attributes`    | Canonical Instance attribute-name constants (per-player `Checkpoint`, `InSafeRoom`, `KeyCount`, `GameState`, `FlashlightBattery`) — the `Tags` discipline applied to attributes. |
| `Config`        | Single source of truth for every tunable number (frozen sections). |
| `Enums`         | Enum-like constant tables (`GameState`; `MonsterType`/`MonsterState` stubs). |
| `Types`         | Shared Luau `export type` definitions. |
| `Discovery`     | Thin `CollectionService` wrapper — `getAll`, `observe`. |
| `Spatial`       | Pure geometry — `isInsidePart`, `withinRange`. |
| `Remotes`       | RemoteEvent registry under one ReplicatedStorage folder; fetch by name. |
| `PlayerUtil`    | Player-character helpers (e.g. `livingRootPart`) shared by the polling services. |

## Systems (`src/server/`, `src/client/`)

| System | Side | Role |
| ------ | ---- | ---- |
| `GameBootstrap` | server | Skeleton sanity check: prints discovered marker counts on start. |
| `SafeRoomService` | server | Authority on "is this player safe" + their checkpoint. Polls each living HRP against `SafeRoom` parts with `Spatial`, fires `SafeRoomEntered`/`SafeRoomLeft`, and writes the `Checkpoint` attribute. |
| `SpawnService` | server | Single owner of spawn placement. On every `CharacterAdded`, places the character at the `Checkpoint` attribute, else a `PlayerStart` marker. |
| `KeyService` | server | Spawns the round's keys at a random subset of `KeySpot` markers; detects pickups by `Spatial.withinRange`; tracks each player's `KeyCount` (survives respawn); fires `KeyCollected`. |
| `ExitService` | server | Win check: at an `ExitDoor` with enough keys → sets `GameState=Won`, freezes the player, fires `GameWon`; at the door without enough → one-shot `ExitLocked`. |
| `KillBrickService` | server | **Temporary test tool.** A part tagged `KillBrick` kills whoever touches it — the lone sanctioned `Touched` handler, for testing death/respawn. Delete the brick (and eventually this file) when done. |
| `FlashlightController` | client | Head-parented `SpotLight` (Config-driven) toggled with `Config.Flashlight.ToggleKey`; client-side battery that drains while lit outside a safe room and recharges inside one (gate from server remotes). Publishes battery via the `FlashlightBattery` attribute for the HUD. |
| `HUDController` | client | Icon-forward HUD: key pips (count = `Config.Keys.RequiredToWin`), battery gauge, an exit arrow shown only once all keys are in (points at the `ExitDoor`), and a win overlay. Renders only; no asset IDs (placeholder shapes/glyphs + empty `Sound`/icon slots to fill). |

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
