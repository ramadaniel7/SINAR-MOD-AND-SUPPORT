// npm run diagnose  -> memeriksa seluruh rantai & menjelaskan kenapa sebuah perintah masih "pending".
import { db, staffApi } from "./backend.js";
import { env } from "./env.js";

const ok = (m: string) => console.log(`  ✅ ${m}`);
const bad = (m: string) => console.log(`  ❌ ${m}`);
const info = (m: string) => console.log(`  ℹ️  ${m}`);
const age = (iso?: string | null) => (iso ? `${Math.round((Date.now() - Date.parse(iso)) / 1000)} dtk lalu` : "-");

async function main() {
  console.log("\n=== 1. Database & seed ===");
  const roles = await db.from("staff_roles").select("role_key");
  if (roles.error) bad(`Tidak bisa membaca database: ${roles.error.message} (cek SUPABASE_URL / SERVICE_ROLE_KEY, atau project sedang di-pause)`);
  else if ((roles.data?.length ?? 0) < 6) bad(`staff_roles baru ${roles.data?.length} baris. Jalankan supabase/seed.sql di SQL Editor.`);
  else ok(`staff_roles terisi (${roles.data!.length} role)`);
  const cfg = await db.from("anticheat_config").select("key");
  cfg.data?.length ? ok(`anticheat_config terisi (${cfg.data.length} kunci)`) : bad("anticheat_config kosong. Jalankan seed.sql.");

  console.log("\n=== 2. Edge Function ===");
  const probe = await staffApi("ping", {});
  if (probe.error === "unknown_kind") ok("staff-api ter-deploy dan STAFF_API_KEY cocok");
  else if (probe.error === "unauthorized") bad("staff-api menolak kunci: STAFF_API_KEY di .env ≠ secret di Supabase (supabase secrets set STAFF_API_KEY=...)");
  else if (probe.error === "server_misconfigured") bad("Secret STAFF_API_KEY belum di-set di Supabase");
  else bad(`staff-api tidak merespons wajar: ${probe.error}. Sudah di-deploy? (npx supabase functions deploy staff-api --no-verify-jwt)`);
  try {
    const r = await fetch(`${env.supabaseUrl}/functions/v1/roblox-gateway`, { method: "POST", body: "{}", headers: { "content-type": "application/json" } });
    const j: any = await r.json().catch(() => ({}));
    if (r.status === 401 && j.error === "unauthorized") ok("roblox-gateway ter-deploy (menolak request tanpa kunci, benar)");
    else if (r.status === 404) bad("roblox-gateway BELUM di-deploy (npx supabase functions deploy roblox-gateway --no-verify-jwt)");
    else if (j.error === "server_misconfigured") bad("Secret ROBLOX_GATEWAY_KEY belum di-set di Supabase");
    else info(`roblox-gateway merespons HTTP ${r.status} ${j.error ?? ""}`);
  } catch (e) { bad(`roblox-gateway tidak terjangkau: ${e}`); }

  console.log("\n=== 3. Server game Roblox ===");
  const sess = await db.from("sessions").select("job_id,last_seen_at,ended_at").order("last_seen_at", { ascending: false }).limit(1);
  const last = sess.data?.[0];
  if (!last) bad("Belum pernah ada kontak dari server Roblox. Server game harus berjalan dengan Config.Backend terisi & Allow HTTP Requests ON.");
  else if (Date.now() - Date.parse(last.last_seen_at) > 120_000) bad(`Kontak terakhir server game ${age(last.last_seen_at)} — tidak ada server yang sedang hidup. Ban/kick TIDAK akan dieksekusi sampai ada server game yang berjalan.`);
  else ok(`Server game aktif (kontak ${age(last.last_seen_at)})`);

  console.log("\n=== 4. Antrean perintah (10 terakhir) ===");
  const q = await db.from("command_queue").select("id,command_type,status,attempts,claimed_by,last_error,created_at,expires_at").order("created_at", { ascending: false }).limit(10);
  if (!q.data?.length) info("Antrean kosong (belum ada command masuk, atau sudah dibersihkan).");
  for (const c of q.data ?? []) {
    console.log(`  • ${c.id.slice(0, 8)} ${c.command_type.padEnd(16)} ${c.status.padEnd(10)} percobaan=${c.attempts} dibuat ${age(c.created_at)}${c.last_error ? "  error=" + c.last_error : ""}`);
  }
  const stuck = (q.data ?? []).filter((c) => c.status === "pending" && c.attempts === 0 && Date.now() - Date.parse(c.created_at) > 30_000);
  if (stuck.length) bad(`${stuck.length} perintah 'pending' belum pernah di-claim server game (>30 dtk). Penyebab umum: tidak ada server Roblox hidup, Backend.Key/Url salah di Config, HTTP belum di-enable, atau gateway versi lama (bug "[]" — deploy ulang roblox-gateway).`);

  console.log("\n=== 5. Tindakan moderasi (10 terakhir) ===");
  const a = await db.from("moderation_actions").select("id,action_type,status,execution_status,is_permanent,actor_id,approved_by_actor,execution_error,created_at").order("created_at", { ascending: false }).limit(10);
  for (const x of a.data ?? []) {
    console.log(`  • ${x.id.slice(0, 8)} ${x.action_type.padEnd(6)} ${x.is_permanent ? "PERMANEN" : "        "} status=${x.status.padEnd(16)} eksekusi=${x.execution_status} ${x.execution_error ? "error=" + x.execution_error : ""}`);
  }
  const waiting = (a.data ?? []).filter((x) => x.status === "pending_approval");
  if (waiting.length) info(`${waiting.length} ban PERMANEN menunggu persetujuan. Yang menyetujui harus ORANG LAIN (Management/Founder) lewat tombol di channel moderations-log atau dashboard. Pemohon tidak bisa menyetujui sendiri. Untuk uji coba solo, pakai ban sementara (1 hari).`);
  const queued = (a.data ?? []).filter((x) => x.status === "queued");
  if (queued.length) info(`${queued.length} tindakan 'queued' = sudah di antrean, menunggu server game mengeksekusi.`);
  console.log("");
}
main().catch((e) => { console.error("diagnose gagal:", e); process.exit(1); });
