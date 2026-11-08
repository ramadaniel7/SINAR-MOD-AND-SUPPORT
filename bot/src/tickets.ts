// Sistem tiket /report (v2)
//  1. /report di channel report -> channel PRIVAT (hanya pelapor + staf) di kategori yang sama; staf (kecuali Founder) langsung di-tag.
//  2. Pelapor mengisi username, jenis, detail, dan mengunggah bukti (gambar/video) -> "Kirim laporan".
//  3. TIKET HANYA BISA DITUTUP STAF. Saat ditutup: bukti diarsipkan ke Moderations Log, kasus dicatat di Log publik (hijau),
//     pelapor menerima DM berisi keterangan staf + permintaan review, lalu channel tiket DIHAPUS otomatis.
//  4. Jika DM gagal (DM tertutup), seluruh isi DM dikirim ke Moderations Log.
import {
  ActionRowBuilder, AttachmentBuilder, ButtonBuilder, ButtonInteraction, ButtonStyle, ChannelType, ChatInputCommandInteraction, Client,
  EmbedBuilder, Message, ModalBuilder, ModalSubmitInteraction, PermissionFlagsBits, StringSelectMenuBuilder, StringSelectMenuInteraction,
  TextInputBuilder, TextInputStyle, type OverwriteResolvable,
} from "discord.js";
import { channels, db, loadRoles, resolveRoblox, roleCan, staffApi, staffRoleDiscordId, staffRoleOfUser } from "./backend.js";
import { clip, COLOR, sleep, ts } from "./ui.js";

type Evidence = { name: string; kind: "image" | "video"; size: number; url: string };
type Ticket = {
  id: string; channel_id: string; panel_message_id: string | null; reporter_discord_id: string; status: string;
  category: string | null; reported_user_id: number | null; reported_username: string | null; description: string | null;
  evidence: Evidence[]; report_id: string | null; created_at: string; closed_at: string | null;
  review_rating: number | null; dm_status: string | null; review_reminded_at: string | null;
};

const CATEGORIES: Record<string, string> = {
  cheating: "Cheat / Exploit", fail_roleplay: "Fail Roleplay", harassment: "Pelecehan / Perilaku tidak pantas", other: "Lainnya",
};
const MAX_EVIDENCE = 10;
const MAX_FILE_BYTES = 100 * 1024 * 1024;
const ARCHIVE_MAX_BYTES = 24 * 1024 * 1024; // batas unggah bot (default server 25 MB); lebih besar = tidak ikut diarsipkan
const IMAGE_EXT = ["png", "jpg", "jpeg", "gif", "webp"];
const VIDEO_EXT = ["mp4", "mov", "webm", "mkv"];
const DRAFT_TTL_MS = 30 * 60_000;
const MAX_OPEN_PER_USER = 3;
const MAX_TICKETS_PER_HOUR = 5;
const REVIEW_REMINDER_MS = 24 * 3600_000;
const STAFF_VIEW = ["founder", "management", "developer", "administrator", "helper"]; // yang bisa MELIHAT tiket
const STAFF_PING = ["management", "developer", "administrator", "helper"];            // yang di-TAG (Founder tidak)

const ticketChannels = new Set<string>();

// ---------- kunci per tiket (cegah double click / unggahan beruntun) ----------
const chains = new Map<string, Promise<unknown>>();
function withLock<T>(key: string, fn: () => Promise<T>): Promise<T> {
  const prev = chains.get(key) ?? Promise.resolve();
  const result = prev.catch(() => undefined).then(fn);
  const tail = result.catch(() => undefined);
  chains.set(key, tail);
  void tail.then(() => { if (chains.get(key) === tail) chains.delete(key); });
  return result;
}

const getTicket = async (id: string) => ((await db.from("discord_tickets").select("*").eq("id", id).maybeSingle()).data as Ticket | null);
const getTicketByChannel = async (cid: string) => ((await db.from("discord_tickets").select("*").eq("channel_id", cid).maybeSingle()).data as Ticket | null);
const patchTicket = (id: string, patch: Record<string, unknown>) => db.from("discord_tickets").update(patch).eq("id", id);

export async function loadTicketChannels() {
  const { data } = await db.from("discord_tickets").select("channel_id").in("status", ["drafting", "open"]);
  for (const t of data ?? []) ticketChannels.add(t.channel_id);
}

async function textChannel(client: Client, id: string) {
  const c = await client.channels.fetch(id).catch(() => null);
  return c && c.isTextBased() && "send" in c ? (c as any) : null;
}
async function modLog(client: Client) { return textChannel(client, (await channels()).moderation_log); }
const mentionRoles = (keys: string[]) => keys.map(staffRoleDiscordId).filter((x): x is string => !!x);

