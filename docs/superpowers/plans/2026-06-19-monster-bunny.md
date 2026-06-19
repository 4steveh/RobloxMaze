# The Bunny — Monster MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the game's first monster — a server-authoritative patrol/chase/search stalker ("the bunny") that hunts the player and, on catching them, triggers the existing death→jumpscare→respawn loop — built and tested in a greybox maze.

**Architecture:** A `MonsterService` server entry point owns the rig, sensing, `PathfindingService` movement, and lifecycle; it ticks a pure `BunnyFSM` decision module each `Config.Spatial.PollInterval`. Detection is a vision cone + line-of-sight raycast on the server poll (never `Touched`). A catch sets `Humanoid.Health = 0` (reusing the hardened respawn) and fires one `MonsterCaught` remote so the client plays a placeholder jumpscare. SafeRooms are sanctuaries via the existing `InSafeRoom` attribute.

**Tech Stack:** Roblox Luau, Rojo v7, `PathfindingService`, `CollectionService` (via `Discovery`), the project's `Spatial`/`Config`/`Enums`/`Remotes`/`Attributes`/`PlayerUtil` shared modules. Tooling: Rokit-pinned `rojo`, `stylua`, `selene`. Behavioral testing via the Roblox Studio MCP bridge.

## Global Constraints

Copied verbatim from CLAUDE.md and the spec — every task's requirements implicitly include these:

- **Server-authoritative.** All AI, detection, movement, and the catch decision live and are validated on the server. The client only renders and plays the local jumpscare.
- **Detection is spatial, not touch-based.** Use `Spatial`/raycasts on the `Config.Spatial.PollInterval` cadence. **Never** `Touched`/`TouchEnded`.
- **Tag-based discovery.** Find level objects via `Discovery` + `Tags` only — never hardcode instance paths/names. Reuse the existing `Tags.MonsterSpawn` and `Tags.PatrolPoint`.
- **`Config` is the single source of truth.** No magic numbers in logic — every tunable is a named, commented field in a frozen `Config` section. UI/effects read counts/durations from `Config`.
- **One system per module.** `MonsterService` (world + lifecycle) and `BunnyFSM` (pure decisions) stay separate; `BunnyFSM` performs no Instance mutation.
- **Type-check headers.** First line of every script: `--!strict` for self-contained logic (`BunnyFSM`), `--!nonstrict` for Instance-API-heavy entry points (`MonsterService`, the client script). No `:: SomeType` casts to silence the checker.
- **Done = StyLua and Selene clean.** Run `stylua .` and `selene .` (0 errors, 0 warnings) before any task is considered done. Regenerate `sourcemap.json` when the instance tree changes.
- **Constants live in their registries.** Tag strings in `Tags`, attribute names in `Attributes`, remote names in `Remotes.Names`, enum values in `Enums`, numbers in `Config`.

**Toolchain note (all `stylua`/`selene`/`rojo` commands):** prepend Rokit's shim dir to PATH in non-interactive shells: `export PATH="$HOME/.rokit/bin:$PATH"`. The dev sync server is `rojo serve` on port **34873**; it must be running and connected to Studio for repo modules to appear in the Studio data model for MCP tests.

**MCP test note (require-cache):** Studio caches a `require`d ModuleScript by instance, so re-requiring `ServerScriptService.BunnyFSM` after a Rojo re-sync can return the STALE pre-edit module. Every `BunnyFSM` unit-test snippet below therefore requires a fresh `:Clone()` of the module (a new instance ⇒ fresh execution), sidestepping the cache. Also set the active Studio to `RobloxMaze.rbxl` (two Studios run concurrently; never target `WildWorld`).

---

## File Structure

| File | Responsibility | Change |
| --- | --- | --- |
| `src/shared/Enums.luau` | Add `MonsterType.Bunny` and `MonsterState.{Patrol,Chase,Search}` | Modify |
| `src/shared/Remotes.luau` | Register `MonsterCaught` (server→client) | Modify |
| `src/shared/Config.luau` | Add the frozen `Config.Monster` section | Modify |
| `src/server/BunnyFSM.luau` | Pure FSM: `newState()` + `tick(state, sensed)` → decisions only | Create |
| `src/server/MonsterService.server.luau` | Owns rig, sensing (cone+LoS), pathfinding, tick loop, catch handoff, lifecycle | Create |
| `src/client/JumpscareController.client.luau` | On `MonsterCaught`, play a placeholder full-screen jumpscare for `RespawnDelay` | Create |
| `CLAUDE.md` | Document the new systems + shared additions | Modify |
| (Studio place) `Workspace.MazeMarkers` | Greybox maze geometry + repositioned/added markers; saved into the place | Studio-side (MCP) |

### Interface contract (names/types every task must use verbatim)

```
-- BunnyFSM types (declared in BunnyFSM.luau, consumed by MonsterService)
PlayerSense = { player: Player, position: Vector3, visible: boolean }
Sensed = { dt: number, rigPosition: Vector3, patrolNodes: { Vector3 }, players: { PlayerSense } }
FSMState = {
    name: string,            -- one of Enums.MonsterState
    patrolTarget: Vector3?,  -- the patrol node currently being walked to
    recentNodes: { Vector3 },-- recently-visited patrol nodes (so it tours, not ping-pongs)
    targetUserId: number?,   -- UserId of the player being chased
    lastSeen: Vector3?,      -- last position the chased player was visible at
    timeSinceSeen: number,   -- seconds since the chased player was last visible (behind-a-wall grace)
    searchElapsed: number,   -- seconds spent in Search
    searchTarget: Vector3?,  -- current point being investigated while searching
}
TickResult = { moveTarget: Vector3?, speed: number, caught: Player? }

BunnyFSM.newState() -> FSMState            -- fresh Patrol-state table
BunnyFSM.tick(state: FSMState, sensed: Sensed) -> TickResult  -- MUTATES state in place

-- MonsterService consumes only BunnyFSM.newState / BunnyFSM.tick.
-- MonsterService is an entry-point script; it produces nothing other modules import,
-- except a server-only debug global _G.__MonsterSensePlayers for Task 7's test.
```

`Config.Monster` keys (exact names used throughout): `PatrolSpeed`, `ChaseSpeed`, `DetectRange`, `DetectHalfAngle`, `EyeHeight`, `LoseSightSeconds`, `SearchDuration`, `SearchWanderRadius`, `CatchRadius`, `RepathInterval`, `AgentRadius`, `AgentHeight`, `WaypointReachedDistance`, `PatrolMemory`, `StallEpsilon`, `StallTicks`, `BodySize`, `BodyColor`.

---

## Task 1: Greybox test maze (Studio content via MCP)

Build the walkable greybox the bunny needs, then save the place. Studio-side content generated reproducibly through the MCP `execute_luau` bridge — no repo Luau, so no StyLua/Selene; verification is MCP inspection. The wall layout below leaves **explicit corridor gaps** so a route is walkable by construction, and Step 3's path check is a hard gate.

**Files:**
- Studio-side only: `Workspace.MazeMarkers` (floor, walls, repositioned + new markers). Saved into the opened place.

**Interfaces:**
- Consumes: nothing.
- Produces: a navmesh-walkable maze; `PlayerStart`/`SafeRoom`/`KeySpot`(×5)/`ExitDoor` repositioned inside it; `PatrolPoint`(×5) and `MonsterSpawn`(×1) tagged markers placed (the `MonsterSpawn` is off every `PatrolPoint`). These tags are what `MonsterService` discovers.

- [ ] **Step 1: Confirm the active Studio is RobloxMaze and in Edit mode**

MCP: `list_roblox_studios` → `set_active_studio` to the `RobloxMaze.rbxl` id → `get_studio_state` (expect `Edit`).

- [ ] **Step 2: Generate the greybox geometry + markers (MCP `execute_luau`, datamodel `Edit`)**

