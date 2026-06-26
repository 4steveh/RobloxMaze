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
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Tags = require(ReplicatedStorage.Tags)
local Discovery = require(ReplicatedStorage.Discovery)
local Spatial = require(ReplicatedStorage.Spatial)
local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Enums = require(ReplicatedStorage.Enums)
local WorldFolders = require(ReplicatedStorage.WorldFolders)
local PlayerUtil = require(ReplicatedStorage.PlayerUtil)
local ServerSignals = require(script.Parent.ServerSignals)

Remotes.init()
local trapRemote = Remotes.get(Remotes.Names.TrapTriggered)
local noiseSignal = ServerSignals.get(ServerSignals.Names.NoiseEvent) -- a sprung trap pulls the monkey
local C = Config.Traps

-- A monster is only TRIPPED by a trap while HUNTING (ran over it chasing a player) -- so a rig
-- pacing its nest next to a trap never stuns itself. Mirrors the radar's "hunting" set.
local HUNTING = {
	[Enums.MonsterState.Chase] = true,
	[Enums.MonsterState.Investigate] = true,
	[Enums.MonsterState.Alert] = true,
}

local monstersFolder = nil
local function getMonsters(): Instance?
	if not (monstersFolder and monstersFolder.Parent) then
		monstersFolder = Workspace:FindFirstChild(WorldFolders.Monsters)
	end
	return monstersFolder
end

-- A HUNTING rig standing on the trap (it ran over it mid-chase), or nil.
local function huntingMonsterOn(part: BasePart): Model?
	local folder = getMonsters()
	if not folder then
		return nil
	end
	for _, rig in folder:GetChildren() do
		local root = rig:IsA("Model") and rig:FindFirstChild("HumanoidRootPart")
		if
			root
			and HUNTING[rig:GetAttribute(Attributes.MonsterState)] == true
			and Spatial.withinRange(root.Position, part.Position, C.MonsterTriggerRadius)
		then
			return rig
		end
	end
	return nil
end

-- Ensure each trap carries a clearly-visible red danger glow (adopt an existing placed
-- PointLight or create one), set bright from Config -- so a trap reads as DANGER, not decor,
-- and it's reproducible from code (not reliant on baked place geometry). Named so the client
-- TrapFXController can find + pulse it. Replicates to every client.
local function ensureGlow(part: BasePart)
	local glow = part:FindFirstChild("TrapGlow")
	if not (glow and glow:IsA("PointLight")) then
		glow = part:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
		glow.Name = "TrapGlow"
		glow.Parent = part
	end
	glow.Color = C.GlowColor
	glow.Brightness = C.GlowBrightness
	glow.Range = C.GlowRange
	glow.Shadows = false
end

