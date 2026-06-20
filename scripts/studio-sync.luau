-- studio-sync.luau — code-sync FALLBACK for when the Rojo Studio plugin isn't
-- connected. Start the file server first (`make serve-files` or scripts/serve-files.sh),
-- then paste this whole file into the Studio Command Bar in EDIT mode and run it.
--
-- It auto-discovers every src/*.luau over HTTP and writes each into the place at the
-- Rojo-mapped location, overwriting .Source. Idempotent. This is a stopgap; the
-- supported workflow is `rojo serve` + the plugin's Connect. (NOT a Rojo-loaded module
-- — it lives in scripts/, outside src/, and is run by hand.)
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local BASE = "http://127.0.0.1:8777/src/"

-- src/<dir> -> Roblox parent (matches default.project.json).
local PARENTS = { shared = RS, server = SSS, client = SPS }

local function classAndName(file)
	if file:match("%.server%.luau$") then
		return "Script", (file:gsub("%.server%.luau$", ""))
	elseif file:match("%.client%.luau$") then
		return "LocalScript", (file:gsub("%.client%.luau$", ""))
	end
	return "ModuleScript", (file:gsub("%.luau$", ""))
end

local prev = HttpService.HttpEnabled
HttpService.HttpEnabled = true

local ok, fail = 0, 0
for dir, parent in PARENTS do
	-- python's http.server returns an HTML directory listing we scrape for *.luau.
	local good, html = pcall(function()
		return HttpService:GetAsync(BASE .. dir .. "/", false)
	end)
	if not good then
		fail += 1
		warn("studio-sync: cannot list " .. dir .. "/ -> " .. tostring(html))
		continue
	end
	for file in html:gmatch('href="([^"]+%.luau)"') do
		local body
		good, body = pcall(function()
			return HttpService:GetAsync(BASE .. dir .. "/" .. file, false)
		end)
		if good then
			local class, name = classAndName(file)
			local inst = parent:FindFirstChild(name)
			if inst and inst.ClassName ~= class then
				inst:Destroy()
				inst = nil
			end
			if not inst then
				inst = Instance.new(class)
				inst.Name = name
				inst.Parent = parent
			end
			inst.Source = body
			ok += 1
		else
			fail += 1
			warn("studio-sync: failed " .. file .. " -> " .. tostring(body))
		end
	end
end

HttpService.HttpEnabled = prev
print(string.format("studio-sync: %d synced, %d failed", ok, fail))
