// Central moderation policy. EVERY entry point (Roblox in-game staff, Discord bot,
// dashboard) goes through these functions, so authorization lives in ONE place.
import { db, isUserId, str } from "./core.ts";

export type Actor = {
  type: "staff_dashboard" | "staff_discord" | "staff_ingame" | "system";
  id: string;                 // dashboard member uuid / discord user id / roblox user id / "anticheat:<detector>"
  roleKey: string | null;     // resolved by the CALLER from a trusted source, never from user input
};
export type ActionSource = "discord" | "dashboard" | "ingame" | "anticheat" | "appeal";
export type Result<T = Record<string, unknown>> = ({ ok: true } & T) | { ok: false; error: string };

const TTL = 15_000;
const roleCache = new Map<string, { at: number; perms: Set<string>; rank: number }>();
const cfgCache = new Map<string, { at: number; value: any }>();

export async function roleInfo(roleKey: string | null) {
  if (!roleKey) return null;
  const hit = roleCache.get(roleKey);
  if (hit && Date.now() - hit.at < TTL) return hit;
  const [{ data: role }, { data: perms }] = await Promise.all([
    db.from("staff_roles").select("rank").eq("role_key", roleKey).maybeSingle(),
    db.from("role_permissions").select("permission_key").eq("role_key", roleKey),
  ]);
  if (!role) return null;
  const entry = { at: Date.now(), rank: role.rank as number, perms: new Set((perms ?? []).map((p) => p.permission_key as string)) };
  roleCache.set(roleKey, entry);
  return entry;
}

export async function can(actor: Actor, perm: string): Promise<boolean> {
  if (actor.type === "system") return false; // system actors never get staff permissions
  const info = await roleInfo(actor.roleKey);
  return !!info && info.perms.has(perm);
}

export async function getConfig<T = any>(key: string, fallback: T): Promise<T> {
  const hit = cfgCache.get(key);
  if (hit && Date.now() - hit.at < TTL) return hit.value as T;
  const { data } = await db.from("anticheat_config").select("value").eq("key", key).maybeSingle();
  const value = (data?.value ?? fallback) as T;
  cfgCache.set(key, { at: Date.now(), value });
  return value;
}

export async function audit(actor: Actor, action: string, targetType: string, targetId: string, details: Record<string, unknown> = {}) {
  const { error } = await db.rpc("write_audit", {
    p_actor_type: actor.type, p_actor_id: actor.id, p_actor_role: actor.roleKey,
    p_action: action, p_target_type: targetType, p_target_id: targetId,
    p_correlation_id: null, p_details: details,
  });
  if (error) console.error("audit_failed", action, error.message); // never silently ignore
}

export interface CreateActionInput {
  actor: Actor;
  source: ActionSource;
  targetUserId: number;
  actionType: string;
  durationSeconds?: number | null;
  permanent?: boolean;
  publicReason: string;
  privateReason: string;
  idempotencyKey: string;
  reportId?: string | null;
}

export async function createAction(i: CreateActionInput): Promise<Result<{ actionId: string; status: string; duplicate?: boolean }>> {
  // ---- 1. Input validation ------------------------------------------------
  if (!isUserId(i.targetUserId)) return { ok: false, error: "invalid_target" };
  if (!["warn", "kick", "ban", "unban"].includes(i.actionType)) return { ok: false, error: "invalid_action_type" };
  if (!str(i.publicReason, 3, 400) || !str(i.privateReason, 3, 2000)) return { ok: false, error: "invalid_reason" };
  if (!str(i.idempotencyKey, 8, 128)) return { ok: false, error: "invalid_idempotency_key" };
  const permanent = i.actionType === "ban" && i.permanent === true;
  const duration = i.actionType === "ban" && !permanent ? Number(i.durationSeconds) : null;

  // ---- 2. Idempotency: same key -> same action, never a second punishment ------
  const { data: existing } = await db.from("moderation_actions").select("id,status").eq("idempotency_key", i.idempotencyKey).maybeSingle();
  if (existing) return { ok: true, actionId: existing.id, status: existing.status, duplicate: true };

  // ---- 3. Authorization ---------------------------------------------------------
  const a = i.actor;
  if (a.type === "system") {
    // Automated systems may only warn/kick. Bans/unbans always need a human.
    if (!["warn", "kick"].includes(i.actionType)) return { ok: false, error: "system_cannot_ban" };
  } else {
    const perm = i.actionType === "warn" ? "moderation.warn"
      : i.actionType === "kick" ? "moderation.kick"
      : i.actionType === "unban" ? "moderation.unban"
      : permanent ? "moderation.ban.perm.request" : "moderation.ban.temp";
    // In-game staff are authorized by the Roblox server's own role matrix (helper = warn/kick/1-day ban only, etc.).
    // Discord/dashboard actors are checked against role_permissions. Role-based ban caps & hierarchy below apply to EVERY surface.
    if (a.type !== "staff_ingame" && !(await can(a, perm))) return { ok: false, error: "forbidden" };

    if (duration !== null) {
      const durations = await getConfig<Record<string, number | null>>("ban.durations_seconds", {});
      const allowed = Object.values(durations).filter((v): v is number => typeof v === "number");
      if (!allowed.includes(duration)) return { ok: false, error: "duration_not_allowed" };
      const maxByRole = await getConfig<Record<string, number>>("policy.ban_max_seconds_by_role", {});
      if (duration > (maxByRole[a.roleKey ?? ""] ?? 0)) return { ok: false, error: "duration_exceeds_role_limit" };
    }

    // Never act on yourself or on equal/higher-ranked staff.
    if (a.type === "staff_ingame" && a.id === String(i.targetUserId)) return { ok: false, error: "cannot_target_self" };
    const { data: targetStaff } = await db.from("admin_members").select("role_key").eq("roblox_user_id", i.targetUserId).eq("is_active", true).maybeSingle();
    if (targetStaff) {
      const [mine, theirs] = await Promise.all([roleInfo(a.roleKey), roleInfo(targetStaff.role_key)]);
      if (!mine || !theirs || theirs.rank >= mine.rank) return { ok: false, error: "target_outranks_actor" };
    }
  }

  // ---- 4. Insert (permanent bans wait for a SECOND person) -------------------------
  const status = permanent ? "pending_approval" : "approved";
  const { data: row, error } = await db.from("moderation_actions").insert({
    idempotency_key: i.idempotencyKey, target_user_id: i.targetUserId, action_type: i.actionType,
    duration_seconds: duration, is_permanent: permanent, public_reason: i.publicReason,
    source: i.source, actor_type: a.type, actor_id: a.id, actor_role_key: a.roleKey,
    status, report_id: i.reportId ?? null,
  }).select("id,status").single();
  if (error) {
    if (error.code === "23505") { // lost a race on the idempotency key
      const { data: again } = await db.from("moderation_actions").select("id,status").eq("idempotency_key", i.idempotencyKey).maybeSingle();
      if (again) return { ok: true, actionId: again.id, status: again.status, duplicate: true };
    }
    console.error("create_action_insert", error.message);
    return { ok: false, error: "db_error" };
  }
  const { error: pErr } = await db.from("moderation_action_private").insert({ action_id: row.id, private_reason: i.privateReason });
  if (pErr) console.error("create_action_private", pErr.message);

  if (status === "approved") return await queue(row.id);
  return { ok: true, actionId: row.id, status };
}