```lua
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local old = Workspace:FindFirstChild("MazeMarkers")
if old then old:Destroy() end
local folder = Instance.new("Folder")
folder.Name = "MazeMarkers"
folder.Parent = Workspace

local function part(name, size, pos, color, canCollide)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.CanCollide = canCollide
    p.Size = size
    p.Position = pos
    p.Color = color
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = folder
    return p
end

local GREY = Color3.fromRGB(120, 120, 128)
local WALLGREY = Color3.fromRGB(90, 90, 98)
local H = 12

-- Floor: top at y=0 (centred y=-1, 2 thick), 120 x 120.
part("Floor", Vector3.new(120, 2, 120), Vector3.new(0, -1, 0), GREY, true)

-- Perimeter walls.
part("WallN", Vector3.new(120, H, 2), Vector3.new(0, H / 2, 60), WALLGREY, true)
part("WallS", Vector3.new(120, H, 2), Vector3.new(0, H / 2, -60), WALLGREY, true)
part("WallE", Vector3.new(2, H, 120), Vector3.new(60, H / 2, 0), WALLGREY, true)
part("WallW", Vector3.new(2, H, 120), Vector3.new(-60, H / 2, 0), WALLGREY, true)

-- Internal walls, each SHORTER than the span they sit in so a corridor gap always
-- remains (route is open by construction). Two vertical dividers + two horizontal
-- caps form a central loop; two stubs make dead ends.
part("Int1", Vector3.new(2, H, 80), Vector3.new(-20, H / 2, -10), WALLGREY, true) -- vertical (gap at north)
part("Int2", Vector3.new(2, H, 80), Vector3.new(20, H / 2, 10), WALLGREY, true)   -- vertical (gap at south)
part("Int3", Vector3.new(30, H, 2), Vector3.new(0, H / 2, 22), WALLGREY, true)    -- loop cap (gaps at both ends)
part("Int4", Vector3.new(30, H, 2), Vector3.new(0, H / 2, -22), WALLGREY, true)   -- loop cap (gaps at both ends)
part("Int5", Vector3.new(2, H, 24), Vector3.new(-40, H / 2, 28), WALLGREY, true)  -- dead-end stub (NW)
part("Int6", Vector3.new(2, H, 24), Vector3.new(40, H / 2, -28), WALLGREY, true)  -- dead-end stub (SE)

local function marker(name, tag, size, pos, color, transparency, canCollide)
    local p = part(name, size, pos, color, canCollide)
    p.Transparency = transparency
    CollectionService:AddTag(p, tag)
    return p
end

marker("PlayerStart", "PlayerStart", Vector3.new(4, 1, 4), Vector3.new(-52, 0.5, -52), Color3.fromRGB(80, 160, 80), 0, true)
marker("SafeRoom", "SafeRoom", Vector3.new(14, 8, 14), Vector3.new(-45, 4, 45), Color3.fromRGB(80, 180, 160), 0.6, false)
marker("ExitDoor", "ExitDoor", Vector3.new(10, 8, 2), Vector3.new(50, 4, 58), Color3.fromRGB(200, 180, 60), 0.3, false)

local keySpots = {
    Vector3.new(-50, 1, 0), Vector3.new(0, 1, 50), Vector3.new(50, 1, 0),
    Vector3.new(0, 1, -50), Vector3.new(-40, 1, -40),
}
for i, pos in keySpots do
    marker("KeySpot" .. i, "KeySpot", Vector3.new(3, 0.4, 3), pos, Color3.fromRGB(120, 120, 60), 0.2, true)
end

-- 5 patrol points spread to the corners/edges so the tour visits the whole maze.
local patrolPoints = {
    Vector3.new(-48, 1, -48), Vector3.new(-48, 1, 48),
    Vector3.new(48, 1, 48), Vector3.new(48, 1, -48), Vector3.new(0, 1, 48),
}
for i, pos in patrolPoints do
    marker("PatrolPoint" .. i, "PatrolPoint", Vector3.new(2, 0.4, 2), pos, Color3.fromRGB(60, 60, 160), 0.4, false)
end

-- MonsterSpawn deeper in, NOT coincident with any PatrolPoint.
marker("MonsterSpawn", "MonsterSpawn", Vector3.new(3, 0.4, 3), Vector3.new(0, 1, -8), Color3.fromRGB(160, 60, 60), 0.4, false)

return "greybox built: floor + 10 walls + markers (1 PlayerStart, 1 SafeRoom, 1 ExitDoor, 5 KeySpot, 5 PatrolPoint, 1 MonsterSpawn)"
```

Expected return: the summary string.

- [ ] **Step 3: Verify the navmesh is walkable and markers are discoverable (hard gate) (MCP `execute_luau`, `Edit`)**

```lua
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local function count(t) return #CollectionService:GetTagged(t) end
local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
path:ComputeAsync(Vector3.new(-52, 3, -52), Vector3.new(50, 3, 58)) -- PlayerStart -> ExitDoor
return string.format("PlayerStart=%d SafeRoom=%d ExitDoor=%d KeySpot=%d PatrolPoint=%d MonsterSpawn=%d | pathStatus=%s waypoints=%d",
    count("PlayerStart"), count("SafeRoom"), count("ExitDoor"), count("KeySpot"), count("PatrolPoint"), count("MonsterSpawn"),
    tostring(path.Status), #path:GetWaypoints())
```

Expected: `PlayerStart=1 SafeRoom=1 ExitDoor=1 KeySpot=5 PatrolPoint=5 MonsterSpawn=1 | pathStatus=Enum.PathStatus.Success waypoints=` (>1). **This is a hard gate.** If `pathStatus` is not `Success`, a wall is sealing the route — widen a gap by shortening the offending `Int*` wall (e.g. drop `Int1`/`Int2` length from 80 to 64, leaving a larger gap) and re-run Step 2.

- [ ] **Step 4: Save the place**

Studio: File → Save (Workspace is not Rojo-synced; the greybox only persists in the saved place). Confirm by re-running Step 3's counts after the save.

- [ ] **Step 5: Record completion (no repo files changed)**

The greybox lives in the gitignored place file — nothing to stage. Note completion in the task tracker. (If a `.rbxlx` is later checked in, commit it here.)

---

## Task 2: Shared constants — Enums, Remotes, Config.Monster

Add every shared registry value the bunny needs, in one reviewable unit. No behavior — verification is static + a `require` smoke test.

**Files:**
- Modify: `src/shared/Enums.luau`
- Modify: `src/shared/Remotes.luau`
- Modify: `src/shared/Config.luau`

**Interfaces:**
- Consumes: nothing.
- Produces: `Enums.MonsterType.Bunny`, `Enums.MonsterState.{Patrol,Chase,Search}`, `Remotes.Names.MonsterCaught`, `Config.Monster.*` (all keys from the contract).

- [ ] **Step 1: Populate the `Enums` monster stubs**

In `src/shared/Enums.luau`, replace the two empty stub tables:

```lua
-- Monster taxonomy.
Enums.MonsterType = table.freeze({
	Bunny = "Bunny",
})

-- Monster behaviour states for the FSM.
Enums.MonsterState = table.freeze({
	Patrol = "Patrol", -- wandering patrol routes, scanning for players
	Chase = "Chase", -- a player was detected; pursuing at chase speed
	Search = "Search", -- lost sight; investigating the last-seen point before giving up
})
```

- [ ] **Step 2: Register the `MonsterCaught` remote**

In `src/shared/Remotes.luau`, add to the `Names` table (after `ExitLocked`):

```lua
	MonsterCaught = "MonsterCaught", -- server -> client: this player was caught by a monster (play the jumpscare)
```

and add to the `REMOTE_EVENTS` list (after `Names.ExitLocked`):

```lua
	Names.MonsterCaught,
```

- [ ] **Step 3: Add the `Config.Monster` section**

In `src/shared/Config.luau`, add before the "Future sections" comment block:

```lua
-- Monster: the bunny (server-authoritative FSM stalker) --------------------------
-- Speeds in studs/second (player default WalkSpeed is 16 -- ChaseSpeed exceeds it
-- so you cannot outrun it; you must break line of sight). Angles in degrees,
-- distances in studs, durations in seconds.
Config.Monster = table.freeze({
	PatrolSpeed = 10, -- WalkSpeed while patrolling / searching
	ChaseSpeed = 21, -- WalkSpeed while chasing (faster than the player)

	DetectRange = 50, -- max distance the bunny can see a player
	DetectHalfAngle = 45, -- half the vision cone (so a 90-degree total cone)
	EyeHeight = 2, -- studs above the rig's HRP that the line-of-sight ray starts from

	LoseSightSeconds = 3, -- seconds of broken sight (behind a wall) before a chase drops to Search
	SearchDuration = 6, -- seconds spent searching the last-seen area before giving up
	SearchWanderRadius = 12, -- studs the bunny pokes around the last-seen point while searching

	CatchRadius = 5, -- distance to a player that counts as a catch (instant)

	RepathInterval = 0.4, -- seconds between PathfindingService recomputations during a chase
	AgentRadius = 2, -- CreatePath agent radius (fits the corridors)
	AgentHeight = 5, -- CreatePath agent height
	WaypointReachedDistance = 4, -- studs: advance to the next path waypoint within this distance

	PatrolMemory = 2, -- patrol nodes remembered as "recently visited" so it tours rather than ping-pongs
	StallEpsilon = 0.5, -- studs: movement below this in a tick counts as "not moving"
	StallTicks = 10, -- consecutive stalled ticks (with a target) that force a repath

	BodySize = Vector3.new(2.5, 3.5, 2.5), -- placeholder rig body dimensions
	BodyColor = Color3.fromRGB(220, 218, 225), -- placeholder rig tone (pale, faintly sickly)
})
```

