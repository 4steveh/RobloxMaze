--!strict
-- Maze.luau
-- Pure maze generator (the runtime-randomization brain). An ITERATIVE recursive-backtracker over a
-- Cols x Rows grid that returns a SPANNING TREE: every cell is connected BY CONSTRUCTION, so
-- connectivity needs no validation -- a corridor always reaches every cell centre (where the
-- keys/exit/spawns sit). The output is the set of OPEN interior edges (the walls MazeService slides
-- DOWN into wells); every other wall stays raised. No Instance work, no global state -- the caller
-- passes a seeded `Random`, so a seed reproduces a maze. Unit-testable like Gaits.
--
-- Edge ids encode a physical wall:
--   "V_c_r" = the VERTICAL wall on the line between columns c and c+1, at row r  (c in 0..Cols-2)
--   "H_c_r" = the HORIZONTAL wall on the line between rows r and r+1, at column c (r in 0..Rows-2)
-- MazeService maps each id to a world-positioned wall part.

local Maze = {}

local function cellKey(c: number, r: number): string
	return c .. "," .. r
end

-- The in-grid neighbours of (c,r), each paired with the edge id of the wall BETWEEN them.
local function neighbours(c: number, r: number, cols: number, rows: number): { { c: number, r: number, edge: string } }
	local out = {}
	if c + 1 < cols then
		table.insert(out, { c = c + 1, r = r, edge = "V_" .. c .. "_" .. r })
	end
	if c - 1 >= 0 then
		table.insert(out, { c = c - 1, r = r, edge = "V_" .. (c - 1) .. "_" .. r })
	end
	if r + 1 < rows then
		table.insert(out, { c = c, r = r + 1, edge = "H_" .. c .. "_" .. r })
	end
	if r - 1 >= 0 then
		table.insert(out, { c = c, r = r - 1, edge = "H_" .. c .. "_" .. (r - 1) })
	end
	return out
end

-- Every interior edge id of the grid (used by braiding + as the full wall set).
function Maze.allEdges(cols: number, rows: number): { string }
	local all = {}
	for c = 0, cols - 2 do
		for r = 0, rows - 1 do
			table.insert(all, "V_" .. c .. "_" .. r)
		end
	end
	for c = 0, cols - 1 do
		for r = 0, rows - 2 do
			table.insert(all, "H_" .. c .. "_" .. r)
		end
	end
	return all
end

-- Generate a spanning-tree maze. Returns { open = { [edge] = true } }: exactly cols*rows-1 open
-- edges, every cell reachable by construction. `rng` is a seeded Random (purity/determinism).
function Maze.generate(
	cols: number,
	rows: number,
	rng: Random,
	startC: number?,
	startR: number?
): { open: { [string]: boolean } }
	local visited: { [string]: boolean } = {}
	local open: { [string]: boolean } = {}
	local stack: { { c: number, r: number } } = {}
	local sc, sr = startC or 0, startR or 0
	visited[cellKey(sc, sr)] = true
	table.insert(stack, { c = sc, r = sr })
	while #stack > 0 do
		local cur = stack[#stack]
		local unvisited = {}
		for _, n in neighbours(cur.c, cur.r, cols, rows) do
			if not visited[cellKey(n.c, n.r)] then
				table.insert(unvisited, n)
			end
		end
		if #unvisited == 0 then
			table.remove(stack) -- dead end -> backtrack
		else
			local pick = unvisited[rng:NextInteger(1, #unvisited)]
			open[pick.edge] = true
			visited[cellKey(pick.c, pick.r)] = true
			table.insert(stack, { c = pick.c, r = pick.r })
		end
	end
	return { open = open }
end

-- Braid: open a random FRACTION of the still-closed edges. This only ever OPENS edges, so it can
-- never disconnect the maze -- it just removes some dead-ends so the layout isn't one perfect
-- corridor (more loops = more interesting routes). Mutates `open`.
function Maze.braid(open: { [string]: boolean }, cols: number, rows: number, rng: Random, fraction: number)
	for _, e in Maze.allEdges(cols, rows) do
		if not open[e] and rng:NextNumber() < fraction then
			open[e] = true
		end
	end
end

-- Flood-fill the cells reachable from (startC,startR) through the open edges (verification layer 1:
-- a spanning tree is reachable by construction, but this catches a wall that physically FAILED to
-- move, in microseconds). Returns a set of "c,r" keys.
function Maze.floodReachable(
	open: { [string]: boolean },
	cols: number,
	rows: number,
	startC: number,
	startR: number
): { [string]: boolean }
	local reach: { [string]: boolean } = {}
	local q: { { c: number, r: number } } = { { c = startC, r = startR } }
	reach[cellKey(startC, startR)] = true
	local qi = 1
	while qi <= #q do
		local cur = q[qi]
		qi += 1
		for _, n in neighbours(cur.c, cur.r, cols, rows) do
			if open[n.edge] and not reach[cellKey(n.c, n.r)] then
				reach[cellKey(n.c, n.r)] = true
				table.insert(q, { c = n.c, r = n.r })
			end
		end
	end
	return reach
end

-- Are ALL cells reachable from the start? (the spanning-tree guarantee, cheaply re-checked.)
function Maze.allReachable(
	open: { [string]: boolean },
	cols: number,
	rows: number,
	startC: number,
	startR: number
): boolean
	local reach = Maze.floodReachable(open, cols, rows, startC, startR)
	local n = 0
	for _ in reach do
		n += 1
	end
	return n == cols * rows
end

return Maze
