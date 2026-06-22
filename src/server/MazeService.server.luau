--!nonstrict
-- MazeService.server.luau
-- Owns the RUNTIME MAZE (the replayability lever): a different layout every round, navmesh-safe.
--
-- It builds a permanent wall SUPERSTRUCTURE from code (one anchored wall per potential interior edge
-- of the Cols x Rows grid, + the grid perimeter with the daycare-entrance gap and the exit gate gap),
-- then each round carves a fresh random spanning tree (the pure Maze.generate) by SLIDING the "open"
-- edges' walls DOWN into a well below the floor (+ CanCollide off) and raising the rest. It NEVER
-- destroys a wall at runtime -- moving anchored parts re-rasterizes the PathfindingService navmesh
-- reliably, while destroying/creating them is the confirmed unfixed engine bug that strands the AI.
--
-- Connectivity is GUARANTEED BY CONSTRUCTION (a spanning tree reaches every cell centre, where the
-- keys/exit/spawns sit), and re-verified two ways: a graph flood-fill (catches a wall that failed to
-- move) + a real PathfindingService:ComputeAsync smoke test entrance->gate (catches a stale navmesh
-- tile). MonsterService's peace window covers the settle, so monsters never path a half-built maze.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Config)
local Maze = require(ReplicatedStorage.Maze)
local Tags = require(ReplicatedStorage.Tags)
local ServerSignals = require(script.Parent.ServerSignals)

local M = Config.Maze
local SHARED = Config.Monster.Shared -- pathfinding agent dims (single source of truth)
local mazeRebuilt = ServerSignals.get(ServerSignals.Names.MazeRebuilt)

if not M.Enabled then
	return -- static layout: leave the placed maze untouched
end

-- A clean checkout has no Workspace.Maze (it's unsaved place content). Bound the wait so a missing
-- folder DEGRADES (warn, leave the static maze / no maze) instead of hanging the service forever.
local maze = Workspace:WaitForChild("Maze", 10)
if not maze then
	warn("[MazeService] Workspace.Maze not found within 10s -- runtime maze randomization disabled this session.")
	return
end

-- World position of cell (c,r)'s centre (floor height).
local function cellCenter(c: number, r: number): Vector3
	return Vector3.new(
		M.OriginX + M.CellSize * c + M.CellSize / 2,
		M.FloorY,
		M.OriginZ + M.CellSize * r + M.CellSize / 2
	)
end

-- The closed-state world position + size of an interior edge wall.
local function edgeGeom(edge: string): (Vector3, Vector3)
	local t, cs, rs = edge:match("^(%a)_(%d+)_(%d+)$")
	local c, r = tonumber(cs), tonumber(rs)
	local y = M.FloorY + M.WallHeight / 2
	if t == "V" then -- vertical wall on the line between columns c and c+1, at row r
		local x = M.OriginX + M.CellSize * (c + 1)
		local z = M.OriginZ + M.CellSize * r + M.CellSize / 2
		return Vector3.new(x, y, z), Vector3.new(M.WallThickness, M.WallHeight, M.CellSize + M.WallThickness)
	end -- "H": horizontal wall on the line between rows r and r+1, at column c
	local z = M.OriginZ + M.CellSize * (r + 1)
	local x = M.OriginX + M.CellSize * c + M.CellSize / 2
	return Vector3.new(x, y, z), Vector3.new(M.CellSize + M.WallThickness, M.WallHeight, M.WallThickness)
end

local function makeWall(name: string, pos: Vector3, size: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Color = M.WallColor
	p.Material = M.WallMaterial
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = maze
	return p
end

-- 1) Remove the old FIXED-layout walls (the placed "W" set) -- but keep the tagged ExitGate, which
-- ExitService owns. This runs ONCE at boot, before any monster paths, so destroying here is safe
-- (no prior navmesh to leave stale); at runtime we only ever MOVE walls.
for _, w in ipairs(maze:GetChildren()) do
	if w:IsA("BasePart") and w.Name == "W" and not CollectionService:HasTag(w, "ExitGate") then
		w:Destroy()
	end
end

-- 2) Build the interior superstructure: one wall per edge, raised (closed) to start.
local OPEN_Y = M.FloorY + M.WallHeight / 2 - M.WellDepth
local edgeWalls = {} -- [edge] = { part, closedPos }
for _, edge in ipairs(Maze.allEdges(M.Cols, M.Rows)) do
	local pos, size = edgeGeom(edge)
	edgeWalls[edge] = { part = makeWall("MW_" .. edge, pos, size), closedPos = pos }
end

-- 3) Build the grid perimeter rows (north = the exit-gate line, south = the daycare-entrance line),
-- solid except their one gap column. The existing MazeWallW/E (X = ±60) close the sides; the ExitGate
-- fills the north gap; the daycare doorway aligns with the south gap.
local function buildPerimeterRow(z: number, gapCol: number, prefix: string)
	for c = 0, M.Cols - 1 do
		if c ~= gapCol then
			local x = M.OriginX + M.CellSize * c + M.CellSize / 2
			makeWall(
				prefix .. c,
				Vector3.new(x, M.FloorY + M.WallHeight / 2, z),
				Vector3.new(M.CellSize + M.WallThickness, M.WallHeight, M.WallThickness)
			)
		end
	end
end
buildPerimeterRow(M.OriginZ + M.CellSize * M.Rows, M.ExitCol, "MGN_") -- grid-north (the gate line)
buildPerimeterRow(M.OriginZ, M.EntranceCol, "MGS_") -- grid-south (the daycare-entrance line)

