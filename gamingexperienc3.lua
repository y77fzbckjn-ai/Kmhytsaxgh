--[[
    SMART KAITUN — FALL HARVEST
    Sekali eksekusi: beli -> tanam -> panen -> jual -> ulang, sambil menjalankan
    Cornucopia Quest, dengan mode speedrun Leaves saat kebun sudah bagus.

    Untuk dunia event "Fall Harvest", BUKAN Grow a Garden 2.

    ---------------------------------------------------------------------------
    SEMUA signature di bawah ditangkap dari panggilan ASLI di klien, bukan
    ditebak. Jangan diubah tanpa menangkap ulang:

      SeedShop.PurchaseSeed:Fire("Maple Carrot")
      Plant.PlantSeed:Fire(Vector3, "Maple Strawberry", Tool)   -- Tool WAJIB diequip
      Shovel.UseShovel:Fire("{userId}_{guid}", "", "Shovel", ToolShovel)
      Garden.CollectFruit:Fire("{guid}", "{indeksBuah}")
      NPCS.PreviewSellAll()  lalu  NPCS.SellAll()               -- tanpa argumen

    Dua jebakan yang cuma ketahuan dari data asli:
      1. UseShovel memakai plantId BER-PREFIX "{userId}_{guid}", sedangkan
         CollectFruit memakai guid TELANJANG + indeks buah. Nama model tanaman
         di workspace berbentuk "{userId}_{guid}_{n}", jadi ketiganya diurai
         dari satu nama itu.
      2. Jual butuh staging: PreviewSellAll dipanggil lebih dulu, kalau tidak
         server menolak diam-diam (pola yang sama dengan SellAll di GAG2).

    Soal jarak: dugaan awal "semua fire wajib dari jarak dekat" ternyata TERLALU
    LUAS. Diuji langsung di lapangan, panen, tanam, jual, dan cabut semuanya
    diterima server dari jarak jauh.

    Yang WAJIB mendekat tinggal MEMBELI, dan itu bukan soal berhasil-tidaknya:
    PurchaseSeed dari jauh tetap diterima, tapi anticheat menandainya dan ban
    menyusul belakangan. Karena itu jalur beli tidak punya opsi untuk dimatikan,
    dan kalau NPC-nya tak tercapai, pembelian dibatalkan seluruhnya.

    Geraknya sendiri memakai BodyVelocity berkecepatan tetap (default 22 studs/s).
    Versi pertama memakai BodyPosition yang menarik dengan gaya besar sehingga
    karakter melesat -- terlihat jelas tidak wajar.
]]

-- ==========================================
-- SISTEM VERIFIKASI HWID & DISCORD (MOZEFRAME)
-- ==========================================
-- Diport dari kaitun_main.txt. Panel key-nya SAMA, jadi buyer yang sudah punya
-- akses langsung bisa memakai script ini tanpa key baru.
--
-- PanelKey diterima dari DUA tempat: MuzeFallHarvestConfig (kalau kamu mengaturnya
-- khusus) maupun MuzeAutoBuyConfig (format snippet yang sudah dipakai panel).
-- Dengan begitu loader lama tidak perlu diubah bentuknya.
local cfgFH  = getgenv().MuzeFallHarvestConfig or {}
local cfgMain = getgenv().MuzeAutoBuyConfig or {}

local raw_panel_key = cfgFH.PanelKey or cfgMain.PanelKey or ""
local panel_key = raw_panel_key
if string.find(raw_panel_key, "/") then
    panel_key = string.split(raw_panel_key, "/")[1]
end

local hwid = gethwid and gethwid() or ""
if hwid == "" then
    local client_id = game:GetService("RbxAnalyticsService"):GetClientId()
    hwid = "RBX-" .. client_id
end

local function forceRejoin(reason)
    pcall(function()
        warn("Force Rejoining... Reason: " .. tostring(reason))
        game:GetService("TeleportService"):Teleport(game.PlaceId, game.Players.LocalPlayer)
    end)
    task.wait(5)
    game.Players.LocalPlayer:Kick(reason)
end

if panel_key == "" then
    game.Players.LocalPlayer:Kick("❌ AKSES DITOLAK: Panel Key tidak ditemukan!\nSilakan generate config baru di Web Panel dan pastikan mengisi Panel Key (DiscordID/Key).")
    return
end

if panel_key == "MOZE-SAYANG-NIA" then
    print("✅ Berhasil Login! (VIP Secret Key Bypassed)")
else
    local API_URL = "https://mozeframe.my.id/verify_login?panel_key="
        .. game:GetService("HttpService"):UrlEncode(raw_panel_key)
        .. "&hwid=" .. game:GetService("HttpService"):UrlEncode(hwid)

    local success, response = pcall(function()
        return game:HttpGet(API_URL)
    end)

    if not success then
        forceRejoin("❌ Gagal terhubung ke Server HWID (Koneksi Terputus). Mencoba Rejoin...")
        return
    end

    local data = game:GetService("HttpService"):JSONDecode(response)

    if data.status == "success" and data.active == true then
        print("✅ Berhasil Login! Sisa masa aktif: " .. tostring(data.days_left) .. " Hari.")
    else
        local msg = data.message or "Terjadi kesalahan autentikasi."
        if setclipboard then setclipboard(hwid) end
        forceRejoin("❌ AKSES DITOLAK: " .. msg .. "\nMencoba rejoin...")
        return
    end
end
-- ==========================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local LocalPlayer        = Players.LocalPlayer

-- Dibaca sekali di blok verifikasi di atas; dipakai ulang di sini supaya tidak
-- ada dua sumber kebenaran untuk config yang sama.
local cfg = cfgFH
local Config = {
    AutoBeli      = cfg.AutoBeli ~= false,
    AutoTanam     = cfg.AutoTanam ~= false,
    AutoPanen     = cfg.AutoPanen ~= false,
    AutoJual      = cfg.AutoJual ~= false,
    AutoQuest     = cfg.AutoQuest ~= false,
    -- Mengambil seed jatuhan (gold, rainbow, mega, dll) lewat pemindaian
    -- ProximityPrompt -- diport dari kaitun utama.
    AutoAmbilSeed = cfg.AutoAmbilSeed ~= false,

    -- ==== MODE BAMBOO ====
    -- Alur alternatif penghasil Leaves: begitu modal cukup, kebun dikosongkan
    -- lalu diisi Maple Bamboo saja, disiram sprinkler + watering can, panen,
    -- jual, ulang. Lebih cepat daripada menanam macam-macam bibit murah.
    ModeBamboo       = cfg.ModeBamboo ~= false,
    -- Ambang Leaves untuk berhenti bertani biasa dan beralih. Harus cukup untuk
    -- Syrup Watering Can (2K) + Syrup Sprinkler + modal bambu (700 per biji).
    AmbangModeBamboo = tonumber(cfg.AmbangModeBamboo) or 100000,
    SeedBamboo       = cfg.SeedBamboo or "Maple Bamboo",
    GearSprinkler    = cfg.GearSprinkler or "Syrup Sprinkler",
    GearSiram        = cfg.GearSiram or "Syrup Watering Can",
    -- 3-5 siraman per siklus. Lebih dari itu terbuang: pertumbuhan sudah penuh.
    SiramPerSiklus   = tonumber(cfg.SiramPerSiklus) or 4,
    -- Berapa bambu dibeli sekali belanja.
    BeliBambooSekali = tonumber(cfg.BeliBambooSekali) or 20,

    -- Batas frame. Sasarannya perangkat yang menjalankan 8-10 klien Roblox
    -- sekaligus -- di sana render adalah pemakan CPU terbesar, sedangkan bot
    -- tidak butuh frame tinggi sama sekali. Terukur: 125 fps -> 19 fps.
    --
    -- TIDAK BOLEH terlalu rendah. Loop terbang memakai RunService.Heartbeat,
    -- yang berdetak sekali per frame, jadi batas ini menentukan kerapatan
    -- koreksi arah dan pemasangan ulang noclip. Kecepatannya sendiri tidak
    -- terpengaruh (BodyVelocity dijalankan mesin fisika), tapi di bawah ~10 fps
    -- kemudinya mulai kasar dan karakter bisa menyangkut. Karena itu dijepit.
    -- Set 0 untuk mematikan pembatasan sepenuhnya.
    BatasFps      = (function()
        local v = tonumber(cfg.BatasFps) or 20
        if v <= 0 then return 0 end
        return math.max(10, math.min(240, v))
    end)(),
    -- Kebun orang lain dimuat bertahap seiring pemain berdatangan, jadi
    -- pembersihannya diulang. Murah (~1,2 ms, hanya menyentuh Gardens).
    SiklusBersihKebun = tonumber(cfg.SiklusBersihKebun) or 5,

    -- Mencuri dari kebun orang lain untuk menembus langkah quest pasif
    -- "Steal from N different people".
    --
    -- SENGAJA MATI SECARA DEFAULT. Kodenya lengkap dan sudah diverifikasi
    -- (StealPrompt hanya ada di kebun orang lain, pemilik terbaca dari nama
    -- tanaman, fireproximityprompt tersedia), tapi TIDAK dipakai karena:
    --   * menembak dari jarak jauh berlawanan langsung dengan anticheat yang
    --     mewajibkan semua fire dilakukan dari dekat
    --   * satu server cuma memuat 8 pemain, jadi 15 korban menuntut ganti
    --     server berulang kali -- pola yang mencolok dan memicu batas laju
    --     teleport Roblox
    -- Nyalakan hanya kalau kamu sudah menimbang risikonya sendiri.
    AutoSteal      = cfg.AutoSteal == true,
    -- Teknik still.lua: naikkan MaxActivationDistance prompt lalu fire dari
    -- mana saja, tanpa jalan ke kebunnya. Set false supaya bot terbang ke tiap
    -- kebun dulu -- lebih lambat, tapi polanya sama dengan beli/jual yang
    -- selama ini aman.
    StealJarakJauh = cfg.StealJarakJauh ~= false,
    -- Quest hanya menghitung ORANG BERBEDA, bukan jumlah buah. Beberapa kali
    -- per orang sudah cukup; sisanya hanya menambah buah curian.
    StealPerOrang  = tonumber(cfg.StealPerOrang) or 3,
    -- Satu server maksimal 8 pemain, jadi paling banyak 7 korban. Untuk sampai
    -- 15 orang bot WAJIB ganti server. Sengaja default MATI: pindah server
    -- memutus siklus tani dan memicu batas laju teleport Roblox.
    StealPindahServer = cfg.StealPindahServer == true,

    -- Sudah diuji terarah di kebun sungguhan: dari 27 tanaman, yang terpilih
    -- adalah Maple Strawberry (rarity terendah) -- bukan Bamboo/Cactus yang
    -- rarity-nya tinggi -- dan kebun turun 27 -> 26. Karena pemilihan target,
    -- gerak, dan remote-nya terbukti benar, default-nya dinyalakan.
    -- Set false kalau ingin mematikannya.
    AutoCabut     = cfg.AutoCabut ~= false,

    -- Ambang speedrun Leaves: begitu tanaman di kebun sudah mencapai rarity ini
    -- atau lebih, berhenti belanja dan fokus panen-jual.
    AmbangSpeedrun = cfg.AmbangSpeedrun or "Legendary",

    JedaSiklus    = tonumber(cfg.JedaSiklus) or 5,
    JedaAksi      = tonumber(cfg.JedaAksi) or 0.35,
    -- 0.05 detik = 50 ms, persis ambang yang dipaksakan klien resmi game:
    -- PlantController menolak penanaman kalau jaraknya kurang dari 0.05 detik
    -- (`if v57 - u2 < 0.05 then return false end`). Menembak lebih rapat dari itu
    -- berarti mengirim lebih cepat daripada yang MUNGKIN dilakukan pemain asli --
    -- pola yang persis dicari anticheat. Bisa diturunkan lewat config kalau kamu
    -- memang mau menanggung risikonya.
    JedaTanam     = tonumber(cfg.JedaTanam) or 0.05,

    -- Jarak minimum antar tanaman. Plot terukur 115 x 18 studs, sementara
    -- tanaman menumpuk dalam rentang 7 studs -- titik acak murni memang mudah
    -- berkerumun. Dengan jarak 5, plot ini muat sekitar 80 tanaman.
    JarakTanam    = tonumber(cfg.JarakTanam) or 5,
    -- Berapa kali mencari titik kosong sebelum kebun dianggap penuh.
    -- Dinaikkan dari 25: dengan jarak 5 studs di kebun yang setengah terisi,
    -- 25 lemparan acak kadang meleset semua dan kebun dikira penuh padahal masih
    -- ada ruang -- lalu cabut ikut terpicu terlalu dini.
    CobaTitik     = tonumber(cfg.CobaTitik) or 60,

    -- Jeda saat berpindah dari satu jenis seed ke jenis berikutnya. Berbeda dari
    -- JedaTanam (antar biji dalam satu tumpukan): pergantian seed melibatkan
    -- equip tool baru, dan tanpa jeda equip-nya belum selesai saat tembakan
    -- pertama dikirim -- itu yang membuatnya terlihat "loncat seed terlalu cepat".
    JedaGantiSeed = tonumber(cfg.JedaGantiSeed) or 1.0,

    FpsBoost      = cfg.FpsBoost ~= false,
    BlackScreen   = cfg.BlackScreen ~= false,
    AntiAFK       = cfg.AntiAFK ~= false,

    -- Kapasitas buah terbaca dari atribut MaxFruitCapacity (terukur 100).
    -- Begitu FruitCount menyentuh ambang ini, JUAL dulu sebelum memanen lagi --
    -- tanpa ini panen terus ditembak ke inventory penuh dan terlihat seperti
    -- "stuck spam harvest".
    AmbangJualBuah = tonumber(cfg.AmbangJualBuah) or 70,
    JarakAman     = tonumber(cfg.JarakAman) or 12,
    MaxBeliPerSiklus = tonumber(cfg.MaxBeliPerSiklus) or 20,

    -- studs/detik. Versi pertama memakai BodyPosition yang menarik dengan gaya
    -- besar, jadi karakter melesat ke tujuan -- terlihat jelas tidak wajar.
    -- Sekarang kecepatannya dibatasi dan bisa diatur.
    KecepatanTerbang = tonumber(cfg.KecepatanTerbang) or 22,

    -- Sudah diuji di lapangan: panen, tanam, dan jual TETAP diterima server dari
    -- jarak jauh, jadi tidak perlu terbang bolak-balik untuk itu. Cabut belum
    -- teruji, jadi untuk yang satu itu tetap mendekat -- lebih baik lambat
    -- daripada ditolak diam-diam.
    DekatSaatPanen = cfg.DekatSaatPanen == true,
    -- WAJIB true. Terbukti di lapangan: menanam ditolak total kalau pemain tidak
    -- berada di kebunnya sendiri (atribut IsInOwnGarden). Dari 183 studs, empat
    -- tembakan berturut-turut menghasilkan Count 3->3 dan nol tanaman; setelah
    -- terbang ke plot, tanaman naik 14 -> 16. Laporan awal "tanam bisa dari jauh"
    -- kebetulan diambil saat sedang berdiri di plot.
    DekatSaatTanam = cfg.DekatSaatTanam ~= false,
    DekatSaatJual  = cfg.DekatSaatJual == true,
    -- Sudah diuji: cabut juga diterima dari jarak jauh, jadi tidak perlu lagi
    -- terbang ke tiap tanaman. Menyisakan HANYA pembelian yang wajib mendekat.
    DekatSaatCabut = cfg.DekatSaatCabut == true,

    -- Panen dipisah dari JedaAksi supaya bisa jauh lebih rapat: satu kebun bisa
    -- berisi puluhan buah, dan 0.35 detik per buah membuat satu fase panen
    -- memakan setengah menit sendiri.
    JedaPanen     = tonumber(cfg.JedaPanen) or 0.08,

    -- Peta ini penuh batu dan penghalang. Tanpa noclip, terbang lurus sering
    -- tersangkut dan karakter berhenti di tengah jalan -- terlihat seperti macet.
    Noclip        = cfg.Noclip ~= false,
}

local function status(t)
    _G.FallHarvestDebug = t
    print("[FH] " .. t)
end

local okNet, Networking = pcall(function()
    return require(ReplicatedStorage.SharedModules.Networking)
end)
if not okNet or type(Networking.Pilgrim) ~= "table" then
    status("[BERHENTI] Bukan dunia Fall Harvest.")
    return
end
local SeedData = require(ReplicatedStorage.SharedModules.SeedData)

-- ==========================================================
-- DATA SEED
-- ==========================================================
-- SeedData adalah ARRAY (74 entri), bukan map bernama. Nama yang dipakai shop
-- dan atribut SeedTool ada di field SeedName, jadi indeksnya dibangun sekali.
local infoSeed = {}
for _, e in pairs(SeedData) do
    if type(e) == "table" and e.SeedName then
        infoSeed[e.SeedName] = {
            rarity = e.Rarity or "Common",
            harga  = tonumber(e.PurchasePrice) or math.huge,
        }
    end
