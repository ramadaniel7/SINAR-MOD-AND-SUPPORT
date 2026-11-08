import { Client, Events, GatewayIntentBits, REST, Routes } from "discord.js";
import { env } from "./env.js";
import { loadRoles, staffApi, sweepStaffCache } from "./backend.js";
import { commandDefs, handleCommand, sweepCommandCaches } from "./commands.js";
import { handleButton, handleModal, pollOnce } from "./notifier.js";
import { applyProfile, startPresence } from "./profile.js";
import { handleReviewButton, handleReviewModal, handleTicketButton, handleTicketModal, handleTicketSelect, loadTicketChannels, onMessage, ticketMaintenance } from "./tickets.js";

// MessageContent = intent istimewa: dipakai HANYA agar bot bisa membaca lampiran bukti (gambar/video) di channel tiket.
const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent] });

// Never let one bad promise crash the bot silently: log with context.
process.on("unhandledRejection", (e) => console.error("[unhandledRejection]", e));
process.on("uncaughtException", (e) => console.error("[uncaughtException]", e));

client.once(Events.ClientReady, async (c) => {
  console.log(`[bot] login sebagai ${c.user.tag}`);
  console.log("[bot] log lengkap: tiap /command & panggilan ke backend akan tampil di sini. Hasil eksekusi ban/kick (dari server Roblox) muncul di channel moderations-log, bukan di terminal.");
  await loadRoles(true);
  await loadTicketChannels();
  try {
    const rest = new REST({ version: "10" }).setToken(env.token);
    // GLOBAL -> aplikasi mendapat badge "Supports Commands". Handler tetap hanya melayani server lu (cek guildId).
    await rest.put(Routes.applicationCommands(env.appId), { body: commandDefs });
    // hapus versi per-server lama supaya command tidak muncul dobel
    await rest.put(Routes.applicationGuildCommands(env.appId, env.guildId), { body: [] });
    console.log(`[bot] ${commandDefs.length} slash command GLOBAL terdaftar`);
  } catch (e) {
    console.error("[bot] gagal mendaftarkan slash command:", e);
  }
  await applyProfile();
  startPresence(client);

  // Poll loop with an in-flight guard (no overlapping runs) and fixed 8s cadence.
  let busy = false;
  setInterval(async () => {
    if (busy) return;
    busy = true;
    try { await pollOnce(client); } catch (e) { console.error("[notifier] error:", e instanceof Error ? e.message : e); }
    finally { busy = false; }
  }, 8_000);

  // Tiket: hapus draft terbengkalai & tutup tiket yang report-nya sudah selesai (tiap menit).
  let ticketBusy = false;
  setInterval(async () => {
    if (ticketBusy) return;
    ticketBusy = true;
    try { await ticketMaintenance(client); } catch (e) { console.error("[ticket] maintenance error:", e instanceof Error ? e.message : e); }
    finally { ticketBusy = false; }
  }, 60_000);

  // Penyapu cache (cooldown, cache staf) supaya memori tidak membengkak.
  setInterval(() => { sweepCommandCaches(); sweepStaffCache(); }, 600_000);

  // Hourly retention job (keeps the free-tier database small).
  setInterval(async () => {
    const r = await staffApi("maintenance", {});
    console.log("[maintenance]", r.ok ? JSON.stringify(r.result) : r.error);
  }, 3_600_000);
});

client.on(Events.InteractionCreate, async (i) => {
  try {
    if (i.isChatInputCommand()) {
      console.log(`[cmd] /${i.commandName} oleh ${i.user.tag} (${i.user.id}) di channel ${i.channelId}`);
      await handleCommand(i);
    }
    else if (i.isStringSelectMenu() && i.customId.startsWith("tk:")) await handleTicketSelect(i);
    else if (i.isButton() && i.customId.startsWith("tk:")) await handleTicketButton(i);
    else if (i.isButton() && i.customId.startsWith("rv:")) await handleReviewButton(i);
    else if (i.isModalSubmit() && i.customId.startsWith("tkm:")) await handleTicketModal(i);
    else if (i.isModalSubmit() && i.customId.startsWith("rvm:")) await handleReviewModal(i);
    else if (i.isButton()) await handleButton(i);
    else if (i.isModalSubmit()) await handleModal(i);
  } catch (e) {
    console.error("[interaction] error:", e instanceof Error ? e.stack : e);
    // Interaction may be expired/already replied: best-effort, never throw.
    try {
      if (i.isRepliable()) {
        if (i.deferred || i.replied) await i.editReply("❌ Terjadi error internal.");
        else await i.reply({ content: "❌ Terjadi error internal.", ephemeral: true });
      }
    } catch { /* interaction expired */ }
  }
});

client.on(Events.MessageCreate, (m) => { onMessage(m).catch((e) => console.error("[ticket] onMessage error:", e instanceof Error ? e.message : e)); });

for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, () => { console.log(`[bot] ${sig}: menutup koneksi`); void client.destroy(); setTimeout(() => process.exit(0), 500); });
}

client.login(env.token).catch((e) => {
  const msg = e instanceof Error ? e.message : String(e);
  console.error("[FATAL] Login gagal:", msg);
  if (/disallowed intents/i.test(msg)) {
    console.error("=> Aktifkan 'MESSAGE CONTENT INTENT' di Discord Developer Portal > Bot > Privileged Gateway Intents, lalu jalankan ulang.");
  }
  process.exit(1);
});