- [ ] **Step 4: Format, lint, and smoke-test the requires**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
```

Expected: StyLua exits 0; Selene prints `0 errors, 0 warnings`.

Then, with `rojo serve` connected, via MCP `execute_luau` (datamodel `Edit`):

```lua
local RS = game:GetService("ReplicatedStorage")
local Enums = require(RS.Enums)
local Config = require(RS.Config)
local Remotes = require(RS.Remotes)
return string.format("Bunny=%s states=%s/%s/%s caught=%s chaseSpeed=%d catchRadius=%d patrolMem=%d",
    Enums.MonsterType.Bunny, Enums.MonsterState.Patrol, Enums.MonsterState.Chase, Enums.MonsterState.Search,
    Remotes.Names.MonsterCaught, Config.Monster.ChaseSpeed, Config.Monster.CatchRadius, Config.Monster.PatrolMemory)
```

Expected: `Bunny=Bunny states=Patrol/Chase/Search caught=MonsterCaught chaseSpeed=21 catchRadius=5 patrolMem=2`.

- [ ] **Step 5: Commit**

```bash
cd /home/toor/claude/RobloxMaze
git add src/shared/Enums.luau src/shared/Remotes.luau src/shared/Config.luau
git commit -m "Add monster shared constants: Enums, MonsterCaught remote, Config.Monster"
```

---

## Task 3: BunnyFSM — scaffold + Patrol (touring) + Patrol→Chase

Create the pure decision module with `newState()` and a `tick` that handles touring patrol and entering a chase on detection. Tested by requiring a fresh `:Clone()` of the module via MCP and asserting `tick` outputs against crafted inputs.

**Files:**
- Create: `src/server/BunnyFSM.luau`

**Interfaces:**
- Consumes: `Enums.MonsterState`, `Config.Monster` (from `ReplicatedStorage`).
- Produces: `BunnyFSM.newState()`, `BunnyFSM.tick(state, sensed)` per the contract (Patrol + Patrol→Chase here; Chase/Search added in Tasks 4–5).

- [ ] **Step 1: Write the failing test (MCP `execute_luau`, `Edit`)**

With `rojo serve` connected:

```lua
local SSS = game:GetService("ServerScriptService")
local src = SSS:FindFirstChild("BunnyFSM")
if not src then return "FAIL: BunnyFSM not present yet (implement it; ensure rojo synced)" end
local clone = src:Clone(); clone.Parent = SSS
local FSM = require(clone)
local Enums = require(game:GetService("ReplicatedStorage").Enums)
local out = {}

-- Patrol with no players: moves toward a patrol node at patrol speed, stays Patrol.
local s = FSM.newState()
local r = FSM.tick(s, {
    dt = 0.15, rigPosition = Vector3.new(0, 1, 0),
    patrolNodes = { Vector3.new(40, 1, 0), Vector3.new(-40, 1, 0) }, players = {},
})
table.insert(out, "patrol.name=" .. s.name .. " hasTarget=" .. tostring(r.moveTarget ~= nil) .. " speed=" .. r.speed)

-- A visible player flips Patrol -> Chase and aims at that player.
local s2 = FSM.newState()
local r2 = FSM.tick(s2, {
    dt = 0.15, rigPosition = Vector3.new(0, 1, 0), patrolNodes = { Vector3.new(40, 1, 0) },
    players = { { player = { UserId = 1 }, position = Vector3.new(10, 1, 0), visible = true } },
})
table.insert(out, "afterSeen.name=" .. s2.name .. " targetX=" .. tostring(r2.moveTarget and r2.moveTarget.X) .. " targetZ=" .. tostring(r2.moveTarget and r2.moveTarget.Z))

clone:Destroy()
return table.concat(out, " | ")
```

- [ ] **Step 2: Run it to verify it fails**

Expected: `FAIL: BunnyFSM not present yet ...` (module doesn't exist).

- [ ] **Step 3: Implement the module (Patrol touring + Patrol→Chase)**

Create `src/server/BunnyFSM.luau`:

```lua
--!strict
-- BunnyFSM.luau
-- Pure decision module for the bunny (one FSM per monster type, per CLAUDE.md).
-- `tick` reads sensed inputs and the current state, MUTATES the state, and returns
-- a movement intent + whether a catch happened. It performs NO Instance work --
-- MonsterService owns all world mutation, so this module is unit-testable in
-- isolation. States are Enums.MonsterState.{Patrol, Chase, Search}.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Enums)
local Config = require(ReplicatedStorage.Config)

export type PlayerSense = { player: Player, position: Vector3, visible: boolean }
export type Sensed = {
	dt: number,
	rigPosition: Vector3,
	patrolNodes: { Vector3 },
	players: { PlayerSense },
}
export type FSMState = {
	name: string,
	patrolTarget: Vector3?,
	recentNodes: { Vector3 },
	targetUserId: number?,
	lastSeen: Vector3?,
	timeSinceSeen: number,
	searchElapsed: number,
	searchTarget: Vector3?,
}
export type TickResult = { moveTarget: Vector3?, speed: number, caught: Player? }

local BunnyFSM = {}

-- Flat XZ distance (the rig and players share a floor; ignore Y).
local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Nearest patrol node to `from`, excluding any within WaypointReachedDistance of
-- `exclude`. Returns nil if none.
local function nearestNode(nodes: { Vector3 }, from: Vector3, exclude: Vector3?): Vector3?
	local best, bestDist = nil, math.huge
	for _, node in nodes do
		if exclude and flatDistance(node, exclude) < Config.Monster.WaypointReachedDistance then
			continue
		end
		local d = flatDistance(node, from)
		if d < bestDist then
			best, bestDist = node, d
		end
	end
	return best
end

