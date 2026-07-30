-- ==========================================
-- SCRIPT PERSONAL (UPDATED BY ANTIGRAVITY - REAL HISTORY UI)
-- SCRIPT INI BISA DI-CUSTOM LANGSUNG DARI DALAM KODE
-- ==========================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local RemoteEvent = ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Packet"):WaitForChild("RemoteEvent")
local LocalPlayer = Players.LocalPlayer
local Networking = require(ReplicatedStorage.SharedModules.Networking)
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

local antiAfkEnabled = true

-- VARIABEL TRACKING HISTORY (FORMAT STACKING)
local PurchaseHistoryLog = {}

local function logPurchase(itemName)
    -- Jika item yang baru dibeli sama dengan item paling atas, tambahkan jumlahnya
    if #PurchaseHistoryLog > 0 and PurchaseHistoryLog[1].name == itemName then
        PurchaseHistoryLog[1].count = PurchaseHistoryLog[1].count + 1
    else
        -- Jika beda, masukkan ke urutan paling atas (index 1)
        table.insert(PurchaseHistoryLog, 1, {name = itemName, count = 1})
    end
    
    -- Maksimal simpan 5 baris agar layar tidak penuh
    if #PurchaseHistoryLog > 5 then
        table.remove(PurchaseHistoryLog, 6)
    end
end

-- =========================================================================
-- MENGAMBIL KONFIGURASI DARI LUAR (GETGENV)
local Config = getgenv().MuzeAutoBuyConfig or {
    BlackScreen = true,
    BuySeeds = false,
    BuyGears = false,
    AutoSell = false,
    DailyDeal = false,
    Delay = 10,
    Seeds = {},
    Gears = {}
}
-- =========================================================================

-- 1. BYPASS TUTORIAL
local function completeTutorialInstantly()
    print("[1/6] Bypass tutorial...")
    pcall(function()
        Networking.Tutorial.Complete:Fire()
    end)
end

-- 2. TELEPORT KE STEVEN
local function teleportToSteven()
    print("[2/6] Teleport ke Steven...")
    local steven = Workspace:FindFirstChild("Steven", true)
    
    if not steven then
        repeat
            task.wait(1)
            steven = Workspace:FindFirstChild("Steven", true)
        until steven
    end

    local target = (steven:IsA("Model") and (steven.PrimaryPart or steven:FindFirstChild("HumanoidRootPart"))) or (steven:IsA("BasePart") and steven)
    
    if target then
        for i = 1, 5 do
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = target.CFrame + Vector3.new(0, 3, 3)
                root.Velocity = Vector3.new(0, 0, 0)
                
                local platName = "AntiVoidPlatform_Steven"
                if not Workspace:FindFirstChild(platName) then
                    local plat = Instance.new("Part")
                    plat.Name = platName
                    plat.Size = Vector3.new(50, 2, 50)
                    plat.Position = root.Position - Vector3.new(0, 4, 0)
                    plat.Anchored = true
                    plat.Transparency = 0.5 
                    plat.BrickColor = BrickColor.new("Bright green")
                    plat.Material = Enum.Material.Neon
                    plat.Parent = Workspace
                end
                
                -- Anchor Steven agar tidak jatuh saat map dihancurkan
                if target:IsA("Model") then
                    for _, v in ipairs(target:GetDescendants()) do
                        if v:IsA("BasePart") then v.Anchored = true end
                    end
                elseif target:IsA("BasePart") then
                    target.Anchored = true
                end
            end
            task.wait(5)
        end
    end
end

-- 3. AUTO CLAIM MAIL
local function startAutoClaimMail()
    print("[3/6] Mengaktifkan Auto Claim Mail...")
    task.spawn(function()
        while true do
            local ok, inbox = pcall(function() return Networking.Mailbox.OpenInbox:Fire() end)
            if ok and typeof(inbox) == "table" then
                for id in pairs(inbox) do
                    pcall(function() Networking.Mailbox.Claim:Fire(id) end)
                    task.wait(0.3)
                end
            end
            task.wait(30)
        end
    end)
