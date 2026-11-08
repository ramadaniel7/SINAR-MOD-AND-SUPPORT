// Pembantu Roblox (API publik): profil, thumbnail, tautan masuk server. Semua dengan timeout & cache berbatas.
import { resolveRoblox } from "./backend.js";

export { resolveRoblox };
const TIMEOUT = 8000;

async function getJson(url: string): Promise<any | null> {
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT) });
    return r.ok ? await r.json().catch(() => null) : null;
  } catch { return null; }
}

const headCache = new Map<number, { url: string | null; at: number }>();
export async function headshot(userId: number): Promise<string | null> {
  const hit = headCache.get(userId);
  if (hit && Date.now() - hit.at < 600_000) return hit.url;
  const j = await getJson(`https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=${userId}&size=420x420&format=Png&isCircular=false`);
  const url: string | null = j?.data?.[0]?.state === "Completed" ? j.data[0].imageUrl : null;
  if (headCache.size >= 200) headCache.delete(headCache.keys().next().value as number); // cache berbatas: tidak bocor memori
  headCache.set(userId, { url, at: Date.now() });
  return url;
}

export type RobloxProfile = {
  id: number; name: string; displayName: string; description: string; created: string | null; isBanned: boolean; verified: boolean;
  friends: number | null; followers: number | null; following: number | null;
};
export async function robloxProfile(userId: number): Promise<RobloxProfile | null> {
  const [u, f, fo, fg] = await Promise.all([
    getJson(`https://users.roblox.com/v1/users/${userId}`),
    getJson(`https://friends.roblox.com/v1/users/${userId}/friends/count`),
    getJson(`https://friends.roblox.com/v1/users/${userId}/followers/count`),
    getJson(`https://friends.roblox.com/v1/users/${userId}/followings/count`),
  ]);
  if (!u?.id) return null;
  return {
    id: u.id, name: u.name, displayName: u.displayName ?? u.name, description: String(u.description ?? ""), created: u.created ?? null,
    isBanned: u.isBanned === true, verified: u.hasVerifiedBadge === true,
    friends: f?.count ?? null, followers: fo?.count ?? null, following: fg?.count ?? null,
  };
}

export const profileUrl = (id: number) => `https://www.roblox.com/users/${id}/profile`;
// Roblox kadang mengabaikan gameInstanceId pada tautan https; karena itu embed juga memuat perintah ;goserver sebagai cadangan.
export const joinUrl = (placeId: number | string, jobId: string) =>
  `https://www.roblox.com/games/start?placeId=${placeId}&gameInstanceId=${encodeURIComponent(jobId)}`;
