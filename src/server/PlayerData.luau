--!nonstrict
-- PlayerData.luau (server module)
-- The single in-memory SOURCE OF TRUTH for each player's persistent profile (coins, owned
-- cosmetics, equipped). Required by DataService (DataStore I/O), EconomyService (awards) and
-- ShopService (purchases) -- they coordinate THROUGH this module's API rather than calling each
-- other (the same module discipline as Spatial/Discovery, applied server-side). It mirrors the
-- profile onto leaderstats.Coins + the Coins / EquippedFlashlightColor attributes for the client;
-- those are READ-ONLY views, never the authority.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Attributes)
local Cosmetics = require(ReplicatedStorage.Cosmetics)

local PlayerData = {}

-- [player] = { coins, owned = {[id]=true}, equipped = {[kind]=id}, ready, dirty }
local profiles = {}

local function defaultProfile()
	local owned = {}
	for _, c in Cosmetics.List do
		if c.cost == 0 then
			owned[c.id] = true -- cost-0 starters are owned from the first join
		end
	end
	local equipped = table.clone(Cosmetics.DefaultEquipped)
	return { coins = 0, owned = owned, equipped = equipped, ready = false, dirty = false }
end

-- Push the profile onto the player's leaderstats + attributes (the client's read-only view).
local function mirror(player, p)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local coinsVal = ls:FindFirstChild("Coins")
	if not coinsVal then
		coinsVal = Instance.new("IntValue")
		coinsVal.Name = "Coins"
		coinsVal.Parent = ls
	end
	coinsVal.Value = p.coins
	player:SetAttribute(Attributes.Coins, p.coins)
	player:SetAttribute(Attributes.EquippedFlashlightColor, p.equipped.FlashlightColor)
end

-- Called by DataService after a load (data nil = new/unavailable -> defaults; validated field-wise).
function PlayerData.load(player, data)
	local p = defaultProfile()
	if type(data) == "table" then
		if type(data.coins) == "number" then
			p.coins = math.max(0, math.floor(data.coins))
		end
		if type(data.owned) == "table" then
			for id in data.owned do
				if Cosmetics.get(id) then
					p.owned[id] = true
				end
			end
		end
		if type(data.equipped) == "table" then
			for kind, id in data.equipped do
				if Cosmetics.get(id) and p.owned[id] then
					p.equipped[kind] = id
				end
			end
		end
	end
	p.ready = true
	profiles[player] = p
	mirror(player, p)
	return p
end

function PlayerData.isReady(player)
	local p = profiles[player]
	return p ~= nil and p.ready
end

-- Only the persistent fields (for saving).
function PlayerData.serialize(player)
	local p = profiles[player]
	if not p then
		return nil
	end
	local owned = {}
	for id in p.owned do
		owned[id] = true
	end
	return { coins = p.coins, owned = owned, equipped = p.equipped }
end

-- A snapshot for the client's shop UI (owned set + equipped + coins). Sent on DataReady and
-- kept in sync client-side from ShopResult; coins also live-update via the Coins attribute.
function PlayerData.clientSnapshot(player)
	local p = profiles[player]
	if not p then
		return nil
	end
	local owned = {}
	for id in p.owned do
		table.insert(owned, id)
	end
	return { coins = p.coins, owned = owned, equipped = p.equipped }
end

function PlayerData.isDirty(player)
	local p = profiles[player]
	return p ~= nil and p.dirty
end
function PlayerData.markSaved(player)
	local p = profiles[player]
	if p then
		p.dirty = false
	end
end
function PlayerData.remove(player)
	profiles[player] = nil
end

-- Award coins (EconomyService). Returns the new total.
function PlayerData.award(player, amount)
	local p = profiles[player]
	if not p then
		return 0
	end
	p.coins += math.max(0, math.floor(amount or 0))
	p.dirty = true
	mirror(player, p)
	return p.coins
end

-- Buy a cosmetic (ShopService). Server re-checks cost + ownership. Returns ok, reason.
function PlayerData.tryPurchase(player, id)
	local p = profiles[player]
	if not p then
		return false, "not_ready"
	end
	local c = Cosmetics.get(id)
	if not c then
		return false, "no_item"
	end
	if p.owned[id] then
		return false, "owned"
	end
	if p.coins < c.cost then
		return false, "too_poor"
	end
	p.coins -= c.cost
	p.owned[id] = true
	p.equipped[c.kind] = id -- auto-equip a freshly bought cosmetic (instant feedback; avoids a second rate-limited remote)
	p.dirty = true
	mirror(player, p)
	return true
end

-- Equip an OWNED cosmetic. Returns ok, reason.
function PlayerData.tryEquip(player, id)
	local p = profiles[player]
	if not p then
		return false, "not_ready"
	end
	local c = Cosmetics.get(id)
	if not c then
		return false, "no_item"
	end
	if not p.owned[id] then
		return false, "not_owned"
	end
	p.equipped[c.kind] = id
	p.dirty = true
	mirror(player, p)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	-- DataService saves BEFORE this fires; if it ever doesn't, drop the stale copy here.
	task.delay(5, function()
		PlayerData.remove(player)
	end)
end)

return PlayerData