// ---------- tampilan panel pelapor ----------
function panelPayload(t: Ticket) {
  const ok = (b: boolean) => (b ? "✅" : "⬜");
  const embed = new EmbedBuilder().setTitle("🎫 Report Pemain — lengkapi data").setColor(COLOR.blue)
    .setDescription(`Halo <@${t.reporter_discord_id}>! Staf sudah di-tag dan melihat tiket ini. Lengkapi semua poin lalu tekan **Kirim laporan**.`)
    .addFields({
      name: "Kelengkapan",
      value: [
        `${ok(!!t.reported_user_id)} **Username pemain** ${t.reported_username ? `— ${t.reported_username} (${t.reported_user_id})` : ""}`,
        `${ok(!!t.category)} **Jenis pelanggaran** ${t.category ? `— ${CATEGORIES[t.category]}` : ""}`,
        `${ok(!!t.description)} **Detail kejadian**`,
        `${ok(t.evidence.length > 0)} **Bukti gambar/video** — ${t.evidence.length}/${MAX_EVIDENCE} terkirim`,
      ].join("\n"),
    }, {
      name: "Cara kirim bukti",
      value: `Unggah **gambar/video** langsung di channel ini (maks ${MAX_EVIDENCE} file). Format: ${[...IMAGE_EXT, ...VIDEO_EXT].join(", ")}.`,
    })
    .setFooter({ text: "Hanya pelapor & staf yang bisa melihat tiket ini • Tiket hanya bisa ditutup oleh staf • Draft tanpa kiriman dihapus setelah 30 menit" });
  const select = new StringSelectMenuBuilder().setCustomId(`tk:cat:${t.id}`).setPlaceholder("Pilih jenis pelanggaran")
    .addOptions(Object.entries(CATEGORIES).map(([value, label]) => ({ label, value, default: t.category === value })));
  return {
    embeds: [embed],
    components: [
      new ActionRowBuilder<StringSelectMenuBuilder>().addComponents(select),
      new ActionRowBuilder<ButtonBuilder>().addComponents(
        new ButtonBuilder().setCustomId(`tk:info:${t.id}`).setLabel("📝 Isi username & detail").setStyle(ButtonStyle.Primary),
        new ButtonBuilder().setCustomId(`tk:submit:${t.id}`).setLabel("✅ Kirim laporan").setStyle(ButtonStyle.Success),
      ),
    ],
  };
}

async function refreshPanel(client: Client, t: Ticket, lock = false) {
  if (!t.panel_message_id) return;
  try {
    const ch = await client.channels.fetch(t.channel_id);
    if (!ch || !ch.isTextBased()) return;
    const msg = await ch.messages.fetch(t.panel_message_id);
    const p = panelPayload(t);
    await msg.edit(lock ? { embeds: p.embeds, components: [] } : p);
  } catch (e) { console.error("[ticket] refresh panel:", e instanceof Error ? e.message : e); }
}

