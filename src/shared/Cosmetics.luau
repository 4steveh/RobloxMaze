--!strict
-- Cosmetics.luau
-- The frozen cosmetic catalog -- the ONLY place cosmetic items are defined (the Tags/Config
-- discipline for shop items). Cosmetics are COSMETIC ONLY (never affect battery/range/
-- detection) so the shop can never be pay-to-win. Each `id` is a STABLE string that the
-- DataStore stores forever -- never rename or reuse an id.
--
-- kind = "FlashlightColor": payload is the SpotLight Color3 the client applies to the beam.
-- cost 0 = a starter item every player owns from the first join (seeded by PlayerData).

export type Cosmetic = {
	id: string,
	name: string,
	kind: string,
	cost: number,
	payload: any,
}

local Cosmetics = {}

-- Ordered list (the shop renders in this order). Add new items by appending; never reorder
-- ids out from under saved data.
Cosmetics.List = {
	{
		id = "flc_white",
		name = "Standard",
		kind = "FlashlightColor",
		cost = 0,
		payload = Color3.fromRGB(255, 255, 255),
	},
	{ id = "flc_amber", name = "Amber", kind = "FlashlightColor", cost = 60, payload = Color3.fromRGB(255, 196, 120) },
	{ id = "flc_blood", name = "Blood", kind = "FlashlightColor", cost = 120, payload = Color3.fromRGB(255, 90, 80) },
	{ id = "flc_toxic", name = "Toxic", kind = "FlashlightColor", cost = 120, payload = Color3.fromRGB(150, 240, 120) },
	{
		id = "flc_violet",
		name = "Violet",
		kind = "FlashlightColor",
		cost = 200,
		payload = Color3.fromRGB(180, 130, 255),
	},
	{ id = "flc_ice", name = "Ice", kind = "FlashlightColor", cost = 200, payload = Color3.fromRGB(150, 220, 255) },
}

-- The cost-0 starters every profile owns + the default equipped item, by kind.
Cosmetics.DefaultEquipped = {
	FlashlightColor = "flc_white",
}

local byId = {}
for _, c in Cosmetics.List do
	byId[c.id] = c
end

function Cosmetics.get(id: string): Cosmetic?
	return byId[id]
end

return table.freeze(Cosmetics)
