-- // AUTO AUCTION SNIPE SCRIPT \\ --
-- // Game: Grow a Garden 2 \\ --

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))

-- // Clean Old UI
local uiTarget = CoreGui
local success = pcall(function() local _ = CoreGui.Name end)
if not success then uiTarget = LocalPlayer:WaitForChild("PlayerGui") end

if uiTarget:FindFirstChild("AutoAuctionHub") then
    uiTarget.AutoAuctionHub:Destroy()
end

-- // ANTI AFK
local VirtualUser = game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- // VARIABLES
local isAutoBuying = false
local targetItems = {}
local maxPrice = 0

-- // PARSER FUNCTIONS
local function parsePrice(text)
    text = string.upper(text)
    
    -- Hapus simbol sen dan spasi terlebih dahulu agar aman dari multi-byte
    local clean = string.gsub(text, "¢", "")
    clean = string.gsub(clean, "\194\162", "")
    clean = string.gsub(clean, " ", "")
    
    -- Hapus semua karakter sah (Angka, Titik, Koma, K, M, B, T, $)
    local leftover = string.gsub(clean, "[%d%.%,KMBT%$]", "")
    
    -- Jika masih ada sisa karakter (misal huruf A, X, L, E, V, dll), berarti INI BUKAN HARGA!
    if string.len(leftover) > 0 then
        return math.huge
    end

    local multiplier = 1
    if string.find(text, "K") then multiplier = 1000; text = string.gsub(text, "K", "") end
    if string.find(text, "M") then multiplier = 1000000; text = string.gsub(text, "M", "") end
    if string.find(text, "B") then multiplier = 1000000000; text = string.gsub(text, "B", "") end
    if string.find(text, "T") then multiplier = 1000000000000; text = string.gsub(text, "T", "") end
    
    local num = tonumber((string.gsub(text, "[^%d%.]", "")))
    if num then return num * multiplier else return math.huge end
end

local HttpService = game:GetService("HttpService")
local configName = "AutoAuctionConfig.json"
local maxPriceText = "1M"

local function saveConfig()
    if writefile then
        local data = {
            maxPriceText = maxPriceText,
            targetItems = targetItems
        }
        local s, res = pcall(function() return HttpService:JSONEncode(data) end)
        if s then writefile(configName, res) end
    end
end

local function loadConfig()
    if isfile and readfile and isfile(configName) then
        local s, res = pcall(function() return HttpService:JSONDecode(readfile(configName)) end)
        if s and type(res) == "table" then
            if res.maxPriceText then
                maxPriceText = tostring(res.maxPriceText)
                maxPrice = parsePrice(maxPriceText)
            end
            if res.targetItems then
                targetItems = res.targetItems
            end
        end
    end
end

loadConfig()

local createdToggles = {}

local function createToggleUI(itemName)
    if not _G.ItemsListUI then return end
    
    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.new(1, -10, 0, 25)
    ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 60)
    ToggleBtn.Text = itemName .. " [OFF]"
    ToggleBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    ToggleBtn.Font = Enum.Font.GothamSemibold
    ToggleBtn.TextSize = 12
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.Parent = _G.ItemsListUI
    
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 4)
    UICorner.Parent = ToggleBtn
    
    local isSelected = false
    if itemName == "ALL ITEMS" then
        if targetItems["all"] then isSelected = true end
    else
        if targetItems[itemName:lower()] then isSelected = true end
    end

    if isSelected then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
        ToggleBtn.TextColor3 = Color3.fromRGB(20, 50, 20)
        ToggleBtn.Text = itemName .. " [ON]"
    end
    
    ToggleBtn.MouseButton1Click:Connect(function()
        isSelected = not isSelected
        if isSelected then
            ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
            ToggleBtn.TextColor3 = Color3.fromRGB(20, 50, 20)
            ToggleBtn.Text = itemName .. " [ON]"
            if itemName == "ALL ITEMS" then
                targetItems["all"] = true
            else
                targetItems[itemName:lower()] = true
            end
        else
            ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 60)
            ToggleBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
            ToggleBtn.Text = itemName .. " [OFF]"
            if itemName == "ALL ITEMS" then
                targetItems["all"] = nil
            else
                targetItems[itemName:lower()] = nil
            end
        end
        saveConfig()
    end)
end

local function scanShopForItems()
    local auctionGui = LocalPlayer.PlayerGui:FindFirstChild("Auction")
    if not auctionGui then return end
    local sf = auctionGui:FindFirstChild("ScrollingFrame", true)
    if not sf then return end
    
    for _, child in ipairs(sf:GetChildren()) do
        if child.Name:match("^Lot_auction:") then
            local nameLabel = child:FindFirstChild("ItemName", true)
            if nameLabel and nameLabel:IsA("TextLabel") then
                local itemName = nameLabel.Text
                if not createdToggles[itemName] then
                    createdToggles[itemName] = true
                    createToggleUI(itemName)
                end
            end
        end
    end