// ================= /report =================
export async function startTicket(i: ChatInputCommandInteraction) {
  const chan = await channels();
  if (i.channelId !== chan.player_report) { await i.editReply(`Gunakan **/report** di <#${chan.player_report}>.`); return; }
  const guild = i.guild;
  if (!guild) { await i.editReply("Command ini hanya di server."); return; }

  const { data: active } = await db.from("discord_tickets").select("channel_id,status").eq("reporter_discord_id", i.user.id).in("status", ["drafting", "open"]);
  const drafting = (active ?? []).find((t) => t.status === "drafting");
  if (drafting) { await i.editReply(`Lu masih punya tiket yang belum selesai: <#${drafting.channel_id}>.`); return; }
  if ((active ?? []).length >= MAX_OPEN_PER_USER) { await i.editReply(`Lu masih punya ${MAX_OPEN_PER_USER} laporan yang sedang ditinjau. Tunggu staf menyelesaikannya.`); return; }
  const { count } = await db.from("discord_tickets").select("id", { count: "exact", head: true }).eq("reporter_discord_id", i.user.id).gt("created_at", new Date(Date.now() - 3_600_000).toISOString());
  if ((count ?? 0) >= MAX_TICKETS_PER_HOUR) { await i.editReply("Terlalu banyak tiket dalam 1 jam terakhir. Coba lagi nanti."); return; }

  await loadRoles();
  const base = [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.SendMessages, PermissionFlagsBits.ReadMessageHistory, PermissionFlagsBits.AttachFiles, PermissionFlagsBits.EmbedLinks];
  const overwrites: OverwriteResolvable[] = [
    { id: guild.id, deny: [PermissionFlagsBits.ViewChannel] }, // semua orang lain TIDAK bisa melihat
    { id: i.user.id, allow: base },
    { id: i.client.user.id, allow: [...base, PermissionFlagsBits.ManageChannels, PermissionFlagsBits.ManageMessages, PermissionFlagsBits.MentionEveryone] },
  ];
  for (const rid of mentionRoles(STAFF_VIEW)) overwrites.push({ id: rid, allow: base });

  const parentId = (i.channel as any)?.parentId ?? null; // kategori yang sama dengan channel report
  const slug = i.user.username.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 12) || "user";
  let channel;
  try {
    channel = await guild.channels.create({
      name: `report-${slug}-${Math.random().toString(36).slice(2, 6)}`, type: ChannelType.GuildText, parent: parentId,
      permissionOverwrites: overwrites, topic: `Tiket report dari ${i.user.tag} (${i.user.id}) — hanya pelapor & staf`,
    });
  } catch (e) {
    console.error("[ticket] gagal membuat channel:", e instanceof Error ? e.message : e);
    await i.editReply("❌ Bot tidak bisa membuat channel. Pastikan bot punya izin **Manage Channels** di kategori ini.");
    return;
  }

  const { data: row, error } = await db.from("discord_tickets").insert({ channel_id: channel.id, reporter_discord_id: i.user.id }).select("*").single();
  if (error || !row) {
    await channel.delete("rollback tiket").catch(() => null);
    await i.editReply(error?.code === "23505" ? "Lu sudah punya tiket yang belum selesai." : "❌ Gagal menyimpan tiket. Coba lagi.");
    return;
  }
  const ticket = row as Ticket;
  ticketChannels.add(channel.id);

  // Staf (kecuali Founder) LANGSUNG di-tag saat tiket dibuat.
  const pingIds = mentionRoles(STAFF_PING);
  const panel = await channel.send({
    content: `${pingIds.map((x) => `<@&${x}>`).join(" ")} — tiket report baru dari <@${i.user.id}>`.trim(),
    ...panelPayload(ticket), allowedMentions: { roles: pingIds, users: [i.user.id] },
  });
  await patchTicket(ticket.id, { panel_message_id: panel.id });
  await i.editReply(`✅ Tiket dibuat: <#${channel.id}> — hanya lu dan staf yang bisa melihatnya. Lanjutkan di sana.`);

  const log = await modLog(i.client);
  await log?.send({ embeds: [new EmbedBuilder().setColor(COLOR.blue).setTitle("🎫 Tiket report dibuka").addFields(
    { name: "Pelapor", value: `<@${i.user.id}> (${i.user.id})`, inline: true }, { name: "Channel", value: `<#${channel.id}>`, inline: true }, { name: "Waktu", value: ts(Date.now()), inline: true },
  )] }).catch(() => null);
}

// ================= select: jenis pelanggaran =================
export async function handleTicketSelect(i: StringSelectMenuInteraction) {
  const id = i.customId.split(":")[2];
  await withLock(id, async () => {
    const t = await getTicket(id);
    if (!t || t.status !== "drafting") { await i.reply({ content: "Tiket ini sudah tidak aktif.", ephemeral: true }); return; }
    if (t.reporter_discord_id !== i.user.id) { await i.reply({ content: "Hanya pembuat tiket yang bisa mengisi formulir ini.", ephemeral: true }); return; }
    const value = i.values[0];
    if (!(value in CATEGORIES)) { await i.reply({ content: "Pilihan tidak valid.", ephemeral: true }); return; }
    t.category = value;
    await patchTicket(id, { category: value });
    await i.update(panelPayload(t));
  });
}

