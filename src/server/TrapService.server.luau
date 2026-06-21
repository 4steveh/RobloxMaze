--!nonstrict
-- TrapService.server.luau
-- Server-authoritative floor traps -- the "watch where you step" layer. Each tagged
-- `Trap` marker is FAIR: an always-visible red-arrow telegraph (built by the placer), a
-- short WIND-UP after you enter it (the arrow flashes + clicks) that an attentive player
-- can react to by backing off, then it FIRES -> kills (Health=0 -> the normal checkpoint
-- respawn) AND spikes the victim's `NoiseLevel` (a sprung trap is loud -> it can draw the
-- monkey). Detection is spatial on the shared poll (never Touched); skips InSafeRoom /
-- Won / RespawnGrace players, like the monsters. The client renders the flash + dart FX.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)

Remotes.init()
local trapRemote = Remotes.get(Remotes.Names.TrapTriggered)
local C = Config.Traps

-- [part] = { state = "armed"|"windup"|"cooldown", windupStart?, victim?, cooldownUntil? }
local traps = {}
Discovery.observe(Tags.Trap, function(part)
	if part:IsA("BasePart") then
		traps[part] = { state = "armed" }
	end
end, function(part)
	traps[part] = nil
end)

local function eligible(player: Player): boolean
	return player:GetAttribute(Attributes.InSafeRoom) ~= true
		and player:GetAttribute(Attributes.GameState) ~= Enums.GameState.Won
		and player:GetAttribute(Attributes.RespawnGrace) ~= true
end

-- Fire: lethal + loud, then cool down before it can trigger again.
local function fire(part, t, player: Player)
	t.state = "cooldown"
	t.cooldownUntil = os.clock() + C.RearmSeconds
	t.victim = nil
	trapRemote:FireAllClients(part, "fire")
	player:SetAttribute(Attributes.NoiseLevel, C.NoiseOnTrigger) -- a sprung trap is loud
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0 -- -> SpawnService checkpoint respawn (no jumpscare; it's a trap)
	end
end

while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	for part, t in traps do
		if not part.Parent then
			continue
		end
		if t.state == "cooldown" then
			if now >= (t.cooldownUntil or 0) then
				t.state = "armed"
			end
		elseif t.state == "armed" then
			for _, player in Players:GetPlayers() do
				if eligible(player) then
					local hrp = PlayerUtil.livingRootPart(player)
					if hrp and Spatial.withinRange(hrp.Position, part.Position, C.TriggerRadius) then
						t.state = "windup"
						t.windupStart = now
						t.victim = player
						trapRemote:FireAllClients(part, "windup") -- telegraph flash + click
						break
					end
				end
			end
		elseif t.state == "windup" then
			local player = t.victim
			local hrp = player and eligible(player) and PlayerUtil.livingRootPart(player)
			local stillIn = hrp ~= nil and Spatial.withinRange(hrp.Position, part.Position, C.TriggerRadius)
			if not stillIn then
				-- they reacted and left in time -> disarm with a brief cooldown.
				t.state = "cooldown"
				t.cooldownUntil = now + C.RearmSeconds
				t.victim = nil
			elseif now - (t.windupStart or now) >= C.WindupSeconds then
				fire(part, t, player)
			end
		end
	end
end
