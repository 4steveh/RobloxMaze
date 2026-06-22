--!nonstrict
-- DataService.server.luau
-- The ONLY DataStoreService toucher. On join it CLAIMS A SESSION LOCK and loads the saved profile in
-- one atomic UpdateAsync, then hands it to PlayerData (the in-memory authority); during play
-- PlayerData owns the data (mutated by EconomyService/ShopService) and this script only PERSISTS it --
-- an autosave loop (keeps the lock), a save-and-release on leave, and a bounded, completion-tracked
-- flush on shutdown. Every write is read-modify-write via UpdateAsync (never a blind SetAsync), and
-- never proceeds if a DIFFERENT live session holds the lock -- so two servers (a teleport / fast
-- rejoin / region hop) can't both load the same profile and clobber each other's coins/cosmetics.
-- It DEGRADES GRACEFULLY: if DataStores are unavailable (e.g. Studio "API Services" off, or an
-- outage) it runs in-memory only so the game always plays; and after a failed load OR a live lock
-- held by another session it disables saving for that player, so it can never clobber real data.

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

-- This server's unique session id (live servers get a JobId; a Studio test session is "" -- but
-- DataStores are unavailable there anyway, so the fallback is cosmetic). Used to claim/own a
-- per-profile SESSION LOCK so two servers (a teleport / fast rejoin / region hop) can't both load
-- the same profile and blind-overwrite each other -- the loss the bare GetAsync/SetAsync allowed.
local SESSION = game.JobId ~= "" and game.JobId or "studio-session"

-- Stored record schema (wraps the profile so the lock can ride alongside it):
--   { _v = SCHEMA_V, data = <PlayerData.serialize payload>, lock = <session id | nil>, lockTime = <os.time | nil> }
-- An explicit `_v` discriminator (not "does it have a `data` field?") tells a wrapped record from a
-- pre-lock v1 RAW payload, so the classification can't be fooled by a future schema field. A v1 raw
-- record (no `_v`) is migrated in place on first touch, so existing saves load unchanged.
local SCHEMA_V = 2
local function normalizeRecord(record)
	if type(record) ~= "table" then
		return { _v = SCHEMA_V } -- nil/new player, or corrupted -> fresh wrapper (data nil -> defaults)
	end
	if record._v == SCHEMA_V then
		return record -- already wrapped (current schema)
	end
	return { _v = SCHEMA_V, data = record } -- legacy raw payload -> wrap it (its fields become the data)
end

-- Is this record currently owned by a DIFFERENT, still-LIVE session? (A lock older than
-- SessionLockStaleSeconds is treated as abandoned -- crash recovery -- and may be taken/overwritten.)
local function lockedByOther(record)
	return record.lock ~= nil
		and record.lock ~= SESSION
		and (os.time() - (record.lockTime or 0)) < P.SessionLockStaleSeconds
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

-- Claim the session lock and read the profile, in ONE atomic UpdateAsync (read-modify-write -- no
-- blind overwrite). Returns (data, status): "ok" (we own the lock), "locked" (a live session owns it),
-- "unavailable" (no DataStore), or "error" (call failed). On "ok" we wrote our lock + lockTime.
local function claimSession(player)
	if not store then
		return nil, "unavailable"
	end
	local loadedData, locked = nil, false
	local ok = withRetry(function()
		-- Reset per attempt: withRetry re-runs this closure, so a value left from a failed earlier
		-- attempt must not leak into the result (e.g. a stale `locked` surviving a since-freed lock).
		loadedData, locked = nil, false
		store:UpdateAsync(keyFor(player), function(record)
			record = normalizeRecord(record)
			if lockedByOther(record) then
				locked = true
				return nil -- cancel the write: never steal a live session
			end
			loadedData = record.data
			record.lock = SESSION
			record.lockTime = os.time()
			return record
		end)
		return true
	end)
	if not ok then
		return nil, "error"
	end
	if locked then
		return nil, "locked"
	end
	return loadedData, "ok"
end

local function onPlayerAdded(player)
	local data, status = claimSession(player)
	PlayerData.load(player, data)
	-- "locked"/"error" => we do NOT own this profile, so we NEVER save it (the ERRORED guard below) --
	-- that's what stops a second session clobbering the real data. "unavailable" (no DataStore, e.g.
	-- Studio API off) stays in-memory-only without erroring, exactly as before.
	if status == "locked" then
		player:SetAttribute(ERRORED_ATTR, true)
		warn("[DataService] " .. player.Name .. " is held by another live session -- in-memory only, saving disabled")
	elseif status == "error" then
		player:SetAttribute(ERRORED_ATTR, true)
		warn("[DataService] load failed for " .. player.Name .. " -- in-memory defaults; saving disabled")
	end
	dataReady:FireClient(player, PlayerData.clientSnapshot(player))
end

-- Persist the profile via UpdateAsync (read-modify-write -- never a blind SetAsync overwrite), but
-- only while we still hold the lock; if a different live session has taken it, abandon the write
-- rather than clobber them. `release` clears the lock on the way out (leave/shutdown) so a fast
-- rejoin elsewhere isn't locked out; the autosave keeps it (and refreshes lockTime). Returns ok.
local function persist(player, release)
	if not store or player:GetAttribute(ERRORED_ATTR) then
		return true -- nothing to do counts as done (so the shutdown completion counter advances)
	end
	local payload = PlayerData.serialize(player)
	if not payload then
		return true
	end
	local written = false
	local ok = withRetry(function()
		written = false -- per attempt (withRetry re-runs this); reflects only the final attempt
		store:UpdateAsync(keyFor(player), function(record)
			record = normalizeRecord(record)
			if lockedByOther(record) then
				return nil -- a live session owns it now; don't overwrite their data
			end
			record.data = payload
			record.lock = if release then nil else SESSION
			record.lockTime = if release then nil else os.time()
			written = true
			return record
		end)
		return true
	end)
	-- Only clear the dirty flag if a write actually COMMITTED. A cancelled write (lock lost to another
	-- live session) succeeds without throwing, but marking it saved would silently drop in-memory changes.
	if ok and written then
		PlayerData.markSaved(player)
	end
	return ok
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	persist(player, true) -- final save + RELEASE the lock (so a rejoin elsewhere isn't locked out)
	PlayerData.remove(player)
end)

-- Background autosave of dirty profiles (keeps the lock; refreshes lockTime so an active session's
-- lock never goes stale and gets stolen).
task.spawn(function()
	while true do
		task.wait(P.AutosaveInterval)
		for _, player in Players:GetPlayers() do
			if PlayerData.isDirty(player) then
				pcall(persist, player, false)
			end
		end
	end
end)

-- Flush on shutdown (skip in Studio test sessions). Bounded so a slow DataStore can't hang close --
-- but it now EXITS AS SOON AS every save completes (tracked via a counter), instead of blindly
-- burning the whole budget, and won't cut a save short while one is still in flight under budget.
game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	local players = Players:GetPlayers()
	local remaining = #players
	if remaining == 0 then
		return
	end
	for _, player in players do
		task.spawn(function()
			pcall(persist, player, true) -- final save + release on shutdown
			remaining -= 1
		end)
	end
	local deadline = os.clock() + P.BindToCloseBudgetSeconds
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
end)