// ================= tombol (pelapor & staf) =================
export async function handleTicketButton(i: ButtonInteraction) {
  const [, op, id] = i.customId.split(":");
  const t = await getTicket(id);
  if (!t) { await i.reply({ content: "Tiket tidak ditemukan.", ephemeral: true }); return; }

  // ---- tombol STAF (setelah laporan dikirim) ----
  if (op === "claim" || op === "done" || op === "reject") {
    const roleKey = await staffRoleOfUser(i.user.id);
    if (!roleKey || !roleCan(roleKey, "tickets.close")) { await i.reply({ content: "❌ Hanya staf yang bisa memproses/menutup tiket.", ephemeral: true }); return; }
    if (t.status !== "open" || !t.report_id) { await i.reply({ content: "Tiket ini sudah ditutup / belum dikirim.", ephemeral: true }); return; }
    if (op === "claim") {
      await i.deferReply({ ephemeral: true });
      const r = await staffApi("ticket_claim", { actor: { type: "staff_discord", id: i.user.id, role_key: roleKey }, report_id: t.report_id });
      await i.editReply(r.ok ? `✅ Lu menangani tiket ini (${r.code}).` : `❌ Gagal (${r.error}).`);
      if (r.ok) {
        const ch = i.channel;
        if (ch && "send" in ch) await ch.send({ embeds: [new EmbedBuilder().setColor(COLOR.blue).setDescription(`🔍 <@${i.user.id}> menangani tiket ini.`)] }).catch(() => null);
      }
      return;
    }
    const modal = new ModalBuilder().setCustomId(`tkm:close:${op}:${id}`).setTitle(op === "done" ? "Tutup tiket — TERBUKTI/SELESAI" : "Tutup tiket — DITOLAK")
      .addComponents(new ActionRowBuilder<TextInputBuilder>().addComponents(
        new TextInputBuilder().setCustomId("note").setLabel("Keterangan untuk pelapor (dikirim lewat DM)").setStyle(TextInputStyle.Paragraph)
          .setMinLength(10).setMaxLength(900).setRequired(true).setPlaceholder("Jelaskan hasil pemeriksaan & tindakan yang diambil.")));
    await i.showModal(modal);
    return;
  }

  // ---- tombol PELAPOR (mengisi formulir) ----
  if (t.status !== "drafting") { await i.reply({ content: "Tiket ini sudah tidak aktif.", ephemeral: true }); return; }
  if (t.reporter_discord_id !== i.user.id) { await i.reply({ content: "Hanya pembuat tiket yang bisa memakai tombol ini.", ephemeral: true }); return; }
  
  if (op === "info") {
    const modal = new ModalBuilder()
      .setCustomId(`tkm:info:${id}`)
      .setTitle("Data laporan")
      .addComponents(
        new ActionRowBuilder<TextInputBuilder>().addComponents(
          new TextInputBuilder()
            .setCustomId("username")
            .setLabel("Username Roblox pemain yang dilaporkan")
            .setStyle(TextInputStyle.Short)
            .setMinLength(3)
            .setMaxLength(20)
            .setRequired(true)
            .setPlaceholder("Masukkan username Roblox...")
        ),
        new ActionRowBuilder<TextInputBuilder>().addComponents(
          new TextInputBuilder()
            .setCustomId("desc")
            .setLabel("Detail kejadian (apa, kapan, di mana)")
            .setStyle(TextInputStyle.Paragraph)
            .setMinLength(10)
            .setMaxLength(500)
            .setRequired(true)
            .setPlaceholder("Jelaskan kejadian secara lengkap...")
        )
      );

    await i.showModal(modal);
    return;
  }

  if (op === "submit") {
    await i.deferReply({ ephemeral: true });
    await withLock(id, () => submitTicket(i, id));
  }
}

async function submitTicket(i: ButtonInteraction, id: string) {
  const t = await getTicket(id);
  if (!t || t.status !== "drafting") { await i.editReply("Tiket ini sudah dikirim atau tidak aktif."); return; }
  const missing: string[] = [];
  if (!t.reported_user_id) missing.push("username pemain");
  if (!t.category) missing.push("jenis pelanggaran");
  if (!t.description) missing.push("detail kejadian");
  if (t.evidence.length === 0) missing.push("minimal 1 bukti gambar/video");
  if (missing.length) { await i.editReply(`Belum lengkap: **${missing.join(", ")}**.`); return; }

  const r = await staffApi("ticket_report", {
    idempotency_key: `ticket:${t.id}`, reporter_discord_id: t.reporter_discord_id, reported_user_id: t.reported_user_id,
    category: t.category, description: t.description, evidence: t.evidence,
  });
  if (!r.ok) { await i.editReply(`❌ Gagal mengirim (${r.error ?? "error"}). Coba lagi sebentar.`); return; }
  if (r.outcome === "rate_limited" || r.outcome === "duplicate_recent") {
    await i.editReply(r.outcome === "rate_limited" ? "❌ Terlalu banyak laporan dalam 1 jam. Coba lagi nanti. Channel ini dihapus sebentar lagi."
      : `ℹ️ Laporan serupa untuk pemain ini sudah dikirim (kode **${r.code}**). Channel ini dihapus sebentar lagi.`);
    await patchTicket(id, { status: "cancelled", closed_at: new Date().toISOString() });
    ticketChannels.delete(t.channel_id);
    setTimeout(() => void i.channel?.delete("duplikat/limit").catch(() => null), 8000);
    return;
  }

  await patchTicket(id, { status: "open", report_id: r.report_id, submitted_at: new Date().toISOString() });
  t.status = "open";
  await refreshPanel(i.client, t, true);

  // pemeriksaan otomatis (petunjuk untuk staf)
  const v = await staffApi("verify_report", { report_id: r.report_id });
  const verifText = v.ok ? `**Kecocokan: ${String(v.level).toUpperCase()}** (skor ${v.score})\n${clip(v.text, 900)}` : "Pemeriksaan otomatis gagal.";
  const evidenceLines = t.evidence.map((e, n) => `${n + 1}. ${e.kind === "video" ? "🎬" : "🖼️"} ${e.name}`).join("\n").slice(0, 800);
  const embed = new EmbedBuilder().setTitle(`🚩 Laporan lengkap • ${r.code}`).setColor(COLOR.orange).addFields(
    { name: "Pemain dilaporkan", value: `[${t.reported_username}](https://www.roblox.com/users/${t.reported_user_id}/profile) (${t.reported_user_id})`, inline: true },
    { name: "Jenis", value: CATEGORIES[t.category!], inline: true },
    { name: "Pelapor", value: `<@${t.reporter_discord_id}>`, inline: true },
    { name: "Detail", value: clip(t.description, 900) },
    { name: `Bukti (${t.evidence.length}) — ada di channel ini`, value: evidenceLines || "-" },
    { name: "🔎 Pemeriksaan otomatis (petunjuk, bukan vonis)", value: verifText },
  ).setTimestamp().setFooter({ text: "Bukti >24 MB tidak ikut diarsipkan saat tiket ditutup — simpan manual jika perlu. Tiket hanya bisa ditutup staf." });
  const row = new ActionRowBuilder<ButtonBuilder>().addComponents(
    new ButtonBuilder().setCustomId(`tk:claim:${id}`).setLabel("🔍 Tangani").setStyle(ButtonStyle.Primary),
    new ButtonBuilder().setCustomId(`tk:done:${id}`).setLabel("✅ Tutup: Selesai").setStyle(ButtonStyle.Success),
    new ButtonBuilder().setCustomId(`tk:reject:${id}`).setLabel("❌ Tutup: Ditolak").setStyle(ButtonStyle.Danger),
  );
  const ch = i.channel;
  if (ch && "send" in ch) await ch.send({ embeds: [embed], components: [row] }).catch((e: Error) => console.error("[ticket] kirim ringkasan staf:", e.message));
  await i.editReply(`✅ Laporan terkirim. Kode: **${r.code}**. Staf akan meninjau di sini. Lu akan menerima DM saat laporan ditutup.`);

  const log = await modLog(i.client);
  await log?.send({ embeds: [new EmbedBuilder().setColor(COLOR.orange).setTitle(`📨 Laporan tiket lengkap • ${r.code}`).addFields(
    { name: "Pelapor", value: `<@${t.reporter_discord_id}>`, inline: true }, { name: "Terlapor", value: `${t.reported_username} (${t.reported_user_id})`, inline: true },
    { name: "Jenis", value: CATEGORIES[t.category!], inline: true }, { name: "Kecocokan otomatis", value: v.ok ? `${String(v.level).toUpperCase()} (skor ${v.score})` : "-", inline: true },
    { name: "Tiket", value: `<#${t.channel_id}>`, inline: true },
  )] }).catch(() => null);
}

