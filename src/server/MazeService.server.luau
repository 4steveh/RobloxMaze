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
local ServerSignals = require(script.Parent.ServerSignals)

local M = Config.Maze
local mazeRebuilt = ServerSignals.get(ServerSignals.Names.MazeRebuilt)

if not M.Enabled then
	return -- static layout: leave the placed maze untouched
end

local maze = Workspace:WaitForChild("Maze")

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

-- A path smoke test between two cell centres (navmesh truth -- catches a stale tile).
local function pathOK(fromC: number, fromR: number, toC: number, toR: number): boolean
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function()
		path:ComputeAsync(cellCenter(fromC, fromR) + Vector3.new(0, 3, 0), cellCenter(toC, toR) + Vector3.new(0, 3, 0))
	end)
	return ok and path.Status == Enum.PathStatus.Success
end

-- Carve a fresh random layout, verify, and announce. Retries on a failed smoke test.
local carving = false
local function carve()
	if carving then
		return
	end
	carving = true
	local gateC, gateR = M.ExitCol, M.Rows - 1 -- the cell just south of the gate
	for attempt = 1, M.MaxCarveRetries do
		local rng = Random.new()
		local res = Maze.generate(M.Cols, M.Rows, rng, M.StartCol, 0)
		Maze.braid(res.open, M.Cols, M.Rows, rng, M.BraidFraction)
		-- Layer 1: graph proof (microseconds; catches a logic error before we touch the world).
		if Maze.allReachable(res.open, M.Cols, M.Rows, M.StartCol, 0) then
			for edge in edgeWalls do
				setOpen(edge, res.open[edge] == true)
			end
			-- Layer 2: navmesh truth, after the tiles re-rasterize.
			task.wait(M.NavmeshSettleSeconds)
			if pathOK(M.EntranceCol, 0, gateC, gateR) then
				carving = false
				mazeRebuilt:Fire()
				return
			end
			warn(`[MazeService] carve attempt {attempt}: navmesh smoke test failed; re-carving`)
		end
	end
	warn("[MazeService] all carve retries failed the smoke test; proceeding with the last layout")
	carving = false
	mazeRebuilt:Fire()
end

-- Initial carve at boot (async: the settle wait must not block the rest of server startup; monsters
-- are dormant during the peace window, so the maze is ready long before they hunt).
task.spawn(carve)

-- A fresh layout every round. The peace window re-arms on RoundReset too, covering the settle.
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	task.spawn(carve)
end)
