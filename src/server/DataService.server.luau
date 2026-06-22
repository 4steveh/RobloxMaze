--!nonstrict
-- DataService.server.luau
-- The ONLY DataStoreService toucher. On join it loads the saved profile and hands it to
-- PlayerData (the in-memory authority); during play PlayerData owns the data (mutated by
-- EconomyService/ShopService) and this script only PERSISTS it -- an autosave loop, a save on
-- leave, and a bounded flush on shutdown. It DEGRADES GRACEFULLY: if DataStores are unavailable
-- (e.g. Studio "API Services" off, or an outage) it runs in-memory only so the game always plays,
-- and after a FAILED load it disables saving for that player so it can never clobber real data.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local P = Config.Persistence
Remotes.init()
local dataReady = Remotes.get(Remotes.Names.DataReady)

local ERRORED_ATTR = "__dataErrored" -- set when a load failed: never save (don't overwrite real data)

local store
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(P.DataStoreName)
	end)
	store = ok and s or nil
end

local function keyFor(player)
	return "p_" .. player.UserId
end

-- pcall + exponential backoff. Returns ok, result.
local function withRetry(fn)
	local attempt = 0
	while true do
		attempt += 1
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		if attempt >= P.MaxRetries then
			return false, res
		end
		task.wait(P.RetryBaseDelay * 2 ^ (attempt - 1))
	end
end

local function onPlayerAdded(player)
	local data, errored = nil, false
	if store then
		local ok, res = withRetry(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			data = res
		else
			errored = true
			warn("[DataService] load failed for " .. player.Name .. " -- in-memory defaults; saving disabled")
		end
	end
	PlayerData.load(player, data)
	if errored then
		player:SetAttribute(ERRORED_ATTR, true)
	end
	dataReady:FireClient(player, PlayerData.clientSnapshot(player))
end

local function save(player)
	if not store or player:GetAttribute(ERRORED_ATTR) then
		return
	end
	local payload = PlayerData.serialize(player)
	if not payload then
		return
	end
	local ok = withRetry(function()
		store:SetAsync(keyFor(player), payload)
		return true
	end)
	if ok then
		PlayerData.markSaved(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	save(player)
	PlayerData.remove(player)
end)

-- Background autosave of dirty profiles.
task.spawn(function()
	while true do
		task.wait(P.AutosaveInterval)
		for _, player in Players:GetPlayers() do
			if PlayerData.isDirty(player) then
				pcall(save, player)
			end
		end
	end
end)

-- Flush on shutdown (skip in Studio test sessions). Bounded so a slow DataStore can't hang close.
game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	local deadline = os.clock() + P.BindToCloseBudgetSeconds
	for _, player in Players:GetPlayers() do
		task.spawn(save, player)
	end
	while os.clock() < deadline do
		task.wait(0.1)
	end
end)
