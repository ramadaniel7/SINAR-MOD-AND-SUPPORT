# Integrasi SmartAC × SINAR RP (Fase 1)

Dibuat dari membaca `SINAR_RP_Fase1 (5).rbxmx` (83 script). **Semua ini hasil membaca kode, belum dijalankan di Studio.**

## 1. Penyesuaian yang sudah dilakukan

| Area | Apa yang disesuaikan |
|---|---|
| Daftar staf | **SmartAC punya roster sendiri** (`staff_roster.json`), terpisah dari `ConfigOverhead.STAFF_RANKS` SINAR RP. Fitur bawaan SINAR (aplikasi Staff, perintah chat lama) tetap memakai daftar SINAR. |
| Perintah playtest | `/setuang /setsaldo /kasihuang /kasihsaldo /cek /sembuh /wafat /cepat /lompat /tp /tarik /stat /vipon /vipoff /reset` diteruskan (lewat patch `PlaytestCmd`) ke pipeline SmartAC: roster, batas uang per role, helper sekali per pemain + cooldown, audit. |
| Notifikasi & banner | Warn/pengumuman dari Discord memakai `Net.Notif` dan remote `Umumkan` milik SINAR RP, jadi tampil di UI game lu. Pengumuman global memakai topic MessagingService **`SinarUmumkan`** yang sama dengan aplikasi Staff lu. |
| Penghitung warn | Warn dari Discord menaikkan `Data.Staf.Warn` di profil pemain, sama seperti aplikasi Staff. |
| Aplikasi Staff in-game | Warn/kick dari aplikasi Staff **dicatat ke riwayat moderasi** (muncul di Discord log, `/lookup`, dashboard) lewat patch kecil. |
| Perintah chat admin | `/uang /saldo /item /jam /kerja /resetktp /bintang /spawn /itemadmin /papan /pingsan` **diaudit** (siapa, perintah, argumen). |
| Teleport game | Penjara (Polisi) dan rumah sakit (EMS) diberi *grace* anti-cheat lewat patch. Respawn otomatis diberi grace. Kondisi `PlatformStand` (digendong, pingsan, diborgol) otomatis dikecualikan. |
| Spam remote | Pelanggaran rate limit di `Net` ikut dilaporkan ke SmartAC (kick 80x milik SINAR RP tetap jalan). |
| Ekonomi | Pemantau baca-saja atas Attribute `Uang`/`Saldo`: mencatat kenaikan ≥ Rp5.000.000 dalam 1 menit dan keadaan mustahil (NaN/negatif). Tidak menghukum. |
| Tampilan | Panel admin/report memakai warna & font `Config.Tema` SINAR RP. Di HP muncul tombol kecil (kiri-atas); di PC pakai F3 (report) / F4 (admin). |

## 2. Cara pasang (urutan)
1. Pasang SmartAC (`SmartAC_Server.rbxmx` → ServerScriptService, `SmartAC_Client.rbxmx` → StarterPlayerScripts). Hapus folder SmartAC versi lama jika ada.
2. **Simpan salinan place** (File → Save a Copy). Tutup semua tab script. Buka *View → Command Bar*, tempel isi `roblox/SinarRP_Patcher.lua`, Enter. Harus keluar `terpasang=10` (atau `sudah ada`). Kalau ada `GAGAL anchor tidak ketemu`, pakai patch manual di bagian 4.
3. Isi `SmartAC > Config > Backend` (Url & Key). **Staf cukup diisi di `ConfigOverhead.STAFF_RANKS`** (seperti biasa).
4. Play → Output harus menampilkan `[SmartAC] Aktif ... SINAR RP: terdeteksi`.

## 3. Temuan audit (dari membaca kode)
Secara umum kode lu **rapi**: uang hanya lewat `Ekonomi`, harga/stok/damage dari server, input divalidasi (`Util.Bulat/Teks`), ada rate limit per remote, jarak dicek (Toko/Pengamen). Hal yang patut diperhatikan:

1. **`/uang` & `/saldo` admin sampai Rp10.000.000.000, tanpa jejak** → sekarang diaudit. Siapa pun di Owner/Developer/Admin bisa mencetak uang; pertimbangkan batas per-perintah atau hanya Owner.
2. **`TransferMaks = 500.000.000` per transaksi** (pemilik KTP) → memudahkan memindahkan hasil eksploit/alt-farming dalam satu langkah. Pertimbangkan batas harian & cooldown. Pemantau `economy.large_gain` akan menandai penerima.
3. **Moderator**: di game hanya punya warn/kick, tapi di SmartAC (seed) Moderator bisa **ban sementara ≤ 7 hari**. Samakan kebijakan: ubah `moderation.ban.temp` di `supabase/seed.sql` atau `policy.ban_max_seconds_by_role` jadi `0`.
4. **Kendaraan "skateboard/hoverboard"**: dianggap aman hanya jika modelnya punya `Seat`/`VehicleSeat` (duduk = dikecualikan dari cek speed). Kalau tidak, bisa terkena `movement.speed`. **Uji di mode detect-only.**
5. **Menu `Admin_Aksi`** (spawn kendaraan/ambil item admin) belum diaudit; hanya perintah chat-nya yang diaudit.
6. **Teleport baru** yang ditambah developer RP nanti (rumah, interior, elevator, dll.) **wajib** memanggil `SmartAC.GrantMovementGrace(player, 3, "alasan")` sebelum memindahkan pemain.
7. Dua `Config.Debug` terpisah: SINAR RP (`ReplicatedStorage.SinarRP.Config`) dan SmartAC (`SmartAC.Config`). Matikan keduanya saat rilis.

## 4. Patch manual (kalau patcher gagal)
Tambahkan baris bertanda `-- SMARTAC` (tiap blok hanya menambah). Pola umum: `game:GetService("ServerScriptService"):FindFirstChild("SmartAC")`.

- **Net.lua** → setelah `c.salah = c.salah + 1` tambahkan: `do local f = game:GetService("ServerScriptService"):FindFirstChild("SmartAC"); local a = f and f:FindFirstChild("Api"); if a then pcall(function() require(a).Flag(player, "remote.spam", 2, 1, { remote = nama }) end) end end`
- **Polisi.lua** (fungsi `teleport`) → sebelum `char:PivotTo(...)`: sama seperti di atas dengan `require(a).GrantMovementGrace(player, 4, "polisi_teleport")`.
- **EMS.lua** (sebelum `player.Character:PivotTo(b.CFrame ...)`): `require(a).GrantMovementGrace(player, 4, "ems_teleport")`.
- **Staf.lua**: setelah `local Staf = {}` tambahkan fungsi `smartacRekam(admin, jenis, target, alasan)` yang memanggil `require(Api).RecordStaffAction(...)`; panggil `smartacRekam(player, "warn", target, alasan)` setelah `catat(... warn ...)` dan `smartacRekam(player, "kick", target, alasan)` setelah `catat(... kick ...)`.
- **Chat.lua** (di fungsi yang memanggil `fn(player, bagian)`): sebelum `fn(player, bagian)` panggil `require(Api).AuditCommand(player, nama:lower(), bagian)` bila `VIP.Admin(player)`.

Isi persisnya ada di `roblox/SinarRP_Patcher.lua`.

## 5. Belum teruji / perlu dicek di Studio
- Semua script baru & patch (tidak ada Studio di lingkungan penyusun; hanya anchor patch yang diverifikasi terhadap file lu: tiap anchor ketemu tepat 1x).
- `Humanoid:ApplyDescription`/`GetHumanoidDescriptionFromUserIdAsync` (copy avatar) — dipakai dengan `pcall`.
- Ambang deteksi (speed 16×1.6+8, teleport >80 stud & >500 stud/dtk, dsb.) belum dikalibrasi dengan gameplay nyata lu.

## 6. Catatan tentang Kohl's Admin (file referensi yang lu kirim)
- Tidak dipasang dan tidak disalin. Berkas itu tidak memuat lisensi terbuka, jadi SmartAC hanya meniru **pola interaksi** (prefix `;`, command bar bersaran, selector pemain, dashboard bertab, role bertingkat) dengan kode sendiri.
- Peringatan keamanan: `Loader` Kohl's secara default **memuat MainModule dari asset Roblox milik pihak lain (AUTO_UPDATE)** dan menyertakan interpreter Luau (`Loadstring`). Itu berarti kode jarak jauh berjalan di server lu. Jangan dipasang bersamaan dengan SmartAC/SINAR RP kecuali lu paham risikonya (matikan AutoUpdate).
- Staf SINAR RP yang dimasukkan: lihat README bagian 6c. Daftar hanya ada di `ConfigOverhead` (satu sumber).

## 7. Catatan: perintah admin SINAR lain yang BELUM diatur SmartAC
Perintah chat lama di `Chat.lua` (`/uang`, `/saldo`, `/item`, `/spawn`, ...) dan menu `Admin_Aksi` masih memakai `VIP.Admin` (daftar SINAR) tanpa batas nominal; hanya diaudit. Kalau `STAFF_RANKS` SINAR diisi, pemegangnya bisa mencetak uang tanpa batas Rp1 juta/500 ribu. Kirim `Chat.lua` & `Admin.lua` terbaru kalau mau diteruskan ke aturan yang sama (pola patch sama dengan PlaytestCmd).
