// Notifikasi Discord (polling DB tiap 8 detik). Pemetaan channel dari config `discord.channels`:
//   incident_report : laporan dari dalam game + insiden anti-cheat (staf)         moderation_log : semua tindakan staf, tiket, persetujuan
//   public_log      : info publik (ban merah, kasus selesai hijau)                player_banned  : pengumuman ban PERMANEN (merah)
import {
  ActionRowBuilder, ButtonBuilder, ButtonInteraction, ButtonStyle, Client, EmbedBuilder, ModalBuilder, ModalSubmitInteraction,
  TextInputBuilder, TextInputStyle,
} from "discord.js";
import { channels, db, roleCan, staffApi, staffRoleOfUser } from "./backend.js";
import { errText } from "./commands.js";
import { headshot, joinUrl, profileUrl } from "./roblox.js";
import { clip, COLOR, ts } from "./ui.js";

const MIN_NOTIFY_SEVERITY = 2; // severity 1 (mis. remote.spam, noclip heuristik) hanya di dashboard agar channel tidak banjir
const CATEGORY: Record<string, string> = { cheating: "Cheat / Exploit", fail_roleplay: "Fail Roleplay", harassment: "Pelecehan", other: "Lainnya" };

async function names(ids: number[]): Promise<Map<number, string>> {
  const m = new Map<number, string>();
  const uniq = [...new Set(ids.filter(Boolean))];
  if (!uniq.length) return m;
  const { data } = await db.from("players").select("roblox_user_id,username").in("roblox_user_id", uniq);
  for (const p of data ?? []) if (p.username !== "unknown") m.set(p.roblox_user_id, p.username);
  return m;
}
const who = (m: Map<number, string>, id: number, fallback?: string) => {
  const n = m.get(id) ?? fallback;
  return n ? `[${n}](${profileUrl(id)}) (${id})` : `ID ${id}`;
};
const dur = (a: any) => (a.is_permanent ? "Permanen" : a.duration_seconds ? `${Math.round(a.duration_seconds / 86400)} hari` : "-");
const row = (...b: ButtonBuilder[]) => new ActionRowBuilder<ButtonBuilder>().addComponents(...b);
const btn = (id: string, text: string, style: ButtonStyle) => new ButtonBuilder().setCustomId(id).setLabel(text).setStyle(style);

async function textChannel(client: Client, id: string) {
  const c = await client.channels.fetch(id).catch(() => null);
  return c && c.isTextBased() && "send" in c ? (c as any) : null;
}
async function safe(name: string, fn: () => Promise<void>) {
  try { await fn(); } catch (e) { console.error(`[notifier] ${name}:`, e instanceof Error ? e.message : e); }
}
const actionColor = (t: string, ok = true) => (!ok ? COLOR.red : t === "ban" ? COLOR.red : t === "unban" ? COLOR.green : t === "kick" ? COLOR.orange : COLOR.yellow);