end

-- ==========================
-- FPS BOOST HELPERS
-- ==========================
local function getParentType(desc)
    local current = desc
    local isFruit = false
    local isPlant = false
    while current and current ~= Workspace do
        if current.Name == "Fruits" then isFruit = true end
        if current.Name == "Plants" then isPlant = true end
        current = current.Parent
    end
    return isFruit, isPlant
end

local function superBrutalize(desc)
    if desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("Sparkles") or desc:IsA("Light") or desc:IsA("PostEffect") or desc:IsA("Texture") or desc:IsA("Decal") or desc:IsA("SurfaceAppearance") then
        pcall(function() desc:Destroy() end)
        return
    end
    if desc:IsA("Motor6D") or desc:IsA("Animator") or desc:IsA("AnimationController") then
        pcall(function() desc:Destroy() end)
        return
    end
    if desc:IsA("BasePart") then
        desc.CastShadow = false
        local isFruit, isPlant = getParentType(desc)
        if desc.Name == "HarvestPart" then
            desc.Transparency = 0.5
            desc.Color = Color3.fromRGB(0, 255, 0) 
            desc.Material = Enum.Material.Neon
        elseif isFruit then
            desc.Material = Enum.Material.SmoothPlastic
            desc.Reflectance = 0
        elseif isPlant then
            if desc.Name ~= "Base" then
                desc.Transparency = 1
                desc.CanCollide = false 
            end
            desc.Anchored = true
        else
            desc.Material = Enum.Material.SmoothPlastic
            desc.Reflectance = 0
            if desc.Parent and not desc.Parent:FindFirstChild("Humanoid") then
                desc.Anchored = true
            end
        end
    end
end

local function nukeEnvironment()
    local annoyingStuff = {"BirdVisuals", "Birds", "BlizzardBeams", "Weather", "Clouds", "Rain"}
    for _, name in ipairs(annoyingStuff) do
        local obj = Workspace:FindFirstChild(name)
        if obj then pcall(function() obj:Destroy() end) end
    end
    if Terrain then
        pcall(function()
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.WaterTransparency = 1
            Terrain.Decoration = false
            Terrain:Clear() -- MENGHAPUS SEMUA TERRAIN GEOMETRY (MENGHEMAT RATUSAN MB RAM)
        end)
    end
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        UserSettings():GetService("UserGameSettings").MasterVolume = 0
    end)
end

