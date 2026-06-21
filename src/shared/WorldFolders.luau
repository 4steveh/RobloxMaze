--!strict
-- WorldFolders.luau
-- Canonical names of the runtime Workspace folders the server creates and the client
-- reads -- the same "no stringly-typed shared state" discipline Tags/Attributes/Remotes
-- apply, here for the container folders that cross the server->client boundary. The
-- server builds these under Workspace; the client locates rigs/keys through them. One
-- constant per folder so a rename can never silently desync producer and consumer.

local WorldFolders = table.freeze({
	Monsters = "Monsters", -- holds every live monster rig (MonsterService builds it; anim/audio/FX/jumpscare read it)
	Keys = "Keys", -- holds the round's collectible key parts (KeyService)
	PlayerSpawns = "PlayerSpawns", -- holds each player's hidden SpawnLocation (SpawnService)
})

return WorldFolders
