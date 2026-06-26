--!nonstrict
-- ShopController.client.luau
-- The cosmetics shop UI (render + send-intent only; the server is authoritative). A top-left
-- "SHOP" button shows the live coin balance and toggles a panel listing the Cosmetics catalog:
-- each row shows a colour swatch, name, cost, and a Buy / Equip / Equipped button that sends a
-- ShopAction. Owned/equipped state comes from the DataReady snapshot and stays in sync from
-- ShopResult; coins live-update from the Coins attribute. Disabled until DataReady arrives.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Remotes)
local Attributes = require(ReplicatedStorage.Attributes)
local Cosmetics = require(ReplicatedStorage.Cosmetics)
local Config = require(ReplicatedStorage.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shopAction = Remotes.get(Remotes.Names.ShopAction)
local shopResult = Remotes.get(Remotes.Names.ShopResult)
local dataReady = Remotes.get(Remotes.Names.DataReady)

local owned = {} -- [id] = true
local equipped = {} -- [kind] = id
local ready = false

local gui = Instance.new("ScreenGui")
gui.Name = "Shop"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 25
gui.Parent = playerGui

-- Open button (top-left, below the Roblox topbar) showing the live balance.
local openBtn = Instance.new("TextButton")
openBtn.Name = "OpenShop"
openBtn.Position = UDim2.fromOffset(14, 70)
openBtn.Size = UDim2.fromOffset(140, 34)
openBtn.BackgroundColor3 = Config.UI.PanelColor
openBtn.BackgroundTransparency = 0.25
openBtn.Font = Config.UI.SubheadingFont
openBtn.TextSize = 16
openBtn.TextColor3 = Config.UI.WarnColor
openBtn.Text = "SHOP  0"
local obCorner = Instance.new("UICorner")
obCorner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
obCorner.Parent = openBtn
local obStroke = Instance.new("UIStroke")
obStroke.Color = Config.UI.StrokeColor
obStroke.Transparency = Config.UI.StrokeTransparency
obStroke.Thickness = Config.UI.StrokeThickness
obStroke.Parent = openBtn
openBtn.Parent = gui

-- Panel (centered, hidden by default).
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(420, 420)
panel.BackgroundColor3 = Config.UI.PanelColor
panel.BackgroundTransparency = 0.05
panel.Visible = false
local pCorner = Instance.new("UICorner")
pCorner.CornerRadius = UDim.new(0, Config.UI.PanelCornerRadius)
pCorner.Parent = panel
local pGradient = Instance.new("UIGradient")
pGradient.Color =
	ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1):Lerp(Color3.new(0, 0, 0), Config.UI.PanelGradientDarken))
pGradient.Rotation = 90
pGradient.Parent = panel
local pStroke = Instance.new("UIStroke")
pStroke.Color = Config.UI.StrokeColor
pStroke.Transparency = Config.UI.StrokeTransparency
pStroke.Thickness = Config.UI.StrokeThickness
pStroke.Parent = panel
panel.Parent = gui

local header = Instance.new("TextLabel")
header.Position = UDim2.fromOffset(18, 12)
header.Size = UDim2.fromOffset(300, 28)
header.BackgroundTransparency = 1
header.Font = Config.UI.HeadingFont
header.TextXAlignment = Enum.TextXAlignment.Left
header.TextSize = 22
header.TextColor3 = Config.UI.TextColor
header.Text = "FLASHLIGHT SHOP"
header.Parent = panel

