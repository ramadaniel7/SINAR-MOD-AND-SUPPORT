// Everything the bot needs from the backend: DB reads (service role, trusted) and staff-api calls.
import { createClient } from "@supabase/supabase-js";
import { env } from "./env.js";

export const db = createClient(env.supabaseUrl, env.serviceKey, { auth: { persistSession: false } });

export type StaffApiResult = { ok: boolean; error?: string; [k: string]: any };

export async function staffApi(kind: string, payload: Record<string, unknown>): Promise<StaffApiResult> {
  try {
    const res = await fetch(`${env.supabaseUrl}/functions/v1/staff-api`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-staff-key": env.staffKey },
      body: JSON.stringify({ kind, ...payload }),
      signal: AbortSignal.timeout(15_000),
    });
    const text = await res.text();
    let out: StaffApiResult;
    try { out = JSON.parse(text); } catch { out = { ok: false, error: `bad_response_${res.status}` }; }
    console.log(`[staff-api] ${kind} -> HTTP ${res.status} ${out.ok ? "OK" : "GAGAL: " + out.error}${out.status ? " status=" + out.status : ""}`);
    return out;
  } catch (e) {
    console.error("[staff-api] gagal:", e instanceof Error ? e.message : e);
    return { ok: false, error: "backend_unreachable" };
  }
}

// ---- Staff roles (resolved from the REAL guild member on each interaction) ----
type RoleRow = { role_key: string; rank: number; discord_role_id: string };
let roles: RoleRow[] = [];
let rolesAt = 0;
const perms = new Map<string, Set<string>>();

export async function loadRoles(force = false) {
  if (!force && Date.now() - rolesAt < 60_000 && roles.length) return;
  const [r, p] = await Promise.all([
    db.from("staff_roles").select("role_key,rank,discord_role_id"),
    db.from("role_permissions").select("role_key,permission_key"),
  ]);
  if (r.error || p.error) { console.error("[roles] gagal load:", r.error?.message ?? p.error?.message); return; }
  roles = (r.data ?? []) as RoleRow[];
  perms.clear();
  for (const x of p.data ?? []) {
    if (!perms.has(x.role_key)) perms.set(x.role_key, new Set());
    perms.get(x.role_key)!.add(x.permission_key);
  }
  rolesAt = Date.now();
}

/**
 * Staff role of a Discord USER, looked up by user ID in admin_members (filled from staff_roster.json).
 * Having a Discord role is NOT enough to act as staff: the person must be in the roster.
 */
const staffCache = new Map<string, { role: string | null; at: number }>();
export function sweepStaffCache() {
  const now = Date.now();
  for (const [k, v] of staffCache) if (now - v.at > 120_000) staffCache.delete(k);
}
export async function staffRoleOfUser(discordUserId: string): Promise<string | null> {
  await loadRoles();
  const hit = staffCache.get(discordUserId);
  if (hit && Date.now() - hit.at < 30_000) return hit.role;
  const { data, error } = await db.from("admin_members").select("role_key").eq("discord_user_id", discordUserId).eq("is_active", true).maybeSingle();
  if (error) { console.error("[staff] gagal cek roster:", error.message); return hit?.role ?? null; }
  const role = data?.role_key ?? null;
  if (staffCache.size > 500) sweepStaffCache();
  staffCache.set(discordUserId, { role, at: Date.now() });
  return role;
}
export function roleCan(roleKey: string | null, perm: string): boolean {
  return !!roleKey && !!perms.get(roleKey)?.has(perm);
}

export type Channels = { moderation_log: string; public_log: string; incident_report: string; player_report: string; bot_commands: string; player_banned: string };
export async function channels(): Promise<Channels> {
  const { data } = await db.from("anticheat_config").select("value").eq("key", "discord.channels").maybeSingle();
  if (!data) { console.error("[FATAL] config discord.channels tidak ada. Jalankan seed.sql"); process.exit(1); }
  return data.value;
}

// ---- Roblox identity lookup (public Roblox web API) ----
export async function resolveRoblox(input: string): Promise<{ id: number; name: string } | null> {
  const t = input.trim();
  try {
    if (/^\d{1,13}$/.test(t)) {
      const r = await fetch(`https://users.roblox.com/v1/users/${t}`, { signal: AbortSignal.timeout(8000) });
      if (!r.ok) return null;
      const j: any = await r.json();
      return j?.id ? { id: j.id, name: j.name } : null;
    }
    if (!/^[A-Za-z0-9_]{3,20}$/.test(t)) return null;
    const r = await fetch("https://users.roblox.com/v1/usernames/users", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ usernames: [t], excludeBannedUsers: false }), signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) return null;
    const j: any = await r.json();
    const u = j?.data?.[0];
    return u?.id ? { id: u.id, name: u.name } : null;
  } catch { return null; }
}

export const staffRoleDiscordId = (roleKey: string): string | null =>
  roles.find((r) => r.role_key === roleKey)?.discord_role_id ?? null;