-- Nearest node not within reach of any recently-visited node, so the bunny tours
-- the maze. Falls back to the nearest node other than the most-recent if every
-- node is recent (few-node layouts).
local function nextPatrolNode(nodes: { Vector3 }, from: Vector3, recent: { Vector3 }): Vector3?
	local best, bestDist = nil, math.huge
	for _, node in nodes do
		local isRecent = false
		for _, r in recent do
			if flatDistance(node, r) < Config.Monster.WaypointReachedDistance then
				isRecent = true
				break
			end
		end
		if not isRecent then
			local d = flatDistance(node, from)
			if d < bestDist then
				best, bestDist = node, d
			end
		end
	end
	if best == nil then
		best = nearestNode(nodes, from, recent[#recent])
	end
	return best
end

-- Nearest player flagged visible this tick, or nil.
local function nearestVisible(sensed: Sensed): PlayerSense?
	local best, bestDist = nil, math.huge
	for _, ps in sensed.players do
		if ps.visible then
			local d = flatDistance(ps.position, sensed.rigPosition)
			if d < bestDist then
				best, bestDist = ps, d
			end
		end
	end
	return best
end

function BunnyFSM.newState(): FSMState
	return {
		name = Enums.MonsterState.Patrol,
		patrolTarget = nil,
		recentNodes = {},
		targetUserId = nil,
		lastSeen = nil,
		timeSinceSeen = 0,
		searchElapsed = 0,
		searchTarget = nil,
	}
end

-- Enter Chase aimed at a freshly-seen player. Shared by Patrol and Search.
local function beginChase(state: FSMState, seen: PlayerSense): TickResult
	state.name = Enums.MonsterState.Chase
	state.targetUserId = seen.player.UserId
	state.lastSeen = seen.position
	state.timeSinceSeen = 0
	return { moveTarget = seen.position, speed = Config.Monster.ChaseSpeed, caught = nil }
end

local function tickPatrol(state: FSMState, sensed: Sensed): TickResult
	local seen = nearestVisible(sensed)
	if seen then
		return beginChase(state, seen)
	end
	local reached = state.patrolTarget ~= nil
		and flatDistance(sensed.rigPosition, state.patrolTarget) < Config.Monster.WaypointReachedDistance
	if state.patrolTarget == nil or reached then
		if reached and state.patrolTarget then
			table.insert(state.recentNodes, state.patrolTarget)
			while #state.recentNodes > Config.Monster.PatrolMemory do
				table.remove(state.recentNodes, 1)
			end
		end
		state.patrolTarget = nextPatrolNode(sensed.patrolNodes, sensed.rigPosition, state.recentNodes)
	end
	return { moveTarget = state.patrolTarget, speed = Config.Monster.PatrolSpeed, caught = nil }
end

function BunnyFSM.tick(state: FSMState, sensed: Sensed): TickResult
	if state.name == Enums.MonsterState.Patrol then
		return tickPatrol(state, sensed)
	end
	-- Chase and Search are added in later tasks; default to patrolling so the
	-- function is total in the meantime.
	return tickPatrol(state, sensed)
end

return BunnyFSM
```

- [ ] **Step 4: Re-run the test to verify it passes**

Re-run the Step 1 snippet. Expected: `patrol.name=Patrol hasTarget=true speed=10 | afterSeen.name=Chase targetX=10 targetZ=0`.

- [ ] **Step 5: Format, lint, commit**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
rojo sourcemap --include-non-scripts -o sourcemap.json
git add src/server/BunnyFSM.luau sourcemap.json
git commit -m "Add BunnyFSM: pure FSM scaffold with touring Patrol and Patrol->Chase"
```

Expected: StyLua/Selene clean (`0 errors, 0 warnings`).

---

## Task 4: BunnyFSM — Chase (sight tracking, immediate vs grace give-up, catch)

Extend `tick` for Chase: track the visible target, **give up immediately** when the chased target leaves the sensed set (SafeRoom/death/leave/win), apply the `LoseSightSeconds` grace only when it's merely behind a wall, and report a catch within `CatchRadius`.

**Files:**
- Modify: `src/server/BunnyFSM.luau`

**Interfaces:**
- Consumes: the Task 3 module + `Config.Monster.{ChaseSpeed,CatchRadius,LoseSightSeconds,PatrolSpeed}`.
- Produces: Chase behavior in `BunnyFSM.tick`; `TickResult.caught` set to the caught `Player`.

- [ ] **Step 1: Write the failing test (MCP `execute_luau`, `Edit`)**

```lua
local SSS = game:GetService("ServerScriptService")
local src = SSS:FindFirstChild("BunnyFSM")
if not src then return "FAIL: BunnyFSM missing" end
local clone = src:Clone(); clone.Parent = SSS
local FSM = require(clone)
local Enums = require(game:GetService("ReplicatedStorage").Enums)
local out = {}

-- A) Behind a wall (target still sensed, not visible): accrue grace, stay Chase.
local a = FSM.newState()
a.name = Enums.MonsterState.Chase; a.targetUserId = 7; a.lastSeen = Vector3.new(30, 1, 0); a.timeSinceSeen = 0
local ra = FSM.tick(a, { dt = 1, rigPosition = Vector3.new(0, 1, 0), patrolNodes = {},
    players = { { player = { UserId = 7 }, position = Vector3.new(40, 1, 0), visible = false } } })
table.insert(out, "wall name=" .. a.name .. " t=" .. a.timeSinceSeen .. " moveX=" .. tostring(ra.moveTarget and ra.moveTarget.X))

-- B) Behind a wall past the grace window -> Search.
local b = FSM.newState()
b.name = Enums.MonsterState.Chase; b.targetUserId = 7; b.lastSeen = Vector3.new(30, 1, 0); b.timeSinceSeen = 2.9
FSM.tick(b, { dt = 0.2, rigPosition = Vector3.new(0, 1, 0), patrolNodes = {},
    players = { { player = { UserId = 7 }, position = Vector3.new(40, 1, 0), visible = false } } })
table.insert(out, "graceExpire name=" .. b.name)

-- C) Target gone from the sensed set (SafeRoom/death) -> Search IMMEDIATELY.
local c = FSM.newState()
c.name = Enums.MonsterState.Chase; c.targetUserId = 7; c.lastSeen = Vector3.new(30, 1, 0); c.timeSinceSeen = 0
FSM.tick(c, { dt = 0.2, rigPosition = Vector3.new(0, 1, 0), patrolNodes = {}, players = {} })
table.insert(out, "instant name=" .. c.name)

-- D) Within CatchRadius -> caught.
local d = FSM.newState()
d.name = Enums.MonsterState.Chase
local rd = FSM.tick(d, { dt = 0.15, rigPosition = Vector3.new(0, 1, 0), patrolNodes = {},
    players = { { player = { UserId = 7 }, position = Vector3.new(3, 1, 0), visible = true } } })
table.insert(out, "catch userId=" .. tostring(rd.caught and rd.caught.UserId))

clone:Destroy()
return table.concat(out, " | ")
```

- [ ] **Step 2: Run it to verify it fails**

Expected: `graceExpire name=Chase` and `instant name=Chase` and `catch userId=nil` — Chase isn't implemented, so `tick` still patrols. Any deviation from the Step 4 expected output is a valid failure.

- [ ] **Step 3: Implement Chase**

In `src/server/BunnyFSM.luau`, add after `nearestVisible`:

```lua
-- Nearest eligible player within CatchRadius of the rig, or nil. Catch is pure
-- proximity (it is on top of you), independent of the vision cone.
local function caughtPlayer(sensed: Sensed): Player?
	local best, bestDist = nil, math.huge
	for _, ps in sensed.players do
		local d = flatDistance(ps.position, sensed.rigPosition)
		if d <= Config.Monster.CatchRadius and d < bestDist then
			best, bestDist = ps.player, d
		end
	end
	return best
end

-- Is the player we are chasing still in the sensed set? Absence means it left the
-- eligible set entirely (entered a SafeRoom, died, won, or left) -- not merely
-- broke line of sight behind a wall (which keeps it sensed with visible = false).
local function targetInSensed(state: FSMState, sensed: Sensed): boolean
	if state.targetUserId == nil then
		return false
	end
	for _, ps in sensed.players do
		if ps.player.UserId == state.targetUserId then
			return true
		end
	end
	return false
end
```

Add after `tickPatrol`:

```lua
local function enterSearch(state: FSMState): TickResult
	state.name = Enums.MonsterState.Search
	state.searchElapsed = 0
	state.searchTarget = state.lastSeen
	return { moveTarget = state.searchTarget, speed = Config.Monster.PatrolSpeed, caught = nil }
end

local function tickChase(state: FSMState, sensed: Sensed): TickResult
	-- A catch ends everything this tick.
	local caught = caughtPlayer(sensed)
	if caught then
		return { moveTarget = sensed.rigPosition, speed = Config.Monster.ChaseSpeed, caught = caught }
	end

	-- Re-acquire / maintain the freshest visible target.
	local seen = nearestVisible(sensed)
	if seen then
		state.targetUserId = seen.player.UserId
		state.lastSeen = seen.position
		state.timeSinceSeen = 0
		return { moveTarget = seen.position, speed = Config.Monster.ChaseSpeed, caught = nil }
	end

	-- No one visible. If the chased target left the sensed set, give up immediately;
	-- if it is merely behind a wall (still sensed), burn the grace window.
	if not targetInSensed(state, sensed) then
		return enterSearch(state)
	end
	state.timeSinceSeen += sensed.dt
	if state.timeSinceSeen >= Config.Monster.LoseSightSeconds then
		return enterSearch(state)
	end
	return { moveTarget = state.lastSeen, speed = Config.Monster.ChaseSpeed, caught = nil }
end
```

Update `BunnyFSM.tick` to route Chase:

```lua
function BunnyFSM.tick(state: FSMState, sensed: Sensed): TickResult
	if state.name == Enums.MonsterState.Chase then
		return tickChase(state, sensed)
	end
	-- Search is added in the next task; until then it behaves like Patrol.
	return tickPatrol(state, sensed)
end
```

- [ ] **Step 4: Re-run the test to verify it passes**

Expected: `wall name=Chase t=1 moveX=30 | graceExpire name=Search | instant name=Search | catch userId=7`.

- [ ] **Step 5: Format, lint, commit**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
git add src/server/BunnyFSM.luau
git commit -m "BunnyFSM: implement Chase (grace vs immediate give-up, catch)"
```

---

## Task 5: BunnyFSM — Search (investigate, wander, reacquire / give up)

Extend `tick` for Search: investigate the last-seen point, wander nearby within `SearchWanderRadius`, re-enter Chase on re-detection, and fall back to Patrol after `SearchDuration`.

**Files:**
- Modify: `src/server/BunnyFSM.luau`

**Interfaces:**
- Consumes: the Task 4 module + `Config.Monster.{SearchDuration,SearchWanderRadius,WaypointReachedDistance,PatrolSpeed}`.
- Produces: Search behavior in `BunnyFSM.tick`.

- [ ] **Step 1: Write the failing test (MCP `execute_luau`, `Edit`)**

```lua
local SSS = game:GetService("ServerScriptService")
local src = SSS:FindFirstChild("BunnyFSM")
if not src then return "FAIL: BunnyFSM missing" end
local clone = src:Clone(); clone.Parent = SSS
local FSM = require(clone)
local Enums = require(game:GetService("ReplicatedStorage").Enums)
local out = {}

-- A) Searching past SearchDuration -> Patrol.
local a = FSM.newState()
a.name = Enums.MonsterState.Search; a.searchElapsed = 5.9; a.searchTarget = Vector3.new(10, 1, 0)
FSM.tick(a, { dt = 0.2, rigPosition = Vector3.new(9, 1, 0), patrolNodes = { Vector3.new(40, 1, 0) }, players = {} })
table.insert(out, "expire name=" .. a.name)

-- B) Searching and a player becomes visible -> Chase.
local b = FSM.newState()
b.name = Enums.MonsterState.Search; b.searchElapsed = 1; b.searchTarget = Vector3.new(10, 1, 0)
local rb = FSM.tick(b, { dt = 0.2, rigPosition = Vector3.new(0, 1, 0), patrolNodes = {},
    players = { { player = { UserId = 7 }, position = Vector3.new(5, 1, 0), visible = true } } })
table.insert(out, "reacquire name=" .. b.name .. " moveX=" .. tostring(rb.moveTarget and rb.moveTarget.X))