async function queue(actionId: string): Promise<Result<{ actionId: string; status: string }>> {
  const { error } = await db.rpc("queue_action_execution", { p_action_id: actionId, p_ttl_seconds: 600 });
  if (error) {
    const offline = error.message.includes("target_not_online");
    await db.from("moderation_actions").update({
      status: "rejected", execution_error: offline ? "target_not_online" : "queue_error",
    }).eq("id", actionId).in("status", ["approved", "pending_approval"]);
    return { ok: false, error: offline ? "target_not_online" : "queue_error" };
  }
  return { ok: true, actionId, status: "queued" };
}

export async function decideAction(actor: Actor, actionId: string, decision: "approve" | "reject"): Promise<Result<{ status: string }>> {
  if (!(await can(actor, "moderation.ban.perm.approve"))) return { ok: false, error: "forbidden" };
  const { data: a } = await db.from("moderation_actions").select("id,status,actor_id,is_permanent").eq("id", actionId).maybeSingle();
  if (!a) return { ok: false, error: "not_found" };
  if (a.status !== "pending_approval") return { ok: false, error: "not_pending" };
  if (a.actor_id === actor.id) return { ok: false, error: "self_approval_not_allowed" };

  const patch = decision === "approve"
    ? { status: "approved", approved_by_actor: actor.id, approved_at: new Date().toISOString() }
    : { status: "rejected", execution_error: `rejected_by:${actor.id}`.slice(0, 500) };
  // The status filter makes concurrent double-clicks safe: only one wins.
  const { data: upd, error } = await db.from("moderation_actions").update(patch).eq("id", actionId).eq("status", "pending_approval").select("id");
  if (error) { console.error("decide_action", error.message); return { ok: false, error: "db_error" }; }
  if (!upd?.length) return { ok: false, error: "not_pending" };

  await audit(actor, `moderation_action.${decision}`, "moderation_action", actionId, {});
  if (decision === "reject") return { ok: true, status: "rejected" };
  const q = await queue(actionId);
  return q.ok ? { ok: true, status: "queued" } : q;
}

/** Record a warn/kick that the game server already carried out (no queue, no second execution). */
export async function recordExecutedAction(i: {
  actor: Actor; targetUserId: number; actionType: string; publicReason: string; idempotencyKey: string; jobId: string;
}): Promise<Result<{ actionId: string }>> {
  if (!isUserId(i.targetUserId) || !["warn", "kick"].includes(i.actionType)) return { ok: false, error: "invalid_input" };
  const { data: existing } = await db.from("moderation_actions").select("id").eq("idempotency_key", i.idempotencyKey).maybeSingle();
  if (existing) return { ok: true, actionId: existing.id };
  const { data: row, error } = await db.from("moderation_actions").insert({
    idempotency_key: i.idempotencyKey, target_user_id: i.targetUserId, action_type: i.actionType,
    public_reason: i.publicReason, source: "ingame", actor_type: i.actor.type, actor_id: i.actor.id, actor_role_key: i.actor.roleKey,
    status: "executed", execution_status: "succeeded", executed_at: new Date().toISOString(), executed_job_id: i.jobId,
  }).select("id").single();
  if (error) { console.error("record_action", error.message); return { ok: false, error: "db_error" }; }
  await db.from("moderation_action_private").insert({ action_id: row.id, private_reason: "Dilakukan lewat aplikasi Staff in-game" });
  return { ok: true, actionId: row.id };
}
