import {
  ActionRowBuilder, ButtonBuilder, ButtonStyle, ChatInputCommandInteraction, EmbedBuilder, SlashCommandBuilder,
  type RESTPostAPIChatInputApplicationCommandsJSONBody,
} from "discord.js";
import { channels, db, resolveRoblox, roleCan, staffApi, staffRoleOfUser } from "./backend.js";
import { env } from "./env.js";
import { headshot, profileUrl, robloxProfile } from "./roblox.js";
import { startTicket } from "./tickets.js";
import { clip, COLOR, ts } from "./ui.js";

export const DURATIONS = { "1d": 86_400, "1w": 604_800, "30d": 2_592_000, "365d": 31_536_000 } as const;
const durationChoices = [
  { name: "1 hari", value: "1d" }, { name: "1 minggu", value: "1w" }, { name: "30 hari", value: "30d" },
  { name: "365 hari", value: "365d" }, { name: "Permanen (butuh persetujuan)", value: "permanent" },
];

export const ERR: Record<string, string> = {
  forbidden: "Lu nggak punya izin untuk aksi ini.",
  unknown_role: "Role lu belum terdaftar di sistem.",
  target_outranks_actor: "Target punya rank yang sama/lebih tinggi dari lu.",
  duration_exceeds_role_limit: "Durasi ban melebihi batas untuk role lu.",
  duration_not_allowed: "Durasi tidak diizinkan oleh konfigurasi.",
  target_not_online: "Pemain tidak sedang online di game (kick/warn hanya untuk pemain yang online).",
  invalid_reason: "Alasan harus 3-400 karakter (publik) dan 3-2000 (catatan privat).",
  not_pending: "Permintaan ini sudah diproses.",
  self_approval_not_allowed: "Lu nggak boleh menyetujui permintaan lu sendiri.",
  not_open: "Sudah diproses sebelumnya.",
  no_active_ban: "Akun itu tidak sedang di-ban.",
  appeal_already_open: "Sudah ada appeal yang sedang diproses untuk ban ini.",
  backend_unreachable: "Backend tidak bisa dihubungi. Coba lagi sebentar.",
};
export const errText = (code?: string) => ERR[code ?? ""] ?? `Gagal (${code ?? "unknown"}).`;

const player = (o: any) => o.setName("pemain").setDescription("Username atau UserId Roblox").setRequired(true);
export const commandDefs: RESTPostAPIChatInputApplicationCommandsJSONBody[] = [
  new SlashCommandBuilder().setName("ban").setDescription("Ban pemain Roblox (staf)").setDMPermission(false)
    .addStringOption(player)
    .addStringOption((o) => o.setName("durasi").setDescription("Lama ban").setRequired(true).addChoices(...durationChoices))
    .addStringOption((o) => o.setName("alasan").setDescription("Alasan yang tampil ke pemain (3-400 karakter)").setRequired(true).setMinLength(3).setMaxLength(400))
    .addStringOption((o) => o.setName("catatan").setDescription("Catatan privat staf").setMinLength(3).setMaxLength(1500)),
  new SlashCommandBuilder().setName("kick").setDescription("Kick pemain yang sedang online (staf)").setDMPermission(false)
    .addStringOption(player)
    .addStringOption((o) => o.setName("alasan").setDescription("Alasan").setRequired(true).setMinLength(3).setMaxLength(400))
    .addStringOption((o) => o.setName("catatan").setDescription("Catatan privat staf").setMinLength(3).setMaxLength(1500)),
  new SlashCommandBuilder().setName("warn").setDescription("Peringatan untuk pemain yang sedang online (staf)").setDMPermission(false)
    .addStringOption(player)
    .addStringOption((o) => o.setName("alasan").setDescription("Alasan").setRequired(true).setMinLength(3).setMaxLength(400))
    .addStringOption((o) => o.setName("catatan").setDescription("Catatan privat staf").setMinLength(3).setMaxLength(1500)),
  new SlashCommandBuilder().setName("unban").setDescription("Cabut ban pemain (staf)").setDMPermission(false)
    .addStringOption(player)
    .addStringOption((o) => o.setName("alasan").setDescription("Alasan").setRequired(true).setMinLength(3).setMaxLength(400)),
  new SlashCommandBuilder().setName("lookup").setDescription("Profil & riwayat moderasi pemain (staf)").setDMPermission(false).addStringOption(player),
  new SlashCommandBuilder().setName("announce").setDescription("Pengumuman global ke semua server game (staf)").setDMPermission(false)
    .addStringOption((o) => o.setName("pesan").setDescription("Isi pengumuman (3-200 karakter)").setRequired(true).setMinLength(3).setMaxLength(200)),
  new SlashCommandBuilder().setName("health").setDescription("Status backend & antrean command (staf)").setDMPermission(false),
  new SlashCommandBuilder().setName("report").setDescription("Laporkan pemain: membuat tiket privat bersama staf").setDMPermission(false),
  new SlashCommandBuilder().setName("appeal").setDescription("Ajukan banding atas ban lu").setDMPermission(false)
    .addStringOption((o) => o.setName("roblox").setDescription("Username atau UserId Roblox yang di-ban").setRequired(true))
    .addStringOption((o) => o.setName("pesan").setDescription("Jelaskan kenapa ban perlu ditinjau (min 10 karakter)").setRequired(true).setMinLength(10).setMaxLength(900)),
  new SlashCommandBuilder().setName("check").setDescription("Lihat statistik pemain yang terkena ban (sementara & permanen)").setDMPermission(false),
  new SlashCommandBuilder().setName("robloxprofile").setDescription("Lihat profil Roblox berdasarkan username").setDMPermission(false)
    .addStringOption((o) => o.setName("username").setDescription("Username Roblox (3-20 karakter)").setRequired(true).setMinLength(3).setMaxLength(20)),
].map((c) => c.toJSON());

