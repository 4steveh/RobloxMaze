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
	-- Expanded catalog (cosmetic-only beam tints; the shop ScrollingFrame auto-grows). Costs tier up
	-- so coins earned over many runs keep unlocking new looks -- the retention carrot, never pay-to-win.
	{ id = "flc_ember", name = "Ember", kind = "FlashlightColor", cost = 80, payload = Color3.fromRGB(255, 138, 60) },
	{ id = "flc_sodium", name = "Sodium", kind = "FlashlightColor", cost = 80, payload = Color3.fromRGB(255, 174, 96) },
	{ id = "flc_rose", name = "Rose", kind = "FlashlightColor", cost = 150, payload = Color3.fromRGB(255, 150, 192) },
	{ id = "flc_cyan", name = "Cyan", kind = "FlashlightColor", cost = 150, payload = Color3.fromRGB(120, 252, 238) },
	{ id = "flc_lime", name = "Lime", kind = "FlashlightColor", cost = 150, payload = Color3.fromRGB(192, 255, 110) },
	{ id = "flc_gold", name = "Gold", kind = "FlashlightColor", cost = 250, payload = Color3.fromRGB(255, 214, 110) },
	{
		id = "flc_spectre",
		name = "Spectre",
		kind = "FlashlightColor",
		cost = 250,
		payload = Color3.fromRGB(198, 220, 255),
	},
	{ id = "flc_void", name = "Void", kind = "FlashlightColor", cost = 350, payload = Color3.fromRGB(126, 84, 206) },
	{
		id = "flc_infrared",
		name = "Infrared",
		kind = "FlashlightColor",
		cost = 350,
		payload = Color3.fromRGB(255, 38, 38),
	},
	{ id = "flc_bone", name = "Bone", kind = "FlashlightColor", cost = 500, payload = Color3.fromRGB(236, 228, 208) },
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