-- 4. FPS BOOST & BLACK SCREEN
local function applyFpsBoost()
    print("[4/6] Mengaktifkan Brutal FPS Boost & Custom Black Screen...")
    
    local objectsToDestroy = {"MidLayer", "Baseplate", "Middle", "Grass", "Gardens", "SpawnPoint", "Trees", "Decorations"}
    for _, name in pairs(objectsToDestroy) do 
        if Workspace:FindFirstChild(name) then pcall(function() Workspace[name]:Destroy() end) end 
    end
    
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 0 
        for _, child in pairs(Lighting:GetChildren()) do
            if child:IsA("BloomEffect") or child:IsA("BlurEffect") or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") or child:IsA("DepthOfFieldEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("PostEffect") then 
                child:Destroy() 
            end
        end
    end)
    
    nukeEnvironment()
    
    -- ULTIMATE BRUTALITY (MENGHAPUS SELURUH FISIK MAP KECUALI KITA, NPC, DAN PLATFORM)
    local char = LocalPlayer.Character
    local platName = "AntiVoidPlatform_Steven"
    
    local function isProtected(desc)
        if not desc then return true end
        if char and desc:IsDescendantOf(char) then return true end
        if desc.Name == platName or desc.Name == "TempSeedPlatform" or desc.Name == "Terrain" or desc.Name == "Camera" then return true end
        if desc:IsA("ProximityPrompt") or desc:FindFirstChildWhichIsA("ProximityPrompt") then return true end
        
        local dName = desc.Name:lower()
        if dName:match("seed") or dName:match("drop") or dName:match("gift") or dName:match("fruit") or dName:match("coin") or dName:match("bag") then return true end
        
        -- PROTECT ALL NPCs (Mencegah semua NPC terhapus)
        local current = desc
        local depth = 0
        while current and current ~= Workspace and depth < 6 do
            if current:FindFirstChildWhichIsA("Humanoid") then return true end
            if current.Name:lower() == "npcs" or current.Name:lower() == "npc" then return true end
            current = current.Parent
            depth = depth + 1
        end
        
        return false
    end
    
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if isProtected(desc) then continue end
        
        if desc:IsA("BasePart") or desc:IsA("MeshPart") or desc:IsA("UnionOperation") then
            pcall(function() desc:Destroy() end)
        elseif desc:IsA("Texture") or desc:IsA("Decal") or desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") then
            pcall(function() desc:Destroy() end)
        end
    end
    
    -- AUTO DELETE GRAFIS BARU (MENCEGAH RAM LEAK) DENGAN DEFER AGAR CPU TIDAK SPIKE
    Workspace.DescendantAdded:Connect(function(desc)
        task.defer(function()
            if not desc or not desc.Parent then return end
            if isProtected(desc) then return end
            
            if desc:IsA("BasePart") or desc:IsA("MeshPart") or desc:IsA("UnionOperation") then
                pcall(function() desc:Destroy() end)
            elseif desc:IsA("Texture") or desc:IsA("Decal") or desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Sound") then
                pcall(function() desc:Destroy() end)
            end
        end)
    end)
    
    Workspace.CurrentCamera.FieldOfView = 30

    pcall(function()
        if Config.BlackScreen then
            local bgGui = Instance.new("ScreenGui")
            bgGui.Name = "AFK_BlackScreen"
            bgGui.IgnoreGuiInset = true
            bgGui.ResetOnSpawn = false
            
            local bgFrame = Instance.new("Frame")
            bgFrame.Size = UDim2.new(1, 0, 1, 0)
            bgFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            bgFrame.BorderSizePixel = 0
            bgFrame.Parent = bgGui

            local leftImage = Instance.new("ImageLabel")
            leftImage.Size = UDim2.new(0.3, 0, 0.6, 0) 
            leftImage.Position = UDim2.new(0.05, 0, 0.5, 0)
            leftImage.AnchorPoint = Vector2.new(0, 0.5)
            leftImage.BackgroundTransparency = 1
            leftImage.ScaleType = Enum.ScaleType.Fit
            leftImage.Image = "rbxassetid://79880397850563"
            leftImage.Parent = bgFrame

            local rightImage = Instance.new("ImageLabel")
            rightImage.Size = UDim2.new(0.3, 0, 0.6, 0)
            rightImage.Position = UDim2.new(0.95, 0, 0.5, 0)
            rightImage.AnchorPoint = Vector2.new(1, 0.5)
            rightImage.BackgroundTransparency = 1
            rightImage.ScaleType = Enum.ScaleType.Fit
            rightImage.Image = "rbxassetid://104624206636533"
            rightImage.Parent = bgFrame
            
            local textLabel = Instance.new("TextLabel")
            textLabel.Size = UDim2.new(0.9, 0, 0.25, 0)
            textLabel.Position = UDim2.new(0.5, 0, 0.95, 0)
            textLabel.AnchorPoint = Vector2.new(0.5, 1)
            textLabel.BackgroundTransparency = 1
            textLabel.Text = "AFK MODE ACTIVE\nFENG JIU MY BINI JIR"
            textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            textLabel.TextScaled = true
            textLabel.TextWrapped = true
            textLabel.Font = Enum.Font.Code
            textLabel.ZIndex = 10
            textLabel.Parent = bgFrame
            
            local centerLabel = Instance.new("TextLabel")
            centerLabel.Size = UDim2.new(0.4, 0, 0.2, 0)
            centerLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
            centerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
            centerLabel.BackgroundTransparency = 1
            centerLabel.Text = "Loading..."
            centerLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
            centerLabel.TextScaled = true
            centerLabel.TextWrapped = false
            centerLabel.Font = Enum.Font.GothamBold
            centerLabel.ZIndex = 10
            centerLabel.Parent = bgFrame
            
            local textConstraint = Instance.new("UITextSizeConstraint")
            textConstraint.MaxTextSize = 25
            textConstraint.Parent = centerLabel
            
            local centerStroke = Instance.new("UIStroke")
            centerStroke.Thickness = 1.5
            centerStroke.Color = Color3.fromRGB(0, 0, 0)
            centerStroke.Parent = centerLabel
            
            -- HISTORY UI 
            local historyLabel = Instance.new("TextLabel")
            historyLabel.Size = UDim2.new(0.4, 0, 0.3, 0)
            historyLabel.Position = UDim2.new(0.5, 0, 0.5, 0) 
            historyLabel.AnchorPoint = Vector2.new(0.5, 0)
            historyLabel.BackgroundTransparency = 1
            historyLabel.Text = ""
            historyLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
            historyLabel.TextScaled = false
            historyLabel.TextSize = 14 
            historyLabel.TextXAlignment = Enum.TextXAlignment.Center
            historyLabel.TextYAlignment = Enum.TextYAlignment.Top
            historyLabel.TextWrapped = true
            historyLabel.Font = Enum.Font.GothamBold
            historyLabel.ZIndex = 10
            historyLabel.Parent = bgFrame
            
            local historyStroke = Instance.new("UIStroke")
            historyStroke.Thickness = 1.2
            historyStroke.Color = Color3.fromRGB(0, 0, 0)
            historyStroke.Parent = historyLabel
            
            -- PERFORMANCE UI
            local perfLabel = Instance.new("TextLabel")
            perfLabel.Size = UDim2.new(0.5, 0, 0.05, 0)
            perfLabel.Position = UDim2.new(0.5, 0, 0.02, 0) 
            perfLabel.AnchorPoint = Vector2.new(0.5, 0)
            perfLabel.BackgroundTransparency = 1
            perfLabel.Text = "FPS: - | Ping: - ms | Mem: - MB"
            perfLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            perfLabel.TextScaled = false
            perfLabel.TextSize = 14
            perfLabel.Font = Enum.Font.Code
            perfLabel.ZIndex = 10
            perfLabel.Parent = bgFrame
            
            local perfStroke = Instance.new("UIStroke")
            perfStroke.Thickness = 1
            perfStroke.Color = Color3.fromRGB(0, 0, 0)
            perfStroke.Parent = perfLabel
            
            task.spawn(function()
                local Stats = game:GetService("Stats")
                while true do
                    local sheckles = "0"
                    pcall(function()
                        sheckles = tostring(LocalPlayer.leaderstats.Sheckles.Value)
                    end)
                    local function formatNumber(n)
                        n = tonumber(n) or 0
                        if n >= 1e12 then return string.format("%.2fT", n / 1e12)
                        elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
                        elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
                        elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
                        else return tostring(n) end
                    end
                    centerLabel.Text = "ðŸ‘¤ " .. LocalPlayer.Name .. "\nðŸ’° " .. formatNumber(sheckles)
                    
                    -- Merangkai History Log Terbaru
                    local historyLines = {}
                    for i, data in ipairs(PurchaseHistoryLog) do
                        table.insert(historyLines, data.name .. " " .. data.count .. "x")
                    end
                    
                    if #historyLines > 0 then
                        historyLabel.Text = "ðŸ›’ HISTORY (REAL-TIME):\n" .. table.concat(historyLines, "\n")
                    else
                        historyLabel.Text = ""
                    end
                    
                    -- Update Performance Stats
                    local ping = "0"
                    pcall(function() ping = string.split(Stats.Network.ServerStatsItem["Data Ping"]:GetValueString(), " ")[1] or "0" end)
                    
                    local fps = "0"
                    pcall(function() fps = tostring(math.floor(Workspace:GetRealPhysicsFPS())) end)
                    
                    local mem = "0"
                    pcall(function() mem = string.split(Stats.PerformanceStats.Memory:GetValueString(), " ")[1] or "0" end)
                    
                    perfLabel.Text = string.format("ðŸŽ® FPS: %s  |  ðŸ“¶ Ping: %s ms  |  ðŸ§  Mem: %s MB", fps, ping, mem)
                    
                    task.wait(1)
                end
            end)

            local success = pcall(function() bgGui.Parent = CoreGui end)
            if not success then
                bgGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
            end

            RunService:Set3dRenderingEnabled(false)
        end
        if setfpscap then setfpscap(15) end
    end)
