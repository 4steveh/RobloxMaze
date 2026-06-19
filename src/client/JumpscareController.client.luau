--!nonstrict
-- JumpscareController.client.luau
-- Client-only feedback: when the server says this player was caught (MonsterCaught),
-- play a placeholder full-screen flash for the death->respawn window. Renders only;
-- the catch itself is server-authoritative. Swap the placeholder for real art/sound
-- in a later pass (no asset IDs here).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer
local caughtRemote = Remotes.get(Remotes.Names.MonsterCaught)

local gui = Instance.new("ScreenGui")
gui.Name = "JumpscareGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(140, 0, 0)
flash.BackgroundTransparency = 1
flash.Visible = false
flash.Parent = gui

caughtRemote.OnClientEvent:Connect(function()
	flash.Visible = true
	flash.BackgroundTransparency = 0.1
	local tween = TweenService:Create(
		flash,
		TweenInfo.new(Config.Respawn.RespawnDelay, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		flash.Visible = false
	end)
end)