// ================= modal: formulir pelapor & penutupan staf =================
export async function handleTicketModal(i: ModalSubmitInteraction) {
  const parts = i.customId.split(":"); // tkm:info:<id>  |  tkm:close:<done|reject>:<id>
  if (parts[1] === "close") { await handleCloseModal(i, parts[2] as "done" | "reject", parts[3]); return; }
  const id = parts[2];
  await i.deferUpdate(); // verifikasi username Roblox bisa >3 detik
  await withLock(id, async () => {
    const t = await getTicket(id);
    if (!t || t.status !== "drafting" || t.reporter_discord_id !== i.user.id) { await i.followUp({ content: "Tiket tidak aktif.", ephemeral: true }); return; }
    const rb = await resolveRoblox(i.fields.getTextInputValue("username"));
    if (!rb) { await i.followUp({ content: "❌ Username Roblox tidak ditemukan. Cek ejaannya lalu isi lagi.", ephemeral: true }); return; }
    const desc = i.fields.getTextInputValue("desc").trim();
    if (desc.length < 10) { await i.followUp({ content: "❌ Detail minimal 10 karakter.", ephemeral: true }); return; }
    t.reported_user_id = rb.id; t.reported_username = rb.name; t.description = desc;
    await patchTicket(id, { reported_user_id: rb.id, reported_username: rb.name, description: desc });
    await i.editReply(panelPayload(t));
  });
}

async function handleCloseModal(i: ModalSubmitInteraction, op: "done" | "reject", id: string) {
  await i.deferReply({ ephemeral: true });
  const roleKey = await staffRoleOfUser(i.user.id);
  if (!roleKey || !roleCan(roleKey, "tickets.close")) { await i.editReply("❌ Hanya staf yang bisa menutup tiket."); return; }
  const note = i.fields.getTextInputValue("note").trim();
  const res = await withLock(id, async () => {
    const t = await getTicket(id);
    if (!t || t.status !== "open" || !t.report_id) return { ok: false as const, error: "Tiket sudah ditutup / belum dikirim." };
    const outcome = op === "done" ? "resolved" : "dismissed";
    const r = await staffApi("close_ticket_report", { actor: { type: "staff_discord", id: i.user.id, role_key: roleKey }, report_id: t.report_id, outcome, note });
    if (!r.ok) return { ok: false as const, error: `Backend menolak (${r.error}).` };
    const closer = { discordId: i.user.id, role: roleKey, name: (i.member as any)?.displayName ?? i.user.username };
    await finishClose(i.client, t, { outcome, note, closer, code: r.code });
    return { ok: true as const };
  });
  await i.editReply(res.ok ? "✅ Tiket ditutup. DM dikirim ke pelapor dan channel akan dihapus." : `❌ ${res.error}`);
}

