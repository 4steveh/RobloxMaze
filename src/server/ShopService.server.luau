--!nonstrict
-- ShopService.server.luau
-- Owns the ShopAction inbound remote -- the pay-to-win firewall. Treats the payload as HOSTILE
-- (validates the op + id types, that the id is a real Cosmetic, and rate-limits like SprintIntent),
-- then routes buy/equip through PlayerData, which re-checks cost + ownership server-side (the
-- client's claimed price/ownership is never trusted). Replies via ShopResult.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Cosmetics = require(ReplicatedStorage.Cosmetics)
local PlayerData = require(script.Parent.PlayerData)

Remotes.init()
local shopAction = Remotes.get(Remotes.Names.ShopAction)
local shopResult = Remotes.get(Remotes.Names.ShopResult)

local lastAction = {} -- [player] = os.clock of the last accepted action

shopAction.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		return -- malformed -> ignore
	end
	local op, id = payload.op, payload.id
	if type(op) ~= "string" or type(id) ~= "string" or not Cosmetics.get(id) then
		return -- malformed / unknown item -> ignore
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < Config.Economy.ShopActionRateLimit then
		return -- spam -> ignore
	end
	lastAction[player] = now

	local ok, reason
	if op == "buy" then
		ok, reason = PlayerData.tryPurchase(player, id)
	elseif op == "equip" then
		ok, reason = PlayerData.tryEquip(player, id)
	else
		return
	end
	shopResult:FireClient(player, { ok = ok, op = op, id = id, reason = reason })
end)

Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
end)
