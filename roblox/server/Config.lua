--[[
  SMART ANTICHEAT - KONFIGURASI (satu-satunya file yang perlu lu edit di sisi Roblox)
  Letak: ServerScriptService > SmartAC > Config
  File ini hanya ada di SERVER (tidak pernah dikirim ke client). Jangan pindahkan ke ReplicatedStorage!
]]

local Config = {}

-- true = cetak log penting di Output (claim perintah, hasil eksekusi, penolakan backend). Matikan saat rilis.
Config.Debug = true

-- 1) Koneksi ke backend (isi sesuai README langkah "Hubungkan Roblox")
Config.Backend = {
	Url = "https://PROJECT_REF.supabase.co/functions/v1/roblox-gateway", -- ganti PROJECT_REF
	Key = "GANTI_DENGAN_ROBLOX_GATEWAY_KEY",                             -- sama dengan secret ROBLOX_GATEWAY_KEY
	PollSeconds = 5,       -- seberapa sering cek perintah dari Discord/dashboard
	FlushSeconds = 5,      -- seberapa sering kirim batch insiden/audit
	HeartbeatSeconds = 30, -- "saya masih hidup" untuk sesi pemain
}

-- 2) Daftar staff TIDAK ada di file ini. Satu-satunya sumber: staff_roster.json (root project) ->
--    python3 tools/build_all.py -> menghasilkan modul "Roster" di folder SmartAC (+ SQL untuk Discord/web).
--    Role: founder, management, developer, administrator (Admin), helper.
Config.StaffImmune = true -- staff KEBAL dari anti-cheat SmartAC (tidak dicatat, tidak di-kick). Detail di README.

-- 3) Anti-cheat. MODE AWAL = "detect_only" (hanya mencatat, TIDAK menghukum).
--    Ubah ke "enforced" HANYA setelah lu cek insiden di dashboard beberapa hari dan yakin tidak ada false positive.
Config.AntiCheat = {
	Mode = "detect_only", -- "detect_only" | "enforced"
	-- TERKUNCI detect-only: anti-cheat HANYA mencatat & melapor ke log staf; tidak pernah meng-kick/ban otomatis,
	-- apa pun isi config backend. Ubah ke false HANYA bila nanti sengaja ingin membuka mode enforced (kick saja).
	LockDetectOnly = true,

	-- !!! Angka di bawah adalah titik awal yang BELUM dikalibrasi untuk game RP lu. Kalibrasi di staging. !!!
	Speed    = { SampleSeconds = 0.25, Tolerance = 1.6, FlatBonus = 8, StrikesNeeded = 4 },
	Fly      = { AirSeconds = 3.0, MaxFallSpeed = 25, MaxUpSpeed = 90 },
	Teleport = { MinStuds = 80, StudsPerSecond = 500, VehicleStudsPerSecond = 1500 },
	Noclip   = { MinMove = 4, StrikesNeeded = 3, WindowSeconds = 10 },
	Grace    = { Respawn = 4, Seat = 1.5, Teleport = 2.5 },

	-- Whitelist: alat/kendaraan/lantai yang SAH bergerak cepat atau "tidak menyentuh tanah". Item yang cocok
	-- dikecualikan dari cek speed, fly, dan noclip (cek TELEPORT mustahil tetap berjalan).
	-- Cara menandai: beri Attribute boolean "SmartACWhitelist = true" ATAU CollectionService tag "SmartACWhitelist"
	-- pada Tool / model kendaraan / bagian lantai. Atau cukup daftarkan NAMA-nya di bawah (huruf besar-kecil bebas).
	Whitelist = {
		Tag = "SmartACWhitelist",
		ToolNames = { "Hoverboard", "Skateboard", "Jetpack", "Parachute", "Glider", "Paraglider", "Sepeda", "Scooter" },
		VehicleNames = {},  -- kendaraan apa pun yang DIDUDUKI (Seat/VehicleSeat) sudah otomatis dikecualikan; isi untuk menandai khusus
		PartNames = { "Escalator", "Elevator", "Lift", "MovingPlatform", "Conveyor", "Trampoline", "JumpPad", "Eskalator" },
	},

	Score = {
		DecayPerSecond = 0.1,
		KickScore = 60,              -- skor minimal untuk kick (hanya mode enforced)
		DistinctDetectors = 2,       -- butuh minimal 2 jenis sinyal berbeda dalam 60 detik (kecuali honeypot)
		EmitCooldownSeconds = 10,    -- batasi spam insiden per jenis
	},

	Remote = { PerSecond = 10, Burst = 20 },

	-- Remote jebakan: client asli TIDAK pernah memanggilnya. Ganti nama kalau bentrok dengan remote game lu.
	Honeypots = { "GiveMoney", "AddCash", "SetAdmin", "GiveItem" },
}

-- 4) Integrasi dengan game SINAR RP (notifikasi/banner/warn memakai UI game; otomatis aktif kalau ReplicatedStorage.SinarRP ada).
--    Daftar staf SmartAC TERPISAH dari SINAR RP (lihat staff_roster.json).
Config.Integration = {
	UseSinarRP = true,
	AnnounceTopic = "SinarUmumkan", -- topic MessagingService yang SAMA dengan aplikasi Staff game lu
}

-- 5) Pemantau ekonomi (hanya MENCATAT sinyal; tidak pernah menghukum). Angka dalam Rupiah (Uang + Saldo).
Config.Economy = {
	Enabled = true,
	WindowSeconds = 60,
	GainThreshold = 5000000, -- kenaikan total >= ini dalam 1 menit dicatat (gaji normal ~32rb-200rb per 5 menit)
}

-- 6) Perintah uang/status SINAR RP (;setuang ;kasihuang ...): batas per role. Role tidak terdaftar di Caps = TANPA batas.
Config.StaffMoney = {
	Caps = { administrator = 1000000, helper = 500000 }, -- maks Rupiah PER PERINTAH (setuang/setsaldo/kasihuang/kasihsaldo)
	HelperSameTargetOnce = true,        -- helper hanya boleh 1x perintah yang sama ke pemain yang sama
	HelperSameTargetWindowHours = nil,  -- nil = selamanya; isi angka (jam) untuk membuka lagi setelah jeda itu
	HelperCooldownSeconds = 60,         -- helper: jeda untuk perintah yang sama (grup "playtest")
}

return Config