-- C) Reached the search point: picks a new wander target within the radius.
local c = FSM.newState()
c.name = Enums.MonsterState.Search; c.searchElapsed = 1; c.lastSeen = Vector3.new(10, 1, 0); c.searchTarget = Vector3.new(10, 1, 0)
local rc = FSM.tick(c, { dt = 0.2, rigPosition = Vector3.new(10, 1, 0), patrolNodes = {}, players = {} })
local within = rc.moveTarget ~= nil and (rc.moveTarget - Vector3.new(10, 1, 0)).Magnitude <= 12.01
table.insert(out, "wander withinRadius=" .. tostring(within))

clone:Destroy()
return table.concat(out, " | ")
```

- [ ] **Step 2: Run it to verify it fails**

Expected: `expire name=Search` (not `Patrol`) and `reacquire name=Search` (not `Chase`) — Search routes to the Patrol fallback today, so transitions are wrong. Any deviation from Step 4 expected output is a valid failure.

- [ ] **Step 3: Implement Search**

In `src/server/BunnyFSM.luau`, add after `tickChase`:

```lua
local function tickSearch(state: FSMState, sensed: Sensed): TickResult
	-- Re-detection resumes the chase immediately.
	local seen = nearestVisible(sensed)
	if seen then
		return beginChase(state, seen)
	end

	state.searchElapsed += sensed.dt
	if state.searchElapsed >= Config.Monster.SearchDuration then
		state.name = Enums.MonsterState.Patrol
		state.patrolTarget = nil
		state.targetUserId = nil
		state.lastSeen = nil
		state.searchTarget = nil
		return { moveTarget = nil, speed = Config.Monster.PatrolSpeed, caught = nil }
	end

	-- Investigate: walk to the current search point; on arrival pick a new random
	-- point within SearchWanderRadius of the last-seen position.
	local anchor = state.lastSeen or sensed.rigPosition
	if state.searchTarget == nil or flatDistance(sensed.rigPosition, state.searchTarget) < Config.Monster.WaypointReachedDistance then
		local angle = math.random() * math.pi * 2
		local dist = math.random() * Config.Monster.SearchWanderRadius
		state.searchTarget = anchor + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	end
	return { moveTarget = state.searchTarget, speed = Config.Monster.PatrolSpeed, caught = nil }
end
```

Update `BunnyFSM.tick` to its final form:

```lua
function BunnyFSM.tick(state: FSMState, sensed: Sensed): TickResult
	if state.name == Enums.MonsterState.Chase then
		return tickChase(state, sensed)
	elseif state.name == Enums.MonsterState.Search then
		return tickSearch(state, sensed)
	end
	return tickPatrol(state, sensed)
end
```

- [ ] **Step 4: Re-run the test to verify it passes**

Expected: `expire name=Patrol | reacquire name=Chase moveX=5 | wander withinRadius=true`.

- [ ] **Step 5: Format, lint, commit**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
git add src/server/BunnyFSM.luau
git commit -m "BunnyFSM: implement Search (investigate, wander, reacquire/give up)"
```

---

## Task 6: MonsterService — a valid rig + spawn discovery

Create the server entry point that builds a **valid, walkable** procedural rig at each `MonsterSpawn` and exposes its FSM state as an attribute. No AI yet. Behavioral; tested via a playtest that confirms the rig is **alive and standing**.

**Files:**
- Create: `src/server/MonsterService.server.luau`

**Interfaces:**
- Consumes: `Discovery`, `Tags`, `Config.Monster`, `Enums.MonsterState`, `Enums.MonsterType`.
- Produces: a rig `Model` (named `Bunny`) per `MonsterSpawn`, parented under a `Monsters` folder in Workspace, carrying a `State` attribute, with server-pinned network ownership. Later tasks add sensing/movement/catch into this same file.

- [ ] **Step 1: Implement the rig + spawn skeleton**

Create `src/server/MonsterService.server.luau`:

```lua
--!nonstrict
-- MonsterService.server.luau
-- Owns the bunny: builds a valid procedural placeholder rig at each MonsterSpawn,
-- and (in later steps) senses players, drives PathfindingService movement off the
-- Config.Spatial.PollInterval cadence, ticks the pure BunnyFSM, and routes a catch
-- into the existing SpawnService death/respawn. Server-authoritative; the client
-- only renders the rig and plays the jumpscare via the MonsterCaught remote.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Enums = require(ReplicatedStorage.Enums)

local STATE_ATTRIBUTE = "State" -- on the rig model: current Enums.MonsterState (observability/testing)

local monstersFolder = Instance.new("Folder")
monstersFolder.Name = "Monsters"
monstersFolder.Parent = Workspace

-- A VALID procedural Humanoid rig: a HumanoidRootPart body + a welded Head (a
-- Humanoid needs a Head to be a living character) + a Humanoid with RequiresNeck
-- off and an explicit HipHeight so it stands on the floor and Humanoid:MoveTo can
-- walk it. No art assets -- Config.Monster.Body* are placeholders.
local function createRig(spawnPart): Model
	local rig = Instance.new("Model")
	rig.Name = Enums.MonsterType.Bunny

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Config.Monster.BodySize
	root.Color = Config.Monster.BodyColor
	root.Anchored = false
	root.CanCollide = true
	root.Parent = rig

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1, 1, 1)
	head.Color = Config.Monster.BodyColor
	head.CanCollide = false
	head.Massless = true -- doesn't affect the Humanoid's balance
	head.Parent = rig

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = head
	weld.C0 = CFrame.new(0, Config.Monster.BodySize.Y / 2 + 0.5, 0)
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false -- single-body placeholder has no Neck joint
	humanoid.HipHeight = Config.Monster.BodySize.Y / 2 -- float the root above the floor so it can walk
	humanoid.AutoRotate = true
	humanoid.Parent = rig

	rig.PrimaryPart = root
	rig:PivotTo(CFrame.new(spawnPart.Position + Vector3.new(0, Config.Monster.BodySize.Y, 0)))
	rig.Parent = monstersFolder
	rig:SetAttribute(STATE_ATTRIBUTE, Enums.MonsterState.Patrol)

	-- Keep physics authority on the server so server-driven MoveTo is honored.
	root:SetNetworkOwner(nil)
	return rig
end

-- One bunny per MonsterSpawn marker (MVP expects one). Warn once if none exist.
local warnedNoSpawn = false
local function spawnBunnies()
	local spawns = Discovery.getAll(Tags.MonsterSpawn)
	if #spawns == 0 then
		if not warnedNoSpawn then
			warnedNoSpawn = true
			warn("[MonsterService] No MonsterSpawn marker found; no bunny spawned.")
		end
		return
	end
	for _, spawnPart in spawns do
		if spawnPart:IsA("BasePart") then
			createRig(spawnPart)
		end
	end
end

spawnBunnies()
```

- [ ] **Step 2: Format, lint, sourcemap**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
rojo sourcemap --include-non-scripts -o sourcemap.json
```

Expected: StyLua/Selene clean (`0 errors, 0 warnings`).

- [ ] **Step 3: Playtest — the rig spawns ALIVE and STANDING (MCP)**

`start_stop_play(is_start=true)`, then `execute_luau` (datamodel `Server`):

```lua
local Workspace = game:GetService("Workspace")
task.wait(2) -- let it settle on the floor
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig and rig.PrimaryPart
local hum = rig and rig:FindFirstChildOfClass("Humanoid")
return rig and string.format("alive=%s state=%s health=%.0f y=%.1f notDead=%s",
    tostring(hum.Health > 0), rig:GetAttribute("State"), hum.Health, root.Position.Y,
    tostring(hum:GetState() ~= Enum.HumanoidStateType.Dead)) or "NO RIG"
```

Expected: `alive=true state=Patrol health=100 y=~3 notDead=true` — and re-running after a few more seconds shows the rig is still standing (y didn't fall toward 0/through the floor). If `alive=false` or it falls, the rig template is wrong — recheck the Head weld / `HipHeight` / `RequiresNeck`. `start_stop_play(is_start=false)`.

- [ ] **Step 4: Commit**

```bash
cd /home/toor/claude/RobloxMaze
git add src/server/MonsterService.server.luau sourcemap.json
git commit -m "MonsterService: spawn a valid procedural bunny rig at MonsterSpawn"
```

---

## Task 7: MonsterService — sensing (vision cone + line of sight)

Add the per-tick sensing that builds `BunnyFSM.Sensed.players`: each eligible living player (not in a SafeRoom, not Won) with their position and a `visible` flag from the cone + LoS raycast. Range/cone are measured from the rig **root** (matching the FSM's flat proximity); only the LoS ray originates at the raised eye. Exposed via a server-only debug global so the test exercises the real function.

**Files:**
- Modify: `src/server/MonsterService.server.luau`

**Interfaces:**
- Consumes: `PlayerUtil.livingRootPart`, `Attributes.{InSafeRoom,GameState}`, `Enums.GameState`, `Config.Monster.{DetectRange,DetectHalfAngle,EyeHeight}`.
- Produces: a `sensePlayers(rig)` local returning `{ PlayerSense }` (used by Task 9), plus `_G.__MonsterSensePlayers` (debug seam; not read by game logic).

- [ ] **Step 1: Add the requires and the sensing helper**

In `src/server/MonsterService.server.luau`, add to the requires block:

```lua
local Attributes = require(ReplicatedStorage.Attributes)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
```

Add this helper after `createRig` (before `spawnBunnies`):

```lua
-- Raycast params reused each sense: ignore the rig and all player characters, so
-- only world geometry (walls) can block line of sight.
local function sightParams(rig: Model): RaycastParams
	local filter = { rig }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	return params
