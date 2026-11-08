# Smart Anticheat & Admin Panel — SINAR RP

Anti-cheat server-side + admin in-game (command bar bergaya Kohl's) + tiket report Discord + dashboard web (GitHub Pages) + database Supabase.

> ⚠️ **Status jujur:** semua kode ditulis lengkap, tapi **belum pernah dijalankan** (penyusun tidak punya Studio/Postgres/Discord). Hanya dicek: sintaks TypeScript, XML `.rbxmx`, keseimbangan blok & path `require` Luau, dan pemindaian rahasia. Perkirakan beberapa perbaikan kecil saat pertama jalan — jadwalkan uji **sebelum hari rilis**. Lihat `docs/AUDIT.md`.

## 1. Peta channel Discord (sudah di-seed)

| Channel | ID | Fungsi |
|---|---|---|
| Incident Report | `1560408337441497118` | Laporan dari dalam game (pelapor, terlapor, server+posisi, pemeriksaan otomatis) + insiden anti-cheat. Staf saja |
| Moderations Log | `1560408305887612979` | Semua tindakan staf, tiket (buka/tutup/review), persetujuan ban, appeal, arsip bukti, DM gagal |
| Log (publik) | `1561411539758747688` | Info ban (**merah**) & kasus selesai (**hijau**) |
| Report Player via Discord | `1560409797147496568` | Tempat `/report`; tiket dibuat di kategori channel ini |
| Bot Commands | `1560409018487406632` | `/check`, `/robloxprofile`, `/appeal` untuk pemain |
| Player Banned | `1562268825297231882` | Pengumuman ban **permanen** (merah), alasan diisi staf di web |

## 2. Fitur bot

- **`/report`** (hanya di channel report): membuat channel tiket **privat** (hanya pelapor + staf; semua orang lain tidak bisa melihat), **langsung men-tag staf** (Management, Developer, Admin, Helper — **Founder tidak di-tag** tapi bisa melihat). Pelapor mengisi username (diverifikasi ke Roblox), jenis, detail, dan bukti gambar/video (maks 10). **Hanya staf yang bisa menutup tiket** (tombol *Tutup: Selesai / Ditolak* + keterangan). Saat ditutup: bukti diarsipkan ke Moderations Log (≤24 MB/file), kasus dicatat di Log publik (hijau), pelapor menerima **DM berisi keterangan lengkap staf penutup** + tombol review ⭐ (pengingat sekali setelah 24 jam), lalu **channel dihapus otomatis**. Jika DM tidak bisa dikirim, seluruh isi DM dikirim ke Moderations Log.
- **`/check`** (Bot Commands): statistik ban — total, permanen aktif, sementara aktif, 7 hari, kick, warn, 5 ban terbaru.
- **`/robloxprofile <username>`** (Bot Commands): profil Roblox (avatar, bio, tanggal akun, teman/pengikut, status).
- **Staf:** `/ban /kick /warn /unban /lookup /announce /health`. **Pemain:** `/appeal`.
- Staf dikenali dari **ID akun Discord di `staff_roster.json`** (bukan dari role Discord).
- Profil bot: bio, tag, dan status berputar otomatis. Badge **Supports Commands** muncul karena command didaftarkan global. (Auto-mod dimatikan sesuai permintaan.)

## 3. Pasang — Supabase

1. Buat project Supabase. Catat **Project Ref**. Di *Auth*: **matikan sign-up publik** (staf dibuat manual).
2. `npx supabase login` → `npx supabase link --project-ref <REF>` → `npx supabase db push` (7 migrasi).
3. SQL Editor: jalankan `supabase/seed.sql`, lalu `supabase/staff_roster.sql`. (Ulangi `staff_roster.sql` setiap `staff_roster.json` berubah.)
4. Secret (nilai acak panjang: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`):
   ```bash
   npx supabase secrets set ROBLOX_GATEWAY_KEY=<acak1> STAFF_API_KEY=<acak2> DASHBOARD_ORIGINS=https://USERNAME.github.io
   npx supabase functions deploy roblox-gateway --no-verify-jwt
   npx supabase functions deploy staff-api --no-verify-jwt
   npx supabase functions deploy dashboard-api --no-verify-jwt
   ```
   (`--no-verify-jwt` aman: ketiganya punya autentikasi sendiri; `dashboard-api` memverifikasi JWT login staf + wajib staf aktif.) Jika diminta Docker, tambahkan `--use-api`.
5. Akun login dashboard: Auth → Users → *Add user* (auto-confirm). Tautkan ke roster: tambahkan `"email": "..."` pada entri **Discord** orang itu di `staff_roster.json`, jalankan `python3 tools/build_all.py`, lalu jalankan ulang `staff_roster.sql`.

## 4. Pasang — Bot Discord

1. Developer Portal → Bot: aktifkan **Message Content Intent** (untuk membaca lampiran bukti). Matikan **Public Bot**.
2. Undang bot (scope `bot` + `applications.commands`), izin: *View Channels, Send Messages, Embed Links, Attach Files, Read Message History, **Manage Channels**, **Mention @everyone/@here/All Roles***.
3. Bot butuh akses ke 6 channel di atas dan *Manage Channels* di kategori channel report.
4. `cd bot && cp .env.example .env` → isi token, application id, guild id, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `STAFF_API_KEY` (= `<acak2>`). **`.env` hanya ada di server bot.**
5. `npm install && npm start` (Node ≥ 22.12). Diagnosis: `npm run diagnose`.

## 5. Pasang — Roblox

1. Game Settings → Security → **Allow HTTP Requests = ON**.
2. Hapus folder SmartAC lama (jika ada). `ServerScriptService` → *Insert from File* → `roblox/SmartAC_Server.rbxmx`; `StarterPlayer > StarterPlayerScripts` → `roblox/SmartAC_Client.rbxmx`.
3. Edit `SmartAC > Config > Backend`: `Url` (`https://<REF>.supabase.co/functions/v1/roblox-gateway`) dan `Key` (= `<acak1>`).
4. Simpan salinan place → tempel `roblox/SinarRP_Patcher.lua` di *Command Bar* (hasil `terpasang=8`).
5. Play → Output: `[SmartAC] Aktif ...`. **Report in-game:** `F3` (atau tombol Report di HP) → masuk **Incident Report** dengan pelapor, terlapor, server (JobId), posisi, dan pemeriksaan otomatis. Staf bisa pindah ke server itu: `;goserver <JobId>` (tautan "Masuk server" di embed kadang tidak akurat — Roblox kadang mengabaikan `gameInstanceId`).

## 6. Pasang — Dashboard (GitHub Pages)

Dashboard **statis**: tidak ada server, **tidak ada kunci rahasia, tidak memakai `NEXT_PUBLIC_*`**. Satu-satunya konfigurasi: `dashboard/public/config.js` (URL Supabase + kunci **anon/publishable** — kunci ini memang dirancang publik dan dilindungi RLS). Dashboard menolak berjalan, dan build GitHub gagal, jika ada kunci rahasia di file itu. Aksi sensitif memakai **JWT login staf** ke `dashboard-api`, bukan kunci bersama.

1. Isi `dashboard/public/config.js` (`supabaseUrl`, `supabaseAnonKey`, opsional `appName`, `accent`).
2. Push ke GitHub (branch `main`). Repo → Settings → Pages → Source: **GitHub Actions**.
3. Workflow `.github/workflows/pages.yml` membangun & men-deploy otomatis. URL: `https://USERNAME.github.io/NAMA-REPO/`.
4. Isi secret `DASHBOARD_ORIGINS` di Supabase dengan origin itu (`https://USERNAME.github.io`, tanpa path).
5. Fitur: ringkasan, report (dengan pemeriksaan otomatis & aksi), insiden anti-cheat, moderasi (**buat tindakan**, setujui ban permanen, **edit alasan publik** ban sebelum disetujui), pemain, audit log. Tampilan kaca dengan latar 3D, logo perisai 3D, dan **favicon beranimasi**.

> Repo publik berarti **semua kode terlihat**; `staff_roster.json` berisi ID staf — pertimbangkan repo **privat** (GitHub Pages privat butuh plan berbayar) atau pisahkan folder `dashboard/` ke repo publik tersendiri.

## 7. Staf & role

Satu sumber: **`staff_roster.json`** → `python3 tools/build_all.py` (Roster.lua + staff_roster.sql + .rbxmx).

| Role | Roblox | Web & Discord |
|---|---|---|
| Founder, Management, Developer | semua akses | semua akses |
| Admin | semua akses (uang maks Rp1.000.000/perintah) | terbatas (tanpa audit log, konfigurasi, kelola staf, ban permanen, announce global, identitas pelapor) |
| Helper | warn, kick, ban 1 hari, announce server; uang maks Rp500.000 (sekali per pemain, cooldown 1 menit); tanpa teleport & VIP | warn, kick, ban 1 hari, announce server, menutup tiket |

`;shutdown` hanya **Founder & Developer**. Staf **kebal** dari anti-cheat (`Config.StaffImmune`). Anti-cheat **dikunci detect-only** (`LockDetectOnly`): hanya mencatat & melapor, tidak ada hukuman otomatis.

## 8. Command in-game (`;` buka command bar, `F4` dashboard)

`help players staff whoami serverinfo info lookup bans reports logs` · `warn kick ban unban` · `to bring tp back up down tpos goserver` · `fly noclip view unview esp copyavatar resetavatar invisible visible god ungod` · `speed jump normal heal health respawn freeze unfreeze sit kill` · SINAR: `setuang setsaldo kasihuang kasihsaldo cek sembuh wafat cepat lompat stat reset vipon vipoff` · `grace exempt slock unslock shutdown` · `announce gannounce notify`. Selector: `me all others random admins nonadmins` atau nama/UserId.

## 9. Whitelist gerakan sah

Alat/kendaraan/lantai yang boleh cepat atau melayang: daftarkan nama di `Config.AntiCheat.Whitelist`, atau tandai dengan Attribute/Tag `SmartACWhitelist = true`, atau `SmartAC.GrantMovementGrace(player, 3, "alasan")` dari script game. Kendaraan yang diduduki otomatis aman. Cek *teleport mustahil* tetap berjalan.

## 10. Checklist uji

1. `npm run diagnose` hijau. `/health` menampilkan embed.
2. `/report` di channel report dengan akun non-staf → channel privat muncul, staf ter-tag, akun non-staf lain **tidak** melihat channel → isi form + 1 gambar → kirim → staf menutup (*Selesai*) → DM + review diterima, bukti diarsipkan di Moderations Log, channel terhapus, embed hijau di Log publik. Ulangi dengan DM pelapor dimatikan → isi DM masuk Moderations Log.
3. Report in-game (`F3`) → embed di Incident Report lengkap dengan JobId & posisi.
4. `/ban` 1 hari (akun alt) → embed merah di Log; ban permanen → persetujuan orang lain → embed merah di Player Banned.
5. `/check` dan `/robloxprofile` di Bot Commands (dan ditolak di channel lain untuk non-staf).
6. Dashboard: login, buka report, jalankan pemeriksaan, buat tindakan, edit alasan ban permanen.

## 11. Troubleshooting

| Gejala | Cek |
|---|---|
| Perintah `/ban` "pending" | `npm run diagnose`. Permanen = menunggu orang lain; `pending` di antrean = tidak ada server game hidup / Backend.Key salah / gateway lama |
| Tiket gagal dibuat | bot butuh *Manage Channels* di kategori report |
| Bukti tidak terbaca | *Message Content Intent* belum aktif |
| Dashboard "Konfigurasi diperlukan" | isi `public/config.js` |
| Dashboard login ok tapi "belum terdaftar" | jalankan `staff_roster.sql` + tautkan `email` |
| Web: error CORS | secret `DASHBOARD_ORIGINS` harus persis origin Pages (tanpa path/slash akhir) |
| Slash command tidak muncul | `DISCORD_GUILD_ID` salah / scope `applications.commands` |

## 12. Keamanan

- Rahasia **hanya** di: `bot/.env` (server bot), secret Supabase, dan `SmartAC > Config` (server Roblox). **Tidak ada** di web/GitHub. `service_role` jangan pernah di luar bot/Supabase.
- Rotasi kunci jika bocor. Aktifkan 2FA untuk semua staf (staf kebal anti-cheat).
- Dependabot memperbarui dependency & Actions mingguan; jalankan `npm audit` berkala.
- Backup: `npx supabase db dump -f backup.sql`.