// ================= bukti: unggahan di channel tiket =================
export async function onMessage(msg: Message) {
  if (msg.author.bot || !msg.guild || msg.attachments.size === 0 || !ticketChannels.has(msg.channelId)) return;
  const first = await getTicketByChannel(msg.channelId);
  if (!first || first.status !== "drafting" || first.reporter_discord_id !== msg.author.id) return;
  await withLock(first.id, async () => {
    const t = await getTicket(first.id);
    if (!t || t.status !== "drafting") return;
    const accepted: Evidence[] = [], rejected: string[] = [];
    for (const a of msg.attachments.values()) {
      const ext = (a.name.split(".").pop() ?? "").toLowerCase();
      const kind = IMAGE_EXT.includes(ext) ? "image" : VIDEO_EXT.includes(ext) ? "video" : null;
      const mimeOk = !a.contentType || a.contentType.startsWith("image/") || a.contentType.startsWith("video/");
      if (!kind || !mimeOk) { rejected.push(`${a.name} (format tidak didukung)`); continue; }
      if (a.size > MAX_FILE_BYTES) { rejected.push(`${a.name} (terlalu besar, maks 100 MB)`); continue; }
      if (t.evidence.length + accepted.length >= MAX_EVIDENCE) { rejected.push(`${a.name} (batas ${MAX_EVIDENCE} bukti)`); continue; }
      accepted.push({ name: a.name.slice(0, 60), kind, size: a.size, url: msg.url }); // link pesan (bukan URL CDN yang kedaluwarsa)
    }
    if (accepted.length) {
      t.evidence = [...t.evidence, ...accepted];
      await patchTicket(t.id, { evidence: t.evidence });
      await refreshPanel(msg.client, t);
    }
    if (rejected.length) {
      const warn = await msg.reply({ content: `⚠️ Tidak diterima: ${rejected.join("; ")}`, allowedMentions: { repliedUser: false } }).catch(() => null);
      setTimeout(() => void warn?.delete().catch(() => null), 15_000);
    }
  });
}

// ================= penutupan: arsip -> log -> DM -> hapus channel =================
type Closer = { discordId: string | null; role: string | null; name: string };

async function archiveEvidence(client: Client, t: Ticket, log: any): Promise<string> {
  // Channel tiket akan DIHAPUS: salin bukti ke Moderations Log supaya tidak hilang (maks 24 MB per file).
  const ch: any = await client.channels.fetch(t.channel_id).catch(() => null);
  if (!ch || !log) return "Arsip bukti dilewati (channel/log tidak tersedia).";
  const messageIds = [...new Set(t.evidence.map((e) => e.url.split("/").pop()!).filter(Boolean))];
  let archived = 0; const skipped: string[] = [];
  for (const mid of messageIds) {
    const m = await ch.messages.fetch(mid).catch(() => null);
    if (!m) { skipped.push(`pesan ${mid} sudah dihapus`); continue; }
    for (const a of m.attachments.values()) {
      if (a.size > ARCHIVE_MAX_BYTES) { skipped.push(`${a.name} (${(a.size / 1048576).toFixed(1)} MB, terlalu besar)`); continue; }
      try {
        const res = await fetch(a.url, { signal: AbortSignal.timeout(30_000) });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const buf = Buffer.from(await res.arrayBuffer());
        await log.send({ content: `📎 Arsip bukti tiket \`${t.id.slice(0, 8)}\` — ${a.name}`, files: [new AttachmentBuilder(buf, { name: a.name })] });
        archived++;
      } catch (e) { skipped.push(`${a.name} (gagal: ${e instanceof Error ? e.message : "error"})`); }
    }
  }
  return `${archived} file diarsipkan${skipped.length ? `; dilewati: ${skipped.join(", ").slice(0, 400)}` : ""}.`;
}