end

-- Build the FSM's player list: every eligible living player with a visible flag.
-- Eligible = living HRP, NOT in a SafeRoom, NOT won. (A brand-new player whose
-- InSafeRoom/GameState attributes are still nil is intentionally treated as
-- eligible -- not-safe / not-won.) Visible = within DetectRange of the root,
-- inside the DetectHalfAngle cone, and unobstructed by walls.
local function sensePlayers(rig: Model): { any }
	local root = rig.PrimaryPart
	local eyePos = root.Position + Vector3.new(0, Config.Monster.EyeHeight, 0)
	local facing = root.CFrame.LookVector
	local params = sightParams(rig)

	local result = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(Attributes.InSafeRoom) == true then
			continue
		end
		if player:GetAttribute(Attributes.GameState) == Enums.GameState.Won then
			continue
		end
		local hrp = PlayerUtil.livingRootPart(player)
		if not hrp then
			continue
		end

		-- Range/cone from the root (consistent with the FSM's flat proximity).
		local toPlayer = hrp.Position - root.Position
		local distance = toPlayer.Magnitude
		local visible = false
		if distance <= Config.Monster.DetectRange and distance > 0 then
			local angle = math.deg(math.acos(math.clamp(facing:Dot(toPlayer.Unit), -1, 1)))
			if angle <= Config.Monster.DetectHalfAngle then
				-- LoS ray from the raised eye to the player's HRP; hit == nil => clear.
				local ray = hrp.Position - eyePos
				local hit = Workspace:Raycast(eyePos, ray, params)
				visible = hit == nil
			end
		end
		table.insert(result, { player = player, position = hrp.Position, visible = visible })
	end
	return result
end

-- Debug seam (server-only) so the Task 7 playtest can call the real function.
-- Not read by any game logic.
_G.__MonsterSensePlayers = sensePlayers
```

- [ ] **Step 2: Format, lint, sourcemap**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
rojo sourcemap --include-non-scripts -o sourcemap.json
```

Expected: clean.

- [ ] **Step 3: Playtest — the real `sensePlayers` flips with the cone (MCP)**

`start_stop_play(is_start=true)`. Wait for your character, then `execute_luau` (`Server`) — this calls the actual helper via the debug seam:

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local sense = _G.__MonsterSensePlayers
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local hrp = Players:GetPlayers()[1].Character.HumanoidRootPart

-- In front, within range, clear LoS -> visible.
hrp.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 15)
task.wait(0.15)
local front = sense(rig)[1]
-- Directly behind the rig (outside the cone) -> not visible.
hrp.CFrame = CFrame.new(root.Position - root.CFrame.LookVector * 15)
task.wait(0.15)
local back = sense(rig)[1]
return string.format("inFront.visible=%s behind.visible=%s",
    tostring(front and front.visible), tostring(back and back.visible))
```

Expected: `inFront.visible=true behind.visible=false`. (Wall-blocking LoS is exercised in Task 12.) `start_stop_play(is_start=false)`.

- [ ] **Step 4: Commit**

```bash
cd /home/toor/claude/RobloxMaze
git add src/server/MonsterService.server.luau sourcemap.json
git commit -m "MonsterService: vision-cone + line-of-sight player sensing"
```

---

## Task 8: MonsterService — pathfinding movement with stall recovery

Add `PathfindingService` movement: compute a path to a target, follow waypoints via `Humanoid:MoveTo`, repath on `RepathInterval`, **recover from stalls**, and fall back to direct steering if no path is found. Stop by standing still at the current spot (not `Move(zero)`).

**Files:**
- Modify: `src/server/MonsterService.server.luau`

**Interfaces:**
- Consumes: `Config.Monster.{AgentRadius,AgentHeight,RepathInterval,WaypointReachedDistance,StallEpsilon,StallTicks}`.
- Produces: a per-rig mover (table with `update(targetPosition, dt)`), used by Task 9's loop.

- [ ] **Step 1: Add the require and the mover factory**

Add to the requires block:

```lua
local PathfindingService = game:GetService("PathfindingService")
```

Add after `sensePlayers` (and after the `_G.__MonsterSensePlayers` line):

```lua
-- Per-rig movement: walks the Humanoid along a PathfindingService path toward a
-- target, recomputing at most every RepathInterval (ComputeAsync yields). Detects
-- stalls (wedged on a corner) and forces a repath, and falls back to steering
-- straight at the target when no path is available.
local function createMover(rig: Model)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local path = PathfindingService:CreatePath({
		AgentRadius = Config.Monster.AgentRadius,
		AgentHeight = Config.Monster.AgentHeight,
		AgentCanJump = false,
	})
	local waypoints = {}
	local waypointIndex = 1
	local sinceRepath = math.huge -- force a path on the first update
	local lastPos = nil
	local stalledTicks = 0

	local function repath(target: Vector3)
		local root = rig.PrimaryPart
		local ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
			waypointIndex = 1
		else
			waypoints = {} -- fall back to direct steering
		end
		sinceRepath = 0
	end

	local mover = {}
	function mover.update(target: Vector3?, dt: number)
		local root = rig.PrimaryPart
		if not root then
			return
		end
		if target == nil then
			humanoid:MoveTo(root.Position) -- stand still at the current spot
			lastPos = root.Position
			stalledTicks = 0
			return
		end

		-- Stall recovery: barely moving toward a real target -> force a repath.
		if lastPos and (root.Position - lastPos).Magnitude < Config.Monster.StallEpsilon then
			stalledTicks += 1
		else
			stalledTicks = 0
		end
		lastPos = root.Position
		if stalledTicks >= Config.Monster.StallTicks then
			sinceRepath = math.huge
			stalledTicks = 0
		end

		sinceRepath += dt
		if sinceRepath >= Config.Monster.RepathInterval then
			repath(target)
		end

		if #waypoints == 0 then
			humanoid:MoveTo(target) -- direct fallback
			return
		end
		while waypointIndex <= #waypoints do
			local wp = waypoints[waypointIndex].Position
			if (Vector3.new(wp.X, root.Position.Y, wp.Z) - root.Position).Magnitude < Config.Monster.WaypointReachedDistance then
				waypointIndex += 1
			else
				break
			end
		end
		if waypointIndex <= #waypoints then
			humanoid:MoveTo(waypoints[waypointIndex].Position)
		else
			humanoid:MoveTo(target)
		end
	end

	return mover
end
```

- [ ] **Step 2: Format, lint, sourcemap**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
rojo sourcemap --include-non-scripts -o sourcemap.json
```

Expected: clean. (`PathfindingService` is already in the pinned `roblox.yml`; no std regen needed.)

- [ ] **Step 3: Playtest — the rig walks to a far target (MCP)**

`start_stop_play(is_start=true)`, then `execute_luau` (`Server`):

```lua
local Workspace = game:GetService("Workspace")
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local humanoid = rig:FindFirstChildOfClass("Humanoid")
local root = rig.PrimaryPart
local start = root.Position
humanoid.WalkSpeed = 16 -- test scaffold; production speed comes from Config.Monster in Task 9
local PathfindingService = game:GetService("PathfindingService")
local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
path:ComputeAsync(start, Vector3.new(48, 3, 48))
for _, wp in path:GetWaypoints() do
    humanoid:MoveTo(wp.Position)
    humanoid.MoveToFinished:Wait()
end
return string.format("moved from (%.0f,%.0f) to (%.0f,%.0f)", start.X, start.Z, root.Position.X, root.Position.Z)
```

Expected: the rig ends near `(48, 48)` — proving the procedural rig actually walks the navmesh. `start_stop_play(is_start=false)`.

- [ ] **Step 4: Commit**

```bash
cd /home/toor/claude/RobloxMaze
git add src/server/MonsterService.server.luau sourcemap.json
git commit -m "MonsterService: PathfindingService movement with stall recovery + fallback"
```

---

## Task 9: MonsterService — tick loop (FSM + movement + state + catch)

Wire it together: per `Config.Spatial.PollInterval`, for each rig, sense → `BunnyFSM.tick` → apply speed/movement, write the `State` attribute, and on a catch set the player's `Humanoid.Health = 0` and fire `MonsterCaught`. `dt` is measured from `os.clock()` deltas (not `task.wait`'s return) so FSM timers stay wall-clock accurate despite `ComputeAsync` yields.

**Files:**
- Modify: `src/server/MonsterService.server.luau`

