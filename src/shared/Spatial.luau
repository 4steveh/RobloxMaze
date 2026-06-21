--!strict
-- Spatial.luau
-- Pure geometry helpers so services don't hand-roll math. These decide, in one
-- place, "is the player inside this safe room / close enough to this key". No
-- instance discovery here -- callers pass parts and positions.

local Spatial = {}

-- True if world-space `position` lies within `part`'s oriented bounding box. The
-- point is transformed into the part's local space and tested against the
-- half-extents on each axis, so rotated parts are handled correctly.
function Spatial.isInsidePart(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

-- True if `position` is within `radius` studs of `target` (inclusive).
function Spatial.withinRange(position: Vector3, target: Vector3, radius: number): boolean
	return (position - target).Magnitude <= radius
end

-- Distance from `position` to the CLOSEST POINT on `part`'s oriented bounding box
-- (0 if the point is inside). Unlike withinRange-to-center, this is robust to a
-- large, thick, or off-centre part: a player pressed against a wide door triggers at
-- the door SURFACE, not at its (possibly unreachable) centre. Used for the exit so a
-- big gate part can never make the win unreachable.
function Spatial.distanceToPart(position: Vector3, part: BasePart): number
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	-- Per-axis overshoot beyond the half-extents (clamped at 0 inside the box).
	local dx = math.max(math.abs(localPos.X) - half.X, 0)
	local dy = math.max(math.abs(localPos.Y) - half.Y, 0)
	local dz = math.max(math.abs(localPos.Z) - half.Z, 0)
	return Vector3.new(dx, dy, dz).Magnitude
end

return Spatial