export async function finishClose(client: Client, t: Ticket, o: { outcome: "resolved" | "dismissed"; note: string; closer: Closer; code?: string }) {
  const now = new Date().toISOString();
  await patchTicket(t.id, { status: "closed", closed_at: now, closed_by_discord_id: o.closer.discordId, closed_by_role: o.closer.role, close_outcome: o.outcome, close_note: o.note });
  ticketChannels.delete(t.channel_id);

  const chan = await channels();
  const log = await textChannel(client, chan.moderation_log);
  const pub = await textChannel(client, chan.public_log);
  const { data: rep } = t.report_id ? await db.from("reports").select("report_code,category").eq("id", t.report_id).maybeSingle() : { data: null };
  const code = o.code ?? rep?.report_code ?? t.id.slice(0, 8);
  const resolved = o.outcome === "resolved";
  const outcomeLabel = resolved ? "Terbukti / Selesai ditindak" : "Ditolak (tidak terbukti / tidak cukup bukti)";
  const closerLabel = o.closer.discordId ? `<@${o.closer.discordId}> (${o.closer.role ?? "staf"})` : o.closer.name;

  // 1) arsip bukti
  const archiveInfo = await archiveEvidence(client, t, log);

  // 2) DM pelapor (dengan permintaan review)
  const dm = new EmbedBuilder().setTitle(`✅ Laporan lu telah ditutup • ${code}`).setColor(COLOR.green).addFields(
    { name: "Pemain dilaporkan", value: t.reported_username ? `${t.reported_username} (${t.reported_user_id})` : "-", inline: true },
    { name: "Jenis", value: t.category ? CATEGORIES[t.category] : "-", inline: true },
    { name: "Hasil", value: outcomeLabel, inline: true },
    { name: "Ditutup oleh", value: closerLabel, inline: true },
    { name: "Waktu", value: ts(now, "F"), inline: true },
    { name: "Keterangan dari staf", value: clip(o.note, 1000) },
  ).setFooter({ text: "Terima kasih sudah melapor. Mohon beri ulasan di bawah — ini wajib untuk membantu kami meningkatkan layanan." });
  const stars = new ActionRowBuilder<ButtonBuilder>().addComponents([1, 2, 3, 4, 5].map((n) =>
    new ButtonBuilder().setCustomId(`rv:${t.id}:${n}`).setLabel("⭐".repeat(n)).setStyle(n >= 4 ? ButtonStyle.Success : n === 3 ? ButtonStyle.Primary : ButtonStyle.Secondary)));
  let dmOk = false, dmErr = "";
  try {
    const user = await client.users.fetch(t.reporter_discord_id);
    await user.send({ embeds: [dm], components: [stars] });
    dmOk = true;
  } catch (e) { dmErr = e instanceof Error ? e.message : String(e); }
  await patchTicket(t.id, { dm_status: dmOk ? "sent" : "failed" });

  // 3) Moderations Log: ringkasan penutupan (+ isi DM bila DM gagal)
  const logEmbed = new EmbedBuilder().setColor(resolved ? COLOR.green : COLOR.gray).setTitle(`🔒 Tiket ditutup • ${code}`).addFields(
    { name: "Ditutup oleh", value: closerLabel, inline: true }, { name: "Hasil", value: outcomeLabel, inline: true },
    { name: "Pelapor", value: `<@${t.reporter_discord_id}>`, inline: true },
    { name: "Terlapor", value: t.reported_username ? `${t.reported_username} (${t.reported_user_id})` : "-", inline: true },
    { name: "DM ke pelapor", value: dmOk ? "✅ terkirim" : `❌ GAGAL (${clip(dmErr, 120)}) — isi DM di bawah`, inline: true },
    { name: "Arsip bukti", value: clip(archiveInfo, 500) },
    { name: "Keterangan staf", value: clip(o.note, 1000) },
  ).setTimestamp();
  await log?.send({ embeds: dmOk ? [logEmbed] : [logEmbed, new EmbedBuilder(dm.toJSON()).setTitle("📭 Isi DM yang gagal terkirim (sampaikan manual ke pelapor)")] }).catch(() => null);

  // 4) Log PUBLIK: kasus selesai (hijau). Nama terlapor TIDAK dipublikasikan bila ditolak (menghindari pencemaran nama).
  await pub?.send({ embeds: [new EmbedBuilder().setColor(COLOR.green).setTitle(`✅ Kasus ditutup • ${code}`).addFields(
    { name: "Jenis", value: t.category ? CATEGORIES[t.category] : "-", inline: true },
    { name: "Hasil", value: resolved ? "Terbukti & ditindak" : "Tidak terbukti", inline: true },
    ...(resolved && t.reported_username ? [{ name: "Pemain", value: t.reported_username, inline: true }] : []),
  ).setTimestamp().setFooter({ text: "Terima kasih kepada pelapor." })] }).catch(() => null);

  // 5) hapus channel tiket
  const ch: any = await client.channels.fetch(t.channel_id).catch(() => null);
  if (ch?.send) {
    await ch.send({ embeds: [new EmbedBuilder().setColor(COLOR.green).setTitle("🔒 Tiket ditutup").setDescription(`Hasil: **${outcomeLabel}**. Channel ini dihapus dalam beberapa detik.`)] }).catch(() => null);
    await sleep(6000);
    await ch.delete("tiket ditutup oleh staf").catch((e: Error) => console.error("[ticket] gagal menghapus channel:", e.message));
  }
}

