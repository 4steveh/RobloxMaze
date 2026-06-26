--!strict
-- Progression.luau
-- PURE award math (no Instance/os/clock reads), so it's unit-testable like Spatial/Gaits.
-- Turns a round summary into a coin award. A run is NEVER worth zero -- you always bank a
-- participation floor + per-key progress + capped survival time; escaping is the jackpot.
-- All weights come from Config.Economy (no magic numbers here).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

export type RoundSummary = {
	keys: number, -- keys the team held at round end (this player's KeyCount)
	escaped: boolean, -- did this player reach the exit?
	survivalSeconds: number, -- seconds this player was alive/active this round
	coopEscapers: number?, -- how many players escaped this round (for the co-op-win bonus); nil/0 = solo escape
	bonusKeys: number?, -- OPTIONAL gold bonus keys the team grabbed (round-end coins; nil/0 = none)
}

local Progression = {}

function Progression.computeAward(summary: RoundSummary): number
	local E = Config.Economy
	local award = E.ParticipationFloor
	award += math.max(0, summary.keys) * E.KeyReward
	award += math.max(0, summary.bonusKeys or 0) * E.BonusKeyReward -- the risky gold-key detour pays here
	if summary.escaped then
		award += E.EscapeBonus
		-- Escaping TOGETHER (2+ players out the same round) earns each escapee a small extra -- a
		-- reward for cooperating, sublinear so it never out-values the base escape or punishes solo.
		if (summary.coopEscapers or 0) >= 2 then
			award += E.CoopEscapeBonus
		end
	end
	award += math.min(math.max(0, summary.survivalSeconds), E.SurvivalCap) * E.SurvivalPerSecond
	return math.floor(award)
end

return Progression