**Interfaces:**
- Consumes: `BunnyFSM.newState/tick`, `Discovery`/`Tags.PatrolPoint`, `Remotes`, `Config.Spatial.PollInterval`, Task 7 `sensePlayers`, Task 8 `createMover`.
- Produces: the running bunny. Entry point — nothing imported elsewhere.

- [ ] **Step 1: Add requires, patrol-node discovery, instances, the catch, and the loop**

Add to the requires block:

```lua
local Remotes = require(ReplicatedStorage.Remotes)
local BunnyFSM = require(script.Parent.BunnyFSM)
```

After the `STATE_ATTRIBUTE` line and `monstersFolder` setup, add:

```lua
Remotes.init()
local caughtRemote = Remotes.get(Remotes.Names.MonsterCaught)
```

Add patrol-node discovery (used each tick, so newly-tagged nodes are picked up) just before `spawnBunnies`:

```lua
local warnedNoPatrol = false
local function patrolNodePositions(): { Vector3 }
	local nodes = {}
	for _, m in Discovery.getAll(Tags.PatrolPoint) do
		if m:IsA("BasePart") then
			table.insert(nodes, m.Position)
		end
	end
	if #nodes == 0 and not warnedNoPatrol then
		warnedNoPatrol = true
		warn("[MonsterService] No PatrolPoint markers found; the bunny will idle near its spawn.")
	end
	return nodes
end
```

Replace the `spawnBunnies` definition so it records per-rig instances (state + mover):

```lua
local instances = {} -- { { rig = Model, state = FSMState, mover = Mover } }

local warnedNoSpawn = false
local function spawnBunnies()
	local spawns = Discovery.getAll(Tags.MonsterSpawn)
	if #spawns == 0 then
		if not warnedNoSpawn then
			warnedNoSpawn = true
			warn("[MonsterService] No MonsterSpawn marker found; no bunny spawned.")
		end
		return
	end
	for _, spawnPart in spawns do
		if spawnPart:IsA("BasePart") then
			local rig = createRig(spawnPart)
			table.insert(instances, { rig = rig, state = BunnyFSM.newState(), mover = createMover(rig) })
		end
	end
end
```

(Delete the old `warnedNoSpawn`/`spawnBunnies` block from Task 6 — this replaces it. There must be exactly one `spawnBunnies` and one `warnedNoSpawn`.)

Replace the trailing bare `spawnBunnies()` call with the catch handler, the spawn call, and the loop at the end of the file:

```lua
-- A catch reuses the hardened death/respawn: kill the player and cue the client
-- jumpscare. SpawnService handles RespawnDelay -> respawn at the checkpoint.
local function catch(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
		caughtRemote:FireClient(player)
	end
end

spawnBunnies()

-- Server-authoritative tick on the shared poll cadence (never Touched). dt comes
-- from os.clock deltas so FSM timers stay accurate even when ComputeAsync yields.
local lastClock = os.clock()
while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	local dt = now - lastClock
	lastClock = now
	local nodes = patrolNodePositions()
	for _, inst in instances do
		local rig = inst.rig
		local root = rig.PrimaryPart
		if root and rig.Parent then
			local sensed = {
				dt = dt,
				rigPosition = root.Position,
				patrolNodes = nodes,
				players = sensePlayers(rig),
			}
			local result = BunnyFSM.tick(inst.state, sensed)
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = result.speed
			end
			inst.mover.update(result.moveTarget, dt)
			rig:SetAttribute(STATE_ATTRIBUTE, inst.state.name)
			if result.caught then
				catch(result.caught)
			end
		end
	end
end
```

- [ ] **Step 2: Format, lint, sourcemap**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
rojo sourcemap --include-non-scripts -o sourcemap.json
```

Expected: clean.

- [ ] **Step 3: Playtest — patrol, chase, catch (MCP)**

`start_stop_play(is_start=true)`, then `execute_luau` (`Server`):

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local player = Players:GetPlayers()[1]
local log = {}
task.wait(1.0)
table.insert(log, "t1=" .. tostring(rig:GetAttribute("State"))) -- expect Patrol
local root = rig.PrimaryPart
player.Character.HumanoidRootPart.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 12)
task.wait(0.6)
table.insert(log, "t2=" .. tostring(rig:GetAttribute("State"))) -- expect Chase
return table.concat(log, " ")
```

Expected: `t1=Patrol t2=Chase`. Then leave the player in front a couple seconds and confirm the character dies and respawns at the checkpoint/PlayerStart (full catch flow is the Task 12 gate). `start_stop_play(is_start=false)`.

- [ ] **Step 4: Commit**

```bash
cd /home/toor/claude/RobloxMaze
git add src/server/MonsterService.server.luau sourcemap.json
git commit -m "MonsterService: tick loop wiring FSM + movement + state + catch"
```

---

## Task 10: Client jumpscare cue

A minimal client script: on `MonsterCaught`, show a placeholder full-screen red flash for `Config.Respawn.RespawnDelay`, covering the death→respawn window. No assets/sound yet (a later pass).

**Files:**
- Create: `src/client/JumpscareController.client.luau`

**Interfaces:**
- Consumes: `Remotes.Names.MonsterCaught`, `Config.Respawn.RespawnDelay`.
- Produces: a local visual effect only. Nothing other code imports.

- [ ] **Step 1: Implement the controller**

Create `src/client/JumpscareController.client.luau`:

```lua
--!nonstrict
-- JumpscareController.client.luau
-- Client-only feedback: when the server says this player was caught (MonsterCaught),
-- play a placeholder full-screen flash for the death->respawn window. Renders only;
-- the catch itself is server-authoritative. Swap the placeholder for real art/sound
-- in a later pass (no asset IDs here).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer
local caughtRemote = Remotes.get(Remotes.Names.MonsterCaught)

local gui = Instance.new("ScreenGui")
gui.Name = "JumpscareGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(140, 0, 0)
flash.BackgroundTransparency = 1
flash.Visible = false
flash.Parent = gui

caughtRemote.OnClientEvent:Connect(function()
	flash.Visible = true
	flash.BackgroundTransparency = 0.1
	local tween = TweenService:Create(
		flash,
		TweenInfo.new(Config.Respawn.RespawnDelay, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		flash.Visible = false
	end)
end)
```

- [ ] **Step 2: Format, lint, sourcemap**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua . && selene .
rojo sourcemap --include-non-scripts -o sourcemap.json
```

Expected: clean.

- [ ] **Step 3: Playtest — flash fires on catch (MCP)**

`start_stop_play(is_start=true)`. Trigger a catch by standing the player in front of the rig (as in Task 9 Step 3), then `execute_luau` (datamodel `Client`) immediately after the catch:

```lua
local Players = game:GetService("Players")
local gui = Players.LocalPlayer.PlayerGui:FindFirstChild("JumpscareGui")
local flash = gui and gui:FindFirstChildOfClass("Frame")
return flash and ("flash visible=" .. tostring(flash.Visible) .. " transp=" .. string.format("%.2f", flash.BackgroundTransparency)) or "NO GUI"
```

Expected: shortly after a catch, `flash visible=true` with transparency climbing toward 1 over `RespawnDelay`. Also `screen_capture` to eyeball the red flash. `start_stop_play(is_start=false)`.

- [ ] **Step 4: Commit**

```bash
cd /home/toor/claude/RobloxMaze
git add src/client/JumpscareController.client.luau sourcemap.json
git commit -m "Add JumpscareController: placeholder caught flash over the respawn window"
```

---

## Task 11: Documentation — CLAUDE.md

Record the new systems and shared additions so the convention doc stays accurate.

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing.
- Produces: updated systems + shared-module tables.

- [ ] **Step 1: Update the `Enums` shared-module-index row**

In the "Shared module index" table, replace this exact line:

```markdown
| `Enums`         | Enum-like constant tables (`GameState`; `MonsterType`/`MonsterState` stubs). |
```

with:

```markdown
| `Enums`         | Enum-like constant tables (`GameState`; `MonsterType.Bunny`; `MonsterState.{Patrol,Chase,Search}`). |
```

- [ ] **Step 2: Add the three systems rows**

In the Systems table, after the `KillBrickService` row, add the two server rows:

```markdown
| `MonsterService` | server | The bunny's owner. Spawns a valid procedural rig at each `MonsterSpawn`; each `Config.Spatial.PollInterval` senses players (vision cone + line-of-sight raycast, skipping `InSafeRoom`/`Won`), ticks the pure `BunnyFSM`, drives `PathfindingService` movement (with stall recovery + server `SetNetworkOwner`), writes the rig `State` attribute, and on a catch sets `Humanoid.Health = 0` (reusing SpawnService's respawn) and fires `MonsterCaught`. |
| `BunnyFSM` | server | Pure FSM module (`newState`/`tick`) for the bunny: Patrol (touring) → Chase → Search → give up. No Instance side-effects — `MonsterService` applies its decisions. |
```

and after the `HUDController` row (end of the client systems), add:

```markdown
| `JumpscareController` | client | On `MonsterCaught`, plays a placeholder full-screen flash for `Config.Respawn.RespawnDelay`. Renders only. |
```

- [ ] **Step 3: Note the now-used tags/remote**

In the `Tags` discovery section (or the `Remotes` shared-index row), add a brief note that `MonsterSpawn`/`PatrolPoint` are now in use (no longer "future" stubs) and `MonsterCaught` is registered. Replace this exact `Remotes` shared-index line:

```markdown
| `Remotes`       | RemoteEvent registry under one ReplicatedStorage folder; fetch by name. |
```

with:

```markdown
| `Remotes`       | RemoteEvent registry under one ReplicatedStorage folder; fetch by name (now includes `MonsterCaught`). |
```

- [ ] **Step 4: Commit**

```bash
cd /home/toor/claude/RobloxMaze
git add CLAUDE.md
git commit -m "Docs: document MonsterService, BunnyFSM, JumpscareController in CLAUDE.md"
```

---

## Task 12: Integration playtest — the 7 checks with per-run evidence

Run the spec's full test plan in the greybox via the MCP, capturing actual data (rig `State`, positions, respawn landing), in the same evidence-first style as the respawn verification. This is the definition-of-done gate. Every check below has an executable snippet.

**Files:**
- None (verification only).

- [ ] **Step 1: Start a fresh playtest**

`set_active_studio` → RobloxMaze; `start_stop_play(is_start=true)`. Confirm a rig exists and `State=Patrol`.

- [ ] **Step 2: Check 1 — Patrol tours (MCP `execute_luau`, `Server`)**

```lua
local Workspace = game:GetService("Workspace")
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local p0 = root.Position
task.wait(4)
return string.format("state=%s moved=%.1f", rig:GetAttribute("State"), (root.Position - p0).Magnitude)
```

Expected: `state=Patrol moved=` a value > 5 (it walked).

- [ ] **Step 3: Check 2 — detect → chase (in cone, clear LoS)**

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local hrp = Players:GetPlayers()[1].Character.HumanoidRootPart
hrp.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 14)
task.wait(0.6)
return "state=" .. rig:GetAttribute("State")
```