-- Ensure each trap sits on a flat translucent-red DANGER PAD on the floor (adopt an existing
-- placed "TrapPad" child or create one) -- so the hazard reads as a clear FOOTPRINT on the ground,
-- not just a point glow, telling you exactly where NOT to step. The pad is a Cylinder lying flat:
-- a Cylinder's circular faces are on its X axis, so we roll it 90deg about Z to point the round face
-- up; its radius matches the actual TriggerRadius (the disc is the trigger footprint), Neon so it
-- self-lights in the dark. Purely cosmetic (no collision/query/touch/shadow) and replicates to all.
local function ensurePad(part: BasePart)
	local pad = part:FindFirstChild("TrapPad")
	if not (pad and pad:IsA("BasePart")) then
		pad = Instance.new("Part")
		pad.Name = "TrapPad"
		pad.Shape = Enum.PartType.Cylinder
		pad.Parent = part
	end
	pad.Size = Vector3.new(C.PadThickness, C.TriggerRadius * 2, C.TriggerRadius * 2)
	pad.Material = Enum.Material.Neon
	pad.Color = C.PadColor
	pad.Transparency = C.PadTransparency
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
	-- Lay the disc flat (roll 90deg about Z so the round face points up) and rest it JUST ON the floor
	-- under the trap: the floor surface is the marker's underside; the disc CENTRE sits half its
	-- thickness above that (+ a tiny epsilon) so the disc BOTTOM clears the floor (no z-fighting / sink).
	local floorY = part.Position.Y - part.Size.Y / 2
	local centreY = floorY + C.PadThickness / 2 + 0.02
	pad.CFrame = CFrame.new(part.Position.X, centreY, part.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
end

-- [part] = { state = "armed"|"windup"|"cooldown", windupStart?, victim?, cooldownUntil? }
local traps = {}
Discovery.observe(Tags.Trap, function(part)
	if part:IsA("BasePart") then
		traps[part] = { state = "armed" }
		ensureGlow(part)
		ensurePad(part)
	end
end, function(part)
	traps[part] = nil
end)

-- On a new round, re-arm every trap. Without this a trap caught mid-WINDUP at round end carries its
-- stale windupStart/victim into the next round -- and because `now - windupStart` is then huge, it
-- fires INSTANTLY (no telegraph, no wind-up reaction window) on whoever (re)spawns inside its radius.
-- A reset means every trap is freshly armed and re-telegraphs.
ServerSignals.get(ServerSignals.Names.RoundReset).Event:Connect(function()
	for part in traps do
		traps[part] = { state = "armed" }
	end
end)

local function eligible(player: Player): boolean
	return player:GetAttribute(Attributes.InSafeRoom) ~= true
		and player:GetAttribute(Attributes.GameState) ~= Enums.GameState.Won
		and player:GetAttribute(Attributes.RespawnGrace) ~= true
		and player:GetAttribute(Attributes.Downed) ~= true
end

-- Fire: lethal + loud, then cool down before it can trigger again.
local function fire(part, t, player: Player)
	t.state = "cooldown"
	t.cooldownUntil = os.clock() + C.RearmSeconds
	t.victim = nil
	trapRemote:FireAllClients(part, "fire")
	player:SetAttribute(Attributes.NoiseLevel, C.NoiseOnTrigger) -- a sprung trap is loud
	-- ...and loud enough to draw the near-blind monkey to the TRAP itself (not the now-dead
	-- victim): a careless trap-trip actively summons the hunter. MonsterService routes this to it.
	noiseSignal:Fire(part.Position)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0 -- -> SpawnService checkpoint respawn (no jumpscare; it's a trap)
	end
end

-- Spring on a MONSTER instead: freeze it (StunnedUntil; MonsterService reads it and stands the rig
-- still) and play the same fire FX, then cool down. No death, no noise -- this is the player's
-- escape tool: bait a pursuer across the trap to open a gap. The trip is INSTANT (no telegraph --
-- a monster doesn't read warnings), and it also cancels any player wind-up (the bait spares you).
local function fireOnMonster(part, t, rig)
	t.state = "cooldown"
	t.cooldownUntil = os.clock() + C.RearmSeconds
	t.victim = nil
	rig:SetAttribute(Attributes.MonsterStunnedUntil, Workspace:GetServerTimeNow() + C.MonsterStunSeconds)
	trapRemote:FireAllClients(part, "fire")
end

-- Per-trap state-machine step, factored out so it can be pcall-isolated: a throw on
-- one trap (a destroyed victim character, a nil HRP) must not freeze every trap.
local function processTrap(part, t, now)
	if not part.Parent then
		return
	end
	if t.state == "cooldown" then
		if now >= (t.cooldownUntil or 0) then
			t.state = "armed"
		end
	elseif t.state == "armed" then
		-- A hunting monster on the trap springs it INSTANTLY -- the lure (checked before players).
		local rig = huntingMonsterOn(part)
		if rig then
			fireOnMonster(part, t, rig)
			return
		end
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
		-- A monster reaching the trap mid-windup fires on the MONSTER and SPARES the player (the
		-- bait worked: you ran across, it followed, the trap took it instead of you).
		local rig = huntingMonsterOn(part)
		if rig then
			fireOnMonster(part, t, rig)
			return
		end
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

while true do
	task.wait(Config.Spatial.PollInterval)
	local now = os.clock()
	for part, t in traps do
		local ok, err = pcall(processTrap, part, t, now)
		if not ok then
			warn("[TrapService] tick error for a trap (skipped this tick):", err)
		end
	end
end
