// Pemeriksaan otomatis atas sebuah report: mencocokkan klaim dengan data yang kita punya (sesi, sinyal anti-cheat, riwayat).
// HASIL INI ADALAH PETUNJUK untuk staf, BUKAN vonis. Report tetap harus diverifikasi manual dengan bukti.
import { db } from "./core.ts";

export type Check = { label: string; ok: boolean | null; detail: string };
export type Verification = { level: "tinggi" | "sedang" | "rendah"; score: number; checks: Check[] };

export async function verifyReport(reportId: string): Promise<Verification | null> {
  const { data: r } = await db.from("reports").select("id,reported_user_id,category,created_at,job_id,source").eq("id", reportId).maybeSingle();
  if (!r) return null;
  const { data: priv } = await db.from("report_private").select("reporter_user_id,reporter_discord_id").eq("report_id", reportId).maybeSingle();
  const at = new Date(r.created_at).getTime();
  const iso = (ms: number) => new Date(ms).toISOString();
  const checks: Check[] = [];
  let score = 0;

  // 1. Apakah terlapor benar-benar ada di game pada saat itu?
  if (r.source === "ingame") {
    const { data: s } = await db.from("sessions").select("job_id")
      .eq("roblox_user_id", r.reported_user_id).lte("started_at", r.created_at)
      .or(`ended_at.is.null,ended_at.gte.${iso(at - 120_000)}`).limit(5);
    const present = (s ?? []).some((x) => !r.job_id || x.job_id === r.job_id);
    checks.push({ label: "Terlapor ada di server saat laporan", ok: present, detail: present ? "sesi cocok" : "tidak ada sesi yang cocok" });
    score += present ? 2 : -2;
  } else {
    const { count } = await db.from("sessions").select("id", { count: "exact", head: true })
      .eq("roblox_user_id", r.reported_user_id).gte("started_at", iso(at - 86_400_000));
    checks.push({ label: "Terlapor aktif di game 24 jam sebelum laporan", ok: (count ?? 0) > 0, detail: `${count ?? 0} sesi` });
    score += (count ?? 0) > 0 ? 1 : -1;
  }

  // 2. Sinyal anti-cheat (hanya relevan untuk laporan cheat)
  const { data: vs } = await db.from("violations").select("detector,severity")
    .eq("roblox_user_id", r.reported_user_id).gte("created_at", iso(at - 86_400_000)).lte("created_at", iso(at + 600_000)).limit(100);
  const strong = (vs ?? []).filter((v) => v.severity >= 2);
  if (r.category === "cheating") {
    const kinds = [...new Set(strong.map((v) => v.detector))].slice(0, 4).join(", ");
    checks.push({ label: "Sinyal anti-cheat 24 jam terakhir", ok: strong.length > 0, detail: strong.length ? `${strong.length} sinyal (${kinds})` : "tidak ada sinyal tercatat" });
    score += strong.length > 0 ? 3 : -1;
  } else {
    checks.push({ label: "Sinyal anti-cheat", ok: null, detail: "tidak relevan untuk kategori ini; butuh bukti manual" });
  }

  // 3. Laporan lain terhadap pemain yang sama (7 hari)
  const { count: others } = await db.from("reports").select("id", { count: "exact", head: true })
    .eq("reported_user_id", r.reported_user_id).neq("id", reportId).gte("created_at", iso(at - 7 * 86_400_000));
  checks.push({ label: "Laporan lain terhadap pemain ini (7 hari)", ok: (others ?? 0) > 0 ? true : null, detail: `${others ?? 0} laporan` });
  score += (others ?? 0) >= 2 ? 2 : (others ?? 0) === 1 ? 1 : 0;

  // 4. Riwayat tindakan sebelumnya
  const { count: prior } = await db.from("moderation_actions").select("id", { count: "exact", head: true })
    .eq("target_user_id", r.reported_user_id).eq("status", "executed").in("action_type", ["warn", "kick", "ban"]);
  checks.push({ label: "Riwayat tindakan sebelumnya", ok: (prior ?? 0) > 0 ? true : null, detail: `${prior ?? 0} tindakan` });
  score += (prior ?? 0) > 0 ? 1 : 0;

  // 5. Rekam jejak pelapor
  const col = priv?.reporter_user_id ? (["reporter_user_id", priv.reporter_user_id] as const)
    : priv?.reporter_discord_id ? (["reporter_discord_id", priv.reporter_discord_id] as const) : null;
  if (col) {
    const { data: mine } = await db.from("report_private").select("report_id").eq(col[0], col[1]).neq("report_id", reportId).limit(50);
    const ids = (mine ?? []).map((x) => x.report_id);
    if (ids.length) {
      const { data: rs } = await db.from("reports").select("status").in("id", ids);
      const resolved = (rs ?? []).filter((x) => x.status === "resolved").length;
      const dismissed = (rs ?? []).filter((x) => x.status === "dismissed").length;
      if (resolved + dismissed >= 3) {
        const bad = dismissed / (resolved + dismissed) >= 0.7;
        checks.push({ label: "Rekam jejak pelapor", ok: !bad, detail: `${resolved} terbukti, ${dismissed} ditolak` });
        score += bad ? -2 : resolved / (resolved + dismissed) >= 0.5 ? 1 : 0;
      }
    }
  }

  return { level: score >= 4 ? "tinggi" : score >= 2 ? "sedang" : "rendah", score, checks };
}

export const formatVerification = (v: Verification): string =>
  v.checks.map((c) => `${c.ok === true ? "✅" : c.ok === false ? "❌" : "➖"} ${c.label}: ${c.detail}`).join("\n");
