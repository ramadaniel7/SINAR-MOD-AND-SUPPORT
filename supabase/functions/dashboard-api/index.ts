// dashboard-api: dipanggil LANGSUNG dari browser (dashboard statis di GitHub Pages) memakai JWT login staf.
// TIDAK ADA kunci rahasia di web: identitas = JWT pengguna, otorisasi = role di tabel admin_members + izin di role_permissions.
// CORS dibatasi ke origin di secret DASHBOARD_ORIGINS (mis. https://username.github.io).
import { corsHeaders, db, HttpError, isUserId, readJson, str } from "../_shared/core.ts";
import { Actor, audit, can, createAction, decideAction, roleInfo } from "../_shared/policy.ts";
import { formatVerification, verifyReport } from "../_shared/verify.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (v: unknown): v is string => typeof v === "string" && UUID.test(v);

function reply(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...corsHeaders(req) } });
}

async function resolveRoblox(input: string): Promise<{ id: number; name: string } | null> {
  const t = input.trim();
  try {
    if (/^\d{1,13}$/.test(t)) {
      const r = await fetch(`https://users.roblox.com/v1/users/${t}`, { signal: AbortSignal.timeout(8000) });
      const j = await r.json().catch(() => null);
      return r.ok && j?.id ? { id: j.id, name: j.name } : null;
    }
    if (!/^[A-Za-z0-9_]{3,20}$/.test(t)) return null;
    const r = await fetch("https://users.roblox.com/v1/usernames/users", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ usernames: [t], excludeBannedUsers: false }), signal: AbortSignal.timeout(8000),
    });
    const j = await r.json().catch(() => null);
    const u = j?.data?.[0];
    return r.ok && u?.id ? { id: u.id, name: u.name } : null;
  } catch { return null; }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  try {
    if (req.method !== "POST") throw new HttpError(405, "method_not_allowed");
    // 1) Autentikasi: JWT pengguna (BUKAN kunci bersama)
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (token.length < 20) throw new HttpError(401, "unauthorized");
    const { data: u, error: uErr } = await db.auth.getUser(token);
    if (uErr || !u?.user) throw new HttpError(401, "unauthorized");
    const { data: m } = await db.from("admin_members").select("id,role_key,is_active").eq("auth_user_id", u.user.id).maybeSingle();
    if (!m?.is_active || !(await roleInfo(m.role_key))) throw new HttpError(403, "not_staff");
    const actor: Actor = { type: "staff_dashboard", id: m.id, roleKey: m.role_key };

    const b = await readJson(req, 16384);
    const kind = String(b.kind);

    if (kind === "me") {
      const { data: perms } = await db.from("role_permissions").select("permission_key").eq("role_key", m.role_key);
      return reply(req, { ok: true, member_id: m.id, role: m.role_key, perms: (perms ?? []).map((p) => p.permission_key) });
    }

    if (kind === "create_action") {
      const target = await resolveRoblox(String(b.target ?? ""));
      if (!target) return reply(req, { ok: false, error: "player_not_found" }, 422);
      const permanent = b.permanent === true;
      const res = await createAction({
        actor, source: "dashboard", targetUserId: target.id, actionType: String(b.action_type),
        durationSeconds: typeof b.duration_seconds === "number" ? b.duration_seconds : null, permanent,
        publicReason: String(b.public_reason ?? ""), privateReason: String(b.private_reason ?? "").length >= 3 ? String(b.private_reason) : `Dibuat dari dashboard oleh ${m.id}`,
        idempotencyKey: String(b.idempotency_key ?? ""), reportId: isUuid(b.report_id) ? b.report_id : null,
      });
      return reply(req, { ...res, target: target.name }, res.ok ? 200 : 422);
    }

    if (kind === "decide_action") {
      if (!isUuid(b.action_id) || !["approve", "reject"].includes(String(b.decision))) throw new HttpError(400, "invalid_input");
      const res = await decideAction(actor, b.action_id, b.decision as "approve" | "reject");
      return reply(req, res, res.ok ? 200 : 422);
    }

    // Staf mengubah ALASAN PUBLIK ban permanen (yang tampil di embed "Player Banned") selama masih menunggu persetujuan.
    if (kind === "update_reason") {
      const reason = str(b.public_reason, 3, 400);
      if (!isUuid(b.action_id) || !reason) throw new HttpError(400, "invalid_input");
      const { data: a } = await db.from("moderation_actions").select("id,status,actor_id").eq("id", b.action_id).maybeSingle();
      if (!a) return reply(req, { ok: false, error: "not_found" }, 404);
      if (a.status !== "pending_approval") return reply(req, { ok: false, error: "not_pending" }, 409);
      if (a.actor_id !== actor.id && !(await can(actor, "moderation.ban.perm.approve"))) throw new HttpError(403, "forbidden");
      const { error } = await db.from("moderation_actions").update({ public_reason: reason }).eq("id", b.action_id).eq("status", "pending_approval");
      if (error) throw new HttpError(500, "db_error");
      await audit(actor, "moderation_action.reason_edited", "moderation_action", b.action_id, {});
      return reply(req, { ok: true });
    }

    if (kind === "resolve_report") {
      if (!(await can(actor, "reports.review"))) throw new HttpError(403, "forbidden");
      const status = String(b.status);
      if (!isUuid(b.report_id) || !["in_review", "resolved", "dismissed", "duplicate"].includes(status)) throw new HttpError(400, "invalid_input");
      const patch: Record<string, unknown> = { status };
      if (status === "in_review") patch.assigned_to = actor.id;
      else {
        const note = str(b.resolution, 3, 1000);
        if (!note) throw new HttpError(400, "resolution_required");
        Object.assign(patch, { resolution: note, resolved_by: actor.id, resolved_at: new Date().toISOString() });
      }
      const { data, error } = await db.from("reports").update(patch).eq("id", b.report_id).in("status", ["open", "in_review"]).select("id");
      if (error) throw new HttpError(500, "db_error");
      if (!data?.length) return reply(req, { ok: false, error: "not_open" }, 409);
      await audit(actor, "report.updated", "report", b.report_id, { status });
      return reply(req, { ok: true });
    }

    if (kind === "verify_report") {
      if (!(await can(actor, "reports.read"))) throw new HttpError(403, "forbidden");
      if (!isUuid(b.report_id)) throw new HttpError(400, "invalid_input");
      const v = await verifyReport(b.report_id);
      return v ? reply(req, { ok: true, level: v.level, score: v.score, checks: v.checks, text: formatVerification(v) }) : reply(req, { ok: false, error: "not_found" }, 404);
    }

    throw new HttpError(400, "unknown_kind");
  } catch (e) {
    if (e instanceof HttpError) return reply(req, { ok: false, error: e.code }, e.status);
    console.error("dashboard-api", e instanceof Error ? e.message : e);
    return reply(req, { ok: false, error: "internal_error" }, 500);
  }
});
