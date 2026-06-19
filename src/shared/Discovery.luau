--!strict
-- Discovery.luau
-- Thin wrapper over CollectionService so systems never hardcode instance paths
-- or names. Find tagged level objects via Tags + Discovery only; code then
-- adapts to wherever markers are placed in Studio.

local CollectionService = game:GetService("CollectionService")

local Discovery = {}

-- Returns all instances currently tagged with `tag`.
function Discovery.getAll(tag: string): { Instance }
	return CollectionService:GetTagged(tag)
end

-- Observe a tag. Fires `onAdded` once for every instance already tagged at call
-- time, and again for any instance tagged later; fires the optional `onRemoved`
-- when a tagged instance loses the tag or is destroyed. De-duplicated via a seen
-- set, so an instance present at call time will not also fire from the added
-- signal. Returns a cleanup function that disconnects the observer.
function Discovery.observe(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?): () -> ()
	local seen: { [Instance]: boolean } = {}

	local function handleAdded(instance: Instance)
		if seen[instance] then
			return
		end
		seen[instance] = true
		onAdded(instance)
	end

	local function handleRemoved(instance: Instance)
		if not seen[instance] then
			return
		end
		seen[instance] = nil
		if onRemoved then
			onRemoved(instance)
		end
	end

	-- Connect before snapshotting existing instances so nothing tagged during
	-- setup is missed; the seen set prevents a double fire.
	local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(handleAdded)
	local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(handleRemoved)

	for _, instance in CollectionService:GetTagged(tag) do
		handleAdded(instance)
	end

	return function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		table.clear(seen)
	end
end

return Discovery
