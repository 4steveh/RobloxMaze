--!nonstrict
-- Remotes.luau
-- Central registry of RemoteEvents. The server creates them under a single
-- ReplicatedStorage folder; both sides fetch them by name -- no manual instance
-- plumbing or hardcoded paths. Add new remotes to REMOTE_EVENTS; later prompts
-- populate this list and validate every remote on the server.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

-- Canonical RemoteEvent names. Like Tags for tags, this is the ONLY place these
-- strings live -- server and client both refer to them as Remotes.Names.X.
local Names = table.freeze({
	SafeRoomEntered = "SafeRoomEntered", -- server -> client: the player's HumanoidRootPart entered a SafeRoom
	SafeRoomLeft = "SafeRoomLeft", -- server -> client: ...and then left it
	KeyCollected = "KeyCollected", -- server -> client: a key was picked up (payload: new key count)
	GameWon = "GameWon", -- server -> client: this player reached the exit with enough keys
	ExitLocked = "ExitLocked", -- server -> client: at the exit without enough keys (brief feedback)
	ExitOpened = "ExitOpened", -- server -> ALL clients: a player escaped / the exit gate swung open (door-open SFX + "someone escaped" note for non-winners; payload: escapee name)
	MonsterCaught = "MonsterCaught", -- server -> client: this player was caught (payload: downed:boolean -- true = grabbed into the revivable DOWNED state, false/nil = killed → respawn; species:string -- which monster caught you, so the jumpscare shows the RIGHT creature). Drives the jumpscare.
	MonsterStateChanged = "MonsterStateChanged", -- server -> client: a monster chasing THIS player changed FSM state (payload: state string) -- drives the chase sting
	HuntBegins = "HuntBegins", -- server -> ALL clients: the pre-round PEACE window just ended and the monsters are now hunting (no payload) -- drives a dread sting so the calm->hunt transition is FELT (else the peace window is invisible)
	HuntingAlert = "HuntingAlert", -- server -> ALL clients: a monster just BEGAN actively hunting a player (payload: that player's name) -- the TARGET already gets MonsterStateChanged; this makes the peril TEAM-VISIBLE so teammates can help or scatter (a co-op situational-awareness cue, throttled per target)
	TrapTriggered = "TrapTriggered", -- server -> ALL clients: a trap changed phase (payload: trapPart, "windup"|"fire") -- drives the telegraph flash + dart FX
	RoundSummary = "RoundSummary", -- server -> client: end-of-round results (payload: {coinsGained, total, keys, escaped}) -- drives the results panel
	DataReady = "DataReady", -- server -> client: this player's saved profile has loaded (the shop unlocks)
	AchievementUnlocked = "AchievementUnlocked", -- server -> client: a lifetime-stat milestone just earned (payload: {name, reward}) -- drives the unlock toast (StatsService)
	ShopResult = "ShopResult", -- server -> client: result of a ShopAction (payload: {ok, op, id, reason?})

	-- CLIENT -> SERVER (inbound). Payload is HOSTILE: validate type and rate-limit on the
	-- server (see SprintService). Carries the sprint key held-state.
	SprintIntent = "SprintIntent", -- client -> server: boolean, "is the sprint key held"
	ShopAction = "ShopAction", -- client -> server: HOSTILE payload {op="buy"|"equip", id=string} -- validated + rate-limited (ShopService)
	ThrowDecoy = "ThrowDecoy", -- client -> server: NO payload (just intent). The server computes the landing point from the player's OWN server-known position+facing (never trusts a client position), validates a per-player cooldown, spawns a rattling decoy + fires ServerSignals.NoiseEvent there to misdirect the monkey (DecoyService)
})

-- The authoritative list of RemoteEvent names the server creates. Grow via Names.
local REMOTE_EVENTS: { string } = {
	Names.SafeRoomEntered,
	Names.SafeRoomLeft,
	Names.KeyCollected,
	Names.GameWon,
	Names.ExitLocked,
	Names.ExitOpened,
	Names.MonsterCaught,
	Names.MonsterStateChanged,
	Names.HuntBegins,
	Names.HuntingAlert,
	Names.TrapTriggered,
	Names.RoundSummary,
	Names.DataReady,
	Names.AchievementUnlocked,
	Names.ShopResult,
	Names.SprintIntent,
	Names.ShopAction,
	Names.ThrowDecoy,
}

local Remotes = {}

-- Exposed so callers reference remotes by constant, never raw string.
Remotes.Names = Names

local function isRegistered(name: string): boolean
	for _, registered in REMOTE_EVENTS do
		if registered == name then
			return true
		end
	end
	return false
end

local function ensureFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder
end

-- Server-only. Creates the Remotes folder and every registered RemoteEvent.
-- Idempotent -- call once at server startup so remotes replicate before clients
-- ask for them.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must be called from the server")
	local folder = ensureFolder()
	for _, name in REMOTE_EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

-- Fetch a registered RemoteEvent by name. On the server it is created on demand
-- if missing; on the client it waits for the server to replicate it. Errors on
-- an unregistered name so typos fail loudly instead of silently returning nil.
function Remotes.get(name: string): RemoteEvent
	assert(isRegistered(name), `Remotes: "{name}" is not registered -- add it to REMOTE_EVENTS`)
	if RunService:IsServer() then
		local folder = ensureFolder()
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME):WaitForChild(name)
end

return Remotes
