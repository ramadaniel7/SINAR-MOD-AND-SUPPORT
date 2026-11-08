# Laporan audit & perbaikan

Audit dilakukan dengan **membaca kode** dan pemeriksaan otomatis sederhana. **Tidak ada yang dijalankan** (tidak ada Studio/Postgres/Discord/akses npm). Yang berhasil diperiksa otomatis: sintaks TypeScript (semua file bot, Edge Function, dashboard — tanpa error sintaks), keseimbangan blok/kurung dan resolusi `require()` seluruh script Luau, validitas XML `.rbxmx`, dan pemindaian kunci rahasia di seluruh source (tidak ada yang ditemukan). **Type-check TypeScript (terhadap discord.js/supabase-js) dan parser Luau asli belum bisa dijalankan.**

## Bug / risiko yang ditemukan dan sudah diperbaiki
| # | Temuan | Perbaikan |
|---|---|---|
| 1 | Roblox mengirim tabel kosong sebagai `[]`; gateway menolak (HTTP 400) → `claim` tidak pernah berhasil → ban nyangkut `pending` tanpa log | Gateway menerima `[]` sebagai `{}`; Roblox kini mencetak penolakan backend (tidak lagi gagal diam-diam) |
| 2 | Dashboard lama memakai route server + `STAFF_API_KEY`: tidak mungkin di GitHub Pages dan berisiko bocor | Ditulis ulang sebagai SPA statis; aksi sensitif lewat Edge Function `dashboard-api` dengan **JWT login staf** (tanpa kunci bersama); `config.js` menolak kunci rahasia; build CI gagal bila ada |
| 3 | Satu bagian notifier yang error menghentikan semua notifikasi lain | Tiap bagian dibungkus `safe()` |
| 4 | Cache tak berbatas di bot (cooldown, cache peran staf, cache avatar) → kebocoran memori perlahan | Sapuan berkala + batas ukuran |
| 5 | Bukti tiket hilang bila channel dihapus | Bukti diarsipkan ke Moderations Log sebelum penghapusan (≤24 MB/file) |
| 6 | Pemetaan channel lama salah (channel report dipakai untuk fungsi lain) | Pemetaan 6 channel baru di seed + pembaruan paksa untuk DB lama |
| 7 | Reporter bisa membatalkan tiket sendiri; tag staf hanya setelah dikirim | Sesuai spesifikasi baru: hanya staf yang menutup; staf di-tag saat tiket dibuat |
| 8 | Izin menutup tiket tidak ada untuk Helper (izin report hanya admin ke atas) | Izin baru `tickets.close` untuk semua role staf |
| 9 | Aksi in-game memeriksa izin DB yang bertabrakan dengan matriks Roblox (Admin "semua" vs web "terbatas") | Aktor in-game diotorisasi matriks server Roblox; batas durasi per role & hierarki tetap dipaksa backend |
| 10 | `;reset` bentrok dengan `/reset` SINAR | Fungsi lama diganti nama `;normal` |

## Risiko yang masih ada (tidak bisa dihilangkan dari kode)
- **Kunci anon Supabase tetap terlihat di web** — itu memang dirancang publik; keamanannya bergantung pada **RLS** + JWT. Jangan pernah mengisi kunci service role di web.
- Repo publik = source (termasuk `staff_roster.json`) terlihat semua orang.
- **Ulasan "wajib"** tidak bisa dipaksa secara teknis: bot mengirim tombol bintang + 1 pengingat setelah 24 jam.
- Link "Masuk server" di embed kadang tidak akurat (Roblox mengabaikan `gameInstanceId` pada URL https); gunakan `;goserver <JobId>` di game.
- Staf kebal anti-cheat → akun staf yang diretas tidak terdeteksi. Wajibkan 2FA.
- Ambang deteksi anti-cheat belum dikalibrasi; mode dikunci detect-only.
- Versi dependency diset ke rentang `^` major terbaru yang diketahui saat penulisan (discord.js 14.26, supabase-js 2.x, Next 16, React 19, TypeScript 5.9, Node ≥ 22.12) — **tidak bisa diverifikasi lewat npm di sini**; Dependabot memperbarui mingguan.