end

-- // MAIN LOGIC
local function scanAndSnipe()
    local auctionGui = LocalPlayer.PlayerGui:FindFirstChild("Auction")
    if not auctionGui then return end
    local sf = auctionGui:FindFirstChild("ScrollingFrame", true)
    if not sf then return end
    
    for _, child in ipairs(sf:GetChildren()) do
        if child.Name:match("^Lot_auction:") then
            local itemName = ""
            local price = math.huge
            local stock = 0
            
            -- Get Name
            local nameLabel = child:FindFirstChild("ItemName", true)
            if nameLabel and nameLabel:IsA("TextLabel") then
                itemName = nameLabel.Text:lower()
            end
            
            -- Get Price
            local priceLabel = nil
            for _, desc in ipairs(child:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    local rawText = desc.Text:lower()
                    -- Abaikan label yang jelas bukan harga (Timer, Amount, Stock, ItemName)
                    if desc.Name == "ItemName" or desc.Name == "Amount" or desc.Name == "Timer" or desc.Name == "Stock_Text" then
                        continue
                    end
                    -- Abaikan format Timer ("0m 00s") atau Amount ("x5")
                    if string.match(rawText, "^x%d+") or string.match(rawText, "%d+m %d+s") or rawText == "expired" then
                        continue
                    end
                    
                    -- Price label biasanya bernama "TextLabel" atau "Price" dan mengandung angka
                    if desc.Name == "Price" or desc.Name == "Cost" or string.find(desc.Text, "\194\162") or string.find(desc.Text, "¢") then
                        priceLabel = desc
                        break
                    elseif desc.Name == "TextLabel" and string.match(rawText, "%d") then
                        priceLabel = desc
                        break
                    end
                end
            end
            
            if priceLabel then
                price = parsePrice(priceLabel.Text)
            end
            
            -- Get Stock
            local stockLabel = child:FindFirstChild("Stock_Text", true)
            if stockLabel and stockLabel:IsA("TextLabel") then
                local s = string.match(stockLabel.Text, "%d+")
                stock = tonumber(s) or 0
            end
            
            -- Check Target
            local isTarget = false
            if targetItems["all"] or targetItems["semua"] then
                isTarget = true
            else
                for target, _ in pairs(targetItems) do
                    if string.find(itemName, target, 1, true) then
                        isTarget = true
                        break
                    end
                end
            end
            
            -- Buy Logic
            if isTarget and price <= maxPrice and stock > 0 then
                local lotId = string.gsub(child.Name, "Lot_", "")
                pcall(function()
                    Networking.Auctioneer.PurchaseLot:Fire(lotId, price)
                end)
            end
        end
    end
end

task.spawn(function()
    while task.wait() do -- 20 requests per second spam rate when buying
        if isAutoBuying then
            scanAndSnipe()
        end
    end
end)

task.spawn(function()
    while task.wait(5) do
        scanShopForItems()
    end
end)


-- // UI CREATION
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoAuctionHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = uiTarget

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 320, 0, 380)
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(46, 57, 85)
UIStroke.Thickness = 2
UIStroke.Parent = MainFrame

-- Title
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, 0, 0, 40)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "AUCTION SNIPER"
TitleLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 18
TitleLabel.Parent = MainFrame

local Divider = Instance.new("Frame")
Divider.Size = UDim2.new(1, -20, 0, 1)
Divider.Position = UDim2.new(0, 10, 0, 40)
Divider.BackgroundColor3 = Color3.fromRGB(46, 57, 85)
Divider.BorderSizePixel = 0
Divider.Parent = MainFrame

-- Items List (Dynamic)
local ItemsLabel = Instance.new("TextLabel")
ItemsLabel.Size = UDim2.new(1, -30, 0, 20)
ItemsLabel.Position = UDim2.new(0, 15, 0, 50)
ItemsLabel.BackgroundTransparency = 1
ItemsLabel.Text = "Pilih Item (Auto Scan tiap 5s):"
ItemsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
ItemsLabel.Font = Enum.Font.GothamSemibold
ItemsLabel.TextSize = 13
ItemsLabel.TextXAlignment = Enum.TextXAlignment.Left
ItemsLabel.Parent = MainFrame

local ItemsList = Instance.new("ScrollingFrame")
ItemsList.Size = UDim2.new(1, -30, 0, 90)
ItemsList.Position = UDim2.new(0, 15, 0, 70)
ItemsList.BackgroundColor3 = Color3.fromRGB(15, 19, 26)
ItemsList.BorderSizePixel = 0
ItemsList.ScrollBarThickness = 4
ItemsList.Parent = MainFrame
_G.ItemsListUI = ItemsList

local ItemsCorner = Instance.new("UICorner")
ItemsCorner.CornerRadius = UDim.new(0, 6)
ItemsCorner.Parent = ItemsList

