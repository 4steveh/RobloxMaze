--!nonstrict
-- Remotes.luau
-- Central registry of RemoteEvents. The server creates them under a single
-- ReplicatedStorage folder; both sides fetch them by name -- no manual instance
-- plumbing or hardcoded paths. Add new remotes to REMOTE_EVENTS; later prompts
-- populate this list and validate every remote on the server.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

-- The authoritative list of RemoteEvent names. Empty for the skeleton milestone
-- (no gameplay remotes exist yet); extend it as features land.
local REMOTE_EVENTS: { string } = {
	-- e.g. "KeyCollected", "GameWon", "FlashlightToggled"
}

local Remotes = {}

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