// ---------- cooldown publik (Map berbatas + disapu berkala: tidak bocor memori) ----------
const cooldown = new Map<string, number>();
export function sweepCommandCaches() {
  const now = Date.now();
  for (const [k, until] of cooldown) if (until < now) cooldown.delete(k);
}
const onCooldown = (key: string, ms: number): number => {
  const now = Date.now();
  const until = cooldown.get(key) ?? 0;
  if (until > now) return Math.ceil((until - now) / 1000);
  if (cooldown.size > 2000) sweepCommandCaches();
  cooldown.set(key, now + ms);
  return 0;
};

const PUBLIC_IN_BOT_CHANNEL = new Set(["check", "robloxprofile", "appeal"]);

export async function handleCommand(i: ChatInputCommandInteraction) {
  if (i.guildId !== env.guildId) { await i.reply({ content: "Server tidak dikenali.", ephemeral: true }); return; }
  const name = i.commandName;
  const chan = await channels();
  const roleKey = await staffRoleOfUser(i.user.id);

  // ---- /report: hanya di channel report; tiket privat ----
  if (name === "report") { await i.deferReply({ ephemeral: true }); await startTicket(i); return; }

  // ---- Perintah publik: hanya di channel Bot Commands (staf boleh di mana saja) ----
  if (PUBLIC_IN_BOT_CHANNEL.has(name)) {
    if (!roleKey && i.channelId !== chan.bot_commands) {
      await i.reply({ content: `Gunakan **/${name}** di <#${chan.bot_commands}>.`, ephemeral: true });
      return;
    }
    const wait = onCooldown(`${name}:${i.user.id}`, name === "appeal" ? 60_000 : 8_000);
    if (wait) { await i.reply({ content: `Tunggu ${wait} detik sebelum memakai /${name} lagi.`, ephemeral: true }); return; }
    await i.deferReply({ ephemeral: name === "appeal" });
    if (name === "check") return void (await cmdCheck(i));
    if (name === "robloxprofile") return void (await cmdProfile(i, roleKey));
    return void (await cmdAppeal(i));
  }

  // ---- Perintah staf ----
  await i.deferReply({ ephemeral: true }); // keluaran sensitif hanya terlihat oleh pemanggil
  if (!roleKey) { await i.editReply("❌ Command ini hanya untuk staf yang terdaftar di roster."); return; }
  const actor = { type: "staff_discord", id: i.user.id, role_key: roleKey };

  if (name === "health") {
    const r = await staffApi("health", { actor });
    if (!r.ok) { await i.editReply(`❌ ${errText(r.error)}`); return; }
    const q = r.queue_24h;
    const e = new EmbedBuilder().setTitle("Status Sistem").setColor(COLOR.blue).addFields(
      { name: "Antrean (24 jam)", value: `pending: ${q.pending}\nprocessing: ${q.processing}\nfailed: ${q.failed}\nexecuted: ${q.executed}` },
      { name: "Kontak terakhir server game", value: r.last_game_server_contact ? ts(r.last_game_server_contact, "R") : "belum pernah", inline: true },
      { name: "Menunggu approval", value: String(r.pending_approvals), inline: true },
      { name: "Command pending tertua", value: r.oldest_pending_at ? ts(r.oldest_pending_at, "R") : "-", inline: true },
    );
    await i.editReply({ embeds: [e] });
    return;
  }

  if (name === "announce") {
    const r = await staffApi("announce", {
      actor, message: i.options.getString("pesan", true), from: clip((i.member as any)?.displayName ?? "Staff", 40), idempotency_key: `discord:${i.id}`,
    });
    await i.editReply(r.ok ? "✅ Pengumuman masuk antrean. Tampil di semua server dalam beberapa detik (best-effort)." : `❌ ${errText(r.error)}`);
    return;
  }

  // sisanya butuh target Roblox
  const rb = await resolveRoblox(i.options.getString("pemain", true));
  if (!rb) { await i.editReply("❌ Akun Roblox tidak ditemukan. Cek username/UserId."); return; }

  if (name === "lookup") {
    const r = await staffApi("lookup_player", { actor, user_id: rb.id });
    if (!r.ok) { await i.editReply(`❌ ${errText(r.error)}`); return; }
    const hist = (r.actions ?? []).map((a: any) =>
      `• ${a.action_type}${a.is_permanent ? " (permanen)" : a.duration_seconds ? ` (${Math.round(a.duration_seconds / 86400)}h)` : ""} — ${a.status} — ${clip(a.public_reason, 60)}`).join("\n") || "Tidak ada.";
    const thumb = await headshot(rb.id);
    const e = new EmbedBuilder().setTitle(`${rb.name} (${rb.id})`).setURL(profileUrl(rb.id)).setColor(r.online ? COLOR.green : COLOR.gray).addFields(
      { name: "Status", value: r.online ? "Online di game" : "Offline", inline: true },
      { name: "Violation", value: String(r.violations), inline: true },
      { name: "Report terhadap pemain ini", value: String(r.reports), inline: true },
      { name: "Riwayat moderasi", value: hist.slice(0, 1000) },
    );
    if (thumb) e.setThumbnail(thumb);
    await i.editReply({ embeds: [e] });
    return;
  }

  const reason = i.options.getString("alasan", true);
  const note = i.options.getString("catatan") ?? `Dilakukan via Discord oleh ${i.user.tag}`;
  const base = {
    actor, target_user_id: rb.id, public_reason: reason, private_reason: note.length >= 3 ? note : "via Discord",
    idempotency_key: `discord:${i.id}`, // interaksi yang terkirim ulang tidak pernah menghukum dua kali
  };
  let body: Record<string, unknown>;
  switch (name) {
    case "ban": {
      const d = i.options.getString("durasi", true);
      body = d === "permanent" ? { ...base, action_type: "ban", permanent: true } : { ...base, action_type: "ban", duration_seconds: DURATIONS[d as keyof typeof DURATIONS] };
      break;
    }
    case "kick": body = { ...base, action_type: "kick" }; break;
    case "warn": body = { ...base, action_type: "warn" }; break;
    case "unban": body = { ...base, action_type: "unban" }; break;
    default: await i.editReply("Command tidak dikenal."); return;
  }
  const permNeeded = ({ ban: body.permanent ? "moderation.ban.perm.request" : "moderation.ban.temp", kick: "moderation.kick", warn: "moderation.warn", unban: "moderation.unban" } as Record<string, string>)[name];
  if (!roleCan(roleKey, permNeeded)) { await i.editReply(`❌ ${errText("forbidden")}`); return; }

  const r = await staffApi("create_action", body);
  if (!r.ok) { await i.editReply(`❌ ${errText(r.error)}`); return; }
  const msg = r.status === "pending_approval" ? "⏳ Ban **permanen** dicatat dan menunggu persetujuan Management/Founder (orang lain)."
    : r.duplicate ? "ℹ️ Permintaan ini sudah pernah dikirim." : "✅ Permintaan diterima. Server game mengeksekusi dalam ±5–10 detik; hasilnya muncul di log.";
  await i.editReply(`${msg}\nPemain: **${rb.name}** (${rb.id})`);
}