Expected: `state=Chase`.

- [ ] **Step 4: Check 3 — cone (behind the rig = not detected)**

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local hrp = Players:GetPlayers()[1].Character.HumanoidRootPart
-- first reset to Patrol by moving far away
hrp.CFrame = CFrame.new(-52, 3, -52)
task.wait(Workspace:GetAttribute("_x") or 7) -- wait out LoseSight+Search (~9s) to return to Patrol
hrp.CFrame = CFrame.new(root.Position - root.CFrame.LookVector * 10) -- directly behind, in range
task.wait(0.6)
return "state=" .. rig:GetAttribute("State") .. " (expect Patrol/Search, NOT Chase)"
```

Expected: `state=Patrol` (or `Search`) — **not** `Chase`. (If still Chase from a prior check, wait longer for it to give up first.)

- [ ] **Step 5: Check 4 — line of sight (behind a wall = not detected)**

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local hrp = Players:GetPlayers()[1].Character.HumanoidRootPart
-- place a temporary wall right in front of the rig, then the player just beyond it
local wall = Instance.new("Part")
wall.Anchored = true; wall.Size = Vector3.new(12, 12, 1); wall.Transparency = 0.5
wall.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 6)
wall.Parent = Workspace
hrp.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 10)
task.wait(0.6)
local s = rig:GetAttribute("State")
wall:Destroy()
return "state=" .. s .. " (expect NOT Chase: wall blocks LoS)"
```

Expected: `state` is `Patrol` or `Search` — **not** `Chase` (the wall blocks the LoS ray even though the player is in the cone).

- [ ] **Step 6: Check 5 — break sight (chase → Search → Patrol over the windows)**

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local hrp = Players:GetPlayers()[1].Character.HumanoidRootPart
-- trigger a chase
hrp.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 14)
task.wait(0.6)
local chasing = rig:GetAttribute("State")
-- break sight with a wall AND step aside (behind a wall = grace, not instant)
local wall = Instance.new("Part")
wall.Anchored = true; wall.Size = Vector3.new(14, 14, 1)
wall.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 5)
wall.Parent = Workspace
hrp.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 9 + root.CFrame.RightVector * 8)
task.wait(Config.Monster.LoseSightSeconds + 0.6)
local searching = rig:GetAttribute("State")
task.wait(Config.Monster.SearchDuration + 0.6)
local patrolling = rig:GetAttribute("State")
wall:Destroy()
return string.format("chasing=%s searching=%s patrolling=%s", chasing, searching, patrolling)
```

Expected: `chasing=Chase searching=Search patrolling=Patrol`.

- [ ] **Step 7: Check 6 — catch → respawn with keys intact**

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Attributes = require(ReplicatedStorage.Attributes)
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local player = Players:GetPlayers()[1]
player:SetAttribute(Attributes.KeyCount, 2) -- simulate held keys
local oldChar = player.Character
-- stand right on the rig to force a catch
player.Character.HumanoidRootPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 0, 2))
-- wait for death + the respawn (RespawnDelay) -> new character
local newChar = player.CharacterAdded:Wait()
local newHRP = newChar:WaitForChild("HumanoidRootPart", 5)
task.wait(0.3)
return string.format("respawned=%s keys=%s pos=(%.0f,%.0f,%.0f)",
    tostring(newChar ~= oldChar), tostring(player:GetAttribute(Attributes.KeyCount)),
    newHRP.Position.X, newHRP.Position.Y, newHRP.Position.Z)
```

Expected: `respawned=true keys=2 pos=` near the SafeRoom checkpoint or PlayerStart `(-52,_, -52)` — keys preserved through the catch.

- [ ] **Step 8: Check 7 — SafeRoom sanctuary (instant give-up)**

```lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local rig = Workspace.Monsters:FindFirstChild("Bunny")
local root = rig.PrimaryPart
local hrp = Players:GetPlayers()[1].Character.HumanoidRootPart
-- trigger a chase
hrp.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 14)
task.wait(0.6)
local chasing = rig:GetAttribute("State")
-- dive into the SafeRoom volume (sets InSafeRoom=true within ~1 poll)
local safe = CollectionService:GetTagged("SafeRoom")[1]
hrp.CFrame = CFrame.new(safe.Position.X, 3, safe.Position.Z)
task.wait(0.6) -- well under LoseSightSeconds: proves the drop is IMMEDIATE, not the grace
return string.format("chasing=%s afterSafeRoom=%s (expect not Chase, fast)", chasing, rig:GetAttribute("State"))
```

Expected: `chasing=Chase afterSafeRoom=Search` (or `Patrol`) within ~0.6s — confirming the **immediate** drop on SafeRoom entry, distinct from the 3s grace.

- [ ] **Step 9: Record results, stop, final lint**

Write the per-check observed values into the task notes; every check must pass. `start_stop_play(is_start=false)`. Then:

```bash
export PATH="$HOME/.rokit/bin:$PATH"
cd /home/toor/claude/RobloxMaze
stylua --check . && selene .
```

Expected: clean. If any check fails, file the specific failure and fix the relevant task before declaring done. Then confirm with the user whether to push.

---

## Self-Review (completed by the plan author, post adversarial-verification)

- **Spec coverage:** §2 pillars → Tasks 3–5 (FSM), 7 (detection), 9 (catch). §SafeRoom *immediate* give-up → Task 4 `tickChase` (`targetInSensed`) + Task 7 (`InSafeRoom` skip) + Task 12 check 8. §11 stall→repath → Task 8 mover. §3 build order → Task 1 before 6–9. §4 greybox (open-by-construction, MonsterSpawn off PatrolPoints) → Task 1. §5 valid rig (Head/HipHeight/RequiresNeck/SetNetworkOwner) → Task 6. §6 touring patrol → Task 3. §7 detection (root-based range, eye-based LoS) → Task 7. §8 catch handoff → Task 9 + Task 10. §9–10 registries/Config (incl. PatrolMemory/Stall*) → Task 2. §11 edge cases → warn-once (6, 9), pathfinding fallback + stall (8), SafeRoom/Won/nil-attr skip (7). §13 test plan → Task 12 (all 7 checks have runnable snippets).
- **Placeholder scan:** no TBD/TODO; every code step shows complete code; every command shows expected output; Task 12 checks 3–7 now have executable snippets; CLAUDE.md edits are quoted old→new.
- **Type consistency:** `PlayerSense.player: Player` (non-optional) — `beginChase`/`targetInSensed`/`caughtPlayer` use `.player.UserId`/`.player` accordingly; tests pass `{ UserId = n }` stubs. `newState`/`tick`/`Sensed`/`FSMState`(+`recentNodes`)/`TickResult` and all `Config.Monster.*` keys (incl. `PatrolMemory`/`StallEpsilon`/`StallTicks`) match across Tasks 2–9. `STATE_ATTRIBUTE = "State"` consistent (6/9/12). `MonsterCaught` consistent (2/9/10). `_G.__MonsterSensePlayers` defined in Task 7, used in Task 7 test.
