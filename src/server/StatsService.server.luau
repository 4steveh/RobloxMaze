--!nonstrict
-- StatsService.server.luau
-- The lifetime-stats + ACHIEVEMENTS owner. Listens to ServerSignals.RoundEnded (the same per-player
-- {keys, escaped, survivalSeconds, bonusKeys} summaries EconomyService awards coins from), folds each
-- into the player's persistent stats via PlayerData.recordRound, then runs the PURE Achievements module
-- against the updated stats: any newly-crossed milestone is granted once (PlayerData.grantAchievement),
-- paid a one-time coin reward (PlayerData.award -- the SAME economy path), and announced to the client.
--
-- Separation: EconomyService owns the round COINS; this owns STATS + milestone rewards. Both react to
-- RoundEnded independently (order-independent -- both just add to the coin total). Server-authoritative
-- throughout; the client only renders the unlock toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Remotes)
local Achievements = require(ReplicatedStorage.Achievements)
local ServerSignals = require(script.Parent.ServerSignals)
local PlayerData = require(script.Parent.PlayerData)

Remotes.init()
local achievementRemote = Remotes.get(Remotes.Names.AchievementUnlocked)

-- `summaries` is an ARRAY of { player, keys, escaped, survivalSeconds, bonusKeys, ... } (RoundService
-- keys it by a Player VALUE, not an Instance key, so it survives the BindableEvent copy).
ServerSignals.get(ServerSignals.Names.RoundEnded).Event:Connect(function(summaries)
	for _, s in summaries do
		local player = s.player
		if player and player.Parent and PlayerData.isReady(player) then
			local stats = PlayerData.recordRound(player, s)
			if stats then
				for _, a in Achievements.newlyEarned(stats, PlayerData.getEarnedAchievements(player)) do
					if PlayerData.grantAchievement(player, a.id) then -- true only on the FIRST grant
						PlayerData.award(player, a.reward)
						achievementRemote:FireClient(player, { name = a.name, reward = a.reward })
					end
				end
			end
		end
	end
end)
