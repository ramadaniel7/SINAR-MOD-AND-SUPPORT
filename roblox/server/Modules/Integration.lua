-- Jembatan ke game SINAR RP. Semua akses ke modul SINAR RP dilakukan secara malas (lazy) + pcall,
-- jadi SmartAC tetap jalan normal kalau SINAR RP tidak ada / strukturnya berubah.
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(script.Parent.Parent.Config)
local Util = require(script.Parent.Util)

local Integration = {}
local I = Config.Integration

local cache = {}
local function sinarServerModule(name)
	if cache[name] ~= nil then return cache[name] or nil end
	local root = ServerScriptService:FindFirstChild("SinarRP")
	local folder = root and root:FindFirstChild("Modul")
	local mod = folder and folder:FindFirstChild(name)
	local ok, res = false, nil
	if mod then ok, res = pcall(require, mod) end
	cache[name] = (ok and type(res) == "table") and res or false
	return cache[name] or nil
end

function Integration.Active()
	return I.UseSinarRP and ReplicatedStorage:FindFirstChild("SinarRP") ~= nil and ServerScriptService:FindFirstChild("SinarRP") ~= nil
end

-- ---------- Notifikasi memakai UI game SINAR RP ----------
function Integration.Notif(player, text, kind)
	local Net = Integration.Active() and sinarServerModule("Net")
	if not Net then return false end
	Net.Notif(player, text, kind or "info")
	return true
end

-- Banner "Umumkan" milik SINAR RP. player = nil -> semua pemain di server ini.
function Integration.Banner(text, from, player)
	local Net = Integration.Active() and sinarServerModule("Net")
	if not Net then return false end
	if player then Net.Kirim(player, "Umumkan", text, from) else Net.KirimSemua("Umumkan", text, from) end
	return true
end

-- Pakai topic yang sama dengan aplikasi Staff game (server lain menampilkannya lewat pipeline mereka).
function Integration.PublishGlobal(text, from)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(I.AnnounceTopic, { teks = text, dari = from, job = game.JobId })
	end)
	if not ok then Util.Debug("PublishAsync gagal (pengumuman hanya di server ini):", tostring(err)) end
	return ok
end

-- Samakan penghitung peringatan di data pemain SINAR RP (d.Staf.Warn) saat warn datang dari Discord/dashboard.
function Integration.RecordWarn(target)
	local Data = Integration.Active() and sinarServerModule("Data")
	if not Data or not Data.Ambil then return nil end
	local d = Data.Ambil(target)
	if not d then return nil end
	d.Staf = d.Staf or { Warn = 0 }
	d.Staf.Warn = (d.Staf.Warn or 0) + 1
	return d.Staf.Warn
end

-- Modul Ekonomi SINAR RP (satu-satunya pintu uang). nil jika SINAR RP tidak ada.
function Integration.Ekonomi()
	return Integration.Active() and sinarServerModule("Ekonomi") or nil
end

return Integration