export async function pollOnce(client: Client) {
  const chan = await channels();
  const modLog = await textChannel(client, chan.moderation_log);
  const pubLog = await textChannel(client, chan.public_log);
  const incident = await textChannel(client, chan.incident_report);
  const banned = await textChannel(client, chan.player_banned);

  // ---- 1. Report dari DALAM GAME -> Incident Report (staf): pelapor, terlapor, server, pemeriksaan otomatis ----
  await safe("report-ingame", async () => {
    if (!incident) return;
    const { data: reports } = await db.from("reports").select("id,report_code,reported_user_id,category,description,place_id,job_id,context,created_at")
      .is("discord_message_id", null).eq("status", "open").eq("source", "ingame").order("created_at").limit(5);
    if (!reports?.length) return;
    const { data: privs } = await db.from("report_private").select("report_id,reporter_user_id").in("report_id", reports.map((r) => r.id));
    const reporterOf = new Map((privs ?? []).map((p) => [p.report_id, p.reporter_user_id as number]));
    const n = await names([...reports.map((r) => r.reported_user_id), ...[...reporterOf.values()]]);
    for (const r of reports) {
      const c: any = r.context ?? {};
      const reporterId = reporterOf.get(r.id) ?? 0;
      const v = await staffApi("verify_report", { report_id: r.id });
      const pos = (p: any) => (Array.isArray(p) ? `${p[0]}, ${p[1]}, ${p[2]}` : "-");
      const e = new EmbedBuilder().setTitle(`🚩 Laporan dari dalam game • ${r.report_code}`).setColor(COLOR.orange).addFields(
        { name: "Pelapor", value: reporterId ? who(n, reporterId, c.reporter_name) : "-", inline: true },
        { name: "Terlapor", value: who(n, r.reported_user_id, c.reported_name), inline: true },
        { name: "Kategori", value: CATEGORY[r.category] ?? r.category, inline: true },
        { name: "Deskripsi", value: clip(r.description, 900) },
        { name: "📍 Server & posisi", value: [
          `Server: \`${clip(r.job_id ?? "-", 40)}\``, `Pemain: ${c.players ?? "?"}/${c.max_players ?? "?"} · Versi ${c.place_version ?? "?"}`,
          `Posisi terlapor: ${pos(c.reported_pos)}`, `Posisi pelapor: ${pos(c.reporter_pos)}`,
          r.job_id ? `Masuk via game: \`;goserver ${r.job_id}\`` : "",
        ].filter(Boolean).join("\n") },
        { name: "🔎 Pemeriksaan otomatis (petunjuk, bukan vonis)", value: v.ok ? `**Kecocokan: ${String(v.level).toUpperCase()}** (skor ${v.score})\n${clip(v.text, 900)}` : "Pemeriksaan otomatis gagal." },
      ).setTimestamp(new Date(r.created_at)).setFooter({ text: "Report ≠ bukti. Verifikasi sebelum menindak." });
      const rows = [row(btn(`rep:review:${r.id}`, "Tinjau", ButtonStyle.Primary), btn(`rep:resolve:${r.id}`, "Selesai", ButtonStyle.Success), btn(`rep:dismiss:${r.id}`, "Tolak", ButtonStyle.Secondary))];
      if (r.job_id && r.place_id) rows.push(row(new ButtonBuilder().setLabel("🎮 Masuk server (kadang tidak akurat)").setStyle(ButtonStyle.Link).setURL(joinUrl(r.place_id, r.job_id))));
      const msg = await incident.send({ embeds: [e], components: rows }).catch((err: Error) => { console.error("[notifier] kirim report:", err.message); return null; });
      if (msg) await db.from("reports").update({ discord_message_id: msg.id }).eq("id", r.id);
    }
  });

  // ---- 2. Insiden anti-cheat (detect-only: hanya melapor) -> Incident Report; digabung per pemain+detector ----
  await safe("anticheat", async () => {
    if (!incident) return;
    const { data: viol } = await db.from("violations").select("id,roblox_user_id,detector,severity,score,mode,evidence,created_at,job_id,place_id")
      .is("discord_notified_at", null).gte("severity", MIN_NOTIFY_SEVERITY).order("created_at").limit(40);
    const groups = new Map<string, any[]>();
    for (const v of viol ?? []) {
      const k = `${v.roblox_user_id}:${v.detector}`;
      const a = groups.get(k);
      if (a) a.push(v); else groups.set(k, [v]);
    }
    const vn = await names((viol ?? []).map((v) => v.roblox_user_id));
    let sent = 0;
    for (const rows of groups.values()) {
      if (sent >= 6) break;
      const last = rows[rows.length - 1];
      const maxSev = Math.max(...rows.map((r) => r.severity));
      const e = new EmbedBuilder().setTitle(`🚨 Anti-Cheat: ${last.detector}`).setColor(maxSev >= 4 ? COLOR.red : maxSev === 3 ? COLOR.orange : COLOR.yellow).addFields(
        { name: "Pemain", value: who(vn, last.roblox_user_id), inline: true },
        { name: "Severity / Skor", value: `${maxSev} / ${last.score}`, inline: true },
        { name: "Kejadian", value: `${rows.length}× (sejak ${ts(rows[0].created_at, "R")})`, inline: true },
        { name: "Server", value: last.job_id ? `\`${clip(last.job_id, 40)}\`\n\`;goserver ${last.job_id}\`` : "-" },
        { name: "Mode", value: last.mode === "detect_only" ? "detect-only — **hanya mencatat, tidak ada hukuman**" : String(last.mode), inline: true },
        { name: "Bukti (kejadian terakhir)", value: "```json\n" + clip(JSON.stringify(last.evidence), 800) + "\n```" },
      ).setTimestamp(new Date(last.created_at)).setFooter({ text: "Sinyal otomatis bukan vonis. Staf yang memutuskan." });
      const comps = last.job_id && last.place_id ? [row(new ButtonBuilder().setLabel("🎮 Masuk server (kadang tidak akurat)").setStyle(ButtonStyle.Link).setURL(joinUrl(last.place_id, last.job_id)))] : [];
      const ok = await incident.send({ embeds: [e], components: comps }).then(() => true).catch((err: Error) => { console.error("[notifier] kirim insiden:", err.message); return false; });
      if (ok) { await db.from("violations").update({ discord_notified_at: new Date().toISOString() }).in("id", rows.map((r) => r.id)); sent++; }
    }
  });

  // ---- 3. Ban permanen menunggu orang kedua -> Moderations Log ----
  await safe("approvals", async () => {
    if (!modLog) return;
    const { data: pend } = await db.from("moderation_actions").select("id,target_user_id,public_reason,actor_id,actor_type,actor_role_key,created_at")
      .eq("status", "pending_approval").is("discord_request_message_id", null).order("created_at").limit(5);
    const pn = await names((pend ?? []).map((a) => a.target_user_id));
    for (const a of pend ?? []) {
      const { data: priv } = await db.from("moderation_action_private").select("private_reason").eq("action_id", a.id).maybeSingle();
      const e = new EmbedBuilder().setTitle("⏳ Ban PERMANEN menunggu persetujuan").setColor(COLOR.red).addFields(
        { name: "Pemain", value: who(pn, a.target_user_id), inline: true },
        { name: "Diminta oleh", value: `${a.actor_type} · ${a.actor_id} (${a.actor_role_key ?? "-"})`, inline: true },
        { name: "Alasan publik (tampil di pengumuman ban)", value: clip(a.public_reason, 400) },
        { name: "Catatan privat", value: clip(priv?.private_reason ?? "-", 900) },
      ).setTimestamp(new Date(a.created_at)).setFooter({ text: "Harus disetujui orang LAIN (Management/Founder). Alasan publik bisa diedit di dashboard web sebelum disetujui." });
      const msg = await modLog.send({ embeds: [e], components: [row(btn(`act:approve:${a.id}`, "Setujui", ButtonStyle.Danger), btn(`act:reject:${a.id}`, "Tolak", ButtonStyle.Secondary))] }).catch(() => null);
      if (msg) await db.from("moderation_actions").update({ discord_request_message_id: msg.id }).eq("id", a.id);
    }
  });

  // ---- 4. Hasil tindakan: Moderations Log (lengkap), Log publik (ban MERAH), Player Banned (ban permanen MERAH) ----
  await safe("actions", async () => {
    if (!modLog) return;
    const { data: done } = await db.from("moderation_actions")
      .select("id,target_user_id,action_type,status,duration_seconds,is_permanent,public_reason,actor_id,actor_type,source,execution_error,report_id,executed_at,banned_notice_at")
      .is("discord_notified_at", null).in("status", ["executed", "failed", "expired", "rejected"]).order("updated_at").limit(5);
    const dn = await names((done ?? []).map((a) => a.target_user_id));
    for (const a of done ?? []) {
      const { data: priv } = await db.from("moderation_action_private").select("private_reason").eq("action_id", a.id).maybeSingle();
      const { data: rep } = a.report_id ? await db.from("reports").select("report_code").eq("id", a.report_id).maybeSingle() : { data: null };
      const ok = a.status === "executed";
      const e = new EmbedBuilder().setTitle(`${ok ? "✅" : "⚠️"} ${a.action_type.toUpperCase()} — ${a.status}`).setColor(actionColor(a.action_type, ok)).addFields(
        { name: "Pemain", value: who(dn, a.target_user_id), inline: true }, { name: "Durasi", value: dur(a), inline: true },
        { name: "Oleh", value: `${a.actor_type} · ${a.actor_id} (${a.source})`, inline: true },
        { name: "Alasan publik", value: clip(a.public_reason, 400) }, { name: "Catatan privat", value: clip(priv?.private_reason ?? "-", 900) },
        ...(rep ? [{ name: "Kasus terkait", value: rep.report_code, inline: true }] : []),
        ...(a.execution_error ? [{ name: "Error", value: clip(a.execution_error, 300) }] : []),
      ).setTimestamp();
      if (!(await modLog.send({ embeds: [e] }).then(() => true).catch(() => false))) continue;

      if (ok && ["ban", "kick", "unban"].includes(a.action_type)) {
        const thumb = await headshot(a.target_user_id);
        const title = a.action_type === "ban" ? "🔨 Pemain di-ban" : a.action_type === "unban" ? "♻️ Ban dicabut" : "👢 Pemain di-kick";
        const pe = new EmbedBuilder().setTitle(title).setColor(actionColor(a.action_type)).addFields(
          { name: "Pemain", value: who(dn, a.target_user_id), inline: true }, { name: "Durasi", value: dur(a), inline: true },
          ...(rep ? [{ name: "Kasus", value: rep.report_code, inline: true }] : []),
          { name: "Alasan", value: clip(a.public_reason, 400) }, // tanpa nama staf & tanpa catatan privat
        ).setTimestamp();
        if (thumb) pe.setThumbnail(thumb);
        await pubLog?.send({ embeds: [pe] }).catch(() => null);

        if (a.action_type === "ban" && a.is_permanent && !a.banned_notice_at && banned) {
          const be = new EmbedBuilder().setTitle("🚫 PEMAIN DI-BAN PERMANEN").setColor(COLOR.red)
            .setDescription(`**${dn.get(a.target_user_id) ?? "ID " + a.target_user_id}** telah di-ban **permanen** dari SINAR RP karena pelanggaran berat.`)
            .addFields({ name: "Alasan", value: clip(a.public_reason, 500) }, { name: "Tanggal", value: ts(a.executed_at ?? Date.now(), "F"), inline: true },
              { name: "Banding", value: `Gunakan **/appeal** di <#${chan.bot_commands}>.`, inline: true }).setTimestamp();
          if (thumb) be.setThumbnail(thumb);
          if (await banned.send({ embeds: [be] }).then(() => true).catch(() => false)) await db.from("moderation_actions").update({ banned_notice_at: new Date().toISOString() }).eq("id", a.id);
        }
      }
      await db.from("moderation_actions").update({ discord_notified_at: new Date().toISOString() }).eq("id", a.id);
    }
  });

  // ---- 5. Appeal baru -> Moderations Log ----
  await safe("appeals", async () => {
    if (!modLog) return;
    const { data: apl } = await db.from("appeals").select("id,appeal_code,roblox_user_id,message,created_at").is("discord_message_id", null).eq("status", "open").order("created_at").limit(5);
    const an = await names((apl ?? []).map((a) => a.roblox_user_id));
    for (const a of apl ?? []) {
      const e = new EmbedBuilder().setTitle(`📨 Appeal ${a.appeal_code}`).setColor(COLOR.blue).addFields(
        { name: "Pemain", value: who(an, a.roblox_user_id), inline: true }, { name: "Pesan", value: clip(a.message, 1000) },
      ).setTimestamp(new Date(a.created_at)).setFooter({ text: "Identitas Roblox pengaju BELUM terverifikasi. Pertimbangkan sebelum menerima." });
      const msg = await modLog.send({ embeds: [e], components: [row(btn(`apl:accept:${a.id}`, "Terima (unban)", ButtonStyle.Success), btn(`apl:deny:${a.id}`, "Tolak", ButtonStyle.Danger))] }).catch(() => null);
      if (msg) await db.from("appeals").update({ discord_message_id: msg.id }).eq("id", a.id);
    }
  });
}