end

-- 5. AUTO BUY (MENGGUNAKAN GETGENV CONFIG & API TERBARU ANTI-PATCH)
local function startAutoBuy()
    print("[5/6] Mengaktifkan Auto Buy (Dari Config Dalam, Smart Anti-Patch)...")
    
    task.spawn(function()
        while true do
            -- Membeli Seed jika diaktifkan di config dalam
            if Config.BuySeeds and Config.Seeds then
                for itemName, isEnabled in pairs(Config.Seeds) do 
                    if isEnabled == true then
                        for i = 1, 3 do 
                            local oldMoney = 0
                            pcall(function() oldMoney = LocalPlayer.leaderstats.Sheckles.Value end)
                            
                            pcall(function() Networking.SeedShop.PurchaseSeed:Fire(itemName) end)
                            task.wait(0.5) 
                            
                            local newMoney = 0
                            pcall(function() newMoney = LocalPlayer.leaderstats.Sheckles.Value end)
                            
                            if newMoney < oldMoney then
                                logPurchase(itemName)
                            end
                        end
                    end
                end
            end
            
            -- Membeli Gear jika diaktifkan di config dalam
            if Config.BuyGears and Config.Gears then
                for itemName, isEnabled in pairs(Config.Gears) do 
                    if isEnabled == true then
                        for i = 1, 3 do 
                            local oldMoney = 0
                            pcall(function() oldMoney = LocalPlayer.leaderstats.Sheckles.Value end)
                            
                            pcall(function() Networking.GearShop.PurchaseGear:Fire(itemName) end)
                            task.wait(0.5)
                            
                            local newMoney = 0
                            pcall(function() newMoney = LocalPlayer.leaderstats.Sheckles.Value end)
                            
                            if newMoney < oldMoney then
                                logPurchase(itemName)
                            end
                        end
                    end
                end
            end
            
            task.wait(Config.Delay or 10)
        end
    end)