// ================= review pelapor (di DM) =================
export async function handleReviewButton(i: ButtonInteraction) {
  const [, id, n] = i.customId.split(":");
  const t = await getTicket(id);
  if (!t || t.reporter_discord_id !== i.user.id) { await i.reply({ content: "Ulasan ini bukan untuk akun lu.", ephemeral: true }); return; }
  if (t.review_rating) { await i.reply({ content: "Lu sudah memberi ulasan. Terima kasih!", ephemeral: true }); return; }
  const modal = new ModalBuilder().setCustomId(`rvm:${id}:${n}`).setTitle(`Ulasan ${"⭐".repeat(Number(n))}`).addComponents(
    new ActionRowBuilder<TextInputBuilder>().addComponents(
      new TextInputBuilder().setCustomId("comment").setLabel("Komentar (opsional)").setStyle(TextInputStyle.Paragraph).setMaxLength(450).setRequired(false)));
  await i.showModal(modal);
}

export async function handleReviewModal(i: ModalSubmitInteraction) {
  const [, id, n] = i.customId.split(":");
  const rating = Number(n);
  await i.deferReply({ ephemeral: true });
  if (!(rating >= 1 && rating <= 5)) { await i.editReply("Nilai tidak valid."); return; }
  const t = await getTicket(id);
  if (!t || t.reporter_discord_id !== i.user.id || t.review_rating) { await i.editReply("Ulasan tidak dapat disimpan (sudah diberikan / bukan akun lu)."); return; }
  const comment = i.fields.getTextInputValue("comment").trim();
  await patchTicket(id, { review_rating: rating, review_comment: comment || null, reviewed_at: new Date().toISOString() });
  if (i.isFromMessage()) await i.message.edit({ components: [] }).catch(() => null);
  await i.editReply("Terima kasih atas ulasannya! 💙");
  const log = await modLog(i.client);
  await log?.send({ embeds: [new EmbedBuilder().setColor(rating >= 4 ? COLOR.green : rating === 3 ? COLOR.yellow : COLOR.orange).setTitle(`⭐ Ulasan tiket • ${"⭐".repeat(rating)}`).addFields(
    { name: "Pelapor", value: `<@${t.reporter_discord_id}>`, inline: true }, { name: "Tiket", value: `\`${t.id.slice(0, 8)}\``, inline: true },
    { name: "Komentar", value: comment || "-" })] }).catch(() => null);
}

// ================= perawatan berkala (tiap menit) =================
export async function ticketMaintenance(client: Client) {
  // 1) hapus draft yang terbengkalai
  const { data: stale } = await db.from("discord_tickets").select("*").eq("status", "drafting").lt("created_at", new Date(Date.now() - DRAFT_TTL_MS).toISOString()).limit(10);
  for (const t of (stale ?? []) as Ticket[]) {
    await patchTicket(t.id, { status: "expired", closed_at: new Date().toISOString() });
    ticketChannels.delete(t.channel_id);
    const ch: any = await client.channels.fetch(t.channel_id).catch(() => null);
    await ch?.delete("tiket kedaluwarsa").catch(() => null);
  }

  // 2) tiket yang laporannya ditutup lewat DASHBOARD web -> jalankan alur penutupan yang sama
  const { data: open } = await db.from("discord_tickets").select("*").eq("status", "open").not("report_id", "is", null).limit(50);
  const tickets = (open ?? []) as Ticket[];
  if (tickets.length) {
    const { data: reps } = await db.from("reports").select("id,status,resolution,resolved_by").in("id", tickets.map((t) => t.report_id!)).in("status", ["resolved", "dismissed", "duplicate"]);
    const done = new Map((reps ?? []).map((r) => [r.id, r]));
    for (const t of tickets) {
      const r = done.get(t.report_id!);
      if (!r) continue;
      const isDiscordId = /^\d{15,25}$/.test(String(r.resolved_by ?? ""));
      await withLock(t.id, async () => {
        const fresh = await getTicket(t.id);
        if (!fresh || fresh.status !== "open") return;
        await finishClose(client, fresh, {
          outcome: r.status === "resolved" ? "resolved" : "dismissed",
          note: r.resolution ?? "Laporan ditutup oleh staf lewat dashboard.",
          closer: { discordId: isDiscordId ? String(r.resolved_by) : null, role: null, name: "Staf (dashboard web)" },
        });
      });
    }
  }

  // 3) pengingat review (sekali, setelah 24 jam) — ulasan diwajibkan
  const due = new Date(Date.now() - REVIEW_REMINDER_MS).toISOString();
  const { data: noReview } = await db.from("discord_tickets").select("*").eq("status", "closed").eq("dm_status", "sent").is("review_rating", null).is("review_reminded_at", null).lt("closed_at", due).limit(10);
  for (const t of (noReview ?? []) as Ticket[]) {
    await patchTicket(t.id, { review_reminded_at: new Date().toISOString() });
    try {
      const user = await client.users.fetch(t.reporter_discord_id);
      await user.send({ embeds: [new EmbedBuilder().setColor(COLOR.blue).setTitle("🔔 Pengingat ulasan")
        .setDescription("Lu belum memberi ulasan atas penanganan laporan lu. Gunakan tombol bintang pada DM penutupan laporan sebelumnya. Terima kasih!")] });
    } catch { /* DM tertutup: abaikan */ }
  }
}