// ---------- /appeal ----------
async function cmdAppeal(i: ChatInputCommandInteraction) {
  const rb = await resolveRoblox(i.options.getString("roblox", true));
  if (!rb) { await i.editReply("Akun Roblox tidak ditemukan."); return; }
  const r = await staffApi("create_appeal", { roblox_user_id: rb.id, message: i.options.getString("pesan", true), discord_user_id: i.user.id });
  await i.editReply(r.ok ? `✅ Appeal terkirim. Kode: **${r.code}**. Staf akan meninjau.` : `❌ ${errText(r.error)}`);
}

// ---------- /check ----------
async function cmdCheck(i: ChatInputCommandInteraction) {
  const r = await staffApi("ban_stats", {});
  if (!r.ok) { await i.editReply(`❌ ${errText(r.error)}`); return; }
  const recent = (r.recent ?? []).map((x: any) => `• **${x.name}** — ${x.permanent ? "PERMANEN" : `${x.days ?? "?"} hari`} — ${clip(x.reason, 60)}`).join("\n") || "Belum ada.";
  const e = new EmbedBuilder().setTitle("🔨 Statistik Ban SINAR RP").setColor(COLOR.red).addFields(
    { name: "Total ban tercatat", value: String(r.total_bans), inline: true },
    { name: "Ban permanen (aktif)", value: String(r.permanent_active), inline: true },
    { name: "Ban sementara (aktif)", value: String(r.temp_active), inline: true },
    { name: "Ban 7 hari terakhir", value: String(r.last7d), inline: true },
    { name: "Kick", value: String(r.kicks), inline: true },
    { name: "Peringatan", value: String(r.warns), inline: true },
    { name: "5 ban terbaru", value: recent.slice(0, 1000) },
  ).setFooter({ text: "Data publik. Kena ban keliru? Gunakan /appeal." }).setTimestamp();
  await i.editReply({ embeds: [e] });
}

