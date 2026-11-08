// Profil bot: bio (deskripsi aplikasi), tag aplikasi, dan status (presence) yang berputar.
import { ActivityType, Client, PresenceUpdateStatus, REST, Routes } from "discord.js";
import { db } from "./backend.js";
import { env } from "./env.js";

// Maks 400 karakter. Tampil di profil bot ("Tentang Saya").
export const BIO =
  "Bot resmi moderasi & keamanan SINAR RP. Lapor pemain lewat /report (tiket privat), ajukan banding lewat /appeal, " +
  "log tindakan staf, dan terhubung ke Smart Anticheat di game Roblox. Prinsip kami: bukti dulu, hukuman kemudian.";

// Maks 5 tag, masing-masing maks 20 karakter.
export const TAGS = ["moderation", "roblox", "anticheat", "roleplay", "indonesia"];

export async function applyProfile() {
  try {
    await new REST({ version: "10" }).setToken(env.token).patch(Routes.currentApplication(), { body: { description: BIO.slice(0, 400), tags: TAGS } });
    console.log("[profile] bio & tag aplikasi diperbarui");
  } catch (e) {
    console.error("[profile] gagal mengubah bio/tag lewat API:", e instanceof Error ? e.message : e,
      "\n          => Isi manual: Discord Developer Portal > aplikasi lu > General Information > Description & Tags.");
  }
}

// ---------- Status berputar (maks 5 update / 20 dtk menurut Discord; kita 1 per 30 dtk) ----------
async function playersOnline(): Promise<number | null> {
  const since = new Date(Date.now() - 120_000).toISOString();
  const { count, error } = await db.from("sessions").select("id", { count: "exact", head: true }).is("ended_at", null).gt("last_seen_at", since);
  return error ? null : (count ?? 0);
}

export function startPresence(client: Client) {
  let i = 0;
  const tick = async () => {
    const online = await playersOnline();
    const options: { name: string; type: ActivityType }[] = [
      { name: "SINAR RP • Smart Anticheat", type: ActivityType.Watching },
      { name: "/report untuk lapor pemain", type: ActivityType.Listening },
      { name: "/appeal untuk banding", type: ActivityType.Listening },
    ];
    if (online !== null) options.unshift({ name: `${online} pemain di dalam game`, type: ActivityType.Watching });
    const a = options[i++ % options.length];
    client.user?.setPresence({ status: PresenceUpdateStatus.Online, activities: [{ name: a.name, type: a.type }] });
  };
  void tick();
  setInterval(() => void tick().catch(() => null), 30_000);
}