end

-- ==========================
-- AUTO SELL HELPERS (DARI SCRIPT.TXT)
-- ==========================
local utilityTools = {
    ["Basic Pot"] = true, ["Watering Can"] = true, ["Trowel"] = true,
    ["Super Trowel"] = true, ["Golden Trowel"] = true,
    ["Infinite Watering Can"] = true, ["Seed Bag"] = true,
}

local function isSellableFruit(item)
    if not item:IsA("Tool") then return false end
    if utilityTools[item.Name] then return false end
    
    local patterns = {"Pot", "Can", "Trowel", "Bag", "Fertilizer", "Axe", "Pickaxe", "Shovel", "Sprinkler", "Seed"}
    for _, p in ipairs(patterns) do
        if item.Name:find(p) then return false end
    end
    
    return true
end

local function PerformSell()
    local fruits = {}
    
    for _, item in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if isSellableFruit(item) then table.insert(fruits, item) end
    end
    if LocalPlayer.Character then
        for _, item in ipairs(LocalPlayer.Character:GetChildren()) do
            if isSellableFruit(item) then table.insert(fruits, item) end
        end
    end

    if #fruits > 0 then
        task.spawn(function()
            if Config.DailyDeal then
                -- Coba gunakan Daily Deal secara paksa jika diaktifkan (dibungkus spawn)
                task.spawn(function()
                    pcall(function() Networking.NPCS.UseDailyDealAll:Fire() end)
                end)
                task.wait(0.5)
            end
            
            -- Coba gunakan SellAll secara paksa (dibungkus spawn)
            task.spawn(function()
                pcall(function() Networking.NPCS.SellAll:Fire() end)
            end)
            task.wait(0.5)
            
            -- Fallback brutal (seperti script.txt yang bisa dari mana saja)
            local stillHasFruits = false
            for _, item in ipairs(LocalPlayer.Backpack:GetChildren()) do
                if isSellableFruit(item) then
                    stillHasFruits = true
                    break
                end
            end

            if stillHasFruits then
                for _, tool in ipairs(fruits) do
                    local id = tool:GetAttribute("Id")
                    if id and tool.Parent then
                        pcall(function() Networking.NPCS.SellFruit:Fire(id) end)
                        task.wait()
                    end
                end
            end
        end)
    end