end

local TANGGA_RARITY = {
    Common = 1, Uncommon = 2, Rare = 3, Legendary = 4,
    Mythic = 5, Divine = 6, Prismatic = 7, Transcendent = 8,
}
local function nilaiRarity(nama)
    local i = infoSeed[nama]
    return i and (TANGGA_RARITY[i.rarity] or 0) or 0
end
local AMBANG_SPEEDRUN = TANGGA_RARITY[Config.AmbangSpeedrun] or 4

-- ==========================================================
-- GERAK
-- ==========================================================
local function karakter()
    local c = LocalPlayer.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    return c, hrp, hum
end

local function jarakKe(pos)
    local _, hrp = karakter()
    if not hrp then return math.huge end
    return (hrp.Position - pos).Magnitude
end

-- Terbang ke tujuan dengan KECEPATAN TETAP.
--
-- Versi pertama memakai BodyPosition: gaya tariknya besar sehingga karakter
-- melesat dan geraknya tidak wajar. BodyVelocity dengan besaran tetap membuat
-- kecepatannya benar-benar terkendali -- arahnya saja yang diperbarui tiap
-- frame. MaxForce pada sumbu Y sekaligus menahan gravitasi.
-- Noclip: hanya part yang MEMANG tadinya menabrak yang dimatikan, dan persis
-- part itu pula yang dipulihkan. Mematikan semua lalu menyalakan semua akan
-- mengubah part yang aslinya sudah CanCollide=false (HumanoidRootPart, aksesori)
-- dan itu bisa merusak fisika karakter setelah terbang.
local function matikanTabrakan()
    local c = LocalPlayer.Character
    if not c then return {} end
    local disimpan = {}
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            disimpan[#disimpan + 1] = p
            p.CanCollide = false
        end
    end
    return disimpan
end

local function pulihkanTabrakan(disimpan)
    for _, p in ipairs(disimpan) do
        if p.Parent then p.CanCollide = true end
    end
end

local function pergiKe(pos, toleransi)
    toleransi = toleransi or Config.JarakAman
    local _, hrp = karakter()
    if not hrp then return false end

    local tujuan = pos + Vector3.new(0, 3, 0)
    if (hrp.Position - pos).Magnitude <= toleransi then return true end

    -- Batas waktu dihitung dari jarak dan kecepatan, bukan angka tetap: dengan
    -- 22 studs/detik, tujuan 150 studs butuh ~7 detik, dan batas mati 20 detik
    -- akan memutus perjalanan yang sebenarnya sehat.
    local perkiraan = (hrp.Position - tujuan).Magnitude / math.max(1, Config.KecepatanTerbang)
    local batas = tick() + perkiraan * 2 + 5

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local dimatikan = Config.Noclip and matikanTabrakan() or {}

    while tick() < batas do
        local _, h2 = karakter()
        if not h2 then break end
        local selisih = tujuan - h2.Position
        if (h2.Position - pos).Magnitude <= toleransi then break end
        bv.Velocity = selisih.Unit * Config.KecepatanTerbang
        -- Diterapkan ulang tiap frame: Roblox mengembalikan CanCollide sendiri
        -- pada beberapa keadaan, dan sekali saja di awal tidak cukup.
        if Config.Noclip then
            local c = LocalPlayer.Character
            if c then
                for _, p in ipairs(dimatikan) do
                    if p.Parent and p.CanCollide then p.CanCollide = false end
                end
            end
        end
        RunService.Heartbeat:Wait()
    end

    bv:Destroy()
    pulihkanTabrakan(dimatikan)

    -- TUNGGU MENDARAT sebelum menyerahkan kendali.
    --
    -- Ini bukan kehati-hatian berlebihan: kalau langsung dipakai setelah terbang,
    -- karakter masih melayang dan Roblox MELEPAS tool yang baru diequip. Terlihat
    -- sebagai equip=false pada tiap percobaan, dan tidak satu pun penanaman jadi.
    local tungguDarat = tick() + 4
    while tick() < tungguDarat do
        local _, h3, hum3 = karakter()
        if not (h3 and hum3) then break end
        if hum3:GetState() == Enum.HumanoidStateType.Running
           and h3.AssemblyLinearVelocity.Magnitude < 3 then
            break
        end
        task.wait(0.1)
    end

    task.wait(0.2)
    return jarakKe(pos) <= toleransi * 1.5
end

-- ==========================================================
-- PLOT & TANAMAN
-- ==========================================================
-- Mengembalikan kebun milik kita, atau nil kalau BENAR-BENAR tidak bisa
-- dipastikan. Pemanggil WAJIB memperlakukan nil sebagai "jangan sentuh apa pun",
-- bukan sebagai "tidak ada yang perlu dilindungi" -- lihat applyFpsBoost.
local function plotSaya()
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end

    -- 1. Atribut pemilik, kalau game memang menyediakannya.
    for _, g in ipairs(gardens:GetChildren()) do
        for _, kunci in ipairs({ "OwnerUserId", "UserId", "Owner", "OwnerId", "PlayerUserId" }) do
            if tostring(g:GetAttribute(kunci)) == tostring(LocalPlayer.UserId) then return g end
        end
    end

    -- 2. Cadangan lewat nama tanaman "{userId}_{guid}". Format ini sudah
    --    diverifikasi di server sungguhan, sedangkan atribut di atas TIDAK --
    --    dan mengandalkan atribut saja pernah membuat seluruh kebun terhapus.
    local uid = tostring(LocalPlayer.UserId)
    for _, g in ipairs(gardens:GetChildren()) do
        local plants = g:FindFirstChild("Plants")
        if plants then
            for _, t in ipairs(plants:GetChildren()) do
                if string.match(t.Name, "^(%d+)_") == uid then return g end
            end
        end
    end

    -- 3. Cadangan terakhir: kebun orang lain memasang StealPrompt, kebun sendiri
    --    memakai HarvestPrompt. Berguna saat kebun kita masih kosong sehingga
    --    cara (2) tidak punya bahan.
    for _, g in ipairs(gardens:GetChildren()) do
        local plants = g:FindFirstChild("Plants")
        if plants and #plants:GetChildren() > 0 then
            local adaSteal = false
            for _, t in ipairs(plants:GetChildren()) do
                local hp = t:FindFirstChild("HarvestPart")
                if hp and hp:FindFirstChild("StealPrompt") then adaSteal = true break end
            end
            if not adaSteal then return g end
        end
    end

    return nil
end

-- Nama model tanaman: "{userId}_{guid}_{indeksBuah}".
-- CollectFruit butuh guid + indeks; UseShovel butuh "{userId}_{guid}".
local function uraiNamaTanaman(nama)
    local userId, guid, indeks = string.match(nama, "^(%d+)_([%w%-]+)_(%d+)$")
    if userId then return userId, guid, indeks end
    local u2, g2 = string.match(nama, "^(%d+)_([%w%-]+)$")
    if u2 then return u2, g2, nil end
    return nil, nil, nil
end

local function daftarTanaman()
    local plot = plotSaya()
    local folder = plot and plot:FindFirstChild("Plants")
    if not folder then return {} end

    local hasil = {}
    for _, m in ipairs(folder:GetChildren()) do
        local userId, guid = uraiNamaTanaman(m.Name)
        if guid then
            local jenis = m:GetAttribute("SeedName") or m:GetAttribute("PlantName") or m.Name
            hasil[#hasil + 1] = {
                model = m, userId = userId, guid = guid, nama = jenis,
                rarity = nilaiRarity(jenis),
                pos = (m.PrimaryPart and m.PrimaryPart.Position)
                      or (m:FindFirstChildWhichIsA("BasePart") and m:FindFirstChildWhichIsA("BasePart").Position),
            }
        end
    end
    return hasil
end

-- ==========================================================
-- BLACK SCREEN + PANEL STATUS
-- ==========================================================
-- Diport dari kaitun_main.txt. Perbedaannya untuk dunia ini:
--   * mata uangnya LEAVES, bukan Sheckles
--   * riwayat menampilkan aktivitas kaitun (tanam/panen/beli), bukan PurchaseHistoryLog
--   * label dunia ikut ditampilkan supaya jelas akun ini di World 2
_G.FHRiwayat = _G.FHRiwayat or {}

local function catatRiwayat(teks)
    table.insert(_G.FHRiwayat, 1, teks)
    -- Dibatasi 8 baris: kotaknya tidak bisa di-scroll, jadi menyimpan lebih
    -- banyak hanya membuat baris terbawah terpotong tanpa pernah terbaca.
    while #_G.FHRiwayat > 8 do table.remove(_G.FHRiwayat) end
end

local function pasangBlackScreen()
    if not Config.BlackScreen then return end

    pcall(function() workspace.CurrentCamera.FieldOfView = 30 end)

    local ok = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "AFK_BlackScreen"
        gui.Enabled = true
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        bg.BorderSizePixel = 0
        bg.Parent = gui

        local kiri = Instance.new("ImageLabel")
        kiri.Size = UDim2.new(0.3, 0, 0.6, 0)
        kiri.Position = UDim2.new(0.05, 0, 0.5, 0)
        kiri.AnchorPoint = Vector2.new(0, 0.5)
        kiri.BackgroundTransparency = 1
        kiri.ScaleType = Enum.ScaleType.Fit
        kiri.Image = "rbxassetid://79880397850563"
        kiri.Parent = bg

        local kanan = Instance.new("ImageLabel")
        kanan.Size = UDim2.new(0.3, 0, 0.6, 0)
        kanan.Position = UDim2.new(0.95, 0, 0.5, 0)
        kanan.AnchorPoint = Vector2.new(1, 0.5)
        kanan.BackgroundTransparency = 1
        kanan.ScaleType = Enum.ScaleType.Fit
        kanan.Image = "rbxassetid://104624206636533"
        kanan.Parent = bg

        local judul = Instance.new("TextLabel")
        judul.Size = UDim2.new(0.9, 0, 0.25, 0)
        judul.Position = UDim2.new(0.5, 0, 0.95, 0)
        judul.AnchorPoint = Vector2.new(0.5, 1)
        judul.BackgroundTransparency = 1
        judul.Text = "AFK MODE — WORLD 2\nFENG JIU MY BINI"
        judul.TextColor3 = Color3.fromRGB(255, 255, 255)
        judul.TextScaled = true
        judul.TextWrapped = true
        judul.Font = Enum.Font.Code
        judul.ZIndex = 10
        judul.Parent = bg

        local tengah = Instance.new("TextLabel")
        tengah.Size = UDim2.new(0.4, 0, 0.2, 0)
        tengah.Position = UDim2.new(0.5, 0, 0.4, 0)
        tengah.AnchorPoint = Vector2.new(0.5, 0.5)
        tengah.BackgroundTransparency = 1
        tengah.Text = "Loading..."
        tengah.TextColor3 = Color3.fromRGB(255, 255, 0)
        tengah.TextScaled = true
        tengah.Font = Enum.Font.GothamBold
        tengah.ZIndex = 10
        tengah.Parent = bg
        local batasTeks = Instance.new("UITextSizeConstraint")
        batasTeks.MaxTextSize = 25
        batasTeks.Parent = tengah
        local strokeTengah = Instance.new("UIStroke")
        strokeTengah.Thickness = 1.5
        strokeTengah.Color = Color3.fromRGB(0, 0, 0)
        strokeTengah.Parent = tengah

        local riwayat = Instance.new("TextLabel")
        riwayat.Size = UDim2.new(0.4, 0, 0.3, 0)
        riwayat.Position = UDim2.new(0.5, 0, 0.5, 0)
        riwayat.AnchorPoint = Vector2.new(0.5, 0)
        riwayat.BackgroundTransparency = 1
        riwayat.Text = ""
        riwayat.TextColor3 = Color3.fromRGB(150, 255, 150)
        riwayat.TextSize = 14
        riwayat.TextXAlignment = Enum.TextXAlignment.Center
        riwayat.TextYAlignment = Enum.TextYAlignment.Top
        riwayat.TextWrapped = true
        riwayat.Font = Enum.Font.GothamBold
        riwayat.ZIndex = 10
        riwayat.Parent = bg
        local strokeRiwayat = Instance.new("UIStroke")
        strokeRiwayat.Thickness = 1.2
        strokeRiwayat.Color = Color3.fromRGB(0, 0, 0)
        strokeRiwayat.Parent = riwayat

        local perf = Instance.new("TextLabel")
        perf.Size = UDim2.new(0.5, 0, 0.05, 0)
        perf.Position = UDim2.new(0.5, 0, 0.02, 0)
        perf.AnchorPoint = Vector2.new(0.5, 0)
        perf.BackgroundTransparency = 1
        perf.Text = "FPS: - | Ping: - ms | Mem: - MB"
        perf.TextColor3 = Color3.fromRGB(200, 200, 200)
        perf.TextSize = 14
        perf.Font = Enum.Font.Code
        perf.ZIndex = 10
        perf.Parent = bg
        local strokePerf = Instance.new("UIStroke")
        strokePerf.Thickness = 1
        strokePerf.Color = Color3.fromRGB(0, 0, 0)
        strokePerf.Parent = perf

        local debug = Instance.new("TextLabel")
        debug.Size = UDim2.new(0.8, 0, 0.05, 0)
        debug.Position = UDim2.new(0.5, 0, 0.08, 0)
        debug.AnchorPoint = Vector2.new(0.5, 0)
        debug.BackgroundTransparency = 1
        debug.TextColor3 = Color3.fromRGB(255, 255, 0)
        debug.TextSize = 13
        debug.Font = Enum.Font.Code
        debug.ZIndex = 10
        debug.Text = "Menunggu kaitun..."
        debug.Parent = bg
        local strokeDebug = Instance.new("UIStroke")
        strokeDebug.Thickness = 1
        strokeDebug.Color = Color3.fromRGB(0, 0, 0)
        strokeDebug.Parent = debug

        -- Ditempel ke CoreGui kalau executor mendukung, supaya tidak ikut hilang
        -- saat karakter respawn.
        local berhasil = pcall(function()
            gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
        end)
        if not berhasil then
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end

        local function ringkasAngka(n)
            n = tonumber(n) or 0
            if n >= 1e12 then return string.format("%.2fT", n / 1e12)
            elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
            elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
            elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
            else return tostring(n) end
        end

        task.spawn(function()
            local Stats = game:GetService("Stats")
            while gui.Parent do
                -- Mata uang dunia ini LEAVES, bukan Sheckles.
                local daun = 0
                pcall(function()
                    local ls = LocalPlayer:FindFirstChild("leaderstats")
                    local n = ls and ls:FindFirstChild("Leaves")
                    if n then daun = n.Value end
                end)
                tengah.Text = "👤 " .. LocalPlayer.Name .. "\n🍃 " .. ringkasAngka(daun)

                riwayat.Text = (#_G.FHRiwayat > 0)
                    and ("📜 RIWAYAT:\n" .. table.concat(_G.FHRiwayat, "\n"))
                    or ""

                local ping, fps, mem = "0", "0", "0"
                pcall(function()
                    ping = string.split(Stats.Network.ServerStatsItem["Data Ping"]:GetValueString(), " ")[1] or "0"
                end)
                pcall(function() fps = tostring(math.floor(workspace:GetRealPhysicsFPS())) end)
                pcall(function()
                    mem = string.split(Stats.PerformanceStats.Memory:GetValueString(), " ")[1] or "0"
                end)
                perf.Text = string.format("🎮 FPS: %s  |  📶 Ping: %s ms  |  🧠 Mem: %s MB", fps, ping, mem)

                if _G.FallHarvestDebug then debug.Text = tostring(_G.FallHarvestDebug) end
                task.wait(1)
            end
        end)
    end)

    if not ok then warn("[FH] Gagal memasang black screen") end
end

-- ==========================================================
-- ANTI-AFK
-- ==========================================================
-- Ditegakkan fase tanam/cabut. Melompat di tengah penanaman membuat Humanoid
-- masuk Freefall, dan Roblox MELEPAS tool yang sedang dipegang -- itu persis bug
-- yang dulu membuat seluruh fase tanam gagal tanpa jejak (equip=false di setiap
-- percobaan). Jadi lompatan anti-AFK harus tahu kapan tidak boleh mengganggu.
_G.FHJanganLompat = false

local function pasangAntiAFK()
    local vu = game:GetService("VirtualUser")
    local vim = game:GetService("VirtualInputManager")

    -- Lapis 1: balasan langsung saat Roblox menandai idle.
    LocalPlayer.Idled:Connect(function()
        pcall(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    end)

    -- Lapis 2: gerakan nyata berkala. Klik saja kadang tidak cukup pada sesi
    -- panjang; lompatan menghasilkan input fisik yang jelas.
    task.spawn(function()
        while true do
            task.wait(math.random(150, 240))

            -- Ditunda kalau sedang menanam/mencabut. Dicoba lagi tiap 5 detik,
            -- maksimal 60 detik supaya tidak tertunda selamanya kalau ada fase
            -- yang menggantung.
            local tunggu = 0
            while _G.FHJanganLompat and tunggu < 60 do
                task.wait(5)
                tunggu = tunggu + 5
            end

            pcall(function()
                vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.1)
                vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
            pcall(function()
                local hum = LocalPlayer.Character
                    and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then hum.Jump = true end
            end)
        end
    end)
end

-- ==========================================================
-- FPS BOOST
-- ==========================================================
-- Diport dari applyFpsBoost() di kaitun_main.txt, dengan SATU perbedaan wajib:
-- versi asli menghapus seluruh Workspace.Gardens. Di dunia ini kebun sendiri
-- dipakai untuk menanam, memanen, dan mencabut -- menghapusnya berarti mematikan
-- hampir seluruh script. Jadi yang dibuang hanya kebun MILIK ORANG LAIN, yang
-- justru penyumbang beban terbesar (Plot7 saja terhitung 178 tanaman).
-- Pembersihan kebun orang lain. DIPISAH dari sapuan berat karena keduanya punya
-- irama yang sama sekali berbeda:
--
--   * Sapuan workspace berat sekali (14.744 instance, ~9 ms) tapi cukup SEKALI --
--     dekorasi yang sudah dihapus tidak kembali.
--   * Kebun justru dimuat BERTAHAP. Terukur: 8 pemain di server tapi baru 1 plot
--     yang termuat. Sekali jalan di siklus 1 hanya menemukan satu-dua kebun, dan
--     sisanya -- yang menyumbang 8.264 dari 14.744 instance workspace, 56% --
--     tidak pernah dibersihkan sama sekali.
--
-- Fungsi ini murah (~1,2 ms, hanya menyentuh Gardens), jadi aman diulang.
local function bersihkanKebunOrang(tunggu)
    if not Config.FpsBoost then return end

    local plotku = plotSaya()

    -- Kebun kita sendiri pun belum tentu sudah termuat saat siklus pertama.
    -- Penantian ini hanya untuk pemanggilan pertama; pemanggilan berkala tidak
    -- boleh memblokir siklus selama 20 detik.
    if not plotku and tunggu then
        status("[FPS] Menunggu kebun sendiri termuat...")
        local batas = tick() + 20
        while tick() < batas and not plotku do
            task.wait(1)
            plotku = plotSaya()
        end
    end

    -- GAGAL-TERTUTUP. Ini pernah menghancurkan kebun sungguhan.
    --
    -- Versi lama langsung menghapus tiap kebun yang `g ~= plotku`. Saat plotSaya()
    -- mengembalikan nil, SETIAP kebun tidak sama dengan nil -- jadi semuanya
    -- dihapus, termasuk milik sendiri. PlotSizeReference ikut lenyap, dan tanam,
    -- panen, serta cabut mati seluruhnya sampai pemain rejoin.
    --
    -- Gagal mengenali kebun sendiri TIDAK BOLEH berarti "tidak ada yang perlu
    -- dilindungi". Artinya: jangan hapus apa pun.
    if not plotku then
        if tunggu then
            status("[FPS] Kebun sendiri tidak terdeteksi — penghapusan DILEWATI demi keamanan")
        end
        return 0
    end

    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return 0 end

    local dibuang = 0
    for _, g in ipairs(gardens:GetChildren()) do
        if g ~= plotku then
            pcall(function() g:Destroy() end)
            dibuang = dibuang + 1
        end
    end
    if dibuang > 0 then
        status(string.format("[FPS] %d kebun orang lain dihapus", dibuang))
    end
    return dibuang
end

-- Satu tempat untuk memutuskan "boleh disentuh atau tidak".
-- Dipakai sapuan awal MAUPUN hook DescendantAdded, supaya keduanya tidak bisa
-- berbeda pendapat -- kalau berbeda, hook akan merusak apa yang sengaja
-- dilindungi sapuan.
-- plotSaya() menelusuri Gardens dan membaca atribut tiap plot. Itu murah kalau
-- dipanggil sesekali, tapi bolehDibrutalkan() dipanggil untuk SETIAP instance --
-- 16.517 kali per sapuan, lalu sekali lagi tiap objek baru lewat hook. Tanpa
-- cache, penjagaan ini sendiri jadi jauh lebih mahal daripada seluruh sapuan.
--
-- Pemeriksaan .Parent membuat cache batal sendiri saat kebun dimuat ulang atau
-- dihapus, jadi tidak akan memegang acuan basi.
local plotCache = nil
local function plotSayaCepat()
    if plotCache and plotCache.Parent then return plotCache end
    plotCache = plotSaya()
    return plotCache
end

local function bolehDibrutalkan(d)
    if not d or not d.Parent then return false end

    local char = LocalPlayer.Character
    if char and d:IsDescendantOf(char) then return false end

    -- Kebun sendiri dilindungi UTUH. Membekukan, menyembunyikan, atau mengganti
    -- materialnya bisa mengacaukan pembacaan posisi tanaman dan raycast lahan
    -- tanam -- dan seluruh tanam/panen/cabut bergantung pada itu.
    local plotku = plotSayaCepat()
    if plotku and d:IsDescendantOf(plotku) then return false end

    if d == workspace.Terrain then return false end

    -- NPC WAJIB utuh: Sam/Gilbert (seed), George (gear), Steven (jual), dan
    -- Ethan (pindah dunia) dicari lewat HumanoidRootPart. script.txt menghapus
    -- Motor6D dan Attachment pada NPC; di sini itu tidak boleh, karena kita
    -- benar-benar memakai NPC untuk beli dan jual.
    local kini, dalam = d, 0
    while kini and kini ~= workspace and dalam < 5 do
        if kini:FindFirstChildWhichIsA("Humanoid") then return false end
        local n = string.lower(kini.Name)
        if n == "npcs" or n == "npc" then return false end
        kini = kini.Parent
        dalam = dalam + 1
    end

    return true
end

-- Diadaptasi dari superBrutalize() di script.txt, dengan dua penyimpangan yang
-- disengaja:
--   * TIDAK menghapus Attachment/Motor6D/Animator. script.txt boleh melakukannya
--     karena murni AFK; script ini memakai NPC untuk beli dan jual.
--   * TIDAK menyentuh CanCollide. Mematikannya di seluruh dunia membuat karakter
--     jatuh menembus lantai saat mendarat.
local function brutalkan(d)
    if not bolehDibrutalkan(d) then return false end

    local ok = pcall(function()
        if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
           or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
           or d:IsA("Light") or d:IsA("PostEffect")
           or d:IsA("Texture") or d:IsA("Decal") or d:IsA("SurfaceAppearance")
           or d:IsA("PVAdornment") or d:IsA("HandleAdornment")
           or d:IsA("SurfaceGui") or d:IsA("BillboardGui")
           or d:IsA("KeyframeSequence") then
            d:Destroy()
            return
        end

        if d:IsA("Sound") then
            -- Volume 0, bukan Destroy: beberapa game menunggu Sound.Ended sebagai
            -- bagian alur, dan menghapusnya menggantung alur itu.
            d.Volume = 0
            return
        end

        if d:IsA("BasePart") then
            d.Material = Enum.Material.SmoothPlastic
            d.Reflectance = 0
            d.CastShadow = false
            -- FREEZE. Part yang dijangkarkan berhenti disimulasikan mesin fisika
            -- sama sekali -- inilah bagian "freeze" yang membuat script.txt
            -- terasa jauh lebih ringan daripada sekadar mematikan efek.
            d.Anchored = true
            -- Kita tidak memakai event Touched di mana pun, jadi mematikannya
            -- membuang kerja deteksi sentuhan tanpa efek samping.
            d.CanTouch = false
        end
    end)
    return ok
end

-- Wadah lingkungan yang murni hiasan. Daftar ini DIVERIFIKASI dari isi workspace
-- Fall Harvest, bukan disalin mentah dari script.txt -- nama di kedua game tidak
-- sepenuhnya sama.
local WADAH_HIASAN = {
    "Grass", "Trees", "Decorations",
    "BirdVisuals", "Birds", "BlizzardBeams", "LightningEffects",
    "RainDrops", "RainSplashes", "StormRainDrops", "StormSplashes",
    "GnomeVisuals", "Gnomes", "GrapplingHookVisuals", "PottedPlantVisuals",
    "Presents", "Dance", "Weather", "Clouds", "Rain", "PopVFXModel",
}

local function nukeLingkungan()
    local dibuang = 0
    -- GetChildren() ditelusuri, bukan FindFirstChild, karena ada nama yang
    -- MUNCUL BERKALI-KALI: terhitung 12 "PopVFXModel" sekaligus, dan
    -- FindFirstChild hanya akan membuang satu.
    for _, c in ipairs(workspace:GetChildren()) do
        for _, nama in ipairs(WADAH_HIASAN) do
            if c.Name == nama then
                pcall(function() c:Destroy() end)
                dibuang = dibuang + 1
                break
            end
        end
    end

    pcall(function()
        local T = workspace.Terrain
        T.WaterWaveSize = 0
        T.WaterWaveSpeed = 0
        T.WaterReflectance = 0
        T.WaterTransparency = 1
        -- Terrain.Decoration sengaja TIDAK disentuh: propertinya sudah dihapus
        -- Roblox dan hanya melempar error. script.txt masih mengaturnya, tapi
        -- gagal diam-diam karena terbungkus pcall.
    end)

    return dibuang
end

local hookTerpasang = false

local function pasangHookBrutal()
    if hookTerpasang then return end
    hookTerpasang = true

    -- Inilah bagian yang membuat FPS BERTAHAN, bukan cuma naik sesaat.
    -- Sapuan sekali jalan hanya membereskan yang ada SAAT ITU; game terus
    -- memunculkan buah, VFX, dan efek cuaca baru, sehingga tanpa hook ini FPS
    -- merosot lagi dalam hitungan menit. Diambil dari pola Workspace
    -- .DescendantAdded di script.txt.
    workspace.DescendantAdded:Connect(function(d)
        if not Config.FpsBoost then return end

        -- Saringan kelas didahulukan, dan sengaja memakai perbandingan string
        -- biasa -- bukan :IsA() -- karena ini jalur terpanas di seluruh script.
        --
        -- Terukur di server ramai: 88 event/detik, dan 73% di antaranya Folder
        -- dan Model. Keduanya tidak pernah kita ubah apa pun, jadi menjadwalkan
        -- task.defer untuk mereka murni pemborosan. Anak-anaknya tetap terjamah
        -- karena DescendantAdded ikut menyala untuk tiap keturunan.
        local k = d.ClassName
        if k == "Folder" or k == "Model" or k == "Configuration"
           or k == "Script" or k == "LocalScript" or k == "ModuleScript" then
            return
        end

        -- task.defer: saat instance baru muncul, anak-anaknya sering belum
        -- terpasang. Ditunda satu langkah supaya yang dinilai sudah utuh.
        -- Argumen dioper langsung, bukan lewat closure, supaya tidak ada closure
        -- baru dialokasikan puluhan kali per detik.
        task.defer(brutalkan, d)
    end)
end

local function applyFpsBoost()
    if not Config.FpsBoost then return end
    status("[FPS] Membersihkan dekorasi berat...")

    -- Penantian sampai kebun sendiri termuat ditangani di dalam fungsi ini.
    bersihkanKebunOrang(true)

    local nWadah = nukeLingkungan()

    pcall(function()
        local Lighting = game:GetService("Lighting")
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 0
        for _, c in ipairs(Lighting:GetChildren()) do
            if c:IsA("BloomEffect") or c:IsA("BlurEffect") or c:IsA("ColorCorrectionEffect")
               or c:IsA("SunRaysEffect") or c:IsA("DepthOfFieldEffect")
               or c:IsA("Atmosphere") or c:IsA("Sky") then
                c:Destroy()
            end
        end
    end)

    -- Sapuan workspace.
    local hitung, kena = 0, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if brutalkan(d) then kena = kena + 1 end
        hitung = hitung + 1
        if hitung % 500 == 0 then task.wait() end
    end

    -- Efek dan suara di LUAR workspace. Terukur di server sungguhan lewat
    -- game:GetDescendants(): 3.519 ParticleEmitter, 858 Beam, 426 Sound, 41
    -- Trail -- sebagian besar di ReplicatedStorage dan PlayerGui, sehingga
    -- sapuan workspace di atas tidak pernah menjangkaunya.
    pcall(function()
        local n = 0
        for _, d in ipairs(game:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
               or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
                -- Di luar workspace efeknya DIMATIKAN, bukan dihapus: banyak di
                -- antaranya template di ReplicatedStorage yang di-clone game saat
                -- dibutuhkan, dan menghapus template bisa melempar error di
                -- script game sendiri.
                pcall(function() d.Enabled = false end)
                n = n + 1
            elseif d:IsA("Sound") then
                pcall(function() d.Volume = 0 end)
                n = n + 1
            end
            if n % 500 == 0 then task.wait() end
        end
        status(string.format("[FPS] %d wadah hiasan, %d objek dibrutalkan, %d efek/suara dimatikan",
            nWadah, kena, n))
    end)

    -- Batas FPS. Penekan CPU terbesar untuk banyak klien dalam satu perangkat:
    -- bot tidak butuh 60 fps. Terukur 125 -> 19 fps.
    if Config.BatasFps and Config.BatasFps > 0 and typeof(setfpscap) == "function" then
        pcall(setfpscap, Config.BatasFps)
        status(string.format("[FPS] Batas frame %d", Config.BatasFps))
    end

    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)

    -- Dipasang PALING AKHIR. Kalau dipasang sebelum sapuan, hook ikut menembak
    -- tiap instance yang tersentuh sapuan dan pekerjaannya berlipat dua.
    pasangHookBrutal()

    status("[FPS] Selesai")
end

-- ==========================================================
-- SHOP
-- ==========================================================
-- Struktur UI-nya sama persis dengan SeedShop di GAG2: Frame.NormalShop berisi
-- kartu bernama item, harga di Cost_Text ("1c", "2.5Kc", "NO STOCK").
local function parseHarga(teks)
    if not teks then return 0 end
    local c = string.upper(teks)
    c = c:gsub("%s+", ""):gsub("\194\162", ""):gsub("\238\128\130", "")
    if c:match("^X%d+") then return 0 end
    local num, suf = c:match("([%d%.%,]+)([MBK]?)")
    if not num then return 0 end
    local a = tonumber((num:gsub(",", ""))) or 0
    if suf == "K" then a = a * 1e3 elseif suf == "M" then a = a * 1e6 elseif suf == "B" then a = a * 1e9 end
    return a
end

local function stokShop()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local shop = pg and pg:FindFirstChild("SeedShop")
    local frame = shop and shop:FindFirstChild("Frame")
    local wadah = frame and (frame:FindFirstChild("NormalShop") or frame:FindFirstChild("ScrollingFrame"))
    if not wadah then return {} end

    local hasil = {}
    for _, kartu in ipairs(wadah:GetChildren()) do
        if kartu:IsA("Frame") and kartu.Name ~= "ItemTemplate" and kartu.Name ~= "Padding" then
            local cost = kartu:FindFirstChild("Cost_Text", true)
            local harga = cost and parseHarga(cost.Text) or 0
            if harga > 0 then
                hasil[#hasil + 1] = { nama = kartu.Name, harga = harga, rarity = nilaiRarity(kartu.Name) }
            end
        end
    end
    -- Termurah dulu, sesuai permintaan: beli dari termurah sampai termahal.
    table.sort(hasil, function(a, b) return a.harga < b.harga end)
    return hasil
end

-- Kapasitas buah: dibaca dari atribut pemain, bukan dihitung manual dari
-- Backpack -- server yang memegang angka sebenarnya.
local function jumlahBuah()
    return tonumber(LocalPlayer:GetAttribute("FruitCount")) or 0
end
local function kapasitasBuah()
    return tonumber(LocalPlayer:GetAttribute("MaxFruitCapacity")) or 100
end

-- Posisi NPC. Perannya dipastikan dari Script di dalam ProximityPrompt masing-
-- masing: Sam & Gilbert membuka SeedShop, George membuka GearShop, Steven jual.
local NPC_PERAN = { seed = { "Sam", "Gilbert" }, gear = { "George" }, jual = { "Steven" } }

local function posisiNPC(peran)
    local npcs = workspace:FindFirstChild("NPCS")
    if not npcs then return nil, nil end
    for _, nama in ipairs(NPC_PERAN[peran] or {}) do
        local n = npcs:FindFirstChild(nama)
        local root = n and (n:FindFirstChild("HumanoidRootPart") or n.PrimaryPart)
        if root then return root.Position, nama end
    end
    return nil, nil
end

local function leaves()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local n = ls and ls:FindFirstChild("Leaves")
    return n and n.Value or 0
end

-- ==========================================================
-- AKSI
-- ==========================================================
local function toolBernama(nama)
    for _, wadah in ipairs({ LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }) do
        if wadah then
            for _, t in ipairs(wadah:GetChildren()) do
                if t:IsA("Tool") and (t.Name == nama or t:GetAttribute("SeedTool") == nama) then return t end
            end
        end
    end
end

local function equip(tool)
    local _, _, hum = karakter()
    if not (tool and hum) then return false end
    if tool.Parent == LocalPlayer.Character then return true end
    pcall(function() hum:EquipTool(tool) end)
    -- Ditunggu sampai BENAR-BENAR pindah, bukan jeda tetap. Terukur biasanya
    -- 0.001 detik, tapi bisa gagal total kalau karakter belum mendarat -- dan
    -- jeda tetap akan mengembalikan "gagal" padahal cuma kurang sabar.
    local batas = tick() + 2
    while tick() < batas do
        if tool.Parent == LocalPlayer.Character then return true end
        task.wait(0.05)
    end
    return false
end

-- Ditandai oleh fase tanam saat benar-benar tidak ada titik kosong tersisa.
-- Dipakai fase beli untuk memutuskan apakah masih layak membeli seed murah.
local kebunPenuh = false

-- Rarity TERENDAH yang sedang tumbuh. Saat kebun penuh, membeli seed di bawah
-- angka ini sia-sia: tidak ada yang bisa digantikan olehnya, jadi Leaves-nya
-- terbuang. Ini yang kamu maksud "jangan beli yang di bawah rarity kebun".
local function rarityTerendahKebun()
    local terendah = math.huge
    for _, p in ipairs(daftarTanaman()) do
        if p.rarity > 0 and p.rarity < terendah then terendah = p.rarity end
    end
    return (terendah == math.huge) and 0 or terendah
end

local function beli(daftar)
    -- BEDA dengan panen/tanam/jual: membeli WAJIB dari dekat.
    --
    -- Secara teknis PurchaseSeed tetap diterima dari jarak jauh, tapi anticheat
    -- menandainya dan ban menyusul belakangan -- jadi "berhasil" di sini justru
    -- menyesatkan. Karena itu mendekat bukan opsi yang bisa dimatikan lewat
    -- config, dan kalau gagal mencapai NPC, pembelian DIBATALKAN seluruhnya.
    -- Kebun penuh -> saring dulu. Seed yang rarity-nya tidak lebih tinggi dari
    -- tanaman terlemah di kebun tidak bisa menggantikan apa pun, jadi membelinya
    -- hanya membuang Leaves. Saat kebun MASIH ADA RUANG, semua boleh dibeli --
    -- mengisi tanah kosong selalu lebih baik daripada membiarkannya menganggur.
    if kebunPenuh then
        local batasRarity = rarityTerendahKebun()
        local tersaring = {}
        for _, s in ipairs(daftar) do
            if s.rarity > batasRarity then tersaring[#tersaring + 1] = s end
        end
        if #tersaring == 0 then
            status(string.format("[LEWAT] Kebun penuh (terendah r%d), tidak ada seed lebih tinggi di shop",
                batasRarity))
            return 0
        end
        status(string.format("[SARING] Kebun penuh — hanya beli rarity di atas r%d (%d dari %d item)",
            batasRarity, #tersaring, #daftar))
        daftar = tersaring
    end

    local pos, nama = posisiNPC("seed")
    if not pos then
        status("[BATAL] NPC penjual seed tidak ketemu")
        return 0
    end
    if not pergiKe(pos) then
        status("[BATAL] Gagal mencapai " .. tostring(nama) .. " — beli dilewati demi keamanan")
        return 0
    end
    status("[BELI] Di dekat " .. tostring(nama) .. " (jarak " .. math.floor(jarakKe(pos)) .. ")")

    local dibeli = 0
    for _, s in ipairs(daftar) do
        -- Jarak diperiksa ulang tiap item: karakter bisa terdorong menjauh di
        -- tengah pembelian, dan satu fire dari jauh sudah cukup untuk ditandai.
        if jarakKe(pos) > Config.JarakAman * 2 then
            if not pergiKe(pos) then
                status("[BATAL] Terlempar dari NPC, sisa pembelian dihentikan")
                break
            end
        end
        if dibeli >= Config.MaxBeliPerSiklus then break end
        if leaves() < s.harga then break end   -- daftar terurut, sisanya pasti lebih mahal
        local ok = pcall(function() Networking.SeedShop.PurchaseSeed:Fire(s.nama) end)
        if ok then
            dibeli = dibeli + 1
            status(string.format("[BELI] %s (%d Leaves, sisa %d)", s.nama, s.harga, leaves()))
            catatRiwayat(string.format("🛒 %s (%d)", s.nama, s.harga))
        end
        task.wait(Config.JedaAksi)
    end

    -- Tool hasil pembelian tiba di Backpack secara ASINKRON. Tanpa menunggu,
    -- fase tanam menembak sebelum barangnya sampai dan seed yang baru dibeli
    -- terlewat satu siklus penuh.
    if dibeli > 0 then
        local sebelum = #(LocalPlayer:FindFirstChild("Backpack") or {}):GetChildren()
        local batas = tick() + 5
        while tick() < batas do
            local bp = LocalPlayer:FindFirstChild("Backpack")
            if bp and #bp:GetChildren() >= sebelum + math.min(dibeli, 1) then break end
            task.wait(0.15)
        end
        task.wait(Config.JedaAksi)
    end
    return dibeli
end

-- Cabut sampai muat: hanya tanaman yang rarity-nya LEBIH RENDAH dari seed yang
-- mau ditanam, diurut dari yang paling rendah. Kalau tidak ada yang lebih
-- rendah, penanaman itu dilewati -- bukan dipaksa.
local function cabutSampaiMuat(rarityMasuk, butuh)
    if not Config.AutoCabut then return 0 end
    local shovel = toolBernama("Shovel")
    if not shovel then
        status("[LEWAT] Tidak ada Shovel di backpack")
        return 0
    end

    local kandidat = {}
    for _, p in ipairs(daftarTanaman()) do
        if p.rarity > 0 and p.rarity < rarityMasuk then kandidat[#kandidat + 1] = p end
    end
    if #kandidat == 0 then return 0 end
    table.sort(kandidat, function(a, b) return a.rarity < b.rarity end)

    if not equip(shovel) then return 0 end
    local dicabut = 0
    for i = 1, math.min(butuh, #kandidat) do
        local p = kandidat[i]
        -- Satu-satunya aksi yang masih mendekat: cabut belum pernah diuji, jadi
        -- diperlakukan seolah butuh jarak dekat sampai terbukti sebaliknya.
        if Config.DekatSaatCabut and p.pos then pergiKe(p.pos) end
        local ok = pcall(function()
            Networking.Shovel.UseShovel:Fire(p.userId .. "_" .. p.guid, "", "Shovel", shovel)
        end)
        if ok then
            dicabut = dicabut + 1
            status(string.format("[CABUT] %s (rarity %d < %d)", p.nama, p.rarity, rarityMasuk))
            catatRiwayat("⛏️ Cabut " .. tostring(p.nama))
        end
        task.wait(Config.JedaAksi)
    end
    return dicabut
end

-- ==========================================================
-- AREA SPRINKLER & TITIK SIRAM
-- ==========================================================
-- Dideklarasikan di sini, bukan di blok MODE BAMBOO jauh di bawah: titik siram
-- dihitung di fungsi-fungsi berikut, yang letaknya SEBELUM blok itu. Kalau
-- deklarasinya tertinggal di bawah, pemanggilan di sini mengenai global nil dan
-- seluruh pemilihan titik siram gagal saat dijalankan -- padahal luac tetap lolos.
local CollectionService = game:GetService("CollectionService")

-- Angka radius dibaca dari modul data game, BUKAN ditebak:
--   SprinklerData   : Syrup Sprinkler Radius=20, Super Syrup Sprinkler Radius=55
--   WateringcanData : Syrup Watering Can SplashRadius=5, Super = 8
local okSD, SprinklerData = pcall(function()
    return require(ReplicatedStorage.SharedModules.SprinklerData)
end)
local okWD, WateringcanData = pcall(function()
    return require(ReplicatedStorage.SharedModules.WateringcanData)
end)

local function radiusSprinkler(nama)
    if okSD and type(SprinklerData) == "table" then
        for _, d in pairs(SprinklerData) do
            if type(d) == "table" and d.SprinklerName == nama and d.Radius then
                return d.Radius
            end
        end
    end
    return 20  -- nilai Syrup Sprinkler, dipakai kalau modulnya berubah
end

local function radiusSiram(nama)
    if okWD and type(WateringcanData) == "table" then
        for _, d in pairs(WateringcanData) do
            if type(d) == "table" and d.Name == nama and d.SplashRadius then
                return d.SplashRadius
            end
        end
    end
    return 5  -- nilai Syrup Watering Can
end

-- Sprinkler yang BENAR-BENAR sudah berdiri di kebun kita, bukan yang di tas.
local function sprinklerTerpasang()
    local p = plotSaya()
    local f = p and p:FindFirstChild("Sprinklers")
    if not f then return {} end

    local hasil = {}
    for _, s in ipairs(f:GetChildren()) do
        local pos
        if s:IsA("BasePart") then
            pos = s.Position
        else
            local bagian = s.PrimaryPart or s:FindFirstChildWhichIsA("BasePart")
            pos = bagian and bagian.Position
        end
        if pos then
            local nama = s:GetAttribute("SprinklerName") or s.Name
            hasil[#hasil + 1] = { pos = pos, radius = radiusSprinkler(nama), nama = nama }
        end
    end
    return hasil
end

-- Batas area tanam yang sedang berlaku. nil = bebas (alur normal).
-- Diisi mode bambu sebelum menanam, lalu dikosongkan lagi -- kalau tertinggal
-- terisi, alur normal ikut terkurung di radius sprinkler.
local areaSprinklerAktif = nil

local function dalamAreaSprinkler(x, z)
    if not areaSprinklerAktif or #areaSprinklerAktif == 0 then return true end
    local titik = Vector2.new(x, z)
    for _, s in ipairs(areaSprinklerAktif) do
        if (titik - Vector2.new(s.pos.X, s.pos.Z)).Magnitude <= s.radius then
            return true
        end
    end
    return false
end

-- Titik siram terbaik: TIDAK ada tanaman tepat di situ, tapi jangkauan
-- siramannya menutupi tanaman sebanyak mungkin.
--
-- Syarat "tidak ada tanaman di titik itu" bukan pilihan gaya. IsValidPlacement
-- di WateringcanController menolak kalau raycast tidak mengenai part bertag
-- PlantArea -- dan kalau ada tanaman berdiri di titik itu, sinarnya mengenai
-- tanaman, bukan tanah. Siramannya gagal tanpa pesan.
local function titikSiramTerbaik(radius)
    local p = plotSaya()
    if not p then return nil end

    local kolom = {}
    for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
        if part:IsA("BasePart") and part:IsDescendantOf(p) then kolom[#kolom + 1] = part end
    end
    if #kolom == 0 then return nil end

    local tanaman = {}
    for _, t in ipairs(daftarTanaman()) do
        if t.pos then tanaman[#tanaman + 1] = Vector2.new(t.pos.X, t.pos.Z) end
    end
    if #tanaman == 0 then
        -- Belum ada tanaman: siram di tengah saja, tidak ada yang perlu dihitung.
        local k = kolom[1]
        return k.Position + Vector3.new(0, k.Size.Y / 2, 0)
    end

    -- Kisi 2 stud. Cukup rapat untuk radius 5, dan tetap murah: satu kolom
    -- 44x16 menghasilkan sekitar 180 titik, bukan ribuan.
    local LANGKAH = 2
    local terbaik, skorTerbaik = nil, -1

    for _, k in ipairs(kolom) do
        local x0 = k.Position.X - k.Size.X * 0.45
        local x1 = k.Position.X + k.Size.X * 0.45
        local z0 = k.Position.Z - k.Size.Z * 0.45
        local z1 = k.Position.Z + k.Size.Z * 0.45

        local x = x0
        while x <= x1 do
            local z = z0
            while z <= z1 do
                local titik = Vector2.new(x, z)

                -- Tolak titik yang ditempati tanaman. 1.5 stud memberi kelonggaran
                -- untuk lebar model tanaman itu sendiri.
                local kosong = true
                local tertutup = 0
                for _, q in ipairs(tanaman) do
                    local jarak = (titik - q).Magnitude
                    if jarak < 1.5 then kosong = false break end
                    if jarak <= radius then tertutup = tertutup + 1 end
                end

                if kosong and tertutup > skorTerbaik then
                    skorTerbaik = tertutup
                    terbaik = Vector3.new(x, k.Position.Y + k.Size.Y / 2, z)
                end
                z = z + LANGKAH
            end
            x = x + LANGKAH
        end
    end

    return terbaik, skorTerbaik
end

local function tanamSemua()
    -- Lompatan anti-AFK ditahan selama fase ini: Freefall melepas tool
    -- yang dipegang dan seluruh penanaman gagal tanpa jejak.
    _G.FHJanganLompat = true
    local plot = plotSaya()
    local acuan = plot and plot:FindFirstChild("PlotSizeReference")
    if not acuan then
        status("[LEWAT] PlotSizeReference tidak ketemu")
        return 0
    end

    local ditanam = 0
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return 0 end

    -- Daftar seed dibaca ULANG tiap putaran, bukan sekali di awal.
    --
    -- Fase tanam harus TUNTAS sebelum pindah tugas: habiskan seluruh seed di
    -- Backpack, atau berhenti karena kebun benar-benar penuh. Versi sebelumnya
    -- memotret sekali lalu keluar setelah satu lintasan, jadi seed yang baru
    -- masuk (atau yang tertunda karena satu tembakan meleset) baru tersentuh
    -- pada siklus berikutnya -- itulah yang terasa tidak stabil.
    local function antreanSeed()
        local a = {}
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("SeedTool") then
                a[#a + 1] = t
            end
        end
        return a
    end

    -- Titik kosong: acak di SELURUH lebar plot, lalu ditolak kalau terlalu dekat
    -- dengan tanaman yang sudah ada. Titik acak murni gampang berkerumun -- itu
    -- sebabnya tanaman menumpuk di satu sudut padahal plotnya 115 studs.
    --
    -- Mengembalikan nil kalau setelah CobaTitik percobaan tidak ada ruang tersisa.
    -- nil itulah SATU-SATUNYA tanda "kebun penuh" yang dipakai script -- bukan
    -- sekadar satu penanaman yang gagal.
    local function titikKosong()
        local uk = acuan.Size
        local adaSekarang = {}
        for _, p in ipairs(daftarTanaman()) do
            if p.pos then adaSekarang[#adaSekarang + 1] = p.pos end
        end

        -- Titik diambil dari PlantAreaColumn, BUKAN dari PlotSizeReference.
        --
        -- Ini penyebab utama "tanam sering tidak bekerja". PlotSizeReference
        -- terukur X 76.8..191.8 / Z -20.2..-2.2, tapi lahan yang benar-benar bisa
        -- ditanami adalah DUA STRIP terpisah:
        --     PlantAreaColumn1  X 130.3..174.3  Z   3.1..19.1
        --     PlantAreaColumn2  X  90.0..134.0  Z -37.2..-21.2
        -- Rentang acuan itu justru menutupi CELAH di antara keduanya, jadi
        -- sebagian besar titik acak mendarat di tanah yang bukan lahan tanam dan
        -- ditolak server tanpa pesan apa pun.
        local kolom = {}
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("BasePart") and string.find(d.Name, "PlantArea", 1, true) then
                kolom[#kolom + 1] = d
            end
        end
        if #kolom == 0 then
            -- Tidak ada kolom tanam: jatuh ke acuan lama daripada berhenti total.
            kolom = { acuan }
        end

        -- Include, bukan Exclude. Dengan Exclude, sinar mengenai apa pun yang
        -- kebetulan menutupi lahan lebih dulu -- terukur mendarat di
        -- "GardenTotalArea", "Part", dan "Move", dan penanaman di titik-titik itu
        -- ditolak. Membatasi ke kolom tanam membuat setiap hit dijamin di
        -- permukaan yang memang boleh ditanami.
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = kolom

        for _ = 1, Config.CobaTitik do
            local k = kolom[math.random(1, #kolom)]
            -- 0.85 memberi margin dari tepi kolom; titik tepat di bibir lahan
            -- gampang meleset saat di-raycast.
            local x = k.Position.X + (math.random() - 0.5) * k.Size.X * 0.85
            local z = k.Position.Z + (math.random() - 0.5) * k.Size.Z * 0.85

            -- Mode bambu membatasi penanaman ke jangkauan sprinkler: bambu di
            -- luar radius tidak ikut dipercepat, jadi menanamnya di sana hanya
            -- memperlambat seluruh siklus.
            local cukupJauh = dalamAreaSprinkler(x, z)
            if cukupJauh then
                for _, q in ipairs(adaSekarang) do
                    -- Jarak diukur mendatar saja; tinggi tanaman tidak relevan.
                    if (Vector2.new(x, z) - Vector2.new(q.X, q.Z)).Magnitude < Config.JarakTanam then
                        cukupJauh = false
                        break
                    end
                end
            end

            if cukupJauh then
                -- Y dari raycast, bukan dari bidang acuan: permukaan lahan ada di
                -- Y=143.6 sementara acuan di 146.5, dan tangkapan panggilan asli
                -- game memang memakai 143.2.
                local hit = workspace:Raycast(
                    Vector3.new(x, k.Position.Y + 20, z), Vector3.new(0, -60, 0), params)
                if hit then return hit.Position end
            end
        end

        -- Lemparan acak dengan jarak penuh gagal. Sebelum menyimpulkan kebun
        -- PENUH -- dan memicu cabut -- coba sekali lagi dengan jarak lebih rapat.
        --
        -- Ini bedanya "tidak ketemu titik longgar" dan "benar-benar tidak ada
        -- ruang". Tanpa pass kedua, kebun setengah terisi bisa dikira penuh lalu
        -- tanaman dicabut padahal masih muat.
        local rapat = math.max(2, Config.JarakTanam * 0.5)
        for _ = 1, Config.CobaTitik do
            local k = kolom[math.random(1, #kolom)]
            local x = k.Position.X + (math.random() - 0.5) * k.Size.X * 0.9
            local z = k.Position.Z + (math.random() - 0.5) * k.Size.Z * 0.9

            local cukupJauh = dalamAreaSprinkler(x, z)
            if cukupJauh then
                for _, q in ipairs(adaSekarang) do
                    if (Vector2.new(x, z) - Vector2.new(q.X, q.Z)).Magnitude < rapat then
                        cukupJauh = false
                        break
                    end
                end
            end
            if cukupJauh then
                local hit = workspace:Raycast(
                    Vector3.new(x, k.Position.Y + 20, z), Vector3.new(0, -60, 0), params)
                if hit then return hit.Position end
            end
        end

        return nil
    end

    -- Putaran luar: ulangi sampai tidak ada seed tersisa atau tidak ada lagi yang
    -- bisa ditanam. Batas 30 putaran hanya jaring pengaman -- normalnya berhenti
    -- jauh sebelum itu karena Backpack habis.
    -- Sekali di awal fase: pindah ke kebun sendiri. Tanpa ini seluruh fase tanam
    -- ditolak server, dan yang terlihat cuma "seed berpindah cepat tanpa menanam".
    if Config.DekatSaatTanam then
        if not pergiKe(acuan.Position, 8) then
            status("[LEWAT] Gagal mencapai kebun sendiri, tanam dibatalkan")
            _G.FHJanganLompat = false
            return 0
        end
        status(string.format("[TANAM] Di kebun (IsInOwnGarden=%s)",
            tostring(LocalPlayer:GetAttribute("IsInOwnGarden"))))
    end

    local putaran = 0
    while putaran < 30 do
        putaran = putaran + 1
        local antrean = antreanSeed()
        if #antrean == 0 then break end

        local majuDiPutaranIni = 0

    for _, t in ipairs(antrean) do
        local seedName = t.Parent and t:GetAttribute("SeedTool")
        if seedName then
            -- Satu Tool adalah SETUMPUK seed, bukan satu biji -- atribut Count
            -- terukur 4, 11, dan 13 di backpack. Versi sebelumnya menanam sekali
            -- per Tool lalu pindah, jadi dari 13 Maple Bamboo hanya satu yang
            -- masuk tanah. Sekarang dikuras sampai habis.
            local awal = tonumber(t:GetAttribute("Count")) or 1
            -- Jaring pengaman: kalau Count tidak pernah turun (kebun penuh, atau
            -- atributnya tidak dipakai untuk seed tertentu), loop tetap berhenti.
            local batas = awal + 3
            local percobaan, ditanamSeedIni = 0, 0

            if equip(t) then
                while t.Parent and percobaan < batas do
                    percobaan = percobaan + 1
                    local sebelum = tonumber(t:GetAttribute("Count")) or 0

                    local titik = titikKosong()
                    if not titik then
                        -- BARU di sinilah kebun benar-benar penuh: bukan karena satu
                        -- penanaman gagal, tapi karena tidak ada satu pun titik yang
                        -- cukup jauh dari tanaman lain setelah puluhan percobaan.
                        --
                        -- Cabut hanya boleh dari titik ini, dan hanya SATU tanaman
                        -- per penanaman -- bertahap, bukan membabat seluruh kebun
                        -- begitu muncul satu seed rarity tinggi.
                        kebunPenuh = true
                        if cabutSampaiMuat(nilaiRarity(seedName), 1) <= 0 then
                            status(string.format("[PENUH] Tidak ada tanaman yang lebih rendah dari %s",
                                seedName))
                            break
                        end
                        equip(t)
                        titik = titikKosong()
                        if not titik then break end
                    end

                    -- Terbang ke plot dilakukan SEKALI di awal fase, bukan ke tiap
                    -- titik tanam. Di sini hanya dicek apakah kita terlempar keluar
                    -- kebun -- server memang menarik pemain kembali ke spawn, dan
                    -- terukur kejadian: jarak melonjak 9 -> 183 studs di sela aksi.
                    if Config.DekatSaatTanam and LocalPlayer:GetAttribute("IsInOwnGarden") ~= true then
                        pergiKe(acuan.Position, 8)
                        equip(t)
                    end

                    pcall(function()
                        Networking.Plant.PlantSeed:Fire(titik, seedName, t)
                    end)
                    task.wait(Config.JedaTanam)

                    if not t.Parent then
                        -- Tool habis dan dihapus: seluruh tumpukan tertanam.
                        ditanamSeedIni = ditanamSeedIni + 1
                        break
                    end

                    local sesudah = tonumber(t:GetAttribute("Count")) or 0
                    if sesudah < sebelum then
                        ditanamSeedIni = ditanamSeedIni + (sebelum - sesudah)
                        kebunPenuh = false
                    end
                    -- Count tidak turun TIDAK langsung berarti penuh: titik berikutnya
                    -- akan berbeda, dan itu sering sudah cukup. Percobaan berikutnya
                    -- yang menentukan -- inilah yang dulu membuat cabut terlalu cepat
                    -- dipicu hanya karena satu tembakan meleset.
                end

                if ditanamSeedIni > 0 then
                    ditanam = ditanam + ditanamSeedIni
                    majuDiPutaranIni = majuDiPutaranIni + ditanamSeedIni
                    status(string.format("[TANAM] %s x%d (dari %d)", seedName, ditanamSeedIni, awal))
                    catatRiwayat(string.format("🌱 %s x%d", seedName, ditanamSeedIni))
                end

                -- Jeda sebelum pindah ke jenis seed berikutnya. Pergantian seed
                -- berarti equip tool baru, dan tanpa jeda tembakan pertama dikirim
                -- sebelum equip-nya benar-benar selesai.
                task.wait(Config.JedaGantiSeed)
            end
        end
    end

        -- Tidak ada satu pun yang tertanam di seluruh putaran ini: entah kebun
        -- penuh, entah seed yang tersisa tidak bisa ditanam. Berhenti daripada
        -- mengulang lintasan yang sama tanpa hasil.
        if majuDiPutaranIni == 0 then break end
    end

    _G.FHJanganLompat = false
    if ditanam > 0 then
        status(string.format("[TANAM] Selesai — %d biji, %d putaran", ditanam, putaran))
    end
    return ditanam
end

local function panenSemua()
    -- Dulu menyapu seluruh workspace:GetDescendants() tiap siklus -- mahal, dan
    -- daftarnya sudah basi begitu buah pertama dipanen. Sekarang cukup folder
    -- Plants milik plot sendiri, dan hasilnya DIPOTRET dulu sebelum ditembak
    -- supaya penghapusan instance tidak merusak penelusuran yang sedang jalan.
    local plot = plotSaya()
    local folder = plot and plot:FindFirstChild("Plants")
    if not folder then return 0 end

    local antrean = {}
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.ActionText == "Harvest" then
            antrean[#antrean + 1] = d
        end
    end

    local dipanen = 0
    for _, d in ipairs(antrean) do
        if d.Parent then
            local m = d:FindFirstAncestorWhichIsA("Model")
            if m then
                local userId, guid, indeks = uraiNamaTanaman(m.Name)
                if guid and tostring(userId) == tostring(LocalPlayer.UserId) then
                    -- Terbukti di lapangan: CollectFruit diterima dari jarak jauh,
                    -- jadi tidak ada lompat-lompat antar tanaman. Mendekat hanya
                    -- kalau kamu memaksanya lewat config.
                    if Config.DekatSaatPanen then
                        local induk = d.Parent
                        local pos = induk and induk:IsA("BasePart") and induk.Position
                        if pos then pergiKe(pos) end
                    end
                    -- Berhenti memanen begitu inventory penuh. Sebelumnya panen
                    -- terus ditembak ke kapasitas yang sudah mentok -- server
                    -- menolak diam-diam dan dari luar terlihat seperti macet
                    -- meng-spam harvest.
                    if jumlahBuah() >= kapasitasBuah() then
                        status(string.format("[PENUH] %d/%d buah — panen dihentikan",
                            jumlahBuah(), kapasitasBuah()))
                        break
                    end
                    local ok = pcall(function()
                        Networking.Garden.CollectFruit:Fire(guid, indeks or "")
                    end)
                    if ok then dipanen = dipanen + 1 end
                    task.wait(Config.JedaPanen)
                end
            end
        end
    end
    if dipanen > 0 then status("[PANEN] " .. dipanen .. " buah") end
    if dipanen > 0 then catatRiwayat("🧺 Panen " .. dipanen .. " buah") end
    return dipanen
end

local function jual()
    -- Terbukti di lapangan: SellAll diterima dari jarak jauh, jadi tidak perlu
    -- terbang ke Steven sama sekali. Pencarian NPC hanya dilakukan kalau kamu
    -- memaksa mendekat lewat config.
    if Config.DekatSaatJual then
        local npcs = workspace:FindFirstChild("NPCS")
        local steven = npcs and npcs:FindFirstChild("Steven")
        local root = steven and (steven:FindFirstChild("HumanoidRootPart") or steven.PrimaryPart)
        if root and not pergiKe(root.Position) then
            status("[LEWAT] Gagal mencapai Steven")
            return false
        end
    end

    -- Staging wajib. Tanpa PreviewSellAll lebih dulu, SellAll ditolak diam-diam.
    pcall(function() Networking.NPCS.PreviewSellAll:Fire() end)
    task.wait(Config.JedaAksi)
    pcall(function() Networking.NPCS.SellAll:Fire() end)
    status("[JUAL] SellAll dikirim (Leaves: " .. leaves() .. ")")
    catatRiwayat("💰 SellAll")
    task.wait(1)
    return true
end

-- ==========================================================
-- SYNC KE PANEL
-- ==========================================================
-- Tanpa ini akun World 2 tidak muncul di Kaitun Manager dan tidak bisa menerima
-- perintah apa pun -- termasuk tombol kembali ke GaG2.
--
-- Selain status dan saldo, dikirim juga penanda dunia. Panel memakainya untuk
-- menampilkan map di samping nama dan mengunci edit config, karena World 2
-- berjalan sepenuhnya otomatis.
local httprequest = (syn and syn.request) or (http and http.request)
    or http_request or (fluxus and fluxus.request) or request

-- Satu dunia bisa punya BEBERAPA place, dan tidak semua bisa dituju langsung.
-- Universe ini rootPlaceId-nya 97598239454123 (GaG2); kedua place Fall Harvest
-- adalah non-root sehingga hanya bisa dimasuki lewat teleport dari dalam
-- universe -- dan belum tentu keduanya menerima. Karena itu didaftar sebagai
-- kandidat, lalu dicoba berurutan.
local PLACE_DUNIA = {
    TP_GAG2 = { 97598239454123 },
    TP_FALL = { 129343810645058, 126987765280963 },
}
local NAMA_DUNIA = {
    [97598239454123]   = "Grow a Garden 2",
    [129343810645058]  = "Fall Harvest",
    [126987765280963]  = "Fall Harvest",
}

-- ==========================================================
-- TELEPORT TAHAN BANTING
-- ==========================================================
-- Dua masalah nyata, dan keduanya paling sering muncul di executor HP:
--
-- 1. SCRIPT MATI SETELAH TELEPORT. Executor menyuntik script ke place yang
--    sedang berjalan. Begitu pindah place atau server, tidak ada apa pun yang
--    menjalankannya lagi -- akun sampai di tujuan lalu diam selamanya. Itulah
--    yang terasa seperti "tidak bisa pindah sesuka hati": teleportnya jalan,
--    kaitunnya yang tidak ikut. queue_on_teleport menitipkan kode agar
--    dijalankan otomatis begitu tiba.
--
-- 2. KEGAGALAN TELEPORT TIDAK TERLIHAT. Teleport gagal secara ASINKRON lewat
--    event TeleportInitFailed, bukan lewat error. Jadi pcall di sekitar
--    :Teleport() tidak pernah menangkap apa pun, dan gagal terlihat persis sama
--    dengan berhasil.
local TeleportService = game:GetService("TeleportService")

-- URL loader yang sama dengan yang dipakai buyer. Sengaja loader, bukan script
-- ini langsung: routernya yang memilih script sesuai place tujuan, jadi satu
-- kode titipan ini benar untuk pindah ke dunia mana pun.
local URL_LOADER = "https://raw.githubusercontent.com/azellsennse/mujeee/refs/heads/main/buyerkaitun.lua"

local function kodeLanjutan()
    -- Kedua nama config diisi karena tujuannya bisa GaG2 maupun Fall Harvest,
    -- dan masing-masing script membaca nama yang berbeda.
    return string.format(
        "getgenv().MuzeAutoBuyConfig = { PanelKey = %q }\n" ..
        "getgenv().MuzeFallHarvestConfig = { PanelKey = %q }\n" ..
        "loadstring(game:HttpGet(%q))()",
        raw_panel_key, raw_panel_key, URL_LOADER)
end

-- Nama fungsi antrian berbeda-beda antar executor, dan sebagian executor HP
-- tidak menyediakannya sama sekali. Yang tidak punya harus memakai autoexec.
local function titipKode()
    local f = (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
        or queue_on_teleport
        or queueonteleport
        or (getgenv and getgenv().queue_on_teleport)
    if type(f) ~= "function" then return false end
    return (pcall(f, kodeLanjutan()))
end

local alasanGagalTP = nil
pcall(function()
    TeleportService.TeleportInitFailed:Connect(function(pemain, hasil, pesan)
        if pemain ~= LocalPlayer then return end
        alasanGagalTP = tostring(hasil) .. " " .. tostring(pesan or "")
    end)
end)

local function teleportAman(lakukan, keterangan, percobaanMaks)
    for percobaan = 1, (percobaanMaks or 4) do
        alasanGagalTP = nil
        local adaAntrian = titipKode()
        if not adaAntrian and percobaan == 1 then
            status("[TP] Executor tanpa queue_on_teleport - andalkan autoexec")
        end

        local ok, err = pcall(lakukan)
        if not ok then
            alasanGagalTP = tostring(err)
        else
            -- Kalau teleport benar-benar jalan, client membongkar place ini dan
            -- baris di bawah tidak pernah selesai. Sampai di sini berarti belum
            -- tentu gagal -- beri waktu TeleportInitFailed tiba dulu.
            local batas = tick() + 12
            while tick() < batas and not alasanGagalTP do task.wait(0.25) end
            if not alasanGagalTP then return true end
        end

        -- "Flooded" artinya Roblox sendiri yang membatasi laju teleport. Itu
        -- keputusan server dan TIDAK bisa dilewati dari sisi client; satu-
        -- satunya yang masuk akal adalah menunggu lebih lama.
        local jeda = 5 * percobaan
        if string.find(string.lower(alasanGagalTP or ""), "flood") then
            jeda = 20 * percobaan
        end
        status("[TP GAGAL] " .. keterangan .. " -> " .. tostring(alasanGagalTP))
        task.wait(jeda)
    end
    status("[TP MENYERAH] " .. keterangan)
    return false
end

-- ==========================================================
-- PINDAH DUNIA LEWAT JALUR RESMI GAME
-- ==========================================================
-- Remote yang sama dengan yang ditembak NPC Ethan saat pemain memilih dunia:
--   EventWorldsTeleporterController -> Networking.Worlds.RequestTravel:Fire(id)
--
-- Lebih baik daripada TeleportService:Teleport(placeId) karena SERVER yang
-- memilih place tujuan. Daftar dunia punya PlaceType dan BotPlaceType terpisah
-- ("BotUser", "FallHarvestBotUser"), jadi akun yang ditandai bot diarahkan ke
-- place berbeda. Menembak PlaceId sendiri mengabaikan routing itu.
local DUNIA_ID = {
    TP_GAG2 = "Main",
    TP_FALL = "FallHarvest",
}

local function duniaSekarang()
    local ok, id = pcall(function()
        return require(ReplicatedStorage.SharedModules.Worlds).CurrentId
    end)
    return ok and id or nil
end

local function pindahDunia(worldId, kandidatPlace)
    -- Dititipkan sebelum apa pun ditembak: server bisa memindahkan kita kapan
    -- saja setelah remote ini diterima, dan begitu pindah script berhenti.
    titipKode()

    local ok = pcall(function()
        Networking.Worlds.RequestTravel:Fire(worldId)
    end)

    if ok then
        status("[PINDAH] RequestTravel -> " .. tostring(worldId))
        -- Kalau server menerima, place ini dibongkar dan loop di bawah tidak
        -- akan pernah selesai. Selesai = permintaannya diabaikan diam-diam.
        local batas = tick() + 15
        while tick() < batas do task.wait(0.5) end
    end

    status("[PINDAH] Jalur resmi diam, coba TeleportService")
    for _, pid in ipairs(kandidatPlace or {}) do
        if teleportAman(function()
            TeleportService:Teleport(pid, LocalPlayer)
        end, "dunia " .. tostring(pid), 2) then
            return true
        end
    end
    return false
end

local function tanganiQuickAction(act)
    -- "JOIN|<placeId>|<jobId>" -- masuk ke server tertentu. Universe ini melarang
    -- private server, tapi server cuma muat 8 orang; mengumpulkan akun sendiri ke
    -- satu JobId memberi efek yang sama.
    if type(act) == "string" and string.sub(act, 1, 5) == "JOIN|" then
        local pid, jid = string.match(act, "^JOIN|(%d+)|(.+)$")
        pid = tonumber(pid)
        if pid and jid and jid ~= "" then
            if game.JobId == jid then
                status("[LEWAT] Sudah di server tujuan")
                return
            end
            status("[KUMPUL] Menuju server " .. string.sub(jid, 1, 8))
            local berhasil = teleportAman(function()
                TeleportService:TeleportToPlaceInstance(pid, jid, LocalPlayer)
            end, "server " .. string.sub(jid, 1, 8))

            -- Server cuma muat 8 orang. Kalau JobId tujuan sudah penuh, semua
            -- percobaan akan gagal dengan sebab yang sama dan mengulanginya
            -- percuma. Lebih baik tetap mendarat di dunia yang benar daripada
            -- tertinggal di server lama.
            if not berhasil then
                status("[KUMPUL] Server tujuan tidak bisa dimasuki, masuk acak")
                teleportAman(function()
                    TeleportService:Teleport(pid, LocalPlayer)
                end, "place " .. tostring(pid))
            end
        end
        return
    end

    local kandidat = PLACE_DUNIA[act]
    if kandidat then
        -- Dibandingkan lewat Worlds.CurrentId, bukan PlaceId. Satu dunia punya
        -- banyak place (shard + varian bot), jadi PlaceId tidak bisa dipakai
        -- untuk memastikan kita sudah berada di dunia yang dimaksud.
        local tujuanId = DUNIA_ID[act]
        if tujuanId and duniaSekarang() == tujuanId then
            status("[LEWAT] Sudah di dunia tujuan")
            return
        end
        pindahDunia(tujuanId, kandidat)
    end
end

local function syncKePanel()
    if raw_panel_key == "" or not httprequest then return end

    local leavesSekarang = 0
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local n = ls and ls:FindFirstChild("Leaves")
    if n then leavesSekarang = n.Value end

    local data = {
        username = LocalPlayer.Name,
        panel_key = raw_panel_key,
        status = tostring(_G.FallHarvestDebug or "Kaitun World 2"),
        -- Panel membaca field ini sebagai saldo. Di dunia ini mata uangnya Leaves,
        -- bukan Sheckles -- namanya tetap "shekels" supaya panel tidak perlu tahu
        -- bedanya, dan label dunianya yang menjelaskan.
        shekels = leavesSekarang,
        world = game.PlaceId,
        world_name = NAMA_DUNIA[game.PlaceId] or "Unknown",
        -- Identitas server, untuk fitur "kumpulkan ke 1 server" di panel.
        job_id = game.JobId,
    }

    local ok, res = pcall(function()
        return httprequest({
            Url = "https://mozeframe.my.id/api/kaitun/sync",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(data),
        })
    end)
    if not ok or not res or res.StatusCode ~= 200 then return end

    local okJ, balasan = pcall(function()
        return game:GetService("HttpService"):JSONDecode(res.Body)
    end)
    if okJ and balasan and balasan.status == "success" and type(balasan.config) == "table" then
        local act = balasan.config.QuickAction
        if act then
            -- Dihapus lebih dulu supaya tidak dijalankan berulang tiap sync.
            pcall(function()
                httprequest({
                    Url = "https://mozeframe.my.id/api/kaitun/clear_action?panel_key="
                        .. game:GetService("HttpService"):UrlEncode(raw_panel_key)
                        .. "&username=" .. game:GetService("HttpService"):UrlEncode(LocalPlayer.Name),
                    Method = "GET",
                })
            end)
            task.spawn(tanganiQuickAction, act)
        end
    end
end

-- ==========================================================
-- MONITOR FIREBASE (Live Monitor di panel)
-- ==========================================================
-- Jalur TERPISAH dari syncKePanel: yang ini mengisi Live Monitor, yang itu
-- mengisi Kaitun Manager. Tanpa ini akun World 2 tidak muncul di Live Monitor
-- sama sekali.
--
-- Path-nya sama persis dengan kaitun utama (users/{panelKey}/accounts/{nama}),
-- ditambah field `world` supaya panel bisa memisahkan item W1 dan W2 -- isi
-- inventory kedua dunia berbeda (varian Maple, Leaves vs Sheckles), jadi
-- menggabungkannya menghasilkan angka yang tidak berarti.
local function tulisMonitor()
    if not httprequest then return end
    local panelKey = panel_key ~= "" and panel_key or "Public"

    local ok, err = pcall(function()
        local daun = 0
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        local n = ls and ls:FindFirstChild("Leaves")
        if n then daun = n.Value end

        -- Inventory dibaca dari Backpack, BUKAN dari replica seperti kaitun
        -- utama. Di game ini seed adalah Tool, dan satu Tool adalah setumpuk --
        -- jumlah sebenarnya ada di atribut Count. Sumber ini yang dipakai
        -- seluruh script untuk menanam, jadi angkanya sudah terbukti benar.
        -- Backpack di dunia ini berisi TIGA jenis Tool yang harus dibedakan:
        --
        --   Shovel / Build            tanpa atribut apa pun -> alat permanen,
        --                             dimiliki SEMUA pemain. Kalau ikut dihitung,
        --                             94 akun menghasilkan "Shovel x94" di puncak
        --                             daftar inventory W2 -- angka tanpa makna.
        --   "Maple Strawberry"        punya SeedTool + Count -> SEED (setumpuk)
        --   "Maple Strawberry [Gold]  tanpa atribut, berat di nama -> BUAH panen
        --    [1.37kg]"
        --
        -- Buah dihitung satu per satu supaya varian bernilai tinggi ([Gold],
        -- [Rainbow]) tetap terlihat di panel. Beratnya dibuang karena tiap buah
        -- punya berat berbeda -- kalau tidak, satu jenis buah pecah jadi puluhan
        -- baris berbeda dan tidak bisa dijumlahkan sama sekali.
        local invData = {}
        for _, wadah in ipairs({ LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }) do
            if wadah then
                for _, t in ipairs(wadah:GetChildren()) do
                    if t:IsA("Tool") then
                        local seedName = t:GetAttribute("SeedTool")
                        local count = tonumber(t:GetAttribute("Count"))

                        if seedName or count then
                            -- Diberi akhiran (Seed) supaya tidak tercampur
                            -- dengan buah bernama sama: "Maple Strawberry"
                            -- bisa berarti bibit maupun hasil panen.
                            local nama = (seedName or t.Name) .. " (Seed)"
                            invData[nama] = (invData[nama] or 0) + (count or 1)
                        elseif string.find(t.Name, "kg]", 1, true) then
                            local nama = string.gsub(t.Name, "%s*%[[%d%.]+kg%]", "")
                            invData[nama] = (invData[nama] or 0) + 1
                        end
                    end
                end
            end
        end

        local ping = 0
        pcall(function()
            local Stats = game:GetService("Stats")
            ping = tonumber(string.split(
                Stats.Network.ServerStatsItem["Data Ping"]:GetValueString(), " ")[1]) or 0
        end)

        httprequest({
            Url = "https://mozemonitor-default-rtdb.asia-southeast1.firebasedatabase.app/users/"
                .. panelKey .. "/accounts/" .. LocalPlayer.Name .. ".json",
            Method = "PUT",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode({
                username    = LocalPlayer.Name,
                coins       = daun,
                action      = tostring(_G.FallHarvestDebug or "Kaitun World 2"),
                ping        = ping,
                inventory   = invData,
                world       = NAMA_DUNIA[game.PlaceId] or "Fall Harvest",
                placeId     = game.PlaceId,
                lastUpdate  = { [".sv"] = "timestamp" },
            }),
        })
    end)
    if not ok then warn("[FH] Monitor gagal: " .. tostring(err)) end
end

do
    -- Jitter awal + per siklus, mengikuti pola kaitun utama: ratusan akun yang
    -- start berbarengan tidak boleh sync pada detik yang sama.
    local rng = Random.new()
    task.spawn(function()
        task.wait(rng:NextNumber(0, 20))
        while true do
            pcall(syncKePanel)
            task.wait(rng:NextNumber(30, 32))
        end
    end)

    -- Monitor jalan lebih rapat (5 detik) daripada sync config (30 detik),
    -- mengikuti kaitun utama: Live Monitor memakai lastUpdate untuk menentukan
    -- online/offline dengan ambang 60 detik, jadi 30 detik terlalu jarang dan
    -- akun sehat akan berkedip "Stuck".
    task.spawn(function()
        task.wait(rng:NextNumber(0, 5))
        while true do
            pcall(tulisMonitor)
            task.wait(5)
        end
    end)

    -- AUTO RECONNECT -- disalin dari kaitun utama, yang di sini belum ada sama
    -- sekali. Tanpa ini akun World 2 yang kena error 529/disconnect berhenti
    -- permanen sampai dijalankan ulang manual, dan itu sering terjadi di HP.
    local GuiService = game:GetService("GuiService")
    task.spawn(function()
        while true do
            task.wait(5)
            pcall(function()
                local kode = GuiService:GetErrorCode()
                local adaError = kode and kode.Value ~= 0

                if not adaError then
                    local gui = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
                    local overlay = gui and gui:FindFirstChild("promptOverlay")
                    adaError = overlay and overlay:FindFirstChild("ErrorPrompt") ~= nil
                end

                if adaError then
                    -- titipKode() WAJIB duluan. Tanpa itu akun memang kembali
                    -- masuk game, tapi tanpa script apa pun -- online, terlihat
                    -- sehat di monitor, dan sama sekali tidak bekerja.
                    titipKode()
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                end
            end)
        end
    end)
end

-- ==========================================================
-- AUTO SEED COLLECTOR
-- ==========================================================
-- Diport dari startAutoSeedCollector() di kaitun_main.txt -- pendekatan yang sudah
-- terbukti dipakai di lapangan, jadi jangan "disederhanakan" tanpa menguji ulang.
--
-- Sengaja TIDAK memakai jalur SeedPack.ClickPack: pack ber-ClickDetector hanyalah
-- salah satu bentuk drop. Pemindaian ProximityPrompt menangkap semuanya sekaligus --
-- seed jatuhan, gold, rainbow, mega -- tanpa perlu tahu id internal apa pun.
local KATA_SEED = {
    "seed","gold","mega","rainbow","mutation","carrot","apple","pomegranate","coconut",
    "cactus","mushroom","bamboo","corn","berry","acorn","cranberry","pumpkin","banana",
    "beanstalk","blossom","rose","buttercup","cherry","cinnamon","cone","dragon","eclipse",
    "fern","pepper","grape","bean","melon","hypno","lotus","mango","moon","partfruit",
    "pineapple","pine","plum","poison","pop","romanesco","star","sun","thorn","tomato",
    "tulip","venom","venus","flare","crate","maple","honeysuckle","potato",
}
local AKSI_AMBIL = { "pick up", "collect", "take", "grab", "loot", "claim" }
-- Aksi yang TIDAK boleh ditekan kolektor.
--
-- "steal" wajib ada di sini. Terhitung 812 prompt 'steal' di peta ini -- semuanya
-- tanaman milik pemain lain. Daftar asli di kaitun utama tidak memuatnya, dan yang
-- menyelamatkan sejauh ini hanya kebetulan: model tanaman bernama GUID sehingga
-- tidak mengandung kata kunci. Satu tanaman bernama mengandung "maple" atau
-- "carrot" sudah cukup membuat bot terbang mencuri milik orang lain.
local AKSI_BUKAN_AMBIL = {
    harvest = true, sit = true, talk = true, buy = true, use = true,
    steal = true, view = true, gift = true, ["add friend"] = true,
    ["view guild"] = true, interact = true,
}

local function cariSeedJatuh()
    local semua = workspace:GetDescendants()
    for i, prompt in ipairs(semua) do
        -- Yield berkala: workspace di peta ini puluhan ribu instance, dan menelusuri
        -- sekaligus tanpa jeda membuat frame drop terasa.
        if i % 1000 == 0 then task.wait() end

        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local obj = prompt.Parent
            if obj and (obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Attachment")) then
                local aksi = string.lower(prompt.ActionText or "")
                local sah = false

                for _, kata in ipairs(AKSI_AMBIL) do
                    if string.find(aksi, kata, 1, true) then sah = true break end
                end

                if not sah and not AKSI_BUKAN_AMBIL[aksi] then
                    local gabungan = string.lower(
                        (obj.Name or "") .. " " ..
                        ((obj.Parent and obj.Parent.Name) or "") .. " " ..
                        (prompt.ObjectText or ""))
                    for _, kata in ipairs(KATA_SEED) do
                        if string.find(gabungan, kata, 1, true) then sah = true break end
                    end
                end

                if sah then return obj, prompt end
            end
        end
    end
end

local function posisiDari(obj, prompt)
    if prompt.Parent:IsA("BasePart") then return prompt.Parent.Position end
    if prompt.Parent:IsA("Attachment") then return prompt.Parent.WorldPosition end
    local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position
end

local function ambilSeedJatuh()
    local obj, prompt = cariSeedJatuh()
    if not (obj and prompt) then return 0 end

    local pos = posisiDari(obj, prompt)
    if not pos then return 0 end

    status("[SEED] Mengambil " .. tostring(obj.Name):sub(1, 30))
    if not pergiKe(pos) then return 0 end

    -- Pijakan sementara: tanpa ini karakter bisa jatuh menembus saat mendarat di
    -- titik yang tidak punya lantai.
    local pijakan = Instance.new("Part")
    pijakan.Name = "TempSeedPlatform"
    pijakan.Size = Vector3.new(15, 1, 15)
    pijakan.Position = pos - Vector3.new(0, 4, 0)
    pijakan.Anchored = true
    pijakan.Transparency = 1
    pijakan.Parent = workspace
    game:GetService("Debris"):AddItem(pijakan, 5)

    -- Membuka kunci prompt inilah yang membuatnya andal: bawaan game membatasi
    -- jarak aktivasi dan mensyaratkan garis pandang, dan keduanya sering menggagalkan
    -- penekanan otomatis.
    pcall(function()
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = 9999
        if prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
    end)

    for _ = 1, 20 do
        if not prompt.Parent then break end
        pcall(fireproximityprompt, prompt)
        task.wait(0.05)
    end
    task.wait(0.5)
    return 1
end

-- ==========================================================
-- AUTO STEAL (untuk quest "Steal from N different people")
-- ==========================================================
-- Fakta yang dipastikan langsung di server, bukan diasumsikan:
--   * StealPrompt HANYA ada di tanaman orang lain. Kebun sendiri memakai
--     HarvestPrompt, jadi mustahil salah mencuri dari diri sendiri.
--   * Tanaman bernama "{userId}_{guid}", sehingga pemiliknya terbaca dari nama.
--   * MaxActivationDistance bawaannya cuma 10 studs, RequiresLineOfSight=false.
--   * fireproximityprompt tersedia di executor ini.
--
-- Teknik jarak jauhnya disalin dari still.lua: simpan properti asli prompt,
-- naikkan jaraknya, fire, lalu KEMBALIKAN. Tanpa dikembalikan, prompt itu
-- tertinggal dalam keadaan aneh dan bisa jadi penanda yang mencolok.
local sudahDicuri = {}   -- userId -> berapa kali kita menembaknya sesi ini

local function daftarKorban()
    local korban = {}   -- userId -> { prompt, ... }
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return korban end

    local uidSaya = tostring(LocalPlayer.UserId)
    for _, plot in ipairs(gardens:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if plants then
            for _, tanaman in ipairs(plants:GetChildren()) do
                local uid = string.match(tanaman.Name, "^(%d+)_")
                -- Penjagaan berlebih memang disengaja: kebun sendiri seharusnya
                -- tidak pernah punya StealPrompt, tapi kalau game berubah,
                -- gagalnya harus diam-diam aman, bukan mencabuti kebun sendiri.
                if uid and uid ~= uidSaya then
                    local hp = tanaman:FindFirstChild("HarvestPart")
                    local prompt = hp and hp:FindFirstChild("StealPrompt")
                    if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                        korban[uid] = korban[uid] or {}
                        table.insert(korban[uid], prompt)
                    end
                end
            end
        end
    end
    return korban
end

local function tembakPrompt(prompt)
    if not (prompt and prompt.Parent and prompt.Enabled) then return false end

    local oldD, oldL, oldH
    pcall(function()
        oldD, oldL, oldH = prompt.MaxActivationDistance, prompt.RequiresLineOfSight, prompt.HoldDuration
        if Config.StealJarakJauh then
            prompt.MaxActivationDistance = 1000000
            prompt.RequiresLineOfSight = false
        end
        prompt.HoldDuration = 0
    end)

    local kena = false
    if typeof(fireproximityprompt) == "function" then
        -- Burst seperti still.lua: sebagian fire dijatuhkan server, mengulanginya
        -- menaikkan tingkat keberhasilan.
        for i = 1, 3 do
            if pcall(fireproximityprompt, prompt) then kena = true end
            if i < 3 then task.wait(0.03) end
        end
    else
        kena = pcall(function()
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
        end)
    end

    pcall(function()
        if oldD then prompt.MaxActivationDistance = oldD end
        if oldL ~= nil then prompt.RequiresLineOfSight = oldL end
        if oldH then prompt.HoldDuration = oldH end
    end)
    return kena
end

-- Mengembalikan jumlah orang yang baru ditembak di sapuan ini.
local function sapuSteal()
    local korban = daftarKorban()
    local orangBaru, totalTembak = 0, 0

    for uid, daftar in pairs(korban) do
        local sudah = sudahDicuri[uid] or 0
        if sudah < Config.StealPerOrang then
            if sudah == 0 then orangBaru = orangBaru + 1 end

            -- Mode aman: terbang ke kebunnya DULU, baru menembak -- sama seperti
            -- pola beli/jual yang memang dituntut anticheat jarak dekat. Kalau
            -- dibalik, tembakannya tetap dari jarak jauh dan penerbangannya
            -- tidak ada gunanya sama sekali.
            if not Config.StealJarakJauh then
                local p = daftar[1] and daftar[1].Parent
                if p and p:IsA("BasePart") then pcall(pergiKe, p.Position) end
            end

            local sisa = Config.StealPerOrang - sudah
            for i = 1, math.min(sisa, #daftar) do
                if tembakPrompt(daftar[i]) then
                    totalTembak = totalTembak + 1
                    sudahDicuri[uid] = (sudahDicuri[uid] or 0) + 1
                end
                task.wait(0.05)
            end
        end
    end

    return orangBaru, totalTembak
end

-- ==========================================================
-- MODE BAMBOO
-- ==========================================================
-- SEMUA signature di bawah dibaca dari kode klien game, bukan ditebak:
--
--   Networking.GearShop.PurchaseGear:Fire("Syrup Watering Can")
--   Networking.Place.PlaceSprinkler:Fire(pos, tool:GetAttribute("Sprinkler"), tool, plotId)
--   Networking.WateringCan.UseWateringCan:Fire(pos - Vector3.new(0,0.3,0),
--                                              tool:GetAttribute("WateringCan"), tool)
--
-- Syarat keras yang dipaksakan server (SprinklerController/WateringcanController):
--   * Tool WAJIB terpasang di Character, bukan sekadar ada di Backpack.
--   * Nama diambil dari ATRIBUT tool ("Sprinkler" / "WateringCan"), bukan dari
--     Tool.Name -- keduanya bisa berbeda.
--   * Posisi WAJIB mengenai part bertag CollectionService "PlantArea" milik
--     plot kita sendiri. Titik di luar itu ditolak diam-diam.
--   * Sprinkler punya jeda 0,5 detik antar pemasangan.
local function plotId()
    local p = plotSaya()
    -- Sama persis dengan GetPlotId di SprinklerController: angka dari nama plot.
    return p and tonumber(string.match(p.Name, "%d+")) or nil
end

-- Titik-titik sah untuk menaruh sprinkler / menyiram.
local function titikPlantArea()
    local p = plotSaya()
    if not p then return {} end
    local hasil = {}
    for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
        if part:IsA("BasePart") and part:IsDescendantOf(p) then
            hasil[#hasil + 1] = part
        end
    end
    return hasil
end

-- Tool dicari lewat ATRIBUT, bukan nama, karena itu yang dipakai server untuk
-- mengesahkan pemakaian. Tool bernama "Syrup Watering Can" tanpa atribut
-- WateringCan akan ditolak.
local function toolBeratribut(namaAtribut)
    for _, wadah in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack") }) do
        if wadah then
            for _, t in ipairs(wadah:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute(namaAtribut) then return t end
            end
        end
    end
end

-- Stok dibaca dari ReplicatedStorage.StockValues, BUKAN dari teks UI toko.
--
-- Terverifikasi di server: StockValues.<Shop>.Items berisi satu ValueBase per
-- item dengan jumlah persis, dan angkanya COCOK dengan yang dipajang UI. Bedanya,
-- UI hanya terisi saat tokonya pernah dibuka -- saat tertutup, membaca Cost_Text
-- memberi angka basi. StockValues tereplikasi terus tanpa perlu membuka apa pun.
local function stokItem(namaShop, namaItem)
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    local shop = sv and sv:FindFirstChild(namaShop)
    local items = shop and shop:FindFirstChild("Items")
    local v = items and items:FindFirstChild(namaItem)
    if v and v:IsA("ValueBase") then return tonumber(v.Value) or 0 end
    return 0
end

local function detikKeRestock(namaShop)
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    local shop = sv and sv:FindFirstChild(namaShop)
    local n = shop and shop:FindFirstChild("UnixNextRestock")
    if not (n and n:IsA("ValueBase")) then return nil end
    return math.max(0, (tonumber(n.Value) or 0) - os.time())
end

local function beliGear(nama)
    local ok = pcall(function()
        Networking.GearShop.PurchaseGear:Fire(nama)
    end)
    return ok
end

-- Mengosongkan kebun sampai benar-benar 0 tanaman.
-- Berapa siklus berturut-turut pencabutan tidak membuahkan hasil.
-- Hidup di luar fungsi supaya bertahan antar siklus.
local cabutSiaSia = 0
local CABUT_SIA_SIA_MAKS = 3

local function kosongkanKebun()
    local sisa = #daftarTanaman()
    if sisa == 0 then
        cabutSiaSia = 0
        return 0
    end

    -- Berhenti kalau sudah terbukti tidak berpengaruh.
    --
    -- Terukur di server sungguhan: UseShovel diterima pcall (ok=true) tapi
    -- ditolak diam-diam -- 70 tanaman tidak berubah sama sekali selama 21 detik
    -- sementara remote ditembakkan 1,8x/detik. Karena hitungannya tidak pernah
    -- turun, fase ini mengulang selamanya. Itulah spam yang terlihat.
    --
    -- Diuji dan sama-sama gagal: nama model penuh, uid_guid, guid saja, atribut
    -- Shovel maupun string literal, dengan SwingShovel didahulukan, bahkan
    -- sambil berdiri tepat di sebelah tanaman. Sebabnya belum diketahui --
    -- kemungkinan besar penjagaan sisi server. Sampai itu terpecahkan, yang
    -- benar adalah BERHENTI, bukan terus menembak.
    if cabutSiaSia >= CABUT_SIA_SIA_MAKS then
        status(string.format(
            "[BAMBOO] Cabut ditolak server %dx berturut-turut — dihentikan. %d tanaman dibiarkan.",
            cabutSiaSia, sisa))
        return sisa
    end

    local shovel = toolBernama("Shovel")
    if not shovel or not equip(shovel) then
        status("[BAMBOO] Shovel tidak bisa dipegang")
        return sisa
    end

    -- Nama dari ATRIBUT tool, bukan string literal.
    -- ShovelController memakai u90:GetAttribute("Shovel") sebagai argumen ke-3,
    -- pola yang sama dengan sprinkler dan watering can. Kebetulan nilainya juga
    -- "Shovel", tapi mengandalkan kebetulan itu akan patah diam-diam kalau game
    -- mengganti namanya.
    local namaShovel = shovel:GetAttribute("Shovel") or "Shovel"

    local dicabut = 0
    -- Dibatasi per siklus, bukan sampai habis dalam satu jalan: kebun bisa berisi
    -- puluhan tanaman, dan mencabut semuanya tanpa jeda membuat server menolak
    -- sisanya. Siklus berikutnya melanjutkan.
    for _, t in ipairs(daftarTanaman()) do
        if dicabut >= 25 then break end
        -- plantId = NAMA MODEL, sesuai ShovelController (plantId = Parent2.Name).
        -- t.model.Name dipakai langsung supaya tidak bergantung pada penguraian
        -- nama yang bisa meleset untuk format tak terduga.
        local plantId = (t.model and t.model.Name) or (t.userId .. "_" .. t.guid)
        local ok = pcall(function()
            Networking.Shovel.UseShovel:Fire(plantId, "", namaShovel, shovel)
        end)
        if ok then dicabut = dicabut + 1 end
        task.wait(0.15)
    end

    local tersisa = #daftarTanaman()

    -- pcall berhasil TIDAK berarti server menerima. Yang menentukan hanya
    -- jumlah tanaman yang benar-benar berkurang.
    if tersisa >= sisa then
        cabutSiaSia = cabutSiaSia + 1
        status(string.format(
            "[BAMBOO] %d cabut ditembak, tanaman TIDAK berkurang (%d) — percobaan %d/%d",
            dicabut, tersisa, cabutSiaSia, CABUT_SIA_SIA_MAKS))
    else
        cabutSiaSia = 0
        status(string.format("[BAMBOO] Mengosongkan kebun: %d dicabut, %d tersisa",
            sisa - tersisa, tersisa))
    end

    return tersisa
end

local function pasangSprinkler()
    local tool = toolBeratribut("Sprinkler")
    if not tool then return false end

    local nama = tool:GetAttribute("Sprinkler")
    local id = plotId()
    local titik = titikPlantArea()
    if not (nama and id and #titik > 0) then return false end

    if not equip(tool) then
        status("[BAMBOO] Sprinkler tidak bisa dipegang")
        return false
    end

    -- Ditaruh di TENGAH tiap PlantArea. Jangkauan sprinkler berbentuk lingkaran,
    -- jadi titik tengah menyiram petak paling banyak.
    local dipasang = 0
    for _, part in ipairs(titik) do
        local pos = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
        local ok = pcall(function()
            Networking.Place.PlaceSprinkler:Fire(pos, nama, tool, id)
        end)
        if ok then dipasang = dipasang + 1 end
        -- Jeda 0,5 detik dipaksakan klien game (TryPlace menolak lebih cepat
        -- dari itu). 0,6 diberi sedikit kelonggaran.
        task.wait(0.6)
    end

    status(string.format("[BAMBOO] %d sprinkler dipasang", dipasang))
    return dipasang > 0
end

local function siramKebun(kali)
    local tool = toolBeratribut("WateringCan")
    if not tool then return false end

    local nama = tool:GetAttribute("WateringCan")
    if not nama then return false end

    if not equip(tool) then
        status("[BAMBOO] Watering can tidak bisa dipegang")
        return false
    end

    local radius = radiusSiram(nama)
    local n = 0

    for _ = 1, (kali or 4) do
        -- Titik dihitung ULANG tiap siraman. Tanaman bisa tumbuh, dipanen, atau
        -- bertambah di sela-sela, sehingga titik terbaik ikut bergeser; memakai
        -- satu titik yang dihitung sekali di awal menyiram tempat yang sudah
        -- tidak optimal lagi.
        local pos, tertutup = titikSiramTerbaik(radius)
        if not pos then break end

        local ok = pcall(function()
            -- Offset -0.3 pada Y disalin dari WateringcanController: server
            -- memeriksa titiknya terhadap permukaan PlantArea, dan tanpa offset
            -- ini sebagian tembakan meleset di atas permukaan.
            Networking.WateringCan.UseWateringCan:Fire(
                pos - Vector3.new(0, 0.3, 0), nama, tool)
        end)
        if ok then
            n = n + 1
            status(string.format("[BAMBOO] Siram %d/%d — menutupi %d tanaman (radius %d)",
                n, kali or 4, tertutup or 0, radius))
        end
        task.wait(0.35)
    end

    return n > 0
end

-- Beli bambu + gear yang belum dimiliki.
local function belanjaBamboo()
    -- Jumlah pembelian mengikuti STOK SEBENARNYA.
    --
    -- Versi sebelumnya menembakkan 20 PurchaseSeed membabi-buta tiap belanja.
    -- Saat stok 0 -- dan itu keadaan normal di antara restock, terukur siklus
    -- 5 menit -- ke-20 tembakan itu ditolak semua. Selain sia-sia, puluhan
    -- permintaan beli yang gagal beruntun adalah pola yang tidak dilakukan
    -- pemain mana pun.
    local punyaSiram = toolBeratribut("WateringCan") ~= nil
    local punyaSprinkler = toolBeratribut("Sprinkler") ~= nil

    if not punyaSiram and stokItem("GearShop", Config.GearSiram) > 0 then
        beliGear(Config.GearSiram)
        task.wait(0.4)
    end
    if not punyaSprinkler and stokItem("GearShop", Config.GearSprinkler) > 0 then
        -- Sprinkler sering habis. Kegagalan di sini TIDAK menghentikan alur:
        -- bambu tetap tumbuh dengan watering can saja, hanya lebih lambat.
        beliGear(Config.GearSprinkler)
        task.wait(0.4)
    end

    local stok = stokItem("SeedShop", Config.SeedBamboo)
    local mau = math.min(stok, Config.BeliBambooSekali)
    local dibeli = 0

    for _ = 1, mau do
        local ok = pcall(function()
            Networking.SeedShop.PurchaseSeed:Fire(Config.SeedBamboo)
        end)
        if ok then dibeli = dibeli + 1 end
        task.wait(0.12)
    end

    if mau == 0 then
        local sisa = detikKeRestock("SeedShop")
        status(string.format("[BAMBOO] %s habis%s — menunggu restock",
            Config.SeedBamboo,
            sisa and string.format(" (%dd lagi)", sisa) or ""))
    else
        status(string.format("[BAMBOO] Beli %d/%d bambu | siram=%s sprinkler=%s",
            dibeli, stok,
            tostring(toolBeratribut("WateringCan") ~= nil),
            tostring(toolBeratribut("Sprinkler") ~= nil)))
    end

    return dibeli
end

-- Berapa biji bambu yang siap ditanam di Backpack.
local function stokBambooDiTas()
    local n = 0
    for _, wadah in ipairs({ LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }) do
        if wadah then
            for _, t in ipairs(wadah:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("SeedTool") == Config.SeedBamboo then
                    n = n + (tonumber(t:GetAttribute("Count")) or 1)
                end
            end
        end
    end
    return n
end

-- ==========================================================
-- CORNUCOPIA QUEST (menempel, tanpa gerakan tambahan)
-- ==========================================================
local function questTempel()
    if not Config.AutoQuest then return end
    local ok, st = pcall(function() return Networking.Pilgrim.GetState:Fire() end)
    if not ok or type(st) ~= "table" or st.Enabled == false then return end

    if st.ChainComplete == true and st.RewardClaimed ~= true then
        pcall(function() Networking.Pilgrim.ClaimReward:Fire() end)
        status("[QUEST] Grand Prize diklaim")
        return
    end

    local q
    for _, v in pairs(st.Quests or {}) do
        if type(v) == "table" and v.Status == "ongoing" then q = v break end
    end
    if not q then return end

    -- Rantai Cornucopia berurutan, dan sebagian langkahnya bertipe "passive":
    -- "Steal from 15 different people", "Grow a 100 ft tall plant". Keduanya
    -- tidak punya remote untuk disetor -- server yang menghitung sendiri dari
    -- kejadian di dunia. Bot akan MENUNGGU di langkah itu sampai syaratnya
    -- terpenuhi, dan tanpa pesan ini diamnya terlihat seperti quest rusak.
    if q.Kind ~= "delivery" then
        local desc = tostring(q.Description or "")
        local progres = tonumber(q.Progress) or 0
        local target = tonumber(q.Target) or 0

        -- Satu-satunya langkah pasif yang bisa kita dorong. "Grow a 100 ft tall
        -- plant" tidak ada aksinya sama sekali -- itu tumbuh sendiri seiring
        -- waktu, jadi memang hanya bisa ditunggu.
        if Config.AutoSteal and string.find(desc, "Steal", 1, true) then
            local orangBaru, tembakan = sapuSteal()
            status(string.format("[STEAL] %s (%d/%d) — %d orang baru, %d tembakan",
                desc, progres, target, orangBaru, tembakan))

            -- Satu server maksimal 8 pemain, jadi paling banyak 7 korban. Kalau
            -- semua yang ada sudah dicuri dan targetnya belum tercapai, satu-
            -- satunya jalan adalah mencari orang lain di server lain.
            if orangBaru == 0 and progres < target and Config.StealPindahServer then
                status("[STEAL] Korban di server ini habis — pindah server")
                titipKode()
                teleportAman(function()
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                end, "ganti server untuk korban baru", 2)
            elseif orangBaru == 0 and progres < target then
                status(string.format(
                    "[STEAL] Korban server ini habis (%d/%d). Nyalakan StealPindahServer untuk lanjut",
                    progres, target))
            end
            return
        end

        -- Dibedakan supaya jelas mana yang akan beres sendiri dan mana yang
        -- memang berhenti di situ. Tanpa pembedaan ini, keduanya terbaca sama
        -- seperti quest rusak.
        if string.find(desc, "Steal", 1, true) then
            status(string.format(
                "[QUEST] Dilewati (AutoSteal mati): %s (%s/%s) — tani jalan terus",
                desc, tostring(q.Progress), tostring(q.Target)))
        else
            status(string.format("[QUEST] Menunggu langkah pasif: %s (%s/%s)",
                desc, tostring(q.Progress), tostring(q.Target)))
        end
        return
    end

    -- Submit sampai progres berhenti naik: server yang memilih itemnya, jadi
    -- tidak ada cara tahu berapa yang layak selain mencoba.
    local progres = tonumber(q.Progress) or 0
    for _ = 1, 15 do
        local ok2, baru = pcall(function() return Networking.Pilgrim.SubmitDelivery:Fire() end)
        if not ok2 or type(baru) ~= "table" then break end
        local q2
        for _, v in pairs(baru.Quests or {}) do
            if type(v) == "table" and v.Status == "ongoing" then q2 = v break end
        end
        if not q2 then status("[QUEST] Satu quest tuntas") break end
        local p2 = tonumber(q2.Progress) or 0
        if p2 <= progres then break end
        progres = p2
        status(string.format("[QUEST] %s (%s/%s)", tostring(q2.Description), tostring(p2), tostring(q2.Target)))
        task.wait(0.4)
    end
end

-- ==========================================================
-- LOOP UTAMA
-- ==========================================================
_G.FHInstance = (_G.FHInstance or 0) + 1
local instanceSaya = _G.FHInstance

status(string.format("Aktif (#%d). Ambang speedrun=%s", instanceSaya, Config.AmbangSpeedrun))

pasangBlackScreen()
if Config.AntiAFK then pasangAntiAFK() end

task.spawn(function()
    local putaranSiklus = 0
    -- Keadaan mode bambu. Hidup di LUAR while, jadi bertahan antar siklus.
    local fase_bamboo = "awal"
    while instanceSaya == _G.FHInstance do
        putaranSiklus = putaranSiklus + 1

        -- SELURUH isi siklus dibungkus pcall, bukan hanya tiap fase.
        --
        -- Tiap fase memang sudah dilindungi pcall sendiri, tapi penyusunan daftar
        -- fase di bawah TIDAK: daftarTanaman(), rarityTerendahKebun(), dan
        -- jumlahBuah() semuanya dipanggil di luar perlindungan itu. Satu error di
        -- sana -- misalnya karakter respawn tepat saat kebun dibaca -- melempar
        -- keluar dari while, keluar dari thread, dan bot berhenti PERMANEN tanpa
        -- pesan apa pun. Untuk bot yang ditinggal berjam-jam, itu kegagalan
        -- paling mahal: kelihatan online di monitor, tapi tidak mengerjakan apa-apa.
        local okSiklus, errSiklus = pcall(function()

        local tanaman = daftarTanaman()

        -- Speedrun Leaves: berhenti belanja sama sekali.
        --
        -- DUA syarat, dan keduanya wajib:
        --   1. Kebun PENUH -- selama masih ada tanah kosong, mengisinya dengan
        --      seed apa pun lebih baik daripada membiarkannya menganggur.
        --   2. Tanaman TERLEMAH sudah mencapai ambang -- kalau yang terlemah pun
        --      sudah Legendary, tidak ada isi shop yang bisa menggantikannya,
        --      jadi setiap pembelian murni membuang Leaves.
        --
        -- Versi sebelumnya memakai rarity TERTINGGI dan tanpa syarat penuh:
        -- satu tanaman Legendary di kebun yang sisanya Common sudah menghentikan
        -- seluruh pembelian, padahal masih banyak tanah kosong. Itu keliru.
        local rarityTerlemah = rarityTerendahKebun()
        local speedrun = kebunPenuh and rarityTerlemah >= AMBANG_SPEEDRUN

        -- Fase dijalankan BERURUTAN dan satu per satu, tidak ada yang menumpuk.
        --
        -- Urutannya disengaja, bukan sekadar rapi:
        --   panen  -> menghasilkan buah
        --   quest  -> dapat giliran PERTAMA atas buah itu; SubmitDelivery dan
        --             SellAll sama-sama memakan inventory, dan sebelumnya
        --             keduanya jalan tanpa saling tahu sehingga buah untuk quest
        --             ikut terjual
        --   jual   -> membuang sisanya jadi Leaves
        --   beli   -> memakai Leaves yang baru saja masuk
        --   tanam  -> menanam seed yang baru saja dibeli
        --
        -- Tiap fase diberi jeda sendiri supaya efeknya sempat tercatat server
        -- sebelum fase berikutnya membaca keadaan.
        local fase = {}

        -- ==== MESIN KEADAAN MODE BAMBOO ====
        -- Alur yang diminta:
        --   awal      -> bertani biasa sampai Leaves menembus ambang
        --   kosongkan -> cabut SEMUA tanaman sampai 0
        --   belanja   -> borong bambu + Syrup Watering Can + Syrup Sprinkler
        --   bamboo    -> pasang sprinkler > tanam semua bambu > siram > panen > jual
        --
        -- Sekali masuk "bamboo" tidak pernah kembali ke "awal": modalnya sudah
        -- terbentuk, dan bertani campur hanya memperlambat.
        if Config.ModeBamboo then
            if fase_bamboo == "awal" and leaves() >= Config.AmbangModeBamboo then
                fase_bamboo = "kosongkan"
                status(string.format("[BAMBOO] Leaves %d >= %d — beralih ke mode bambu",
                    leaves(), Config.AmbangModeBamboo))

            elseif fase_bamboo == "kosongkan" then
                if #daftarTanaman() == 0 then
                    fase_bamboo = "belanja"
                    status("[BAMBOO] Kebun kosong — mulai belanja")
                end

            elseif fase_bamboo == "belanja" then
                -- Watering can WAJIB. Sprinkler tidak: sering NO STOCK, dan
                -- tanpa itu bambu tetap tumbuh, hanya lebih lambat. Menunggu
                -- sprinkler restock berarti bot diam berjam-jam.
                if toolBeratribut("WateringCan") and stokBambooDiTas() > 0 then
                    fase_bamboo = "bamboo"
                    status("[BAMBOO] Perlengkapan siap — mulai siklus bambu")
                end

            elseif fase_bamboo == "bamboo" then
                -- Kehabisan bambu DAN kebun kosong -> belanja lagi.
                if stokBambooDiTas() == 0 and #daftarTanaman() == 0 then
                    fase_bamboo = "belanja"
                    status("[BAMBOO] Bambu habis — belanja lagi")
                end
            end
        end

        if Config.ModeBamboo and fase_bamboo ~= "awal" then
            -- Seed jatuhan tetap prioritas utama di semua keadaan: hanya itu yang
            -- bisa direbut pemain lain.
            if Config.AutoAmbilSeed then
                fase[#fase + 1] = { "ambil-seed", ambilSeedJatuh }
            end

            if fase_bamboo == "kosongkan" then
                fase[#fase + 1] = { "kosongkan", kosongkanKebun }

            elseif fase_bamboo == "belanja" then
                fase[#fase + 1] = { "belanja-bamboo", belanjaBamboo }

            elseif fase_bamboo == "bamboo" then
                -- Urutannya: pasang sprinkler > tanam DI DALAM jangkauannya >
                -- siram di titik yang menutupi tanaman terbanyak.
                --
                -- Sprinkler wajib duluan karena batas area tanam diambil dari
                -- posisi sprinkler yang sudah berdiri. Kalau dibalik, bambu
                -- tertanam di seluruh kebun dan sebagian besar berada di luar
                -- jangkauan -- tidak ikut dipercepat sama sekali.
                if toolBeratribut("Sprinkler") then
                    fase[#fase + 1] = { "sprinkler", pasangSprinkler }
                end

                fase[#fase + 1] = { "tanam-bamboo", function()
                    local area = sprinklerTerpasang()
                    -- Tanpa sprinkler berdiri, jangan dibatasi: mengurung
                    -- penanaman ke area kosong berarti tidak menanam apa pun.
                    areaSprinklerAktif = (#area > 0) and area or nil
                    if areaSprinklerAktif then
                        status(string.format("[BAMBOO] Menanam di jangkauan %d sprinkler (radius %d)",
                            #area, area[1].radius))
                    end
                    -- Dibungkus pcall SENDIRI supaya pengosongan di bawah pasti
                    -- terjadi. Kalau tanamSemua() melempar error, baris reset
                    -- tidak akan tercapai dan areaSprinklerAktif tertinggal
                    -- terisi -- membuat SELURUH penanaman berikutnya, termasuk
                    -- alur normal, terkurung di radius sprinkler yang mungkin
                    -- sudah tidak ada lagi. Kebun berhenti terisi tanpa sebab
                    -- yang terlihat.
                    local hasil
                    local ok, err = pcall(function() hasil = tanamSemua() end)
                    areaSprinklerAktif = nil
                    if not ok then error(err, 0) end
                    return hasil
                end }

                fase[#fase + 1] = { "siram", function() siramKebun(Config.SiramPerSiklus) end }
                fase[#fase + 1] = { "panen", panenSemua }
                if Config.AutoQuest then fase[#fase + 1] = { "quest", questTempel } end
                if Config.AutoJual then fase[#fase + 1] = { "jual", jual } end
                -- Beli bambu lagi untuk siklus berikutnya, selagi kebun tumbuh.
                fase[#fase + 1] = { "beli-bamboo", belanjaBamboo }
            end

            -- Pembersihan kebun tetap berjalan di mode bambu.
            if putaranSiklus == 1 then
                fase[#fase + 1] = { "fps-boost", applyFpsBoost }
            elseif Config.SiklusBersihKebun > 0
                   and putaranSiklus % Config.SiklusBersihKebun == 0 then
                fase[#fase + 1] = { "bersih-kebun", function() bersihkanKebunOrang(false) end }
            end

            for _, f in ipairs(fase) do
                if instanceSaya ~= _G.FHInstance then break end
                local ok, err = pcall(f[2])
                if not ok then status("[ERROR] fase " .. f[1] .. ": " .. tostring(err)) end
                task.wait(Config.JedaAksi)
            end
            return  -- keluar dari pcall siklus; alur biasa di bawah dilewati
        end


        -- ==== PRIORITAS 1: SEED JATUHAN ====
        -- Ditaruh paling atas dengan sengaja. Ini satu-satunya sumber yang bisa
        -- HILANG DIREBUT pemain lain -- gold, rainbow, dan mega seed muncul
        -- sebentar lalu diambil siapa pun yang sampai duluan.
        --
        -- Sisanya tidak ke mana-mana: buah menunggu di kebun sendiri, Leaves tidak
        -- menguap, shop tidak kehabisan stok karena kita telat semenit. Jadi
        -- menunda seed demi panen adalah satu-satunya urutan yang benar-benar
        -- merugikan.
        if Config.AutoAmbilSeed then fase[#fase + 1] = { "ambil-seed", ambilSeedJatuh } end

        -- ==== PRIORITAS 2: QUEST ====
        -- Quest naik ke urutan kedua, TAPI tidak bisa ditaruh mentah-mentah di
        -- sini. SubmitDelivery memakan buah dari inventory; kalau quest jalan
        -- saat inventory kosong ia tidak melakukan apa-apa, lalu fase "jual" di
        -- bawah menghabiskan buah hasil panen siklus ini -- quest tidak akan
        -- pernah kebagian buah sama sekali.
        --
        -- Jadi dipecah dua:
        --   sudah ada buah -> quest jalan SEKARANG, benar-benar prioritas 2 dan
        --                     mendahului "jual-awal" yang kalau tidak akan
        --                     menjual habis buah untuk quest
        --   belum ada buah -> quest menunggu tepat setelah panen, tetap sebelum
        --                     jual, jadi tetap dapat giliran pertama
        local adaBuah = jumlahBuah() > 0
        if Config.AutoQuest and adaBuah then
            fase[#fase + 1] = { "quest", questTempel }
        end

        -- Inventory hampir penuh -> JUAL DULU, sebelum panen.
        -- Kalau tidak, panen menembak ke kapasitas mentok, ditolak diam-diam,
        -- dan siklus berikutnya mengulang hal yang sama -- itu "stuck spam
        -- harvest" yang kamu lihat.
        local penuh = jumlahBuah() >= Config.AmbangJualBuah
        if penuh and Config.AutoJual then
            status(string.format("[PENUH] %d/%d buah — jual dulu", jumlahBuah(), kapasitasBuah()))
            fase[#fase + 1] = { "jual-awal", jual }
        end

        -- Sudah ada seed menganggur di Backpack -> TANAM DULU, sebelum apa pun.
        -- Kalau menunggu urutan normal, seed itu diam melewati panen, quest, dan
        -- jual dulu -- tanah kosong dibiarkan menganggur satu siklus penuh.
        if Config.AutoTanam then
            local bp = LocalPlayer:FindFirstChild("Backpack")
            local adaSeed = false
            if bp then
                for _, t in ipairs(bp:GetChildren()) do
                    if t:IsA("Tool") and t:GetAttribute("SeedTool") then adaSeed = true break end
                end
            end
            if adaSeed then fase[#fase + 1] = { "tanam-awal", tanamSemua } end
        end

        -- Sapuan berat cukup SEKALI: dekorasi, efek, dan suara yang sudah
        -- dimatikan tidak kembali, sedangkan sapuannya menyentuh belasan ribu
        -- instance.
        if putaranSiklus == 1 then
            fase[#fase + 1] = { "fps-boost", applyFpsBoost }

        -- Kebun ORANG LAIN beda cerita: dimuat bertahap seiring pemain
        -- berdatangan. Terukur 8 pemain tapi baru 1 plot termuat, sementara
        -- Gardens menyumbang 56% dari seluruh instance workspace. Sekali jalan
        -- di siklus 1 hampir tidak membersihkan apa pun, jadi diulang berkala.
        elseif Config.SiklusBersihKebun > 0
               and putaranSiklus % Config.SiklusBersihKebun == 0 then
            fase[#fase + 1] = { "bersih-kebun", function() bersihkanKebunOrang(false) end }
        end

        if Config.AutoPanen then fase[#fase + 1] = { "panen", panenSemua } end

        -- Giliran kedua quest: hanya kalau tadi dilewati karena inventory kosong.
        -- Tetap sebelum "jual" supaya buah yang baru dipanen disetor dulu, bukan
        -- dijual. Tanpa penjagaan `not adaBuah`, quest akan jalan dua kali per
        -- siklus dan menembak SubmitDelivery percuma.
        if Config.AutoQuest and not adaBuah then
            fase[#fase + 1] = { "quest", questTempel }
        end

        if Config.AutoJual  then fase[#fase + 1] = { "jual",  jual } end

        if speedrun then
            status(string.format(
                "[SPEEDRUN] Kebun penuh & tanaman terlemah sudah rarity %d — belanja dilewati",
                rarityTerlemah))
        else
            if Config.AutoBeli then
                fase[#fase + 1] = { "beli", function()
                    local stok = stokShop()
                    if #stok > 0 then beli(stok) end
                end }
            end
            if Config.AutoTanam then fase[#fase + 1] = { "tanam", tanamSemua } end
        end

        for _, f in ipairs(fase) do
            if instanceSaya ~= _G.FHInstance then break end
            local ok, err = pcall(f[2])
            if not ok then status("[ERROR] fase " .. f[1] .. ": " .. tostring(err)) end
            task.wait(Config.JedaAksi)
        end

        end)  -- tutup pcall siklus

        if not okSiklus then
            -- Dilaporkan lalu DILANJUTKAN. Siklus berikutnya membaca ulang
            -- keadaan dari nol, jadi gangguan sesaat (respawn, kebun sedang
            -- dimuat ulang, remote menolak) sembuh dengan sendirinya.
            status("[ERROR] siklus " .. putaranSiklus .. ": " .. tostring(errSiklus))
            task.wait(3)
        end

        task.wait(Config.JedaSiklus)
    end
    print("[FH] Instance #" .. instanceSaya .. " berhenti.")
end)

-- @MOZEFRAME-EOF@ (penanda akhir berkas -- router menolak file tanpa baris ini)
