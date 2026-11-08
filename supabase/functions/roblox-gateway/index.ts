// roblox-gateway: the ONLY door game servers use to reach the backend.
// Auth: shared secret header (x-sac-key) + single-use nonce + fresh timestamp.
// NOTE: the secret lives in a server-only Luau module. If you suspect a leak, rotate it
// (supabase secrets set ROBLOX_GATEWAY_KEY=... and update the Luau Config).
import { db, handle, HttpError, isUserId, json, readJson, requireSecret, str } from "../_shared/core.ts";
import { Actor, audit, createAction, getConfig, recordExecutedAction, roleInfo } from "../_shared/policy.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DETECTOR = /^[a-z0-9_.]{2,48}$/;
const arr = (v: unknown, max: number): any[] => {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max) throw new HttpError(400, "invalid_batch");
  return v;
};
const obj = (v: unknown, maxChars: number): Record<string, unknown> => {
  if (v === undefined || v === null) return {};
  // Roblox's HttpService:JSONEncode turns an EMPTY Lua table into [] (not {}). Treat an empty array as an empty object,
  // otherwise every request with no fields (claim, config, ...) is rejected with 400 and the command queue never drains.
  if (Array.isArray(v) && v.length === 0) return {};
  if (typeof v !== "object" || Array.isArray(v) || JSON.stringify(v).length > maxChars) throw new HttpError(400, "invalid_object");
  return v as Record<string, unknown>;
};

