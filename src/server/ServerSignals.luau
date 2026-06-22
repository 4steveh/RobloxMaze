--!nonstrict
-- ServerSignals.luau
-- Server-only BindableEvent registry for server<->server coordination -- the sanctioned
-- seam for one server system to broadcast an event others react to, mirroring how Remotes
-- centralizes RemoteEvents (CLAUDE.md forbids direct script-to-script calls and globals).
-- Used so RoundService can announce a new round without reaching into Key/Exit/Spawn/Monster
-- services directly; each of those reacts and resets ONLY its own state.
--
-- Server-only: BindableEvents never replicate, and the module asserts IsServer. The events
-- are cached in this module (one shared instance per server), so no Instance folder is needed.

local RunService = game:GetService("RunService")

-- Canonical signal names -- the only place these strings live (the Tags/Remotes discipline).
local Names = table.freeze({
	RoundReset = "RoundReset", -- a new round is beginning: re-spawn keys, reset state/monsters/spawns
	PlayerCaught = "PlayerCaught", -- a monster reached a player (payload: Player, species string); DownedService decides down-vs-kill (and forwards the species so the jumpscare shows the right monster), so MonsterService stays out of player-life logic
	RoundEnded = "RoundEnded", -- a round just ended (payload: { [player] = {keys, escaped, survivalSeconds} }); EconomyService awards coins BEFORE RoundReset clears state
	NoiseEvent = "NoiseEvent", -- a loud WORLD event happened at a point (payload: position Vector3); the near-blind monkey "hears" it and investigates -- e.g. a sprung trap pulls it toward the trap (TrapService fires this; MonsterService routes it into the monkey's senses)
	MazeRebuilt = "MazeRebuilt", -- the runtime maze just re-carved + settled (no payload); MazeService is the PRODUCER (resets FIRST), and Key/Monster/etc. wait on this before re-arming so they never path against a half-built maze
})

local ServerSignals = {}
ServerSignals.Names = Names

local signals = {} -- [name] = BindableEvent (cached; the module is one shared instance server-side)

local function isRegistered(name: string): boolean
	for _, registered in Names do
		if registered == name then
			return true
		end
	end
	return false
end

-- Fetch (lazily create) the BindableEvent for a registered signal. Connect to `.Event`,
-- broadcast with `:Fire(...)`. Errors on an unregistered name so typos fail loudly.
function ServerSignals.get(name: string): BindableEvent
	assert(RunService:IsServer(), "ServerSignals is server-only")
	assert(isRegistered(name), `ServerSignals: "{name}" is not registered -- add it to Names`)
	local existing = signals[name]
	if existing then
		return existing
	end
	local event = Instance.new("BindableEvent")
	event.Name = name
	signals[name] = event
	return event
end

return ServerSignals
