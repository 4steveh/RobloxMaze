--!nonstrict
-- GameBootstrap.server.luau
-- Skeleton sanity check. On server start, count and print how many instances
-- carry each level-marker tag. This verifies the whole pipeline -- Rojo sync ->
-- Tags -> CollectionService -> Discovery -- before any gameplay exists. No
-- gameplay logic belongs here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)

-- Only the markers expected to exist for this milestone.
local MARKERS = {
	Tags.PlayerStart,
	Tags.ExitDoor,
	Tags.KeySpot,
	Tags.SafeRoom,
}

print("[GameBootstrap] Marker discovery sanity check:")
for _, tag in MARKERS do
	print(string.format("  %s: %d", tag, #Discovery.getAll(tag)))
end
