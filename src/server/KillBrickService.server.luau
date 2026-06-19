--!nonstrict
-- KillBrickService.server.luau
-- TEMPORARY TEST TOOL. Any part tagged KillBrick kills whoever touches it (sets
-- Humanoid.Health = 0). This is the LONE sanctioned Touched handler in the
-- codebase (see CLAUDE.md) -- it exists only so death/respawn can be exercised by
-- hand. Tag a spare part "KillBrick", step on it to verify you respawn at the
-- checkpoint with keys intact, then delete the brick (and, eventually, this file).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)

local function armBrick(brick)
	if not brick:IsA("BasePart") then
		return
	end
	brick.Touched:Connect(function(hit)
		local character = hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
end

-- Fires for any KillBrick present now or tagged later (de-duplicated by Discovery).
Discovery.observe(Tags.KillBrick, armBrick)
