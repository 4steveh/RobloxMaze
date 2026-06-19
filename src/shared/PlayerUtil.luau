--!nonstrict
-- PlayerUtil.luau
-- Small shared helpers for player characters. Instance-API heavy, so --!nonstrict
-- (see CLAUDE.md typing policy).

local PlayerUtil = {}

-- The player's HumanoidRootPart, but only if the character is fully present and
-- the Humanoid is alive. Returns nil during spawning/respawn or when dead, so a
-- per-tick service can simply skip that player without erroring.
function PlayerUtil.livingRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

return PlayerUtil