-- Boot validation: the cell-centre reachability guarantee only holds if the in-grid markers (keys/
-- traps/monkey-nest/patrol nodes) actually SIT at cell centres -- a marker drifted onto an edge can
-- be walled off by a raising wall on some random rounds (a silent, round-dependent break). We can't
-- auto-fix placed content, but we WARN loudly so it's caught before publish, not in a playtest.
local function validateMarkers()
	local gridMaxX = M.OriginX + M.CellSize * M.Cols
	local gridMaxZ = M.OriginZ + M.CellSize * M.Rows
	for _, tag in ipairs({ Tags.KeySpot, Tags.Trap, Tags.MonkeySpawn, Tags.PatrolPoint }) do
		for _, marker in ipairs(CollectionService:GetTagged(tag)) do
			if marker:IsA("BasePart") then
				local p = marker.Position
				if p.X >= M.OriginX and p.X <= gridMaxX and p.Z >= M.OriginZ and p.Z <= gridMaxZ then
					-- in the maze grid: nearest cell centre and the XZ deviation from it
					local c = math.floor((p.X - M.OriginX) / M.CellSize)
					local r = math.floor((p.Z - M.OriginZ) / M.CellSize)
					local centre = cellCenter(c, r)
					local devX, devZ = math.abs(p.X - centre.X), math.abs(p.Z - centre.Z)
					if devX > 2 or devZ > 2 then
						warn(
							`[MazeService] '{marker.Name}' [{tag}] at ({string.format("%.0f,%.0f", p.X, p.Z)}) is OFF cell centre ({string.format(
								"%.0f,%.0f",
								centre.X,
								centre.Z
							)}) by ({string.format("%.0f,%.0f", devX, devZ)}) -- it may be walled off on some random mazes. Snap it to the cell centre.`
						)
					end
				end
			end
		end
	end
end
task.defer(validateMarkers) -- after CollectionService tags settle

-- Open (slide into the well, no collision) or close (raise, collidable) one edge's wall.
local function setOpen(edge: string, open: boolean)
	local w = edgeWalls[edge]
	if not w then
		return
	end
	if open then
		w.part.CanCollide = false
		w.part.Position = Vector3.new(w.closedPos.X, OPEN_Y, w.closedPos.Z)
	else
		w.part.CanCollide = true
		w.part.Position = w.closedPos
	end
end

-- A path smoke test between two cell centres (navmesh truth -- catches a stale tile). Uses the
-- monster AGENT dims (Config single source) so it validates the path the rigs actually walk.
local function pathStatus(fromC: number, fromR: number, toC: number, toR: number): string
	local path = PathfindingService:CreatePath({
		AgentRadius = SHARED.AgentRadius,
		AgentHeight = SHARED.AgentHeight,
		AgentCanJump = false,
	})
	local ok = pcall(function()
		path:ComputeAsync(cellCenter(fromC, fromR) + Vector3.new(0, 3, 0), cellCenter(toC, toR) + Vector3.new(0, 3, 0))
	end)
	return if ok then tostring(path.Status) else "ComputeError"
end

local function applyLayout(open: { [string]: boolean })
	for edge in edgeWalls do
		setOpen(edge, open[edge] == true)
	end
end

-- One carve: generate -> apply -> settle -> smoke test, retrying. NEVER leaves an UNVERIFIED layout:
-- on total failure it reverts to the last layout that passed (the safe fallback), so a freak navmesh
-- hiccup can't ship a round with a possibly-disconnected exit.
local lastGoodLayout: { [string]: boolean }? = nil
local function carveOnce(): boolean
	local gateC, gateR = M.ExitCol, M.Rows - 1 -- the cell just south of the gate
	for attempt = 1, M.MaxCarveRetries do
		local rng = Random.new()
		local res = Maze.generate(M.Cols, M.Rows, rng, M.StartCol, 0)
		Maze.braid(res.open, M.Cols, M.Rows, rng, M.BraidFraction)
		-- Layer 1: graph proof (microseconds; catches a logic error before we touch the world).
		if Maze.allReachable(res.open, M.Cols, M.Rows, M.StartCol, 0) then
			applyLayout(res.open)
			task.wait(M.NavmeshSettleSeconds) -- Layer 2: navmesh truth, after the tiles re-rasterize.
			local status = pathStatus(M.EntranceCol, 0, gateC, gateR)
			if status == "Enum.PathStatus.Success" then
				lastGoodLayout = res.open
				return true
			end
			warn(`[MazeService] carve attempt {attempt}/{M.MaxCarveRetries}: smoke test {status}; re-carving`)
		end
	end
	if lastGoodLayout then
		warn("[MazeService] all carve retries failed; reverting to the last VERIFIED layout")
		applyLayout(lastGoodLayout)
		task.wait(M.NavmeshSettleSeconds)
	else
		warn(
			"[MazeService] all carve retries failed and no verified layout exists; using the last attempt (graph-connected)"
		)
	end
	return false
end

-- Carve, COALESCING re-carve requests: a RoundReset that arrives mid-carve is never dropped (which
-- would silently reuse the previous round's maze) -- it runs once the in-flight carve finishes.
local carving = false
local pendingCarve = false
local function carve()
	if carving then
		pendingCarve = true
		return
	end
	carving = true
	repeat
		pendingCarve = false
		carveOnce()
		mazeRebuilt:Fire() -- announce ready (MonsterService gates its hunt on this)
	until not pendingCarve
	carving = false
end

-- Initial carve at boot (async: the settle wait must not block the rest of server startup; monsters
-- are gated dormant until MazeRebuilt + through the peace window, so the maze is ready before they hunt).
task.spawn(carve)

-- A fresh layout every round.
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	task.spawn(carve)
end)