end

-- 6. AUTO DAILY DEAL (10s) & AUTO SELL (3m)
local function startAutoDailyDealAndSell()
    print("[6/6] Mengaktifkan Auto Daily Deal (10s) & Auto Sell (180s)...")
    
    task.spawn(function()
        local timer = 0
        while true do
            if Config.AutoSell then
                -- Daily Deal tiap 10 detik
                if timer % 10 == 0 and Config.DailyDeal then
                    task.spawn(function()
                        pcall(function() Networking.NPCS.UseDailyDealAll:Fire() end)
                    end)
                end
                
                -- Eksekusi Auto Sell (setiap 180 detik / 3 menit)
                if timer % 180 == 0 then
                    pcall(function()
                        PerformSell()
                    end)
                end
            end
            
            task.wait(1)
            timer = timer + 1
        end
    end)
end

-- AUTO RECONNECT (ERROR CODE 529 DLL)
local function setupAutoReconnect()
    print("[+] Auto Reconnect (Error Handler) diaktifkan.")
    local TeleportService = game:GetService("TeleportService")
    local GuiService = game:GetService("GuiService")
    
    -- Metode 1: Menggunakan GuiService ErrorMessageChanged
    GuiService.ErrorMessageChanged:Connect(function()
        task.wait(2)
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    end)
    
    -- Metode 2: Menggunakan CoreGui PromptOverlay (Cadangan)
    pcall(function()
        local promptOverlay = CoreGui:FindFirstChild("RobloxPromptGui") and CoreGui.RobloxPromptGui:FindFirstChild("promptOverlay")
        if promptOverlay then
            promptOverlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" then
                    task.wait(2)
                    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
                end
            end)
        end
    end)
end

-- ANTI AFK
local function setupAntiAFK()
    print("[+] Anti-AFK diaktifkan.")
    
    LocalPlayer.Idled:Connect(function()
        if antiAfkEnabled then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
    end)

    task.spawn(function()
        while true do
            task.wait(math.random(150, 240)) 
            if antiAfkEnabled then
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                end)
                pcall(function()
                    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        humanoid.Jump = true
                    end
                end)
            end
        end
    end)
end

-- AUTO ADD & ACCEPT FRIEND
local function startAutoFriend()
    print("[+] Mengaktifkan Auto Add & Accept Friend...")
    task.spawn(function()
        while true do
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    pcall(function()
                        LocalPlayer:RequestFriendship(player)
                    end)
                end
            end
            task.wait(10)
        end
    end)
