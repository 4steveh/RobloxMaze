--!nonstrict
-- EconomyService.server.luau
-- Awards coins at the end of each round. Listens to ServerSignals.RoundEnded (which RoundService
-- fires with each player's {keys, escaped, survivalSeconds} BEFORE RoundReset clears KeyCount/
-- GameState), runs the pure Progression.computeAward, banks it via PlayerData.award, and tells
-- each player their results via the RoundSummary remote. A run is never worth zero.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Remotes)
local Progression = require(ReplicatedStorage.Progression)
local ServerSignals = require(script.Parent.ServerSignals)
local PlayerData = require(script.Parent.PlayerData)

Remotes.init()
local roundSummary = Remotes.get(Remotes.Names.RoundSummary)

-- `summaries` is an ARRAY of { player, keys, escaped, survivalSeconds } (see RoundService --
-- keyed by a Player VALUE, not an Instance key, so it survives the BindableEvent copy).
ServerSignals.get(ServerSignals.Names.RoundEnded).Event:Connect(function(summaries)
	for _, s in summaries do
		local player = s.player
		if player and player.Parent and PlayerData.isReady(player) then
			local award = Progression.computeAward(s)
			local total = PlayerData.award(player, award)
			roundSummary:FireClient(player, {
				coinsGained = award,
				total = total,
				keys = s.keys,
				escaped = s.escaped,
			})
		end
	end
end)