Deno.serve(handle(async (req) => {
  requireSecret(req, "x-sac-key", "ROBLOX_GATEWAY_KEY");
  const body = await readJson(req);

  const kind = str(body.kind, 2, 32);
  const nonce = str(body.nonce, 16, 128);
  const jobId = str(body.job_id, 1, 64);
  const placeId = typeof body.place_id === "number" ? body.place_id : null;
  const ts = typeof body.ts === "string" ? new Date(body.ts) : null;
  if (!kind || !nonce || !jobId || !ts || isNaN(ts.getTime())) throw new HttpError(400, "invalid_envelope");

  // Replay protection: fresh timestamp (±60s) and a nonce that can be used only once.
  const { data: fresh, error: nErr } = await db.rpc("consume_nonce", {
    p_nonce: nonce, p_job_id: jobId, p_request_ts: ts.toISOString(), p_max_skew_seconds: 60,
  });
  if (nErr) { console.error("nonce", nErr.message); throw new HttpError(500, "internal_error"); }
  if (fresh !== true) throw new HttpError(409, "replay_or_stale");

  const data = obj(body.data, 100_000);

  switch (kind) {
    // ---------------------------------------------------------------- sessions
    case "players_sync": {
      const joined = arr(data.joined, 50);
      const left = arr(data.left, 50);
      const online = arr(data.online, 100);
      if (joined.length) {
        const players = [], sessions = [];
        for (const j of joined) {
          if (!isUserId(j.user_id) || !str(j.username, 1, 50) || !str(j.session_key, 8, 128)) throw new HttpError(400, "invalid_join");
          players.push({ roblox_user_id: j.user_id, username: j.username, display_name: str(j.display_name, 0, 50), last_seen_at: new Date().toISOString() });
          sessions.push({ session_key: j.session_key, roblox_user_id: j.user_id, place_id: placeId ?? 0, job_id: jobId });
        }
        const p = await db.from("players").upsert(players, { onConflict: "roblox_user_id" });
        if (p.error) { console.error("players_upsert", p.error.message); throw new HttpError(500, "db_error"); }
        const s = await db.from("sessions").upsert(sessions, { onConflict: "session_key", ignoreDuplicates: true });
        if (s.error) { console.error("sessions_upsert", s.error.message); throw new HttpError(500, "db_error"); }
      }
      const leftKeys = left.map((l) => l?.session_key).filter((k) => typeof k === "string" && k.length <= 128);
      if (leftKeys.length) {
        await db.from("sessions").update({ ended_at: new Date().toISOString(), exit_reason: "left" }).in("session_key", leftKeys).is("ended_at", null);
      }
      const onlineKeys = online.filter((k) => typeof k === "string" && k.length <= 128);
      if (onlineKeys.length) {
        await db.from("sessions").update({ last_seen_at: new Date().toISOString() }).in("session_key", onlineKeys).is("ended_at", null);
      }
      return json({ ok: true });
    }

    // -------------------------------------------------------------- violations
    case "violations": {
      const items = arr(data.items, 20);
      const rows = [], ids = new Set<number>();
      for (const v of items) {
        const evidence = obj(v.evidence, 8000);
        if (!str(v.event_key, 8, 128) || !isUserId(v.user_id) || !DETECTOR.test(String(v.detector)) ||
            !Number.isInteger(v.severity) || v.severity < 1 || v.severity > 5 ||
            typeof v.score !== "number" || !(v.score >= 0 && v.score < 100000) ||
            !["detect_only", "enforced"].includes(v.mode)) throw new HttpError(400, "invalid_violation");
        ids.add(v.user_id);
        rows.push({
          event_key: v.event_key, roblox_user_id: v.user_id, detector: v.detector, severity: v.severity,
          score: v.score, mode: v.mode, mitigation: str(v.mitigation, 1, 64), evidence,
          place_id: placeId, job_id: jobId,
        });
      }
      if (rows.length) {
        // FK safety: make sure a player row exists (a real name arrives with players_sync).
        await db.from("players").upsert([...ids].map((id) => ({ roblox_user_id: id, username: "unknown" })), { onConflict: "roblox_user_id", ignoreDuplicates: true });
        const r = await db.from("violations").upsert(rows, { onConflict: "event_key", ignoreDuplicates: true });
        if (r.error) { console.error("violations_upsert", r.error.message); throw new HttpError(500, "db_error"); }
      }
      return json({ ok: true, accepted: rows.length });
    }

    // ----------------------------------------------------------------- reports
    case "report": {
      if (!str(data.idempotency_key, 8, 128) || !isUserId(data.reporter_user_id) || !isUserId(data.reported_user_id) ||
          !["cheating", "fail_roleplay", "harassment", "other"].includes(String(data.category)) ||
          !str(data.description, 1, 500)) throw new HttpError(400, "invalid_report");
      const limits = await getConfig("report.limits", { max_per_hour: 5, duplicate_window_minutes: 30 });
      const { data: rows, error } = await db.rpc("submit_report", {
        p_idempotency_key: data.idempotency_key, p_reporter: data.reporter_user_id, p_reported: data.reported_user_id,
        p_category: data.category, p_description: data.description, p_place_id: placeId, p_job_id: jobId,
        p_max_per_hour: limits.max_per_hour, p_dup_window_minutes: limits.duplicate_window_minutes,
      });
      if (error) {
        if (error.message.includes("self_report")) throw new HttpError(400, "self_report");
        console.error("submit_report", error.message); throw new HttpError(500, "db_error");
      }
      const r = rows?.[0];
      if (r?.o_outcome === "created" && r.o_report_id) {
        // konteks server (posisi, jumlah pemain, nama) untuk embed staf; gagal menyimpan tidak membatalkan report
        const context = obj(data.context, 3500);
        if (Object.keys(context).length) await db.from("reports").update({ context }).eq("id", r.o_report_id);
      }
      return json({ ok: true, outcome: r?.o_outcome, code: r?.o_report_code ?? null });
    }

    // ------------------------------------------------------------ command queue
    case "claim": {
      const { data: cmds, error } = await db.rpc("claim_commands", { p_job_id: jobId, p_limit: 5, p_lease_seconds: 30 });
      if (error) { console.error("claim", error.message); throw new HttpError(500, "db_error"); }
      return json({
        ok: true,
        commands: (cmds ?? []).map((c: any) => ({ id: c.id, type: c.command_type, payload: c.payload, attempts: c.attempts, expires_at: c.expires_at })),
      });
    }
    case "complete": {
      const outcome = String(data.outcome);
      if (typeof data.id !== "string" || !UUID.test(data.id) || !["executed", "failed", "rejected"].includes(outcome)) throw new HttpError(400, "invalid_complete");
      const { data: status, error } = await db.rpc("complete_command", {
        p_id: data.id, p_job_id: jobId, p_outcome: outcome, p_result: obj(data.result, 3000),
        p_error: str(data.error, 0, 500), p_retry_seconds: 15,
      });
      if (error) {
        if (error.message.includes("not_lease_holder")) throw new HttpError(409, "not_lease_holder");
        if (error.message.includes("command_not_found")) throw new HttpError(404, "command_not_found");
        console.error("complete", error.message); throw new HttpError(500, "db_error");
      }
      return json({ ok: true, status });
    }

    // ------------------------------------------------- in-game staff operations
    case "request_action": {
      const role = str(data.role_key, 3, 32);
      if (!isUserId(data.actor_user_id) || !role || !(await roleInfo(role))) throw new HttpError(400, "invalid_actor");
      const actor: Actor = { type: "staff_ingame", id: String(data.actor_user_id), roleKey: role };
      const res = await createAction({
        actor, source: "ingame", targetUserId: data.target_user_id as number, actionType: String(data.action_type),
        durationSeconds: typeof data.duration_seconds === "number" ? data.duration_seconds : null,
        permanent: data.permanent === true, publicReason: String(data.public_reason ?? ""),
        privateReason: String(data.private_reason ?? ""), idempotencyKey: String(data.idempotency_key ?? ""),
      });
      return json(res, res.ok ? 200 : 422);
    }
    // Staff action ALREADY executed by the game itself (e.g. the in-game Staff app's warn/kick): history only, no re-execution.
    case "record_action": {
      const role = str(data.role_key, 3, 32);
      if (!isUserId(data.actor_user_id) || !role || !(await roleInfo(role)) || !isUserId(data.target_user_id) ||
          !["warn", "kick"].includes(String(data.action_type)) || !str(data.idempotency_key, 8, 128)) throw new HttpError(400, "invalid_input");
      const actor: Actor = { type: "staff_ingame", id: String(data.actor_user_id), roleKey: role };
      const res = await recordExecutedAction({
        actor, targetUserId: data.target_user_id, actionType: String(data.action_type),
        publicReason: str(data.reason, 3, 400) ?? "Tindakan staf in-game", idempotencyKey: String(data.idempotency_key), jobId,
      });
      return json(res, res.ok ? 200 : 422);
    }
    case "audit": {
      const action = String(data.action);
      if (!/^ingame\.[a-z_]{2,40}$/.test(action) || !isUserId(data.actor_user_id)) throw new HttpError(400, "invalid_audit");
      const actor: Actor = { type: "staff_ingame", id: String(data.actor_user_id), roleKey: str(data.role_key, 3, 32) };
      await audit(actor, action, "player", String(data.target_id ?? "").slice(0, 64), obj(data.details, 2000));
      return json({ ok: true });
    }
    case "player_history": {
      if (!isUserId(data.user_id)) throw new HttpError(400, "invalid_user");
      const [{ data: actions }, { count: violations }, { count: reports }] = await Promise.all([
        db.from("moderation_actions").select("action_type,status,duration_seconds,is_permanent,public_reason,created_at,expires_at")
          .eq("target_user_id", data.user_id).order("created_at", { ascending: false }).limit(8),
        db.from("violations").select("id", { count: "exact", head: true }).eq("roblox_user_id", data.user_id),
        db.from("reports").select("id", { count: "exact", head: true }).eq("reported_user_id", data.user_id),
      ]);
      return json({ ok: true, actions: actions ?? [], violations: violations ?? 0, reports: reports ?? 0 });
    }

    // Staff money grant (;kasihuang / ;kasihsaldo): financial trail + "helper may give the same player only ONCE" rule.
    case "money_grant": {
      const role = str(data.role_key, 3, 32);
      if (!isUserId(data.actor_user_id) || !role || !(await roleInfo(role)) || !isUserId(data.target_user_id) ||
          !["kasihuang", "kasihsaldo"].includes(String(data.command)) ||
          !Number.isInteger(data.amount) || (data.amount as number) < 1 || (data.amount as number) > 1e10) throw new HttpError(400, "invalid_input");
      const hours = Number.isInteger(data.window_hours) && (data.window_hours as number) > 0 ? data.window_hours : null;
      const { data: outcome, error } = await db.rpc("record_money_grant", {
        p_actor: data.actor_user_id, p_role: role, p_command: data.command, p_target: data.target_user_id,
        p_amount: data.amount, p_enforce_once: data.enforce === true, p_window_hours: hours,
      });
      if (error) { console.error("money_grant", error.message); throw new HttpError(500, "db_error"); }
      return json({ ok: true, outcome });
    }
    case "recent_bans": {
      const { data: bans } = await db.from("moderation_actions")
        .select("target_user_id,duration_seconds,is_permanent,public_reason,status,created_at")
        .eq("action_type", "ban").in("status", ["executed", "queued", "pending_approval"]).order("created_at", { ascending: false }).limit(10);
      return json({ ok: true, bans: bans ?? [] });
    }
    case "open_reports": { // reporter identity is never returned
      const { data: reps, count } = await db.from("reports").select("report_code,reported_user_id,category,status,created_at", { count: "exact" })
        .in("status", ["open", "in_review"]).order("created_at", { ascending: false }).limit(8);
      return json({ ok: true, reports: reps ?? [], total: count ?? 0 });
    }

    // ------------------------------------------------------------------ config
    case "config": {
      const [mode, cmd, durations] = await Promise.all([
        getConfig("enforcement.mode", { mode: "detect_only", auto_kick_enabled: false, auto_ban_enabled: false }),
        getConfig("command.defaults", { poll_interval_seconds: 5 }),
        getConfig("ban.durations_seconds", {}),
      ]);
      return json({ ok: true, enforcement: mode, command: cmd, durations });
    }

    default:
      throw new HttpError(400, "unknown_kind");
  }
}));