end

-- FLY TO TARGET (ANTI-BAN)
local function flyToTarget(targetPos)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("Humanoid") then return false end
    
    local root = char.HumanoidRootPart
    local hum = char.Humanoid
    local finalTarget = Vector3.new(targetPos.X, targetPos.Y + 3, targetPos.Z)
    local distance = (root.Position - finalTarget).Magnitude
    if distance <= 8 then return true end 
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.zero
    bv.Parent = root
    hum.PlatformStand = true 
    
    local noclipConnection
    noclipConnection = game:GetService("RunService").Stepped:Connect(function()
        if char then
            for _, v in ipairs(char:GetChildren()) do
                if v:IsA("BasePart") and v.CanCollide then
                    v.CanCollide = false
                end
            end
        end
    end)
    
    local speed = 25 
    local timeout = 0
    local maxTime = (distance / speed) + 5 
    while char and root and (root.Position - finalTarget).Magnitude > 5 and timeout < maxTime do
        local direction = (finalTarget - root.Position).Unit
        bv.Velocity = direction * speed
        task.wait(0.05)
        timeout = timeout + 0.05
    end
    
    if noclipConnection then noclipConnection:Disconnect() end
    if bv then pcall(function() bv:Destroy() end) end
    root.Velocity = Vector3.zero
    hum.PlatformStand = false 
    task.wait(0.2)
    return (root.Position - finalTarget).Magnitude <= 15
end

-- AUTO SEED COLLECTOR (HEADLESS)
local function startAutoSeedCollector()
    print("[+] Mengaktifkan Auto Seed Collector (Tumbal)...")
    local wasCollecting = false
    
    task.spawn(function()
        while true do
            task.wait(2.5) -- Diperlambat agar CPU tidak panas
            local foundSeed = nil
            local targetPrompt = nil
            
            local descendants = workspace:GetDescendants()
            for i, obj in ipairs(descendants) do
                if i % 1000 == 0 then task.wait() end -- YIELD PENTING: Mencegah CPU Spike / Lag saat looping
                if obj:IsA("Model") or obj:IsA("BasePart") then
                    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt then
                        local name = obj.Name:lower()
                        local parentName = (obj.Parent and obj.Parent.Name) and obj.Parent.Name:lower() or ""
                        local actionText = prompt.ActionText:lower()
                        local objectText = prompt.ObjectText:lower()
                        local isValidSeed = false
                        
                        if actionText:match("pick up") or actionText:match("collect") or actionText:match("take") or actionText:match("grab") or actionText:match("loot") or actionText:match("claim") then
                            isValidSeed = true
                        else
                            local combinedText = name .. " " .. parentName .. " " .. objectText
                            if combinedText:match("seed") or combinedText:match("gold") or combinedText:match("mega") or combinedText:match("rainbow") or combinedText:match("mutation") or combinedText:match("carrot") or combinedText:match("apple") or combinedText:match("pomegranate") or combinedText:match("coconut") or combinedText:match("cactus") or combinedText:match("mushroom") or combinedText:match("bamboo") or combinedText:match("corn") or combinedText:match("berry") then
                                if actionText ~= "harvest" and actionText ~= "sit" and actionText ~= "talk" and actionText ~= "buy" and actionText ~= "use" then
                                    isValidSeed = true
                                end
                            end
                        end
                        
                        if isValidSeed then
                            foundSeed = obj
                            targetPrompt = prompt
                            break
                        end
                    end
                end
            end
            
            if foundSeed and targetPrompt then
                wasCollecting = true
                
                -- AMBIL POSISI DENGAN AMAN (Bisa dari Part, Attachment, atau dalam Model)
                local targetPos = nil
                if targetPrompt.Parent:IsA("BasePart") then
                    targetPos = targetPrompt.Parent.Position
                elseif targetPrompt.Parent:IsA("Attachment") then
                    targetPos = targetPrompt.Parent.WorldPosition
                else
                    local part = foundSeed:IsA("BasePart") and foundSeed or foundSeed:FindFirstChildWhichIsA("BasePart", true)
                    if part then targetPos = part.Position end
                end
                
                if targetPos then
                    local reached = flyToTarget(targetPos)
                    if reached then
                    local char = LocalPlayer.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if root then
                        -- Buat pijakan sementara
                        local tempPlat = Instance.new("Part")
                        tempPlat.Name = "TempSeedPlatform"
                        tempPlat.Size = Vector3.new(15, 1, 15)
                        tempPlat.Position = targetPos - Vector3.new(0, 4, 0)
                        tempPlat.Anchored = true
                        tempPlat.Transparency = 0.5
                        tempPlat.BrickColor = BrickColor.new("Bright green")
                        tempPlat.Material = Enum.Material.Neon
                        tempPlat.Parent = workspace
                        game:GetService("Debris"):AddItem(tempPlat, 5)
                        
                        -- BUKA KUNCI PROMPT AGAR 100% BISA DITEKAN
                        targetPrompt.RequiresLineOfSight = false
                        targetPrompt.MaxActivationDistance = 9999
                        if targetPrompt.HoldDuration > 0 then targetPrompt.HoldDuration = 0 end
                        
                        -- SPAM KLIK SUPER BARBAR DI BACKGROUND (Spam 20x)
                        task.spawn(function()
                            for i=1, 20 do
                                pcall(fireproximityprompt, targetPrompt)
                                task.wait(0.05)
                            end
                        end)
                        
                        task.wait(1) -- Beri waktu sebentar untuk memastikan barang masuk
                    end
                end
                end
            else
                if wasCollecting then
                    wasCollecting = false
                    print("[+] Selesai mungut barang, kembali ke Steven...")
                    local steven = Workspace:FindFirstChild("Steven", true)
                    if steven then
                        local st = (steven:IsA("Model") and (steven.PrimaryPart or steven:FindFirstChild("HumanoidRootPart"))) or (steven:IsA("BasePart") and steven)
                        if st then
                            flyToTarget(st.Position + Vector3.new(0, 0, 3))
                        end
                    end
                end
            end
        end
    end)
