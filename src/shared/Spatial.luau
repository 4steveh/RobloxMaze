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

return Spatial
