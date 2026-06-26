--!strict
-- Achievements.luau
-- PURE milestone logic (no Instance/os/clock reads), so it's unit-testable like Progression/Spatial.
-- Given a player's lifetime `stats` and the set of `earned` achievement ids, returns the achievements
-- they have JUST satisfied (stat >= threshold AND not already earned). StatsService applies the result
-- (grants the id, awards the coins, notifies the client) -- this module decides NOTHING about the world.
-- All thresholds/rewards come from Config.Achievements (no magic numbers here).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

export type Achievement = {
	id: string,
	stat: string,
	threshold: number,
	reward: number,
	name: string,
}

local Achievements = {}

-- The achievements newly satisfied by `stats` that aren't already in `earned` (a set of ids).
-- Order follows Config.Achievements.List, so a multi-tier cross in one round reports lowest-first.
function Achievements.newlyEarned(stats: { [string]: number }, earned: { [string]: boolean }): { Achievement }
	local out = {}
	for _, a in Config.Achievements.List do
		if not earned[a.id] and (stats[a.stat] or 0) >= a.threshold then
			table.insert(out, a)
		end
	end
	return out
end

return Achievements