end

-- ==========================
-- --- EKSEKUSI URUTAN ---
-- ==========================
setupAutoReconnect()
setupAntiAFK()
startAutoFriend()
startAutoSeedCollector()

task.spawn(function()
    -- 1. BYPASS TUTORIAL
    local function isInTutorial()
        local char = LocalPlayer.Character
        return Workspace:GetAttribute("InTutorial") or (char and char:GetAttribute("InTutorial"))
    end

    if isInTutorial() then
        completeTutorialInstantly()
        local waitTime = 0
        while isInTutorial() do
            task.wait(0.5)
            waitTime = waitTime + 0.5
            if waitTime >= 30 then
                print("[!] Tutorial stuck selama 30 detik! Memaksa rejoin...")
                local ts = game:GetService("TeleportService")
                pcall(function() ts:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
                task.wait(3)
                pcall(function() ts:Teleport(game.PlaceId, LocalPlayer) end)
                break
            end
        end
        task.wait(1)
    end
    
    -- 2. TELEPORT KE STEVEN
    teleportToSteven()
    task.wait(1)
    
    -- 3. AUTO CLAIM MAIL
    startAutoClaimMail()
    task.wait(0.5)
    
    -- 4. FPS BOOST
    applyFpsBoost()
    task.wait(0.5)
    
    -- 5. AUTO BUY
    startAutoBuy()
    task.wait(0.5)
    
    -- 6. AUTO DAILY DEAL & SELL
    startAutoDailyDealAndSell()
    
    print("[+] Selesai! Semua fitur telah dijalankan dan sedang bekerja di latar belakang.")
end)