local ItemsStroke = Instance.new("UIStroke")
ItemsStroke.Color = Color3.fromRGB(46, 57, 85)
ItemsStroke.Parent = ItemsList

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Padding = UDim.new(0, 5)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Parent = ItemsList
local UIPadding = Instance.new("UIPadding")
UIPadding.PaddingTop = UDim.new(0, 5)
UIPadding.PaddingLeft = UDim.new(0, 5)
UIPadding.Parent = ItemsList

UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ItemsList.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 10)
end)

-- Default ALL option
createToggleUI("ALL ITEMS")
scanShopForItems()

-- Price Input
local PriceLabel = Instance.new("TextLabel")
PriceLabel.Size = UDim2.new(1, -30, 0, 20)
PriceLabel.Position = UDim2.new(0, 15, 0, 150)
PriceLabel.BackgroundTransparency = 1
PriceLabel.Text = "Max Price (Bisa pakai K/M/B):"
PriceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
PriceLabel.Font = Enum.Font.GothamSemibold
PriceLabel.TextSize = 13
PriceLabel.TextXAlignment = Enum.TextXAlignment.Left
PriceLabel.Parent = MainFrame

local PriceBox = Instance.new("TextBox")
PriceBox.Size = UDim2.new(1, -30, 0, 35)
PriceBox.Position = UDim2.new(0, 15, 0, 170)
PriceBox.BackgroundColor3 = Color3.fromRGB(15, 19, 26)
PriceBox.TextColor3 = Color3.fromRGB(80, 255, 150)
PriceBox.Font = Enum.Font.GothamBold
PriceBox.TextSize = 16
PriceBox.Text = maxPriceText
PriceBox.ClearTextOnFocus = false
PriceBox.Parent = MainFrame
local PriceCorner = Instance.new("UICorner")
PriceCorner.CornerRadius = UDim.new(0, 6)
PriceCorner.Parent = PriceBox
local PriceStroke = Instance.new("UIStroke")
PriceStroke.Color = Color3.fromRGB(46, 57, 85)
PriceStroke.Parent = PriceBox

-- Initial parse
maxPrice = parsePrice(PriceBox.Text)
PriceBox.FocusLost:Connect(function()
    maxPriceText = string.upper(PriceBox.Text)
    maxPrice = parsePrice(maxPriceText)
    PriceBox.Text = maxPriceText
    saveConfig()
end)

-- Instruction / Hint
local HintLabel = Instance.new("TextLabel")
HintLabel.Size = UDim2.new(1, -30, 0, 40)
HintLabel.Position = UDim2.new(0, 15, 0, 215)
HintLabel.BackgroundTransparency = 1
HintLabel.Text = "*Jika barang yang dicari belum ada, tunggu 5 detik. Script akan otomatis scan barang dari papan lelang."
HintLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
HintLabel.Font = Enum.Font.Gotham
HintLabel.TextSize = 11
HintLabel.TextWrapped = true
HintLabel.TextXAlignment = Enum.TextXAlignment.Left
HintLabel.Parent = MainFrame

-- Toggle Button
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -30, 0, 45)
ToggleBtn.Position = UDim2.new(0, 15, 0, 280)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 60)
ToggleBtn.Text = "ENABLE AUTO BUY: OFF"
ToggleBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 16
ToggleBtn.AutoButtonColor = false
ToggleBtn.Parent = MainFrame
local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = ToggleBtn
local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(66, 80, 110)
ToggleStroke.Thickness = 2
ToggleStroke.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    isAutoBuying = not isAutoBuying
    if isAutoBuying then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
        ToggleBtn.TextColor3 = Color3.fromRGB(20, 50, 20)
        ToggleBtn.Text = "AUTO BUYING: ON"
        ToggleStroke.Color = Color3.fromRGB(100, 255, 150)
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 60)
        ToggleBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        ToggleBtn.Text = "ENABLE AUTO BUY: OFF"
        ToggleStroke.Color = Color3.fromRGB(66, 80, 110)
    end
end)

-- Close Button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -35, 0, 5)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.Parent = MainFrame
CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Minimize logic
local isMinimized = false
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -70, 0, 5)
MinBtn.BackgroundTransparency = 1
MinBtn.Text = "-"
MinBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 24
MinBtn.Parent = MainFrame
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        MainFrame:TweenSize(UDim2.new(0, 320, 0, 40), "Out", "Sine", 0.3, true)
        ItemsLabel.Visible = false
        ItemsList.Visible = false
        PriceLabel.Visible = false
        PriceBox.Visible = false
        HintLabel.Visible = false
        ToggleBtn.Visible = false
    else
        MainFrame:TweenSize(UDim2.new(0, 320, 0, 380), "Out", "Sine", 0.3, true)
        task.wait(0.3)
        ItemsLabel.Visible = true
        ItemsList.Visible = true
        PriceLabel.Visible = true
        PriceBox.Visible = true
        HintLabel.Visible = true
        ToggleBtn.Visible = true
    end
end)

print("Auto Auction Loaded!")