// ======================= Tombol & modal (laporan game, persetujuan ban, appeal) =======================
const UUID = /^[0-9a-f-]{36}$/i;
async function staffActor(i: ButtonInteraction | ModalSubmitInteraction) {
  const roleKey = await staffRoleOfUser(i.user.id);
  return roleKey ? { type: "staff_discord", id: i.user.id, role_key: roleKey } : null;
}
function noteModal(customId: string, title: string) {
  return new ModalBuilder().setCustomId(customId).setTitle(title).addComponents(
    new ActionRowBuilder<TextInputBuilder>().addComponents(
      new TextInputBuilder().setCustomId("note").setLabel("Catatan (min 3 karakter)").setStyle(TextInputStyle.Paragraph).setMinLength(3).setMaxLength(900).setRequired(true)));
}

export async function handleButton(i: ButtonInteraction) {
  const [ns, op, id] = i.customId.split(":");
  if (!UUID.test(id ?? "")) return;
  const actor = await staffActor(i);
  if (!actor) { await i.reply({ content: "❌ Hanya staf.", ephemeral: true }); return; }
  if (ns === "rep" && (op === "resolve" || op === "dismiss")) { await i.showModal(noteModal(`repm:${op}:${id}`, op === "resolve" ? "Selesaikan report" : "Tolak report")); return; }
  if (ns === "apl") { await i.showModal(noteModal(`aplm:${op}:${id}`, op === "accept" ? "Terima appeal" : "Tolak appeal")); return; }

  await i.deferReply({ ephemeral: true });
  if (ns === "rep" && op === "review") {
    if (!roleCan(actor.role_key, "reports.review")) { await i.editReply("❌ Tidak punya izin."); return; }
    const r = await staffApi("resolve_report", { actor, report_id: id, status: "in_review" });
    await i.editReply(r.ok ? "✅ Report ditandai sedang ditinjau oleh lu." : `❌ ${errText(r.error)}`);
    return;
  }
  if (ns === "act" && (op === "approve" || op === "reject")) {
    const r = await staffApi("decide_action", { actor, action_id: id, decision: op });
    if (r.ok) await i.message.edit({ components: [] }).catch(() => null); // hapus tombol: cegah klik ganda
    await i.editReply(r.ok ? (op === "approve" ? "✅ Disetujui dan masuk antrean eksekusi." : "✅ Ditolak.") : `❌ ${errText(r.error)}`);
  }
}

export async function handleModal(i: ModalSubmitInteraction) {
  const [ns, op, id] = i.customId.split(":");
  if (!UUID.test(id ?? "")) return;
  await i.deferReply({ ephemeral: true });
  const actor = await staffActor(i);
  if (!actor) { await i.editReply("❌ Hanya staf."); return; }
  const note = i.fields.getTextInputValue("note");
  if (ns === "repm") {
    const r = await staffApi("resolve_report", { actor, report_id: id, status: op === "resolve" ? "resolved" : "dismissed", resolution: note });
    if (r.ok) await i.message?.edit({ components: [] }).catch(() => null);
    await i.editReply(r.ok ? `✅ Report ${r.code} ditutup.` : `❌ ${errText(r.error)}`);
  } else if (ns === "aplm") {
    const r = await staffApi("decide_appeal", { actor, appeal_id: id, decision: op, note });
    if (r.ok) await i.message?.edit({ components: [] }).catch(() => null);
    await i.editReply(r.ok ? `✅ Appeal ${r.code} ${op === "accept" ? "diterima (unban diantrekan)" : "ditolak"}.` : `❌ ${errText(r.error)}`);
  }
}