// ---------- /robloxprofile ----------
async function cmdProfile(i: ChatInputCommandInteraction, staffRole: string | null) {
  const username = i.options.getString("username", true).trim();
  if (!/^[A-Za-z0-9_]{3,20}$/.test(username)) { await i.editReply("❌ Username Roblox tidak valid (3-20 karakter: huruf, angka, underscore)."); return; }
  const rb = await resolveRoblox(username);
  if (!rb) { await i.editReply("❌ Akun Roblox tidak ditemukan."); return; }
  const [p, thumb] = await Promise.all([robloxProfile(rb.id), headshot(rb.id)]);
  if (!p) { await i.editReply("❌ Roblox API sedang bermasalah. Coba lagi sebentar."); return; }
  const e = new EmbedBuilder().setTitle(`${p.displayName} (@${p.name})${p.verified ? " ✔️" : ""}`).setURL(profileUrl(p.id)).setColor(COLOR.blue)
    .setDescription(clip(p.description, 300) || "*Tidak ada deskripsi.*")
    .addFields(
      { name: "User ID", value: `\`${p.id}\``, inline: true },
      { name: "Akun dibuat", value: p.created ? `${ts(p.created, "D")} (${ts(p.created, "R")})` : "-", inline: true },
      { name: "Status akun", value: p.isBanned ? "🚫 Dibanned Roblox" : "✅ Aktif", inline: true },
      { name: "Teman", value: String(p.friends ?? "-"), inline: true },
      { name: "Pengikut", value: String(p.followers ?? "-"), inline: true },
      { name: "Mengikuti", value: String(p.following ?? "-"), inline: true },
    ).setTimestamp();
  if (thumb) e.setThumbnail(thumb);
  if (staffRole) { // data internal hanya untuk staf
    const [a, v] = await Promise.all([
      db.from("moderation_actions").select("id", { count: "exact", head: true }).eq("target_user_id", p.id).eq("status", "executed"),
      db.from("violations").select("id", { count: "exact", head: true }).eq("roblox_user_id", p.id),
    ]);
    e.addFields({ name: "🛡 Catatan SINAR RP (staf)", value: `Tindakan moderasi: ${a.count ?? 0} · Insiden anti-cheat: ${v.count ?? 0}` });
  }
  const row = new ActionRowBuilder<ButtonBuilder>().addComponents(new ButtonBuilder().setLabel("Buka profil Roblox").setStyle(ButtonStyle.Link).setURL(profileUrl(p.id)));
  await i.editReply({ embeds: [e], components: [row] });
}

export const memberRoleIds = (i: { member: any }): string[] =>
  Array.isArray(i.member?.roles) ? i.member.roles : [...(i.member?.roles?.cache?.keys() ?? [])];