local balance = Instance.new("TextLabel")
balance.AnchorPoint = Vector2.new(1, 0)
balance.Position = UDim2.new(1, -52, 0, 14)
balance.Size = UDim2.fromOffset(120, 24)
balance.BackgroundTransparency = 1
balance.Font = Config.UI.HeadingFont
balance.TextXAlignment = Enum.TextXAlignment.Right
balance.TextSize = 18
balance.TextColor3 = Config.UI.WarnColor
balance.Text = "0"
balance.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -14, 0, 12)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.BackgroundColor3 = Config.UI.PanelColor
closeBtn.Font = Config.UI.SubheadingFont
closeBtn.TextSize = 18
closeBtn.TextColor3 = Config.UI.TextColor
closeBtn.Text = "X"
local cbCorner = Instance.new("UICorner")
cbCorner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
cbCorner.Parent = closeBtn
local cbStroke = Instance.new("UIStroke")
cbStroke.Color = Config.UI.StrokeColor
cbStroke.Transparency = Config.UI.StrokeTransparency
cbStroke.Thickness = Config.UI.StrokeThickness
cbStroke.Parent = closeBtn
closeBtn.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(14, 48)
list.Size = UDim2.fromOffset(392, 358)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- One row per cosmetic; we keep handles so refresh() can update state.
local rows = {}
for i, c in Cosmetics.List do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 52)
	row.BackgroundColor3 = Config.UI.PanelColor
	row.LayoutOrder = i
	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
	rCorner.Parent = row
	local rStroke = Instance.new("UIStroke")
	rStroke.Color = Config.UI.StrokeColor
	rStroke.Transparency = Config.UI.StrokeTransparency
	rStroke.Thickness = Config.UI.StrokeThickness
	rStroke.Parent = row

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 12, 0.5, 0)
	swatch.Size = UDim2.fromOffset(28, 28)
	swatch.BackgroundColor3 = if c.kind == "FlashlightColor" then c.payload else Color3.fromRGB(200, 200, 200)
	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0.5, 0)
	sCorner.Parent = swatch
	swatch.Parent = row

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(52, 8)
	name.Size = UDim2.fromOffset(180, 20)
	name.BackgroundTransparency = 1
	name.Font = Config.UI.SubheadingFont
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextSize = 16
	name.TextColor3 = Config.UI.TextColor
	name.Text = c.name
	name.Parent = row

	local cost = Instance.new("TextLabel")
	cost.Position = UDim2.fromOffset(52, 28)
	cost.Size = UDim2.fromOffset(180, 16)
	cost.BackgroundTransparency = 1
	cost.Font = Config.UI.BodyFont
	cost.TextXAlignment = Enum.TextXAlignment.Left
	cost.TextSize = 13
	cost.TextColor3 = Config.UI.MutedTextColor
	cost.Text = if c.cost == 0 then "Free" else (c.cost .. " coins")
	cost.Parent = row

	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -12, 0.5, 0)
	action.Size = UDim2.fromOffset(96, 32)
	action.Font = Config.UI.SubheadingFont
	action.TextSize = 14
	action.TextColor3 = Color3.fromRGB(20, 22, 26)
	local aCorner = Instance.new("UICorner")
	aCorner.CornerRadius = UDim.new(0, Config.UI.ChipCornerRadius)
	aCorner.Parent = action
	local aStroke = Instance.new("UIStroke")
	aStroke.Color = Config.UI.StrokeColor
	aStroke.Transparency = Config.UI.StrokeTransparency
	aStroke.Thickness = Config.UI.StrokeThickness
	aStroke.Parent = action
	action.Parent = row

	action.Activated:Connect(function()
		if not ready then
			return
		end
		if owned[c.id] then
			if equipped[c.kind] ~= c.id then
				shopAction:FireServer({ op = "equip", id = c.id })
			end
		else
			shopAction:FireServer({ op = "buy", id = c.id })
		end
	end)

	row.Parent = list
	rows[c.id] = { action = action }
end

local function refresh()
	balance.Text = tostring(player:GetAttribute(Attributes.Coins) or 0)
	openBtn.Text = string.format("SHOP  %d", player:GetAttribute(Attributes.Coins) or 0)
	for _, c in Cosmetics.List do
		local a = rows[c.id].action
		if equipped[c.kind] == c.id then
			a.Text = "EQUIPPED"
			a.BackgroundColor3 = Config.UI.SafeColor
			a.AutoButtonColor = false
		elseif owned[c.id] then
			a.Text = "EQUIP"
			a.BackgroundColor3 = Config.UI.AccentColor
			a.AutoButtonColor = true
		else
			a.Text = "BUY"
			a.BackgroundColor3 = Config.UI.WarnColor
			a.AutoButtonColor = true
		end
	end
end

local function setOpen(open)
	panel.Visible = open and ready
	if panel.Visible then
		refresh()
	end
end
openBtn.Activated:Connect(function()
	setOpen(not panel.Visible)
end)
closeBtn.Activated:Connect(function()
	setOpen(false)
end)
-- Open/close on the keyboard key or the gamepad button (both from Config, no hardcoded KeyCode).
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and (input.KeyCode == Config.Shop.OpenKey or input.KeyCode == Config.Shop.GamepadOpenKey) then
		setOpen(not panel.Visible)
	end
end)

dataReady.OnClientEvent:Connect(function(snapshot)
	ready = true
	if type(snapshot) == "table" then
		owned = {}
		for _, id in snapshot.owned or {} do
			owned[id] = true
		end
		equipped = snapshot.equipped or {}
	end
	refresh()
end)

shopResult.OnClientEvent:Connect(function(res)
	if type(res) ~= "table" or not res.ok then
		return
	end
	if res.op == "buy" or res.op == "equip" then
		owned[res.id] = true
		local c = Cosmetics.get(res.id)
		if c then
			equipped[c.kind] = res.id -- the server auto-equips a purchase, and equip sets it too
		end
	end
	refresh()
end)

-- Keep the open-button balance current even while the panel is closed.
player:GetAttributeChangedSignal(Attributes.Coins):Connect(refresh)
