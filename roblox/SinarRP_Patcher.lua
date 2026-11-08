--[[
  SmartAC x SINAR RP — PEMASANG PATCH (tempel di Studio: View > Command Bar, lalu Enter).
  PENTING: lakukan saat TIDAK sedang Play, TUTUP semua tab script yang terbuka, dan SIMPAN salinan place dulu
  (File > Save a Copy). Aman dijalankan berulang (yang sudah terpasang dilewati; anchor tidak ketemu = tidak diubah).
  Setiap patch hanya MENAMBAH baris bertanda "-- SMARTAC" dan tidak menghapus kode SINAR RP.
]]
local SSS = game:GetService("ServerScriptService")
local modul = SSS:FindFirstChild("SinarRP") and SSS.SinarRP:FindFirstChild("Modul")
if not modul then error("ServerScriptService.SinarRP.Modul tidak ditemukan. Pasang SINAR RP dulu.") end

local PATCHES = {
	{ modul = "Net", label = "Laporkan spam remote ke SmartAC",
	  find = "\t\tc.salah = c.salah + 1",
	  replace = "\t\tc.salah = c.salah + 1\n\t\tdo local f = game:GetService(\"ServerScriptService\"):FindFirstChild(\"SmartAC\"); local a = f and f:FindFirstChild(\"Api\"); if a then pcall(function() require(a).Flag(player, \"remote.spam\", 2, 1, { remote = nama }) end) end end -- SMARTAC" },
	{ modul = "Polisi", label = "Grace teleport penjara",
	  find = "\t\tchar:PivotTo(bagian.CFrame + Vector3.new(0, 4, 0))",
	  replace = "\t\tdo local f = game:GetService(\"ServerScriptService\"):FindFirstChild(\"SmartAC\"); local a = f and f:FindFirstChild(\"Api\"); if a then pcall(function() require(a).GrantMovementGrace(player, 4, \"polisi_teleport\") end) end end -- SMARTAC\n\t\tchar:PivotTo(bagian.CFrame + Vector3.new(0, 4, 0))" },
	{ modul = "EMS", label = "Grace teleport rumah sakit",
	  find = "\t\tplayer.Character:PivotTo(b.CFrame + Vector3.new(0, 4, 0))",
	  replace = "\t\tdo local f = game:GetService(\"ServerScriptService\"):FindFirstChild(\"SmartAC\"); local a = f and f:FindFirstChild(\"Api\"); if a then pcall(function() require(a).GrantMovementGrace(player, 4, \"ems_teleport\") end) end end -- SMARTAC\n\t\tplayer.Character:PivotTo(b.CFrame + Vector3.new(0, 4, 0))" },
	{ modul = "Staf", label = "Helper rekam tindakan staf",
	  find = "local Staf = {}",
	  replace = "local Staf = {}\nlocal function smartacRekam(admin, jenis, target, alasan) -- SMARTAC\n\tlocal f = game:GetService(\"ServerScriptService\"):FindFirstChild(\"SmartAC\")\n\tlocal a = f and f:FindFirstChild(\"Api\")\n\tif a then pcall(function() require(a).RecordStaffAction(admin, jenis, target, alasan) end) end\nend" },
	{ modul = "Staf", label = "Rekam warn",
	  find = "\t\tcatat(player.Name .. \" warn \" .. target.Name .. \" (#\" .. d.Staf.Warn .. \"): \" .. alasan)",
	  replace = "\t\tcatat(player.Name .. \" warn \" .. target.Name .. \" (#\" .. d.Staf.Warn .. \"): \" .. alasan)\n\t\tsmartacRekam(player, \"warn\", target, alasan) -- SMARTAC" },
	{ modul = "Staf", label = "Rekam kick",
	  find = "\t\tcatat(player.Name .. \" kick \" .. target.Name .. \": \" .. alasan)",
	  replace = "\t\tcatat(player.Name .. \" kick \" .. target.Name .. \": \" .. alasan)\n\t\tsmartacRekam(player, \"kick\", target, alasan) -- SMARTAC" },
	{ modul = "Chat", label = "Audit perintah admin",
	  find = "\tif fn then fn(player, bagian) end",
	  replace = "\tif fn then\n\t\tdo -- SMARTAC: audit perintah admin\n\t\t\tlocal f = game:GetService(\"ServerScriptService\"):FindFirstChild(\"SmartAC\")\n\t\t\tlocal a = f and f:FindFirstChild(\"Api\")\n\t\t\tif a and VIP.Admin(player) then pcall(function() require(a).AuditCommand(player, nama:lower(), bagian) end) end\n\t\tend\n\t\tfn(player, bagian)\n\tend" },
	{ modul = "PlaytestCmd", search = "local perintahPlaytest = {}", label = "Perintah playtest (/setuang, /kasihuang, /tp, ...) diteruskan ke SmartAC",
	  find = "\t\tperintah[nama] = perintah[nama] or fn",
	  replace = "\t\tperintah[nama] = perintah[nama] or function(player, args)\n\t\t\tlocal f = game:GetService(\"ServerScriptService\"):FindFirstChild(\"SmartAC\") -- SMARTAC: roster + batas role\n\t\t\tlocal a = f and f:FindFirstChild(\"Api\")\n\t\t\tif a then pcall(function() require(a).RunSinarCommand(player, nama, args) end) return end\n\t\t\tfn(player, args)\n\t\tend" },
}

local dipasang, dilewati, gagal = 0, 0, 0
for _, p in ipairs(PATCHES) do
	local m
	if p.search then
		-- cari ModuleScript lewat isinya (nama modul bisa berbeda di tiap versi SINAR RP)
		for _, d in ipairs(SSS.SinarRP:GetDescendants()) do
			if d:IsA("ModuleScript") and string.find(d.Source, p.search, 1, true) then m = d break end
		end
	elseif p.root == "ReplicatedStorage" then
		local rs = game:GetService("ReplicatedStorage"):FindFirstChild("SinarRP")
		m = rs and rs:FindFirstChild(p.modul)
	else
		m = modul:FindFirstChild(p.modul)
	end
	if not m then
		warn("[Patch] GAGAL  modul '" .. p.modul .. "' tidak ada: " .. p.label)
		gagal += 1
	else
		local src = m.Source
		if string.find(src, p.replace, 1, true) then
			print("[Patch] sudah terpasang: " .. p.modul .. " — " .. p.label)
			dilewati += 1
		else
			local a, b = string.find(src, p.find, 1, true)
			if not a then
				warn("[Patch] GAGAL  anchor tidak ketemu di " .. p.modul .. " (" .. p.label .. "). Script mungkin sudah diubah: pasang manual (lihat docs/INTEGRASI_SINAR_RP.md).")
				gagal += 1
			else
				m.Source = string.sub(src, 1, a - 1) .. p.replace .. string.sub(src, b + 1)
				print("[Patch] terpasang: " .. p.modul .. " — " .. p.label)
				dipasang += 1
			end
		end
	end
end
print(string.format("[Patch] selesai. terpasang=%d, sudah ada=%d, gagal=%d", dipasang, dilewati, gagal))
