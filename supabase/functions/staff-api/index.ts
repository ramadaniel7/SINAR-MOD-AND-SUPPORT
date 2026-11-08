// staff-api: used ONLY by trusted server-side callers (Discord bot, dashboard server routes).
// Auth: x-staff-key header. The caller resolves the human actor's role from a trusted source
// (Discord guild roles / dashboard session) and passes it in `actor`; this function re-validates
// that the role exists and applies the central policy for every operation.
import { db, handle, HttpError, isUserId, json, readJson, requireSecret, str } from "../_shared/core.ts";
import { Actor, audit, can, createAction, decideAction, roleInfo } from "../_shared/policy.ts";
import { formatVerification, verifyReport } from "../_shared/verify.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (v: unknown): v is string => typeof v === "string" && UUID.test(v);

async function actorFrom(raw: unknown): Promise<Actor> {
  const a = raw as Record<string, unknown> | undefined;
  if (!a || !["staff_discord", "staff_dashboard"].includes(String(a.type)) || !str(a.id, 1, 128) || !str(a.role_key, 3, 32)) {
    throw new HttpError(400, "invalid_actor");
  }
  if (!(await roleInfo(a.role_key as string))) throw new HttpError(403, "unknown_role");
  return { type: a.type as Actor["type"], id: a.id as string, roleKey: a.role_key as string };
}
const need = async (actor: Actor, perm: string) => { if (!(await can(actor, perm))) throw new HttpError(403, "forbidden"); };

Deno.serve(handle(async (req) => {
  requireSecret(req, "x-staff-key", "STAFF_API_KEY");
  const b = await readJson(req, 32768);
  const kind = String(b.kind);

  switch (kind) {
    case "create_action": {
      const actor = await actorFrom(b.actor);
      const res = await createAction({
        actor, source: actor.type === "staff_discord" ? "discord" : "dashboard",
        targetUserId: b.target_user_id as number, actionType: String(b.action_type),
        durationSeconds: typeof b.duration_seconds === "number" ? b.duration_seconds : null,
        permanent: b.permanent === true, publicReason: String(b.public_reason ?? ""),
        privateReason: String(b.private_reason ?? ""), idempotencyKey: String(b.idempotency_key ?? ""),
        reportId: isUuid(b.report_id) ? b.report_id : null,
      });
      return json(res, res.ok ? 200 : 422);
    }

    case "decide_action": {
      const actor = await actorFrom(b.actor);
      if (!isUuid(b.action_id) || !["approve", "reject"].includes(String(b.decision))) throw new HttpError(400, "invalid_input");
      const res = await decideAction(actor, b.action_id, b.decision as "approve" | "reject");
      return json(res, res.ok ? 200 : 422);
    }

    case "resolve_report": {
      const actor = await actorFrom(b.actor);
      await need(actor, "reports.review");
      const status = String(b.status);
      if (!isUuid(b.report_id) || !["in_review", "resolved", "dismissed", "duplicate"].includes(status)) throw new HttpError(400, "invalid_input");
      const patch: Record<string, unknown> = { status };
      if (status === "in_review") patch.assigned_to = actor.id;
      else {
        const note = str(b.resolution, 3, 1000);
        if (!note) throw new HttpError(400, "resolution_required");
        Object.assign(patch, { resolution: note, resolved_by: actor.id, resolved_at: new Date().toISOString() });
        if (isUuid(b.action_id)) patch.resolution_action_id = b.action_id;
      }
      const { data, error } = await db.from("reports").update(patch).eq("id", b.report_id).in("status", ["open", "in_review"]).select("id,report_code");
      if (error) { console.error("resolve_report", error.message); throw new HttpError(500, "db_error"); }
      if (!data?.length) return json({ ok: false, error: "not_open" }, 409);
      await audit(actor, "report.updated", "report", b.report_id, { status });
      return json({ ok: true, code: data[0].report_code });
    }

    case "announce": {
      const actor = await actorFrom(b.actor);
      await need(actor, "announce.global");
      const message = str(b.message, 3, 200);
      const key = str(b.idempotency_key, 8, 128);
      if (!message || !key) throw new HttpError(400, "invalid_input");
      const { data, error } = await db.from("command_queue").upsert({
        command_type: "announce_global", idempotency_key: `announce:${key}`,
        payload: { message, from: str(b.from, 1, 40) ?? "Staff" },
        expires_at: new Date(Date.now() + 5 * 60_000).toISOString(), created_by_actor: actor.id,
      }, { onConflict: "idempotency_key", ignoreDuplicates: true }).select("id");
      if (error) { console.error("announce", error.message); throw new HttpError(500, "db_error"); }
      await audit(actor, "announce.queued", "command", data?.[0]?.id ?? key, { length: message.length });
      return json({ ok: true, queued: !!data?.length });
    }

    case "lookup_player": {
      const actor = await actorFrom(b.actor);
      await need(actor, "players.read");
      if (!isUserId(b.user_id)) throw new HttpError(400, "invalid_user");
      const canViolations = await can(actor, "violations.read");
      const canHistory = await can(actor, "players.history.read");
      const [player, actions, vCount, vRecent, rCount, online] = await Promise.all([
        db.from("players").select("*").eq("roblox_user_id", b.user_id).maybeSingle(),
        canHistory ? db.from("moderation_actions").select("id,action_type,status,duration_seconds,is_permanent,public_reason,created_at,expires_at")
          .eq("target_user_id", b.user_id).order("created_at", { ascending: false }).limit(8) : Promise.resolve({ data: [] }),
        db.from("violations").select("id", { count: "exact", head: true }).eq("roblox_user_id", b.user_id),
        canViolations ? db.from("violations").select("detector,severity,status,created_at").eq("roblox_user_id", b.user_id).order("created_at", { ascending: false }).limit(5) : Promise.resolve({ data: [] }),
        db.from("reports").select("id", { count: "exact", head: true }).eq("reported_user_id", b.user_id),
        db.from("sessions").select("job_id").eq("roblox_user_id", b.user_id).is("ended_at", null).gt("last_seen_at", new Date(Date.now() - 120_000).toISOString()).limit(1),
      ]);
      return json({ ok: true, player: player.data, actions: actions.data, violations: vCount.count ?? 0, recent_violations: vRecent.data, reports: rCount.count ?? 0, online: !!online.data?.length });
    }

    case "health": {
      const actor = await actorFrom(b.actor);
      await need(actor, "system.health.read");
      const since = new Date(Date.now() - 24 * 3600_000).toISOString();
      const count = async (status: string) => (await db.from("command_queue").select("id", { count: "exact", head: true }).eq("status", status).gt("created_at", since)).count ?? 0;
      const [pending, processing, failed, executed, oldest, lastSession, pendingApprovals] = await Promise.all([
        count("pending"), count("processing"), count("failed"), count("executed"),
        db.from("command_queue").select("created_at").eq("status", "pending").order("created_at").limit(1).maybeSingle(),
        db.from("sessions").select("last_seen_at").order("last_seen_at", { ascending: false }).limit(1).maybeSingle(),
        db.from("moderation_actions").select("id", { count: "exact", head: true }).eq("status", "pending_approval"),
      ]);
      return json({
        ok: true, queue_24h: { pending, processing, failed, executed },
        oldest_pending_at: oldest.data?.created_at ?? null, last_game_server_contact: lastSession.data?.last_seen_at ?? null,
        pending_approvals: pendingApprovals.count ?? 0,
      });
    }

    // Public (no staff actor): a banned player files an appeal through Discord.
    case "create_appeal": {
      const message = str(b.message, 10, 1000);
      if (!isUserId(b.roblox_user_id) || !message || !str(b.discord_user_id, 15, 25)) throw new HttpError(400, "invalid_input");
      const { data: last } = await db.from("moderation_actions").select("id,action_type,is_permanent,expires_at,status")
        .eq("target_user_id", b.roblox_user_id).eq("status", "executed").in("action_type", ["ban", "unban"])
        .order("executed_at", { ascending: false }).limit(1).maybeSingle();
      const active = last && last.action_type === "ban" && (last.is_permanent || (last.expires_at && new Date(last.expires_at) > new Date()));
      if (!active) return json({ ok: false, error: "no_active_ban" }, 422);
      const { data, error } = await db.from("appeals").insert({
        action_id: last.id, roblox_user_id: b.roblox_user_id, message: `${message}\n\n[discord:${b.discord_user_id}]`.slice(0, 1000),
      }).select("appeal_code").single();
      if (error) return json({ ok: false, error: error.code === "23505" ? "appeal_already_open" : "db_error" }, 422);
      return json({ ok: true, code: data.appeal_code });
    }

    case "decide_appeal": {
      const actor = await actorFrom(b.actor);
      await need(actor, "appeals.decide");
      const accept = b.decision === "accept";
      if (!isUuid(b.appeal_id) || !["accept", "deny"].includes(String(b.decision))) throw new HttpError(400, "invalid_input");
      const note = str(b.note, 3, 1000);
      if (!note) throw new HttpError(400, "note_required");
      if (accept) await need(actor, "moderation.unban");
      const { data: ap, error } = await db.from("appeals").update({
        status: accept ? "accepted" : "denied", reviewed_by_actor: actor.id, review_note: note, reviewed_at: new Date().toISOString(),
      }).eq("id", b.appeal_id).in("status", ["open", "in_review"]).select("id,roblox_user_id,appeal_code").maybeSingle();
      if (error) { console.error("decide_appeal", error.message); throw new HttpError(500, "db_error"); }
      if (!ap) return json({ ok: false, error: "not_open" }, 409);
      await audit(actor, "appeal.decided", "appeal", ap.id, { decision: b.decision });
      if (accept) {
        const res = await createAction({
          actor, source: "appeal", targetUserId: ap.roblox_user_id, actionType: "unban",
          publicReason: "Appeal accepted", privateReason: note, idempotencyKey: `appeal-unban:${ap.id}`,
        });
        return json({ ok: true, code: ap.appeal_code, unban: res });
      }
      return json({ ok: true, code: ap.appeal_code });
    }

    // Called by the bot when a reporter submits a completed Discord ticket (no staff actor).
    case "ticket_report": {
      const evidence = Array.isArray(b.evidence) ? b.evidence : null;
      if (!str(b.idempotency_key, 8, 128) || !str(b.reporter_discord_id, 15, 25) || !isUserId(b.reported_user_id) ||
          !["cheating", "fail_roleplay", "harassment", "other"].includes(String(b.category)) ||
          !str(b.description, 1, 500) || !evidence || evidence.length < 1 || evidence.length > 10 ||
          evidence.some((e: any) => !e || typeof e.url !== "string" || !e.url.startsWith("https://discord.com/channels/") || e.url.length > 200) ||
          JSON.stringify(evidence).length > 4000) throw new HttpError(400, "invalid_input");
      const clean = evidence.map((e: any) => ({ name: String(e.name ?? "").slice(0, 60), kind: e.kind === "video" ? "video" : "image", size: Number(e.size) || 0, url: e.url }));
      const { data, error } = await db.rpc("submit_ticket_report", {
        p_idempotency_key: b.idempotency_key, p_reporter_discord: b.reporter_discord_id, p_reported: b.reported_user_id,
        p_category: b.category, p_description: b.description, p_evidence: clean, p_max_per_hour: 5, p_dup_window_minutes: 30,
      });
      if (error) { console.error("ticket_report", error.message); throw new HttpError(500, "db_error"); }
      const r = data?.[0];
      return json({ ok: true, outcome: r?.o_outcome, code: r?.o_report_code ?? null, report_id: r?.o_report_id ?? null });
    }

    // Pemeriksaan otomatis report (dipanggil bot saat report masuk ke channel staf).
    case "verify_report": {
      if (!isUuid(b.report_id)) throw new HttpError(400, "invalid_input");
      const v = await verifyReport(b.report_id);
      if (!v) return json({ ok: false, error: "not_found" }, 404);
      return json({ ok: true, level: v.level, score: v.score, text: formatVerification(v) });
    }

    // Statistik publik untuk /check: berapa pemain terkena ban (sementara & permanen). Tidak membuka data pribadi staf.
    case "ban_stats": {
      const { data: rows, error } = await db.from("moderation_actions")
        .select("target_user_id,action_type,is_permanent,duration_seconds,expires_at,executed_at,public_reason")
        .eq("status", "executed").in("action_type", ["ban", "unban"]).order("executed_at", { ascending: true }).limit(5000);
      if (error) { console.error("ban_stats", error.message); throw new HttpError(500, "db_error"); }
      const last = new Map<string, any>();
      for (const r of rows ?? []) last.set(String(r.target_user_id), r); // event terakhir per pemain
      const now = Date.now();
      let permanent = 0, temp = 0;
      for (const r of last.values()) {
        if (r.action_type !== "ban") continue;
        if (r.is_permanent) permanent++; else if (r.expires_at && Date.parse(r.expires_at) > now) temp++;
      }
      const bans = (rows ?? []).filter((r) => r.action_type === "ban");
      const week = now - 7 * 86_400_000;
      const { count: kicks } = await db.from("moderation_actions").select("id", { count: "exact", head: true }).eq("status", "executed").eq("action_type", "kick");
      const { count: warns } = await db.from("moderation_actions").select("id", { count: "exact", head: true }).eq("status", "executed").eq("action_type", "warn");
      const recent = bans.slice(-5).reverse();
      const ids = recent.map((r) => r.target_user_id);
      const { data: names } = ids.length ? await db.from("players").select("roblox_user_id,username").in("roblox_user_id", ids) : { data: [] };
      const nameOf = new Map((names ?? []).map((n) => [n.roblox_user_id, n.username]));
      return json({
        ok: true, total_bans: bans.length, permanent_active: permanent, temp_active: temp,
        last7d: bans.filter((r) => r.executed_at && Date.parse(r.executed_at) > week).length, kicks: kicks ?? 0, warns: warns ?? 0,
        recent: recent.map((r) => ({ name: nameOf.get(r.target_user_id) ?? `ID ${r.target_user_id}`, permanent: r.is_permanent, days: r.duration_seconds ? Math.round(r.duration_seconds / 86400) : null, reason: String(r.public_reason).slice(0, 80), at: r.executed_at })),
      });
    }

    // Staf menandai tiket "sedang ditinjau" (izin tickets.close dimiliki semua role staf).
    case "ticket_claim": {
      const actor = await actorFrom(b.actor);
      await need(actor, "tickets.close");
      if (!isUuid(b.report_id)) throw new HttpError(400, "invalid_input");
      const { data, error } = await db.from("reports").update({ status: "in_review", assigned_to: actor.id }).eq("id", b.report_id).in("status", ["open", "in_review"]).select("report_code");
      if (error) throw new HttpError(500, "db_error");
      if (!data?.length) return json({ ok: false, error: "not_open" }, 409);
      await audit(actor, "ticket.claimed", "report", b.report_id, {});
      return json({ ok: true, code: data[0].report_code });
    }

    // Staf menutup tiket: hasil (terbukti/ditolak) + keterangan untuk pelapor. Hanya staf (tickets.close).
    case "close_ticket_report": {
      const actor = await actorFrom(b.actor);
      await need(actor, "tickets.close");
      const outcome = String(b.outcome);
      const note = str(b.note, 10, 900);
      if (!isUuid(b.report_id) || !["resolved", "dismissed"].includes(outcome)) throw new HttpError(400, "invalid_input");
      if (!note) throw new HttpError(400, "note_required");
      const { data, error } = await db.from("reports").update({ status: outcome, resolution: note, resolved_by: actor.id, resolved_at: new Date().toISOString() })
        .eq("id", b.report_id).in("status", ["open", "in_review"]).select("report_code");
      if (error) { console.error("close_ticket_report", error.message); throw new HttpError(500, "db_error"); }
      if (!data?.length) return json({ ok: false, error: "not_open" }, 409);
      await audit(actor, "ticket.closed", "report", b.report_id, { outcome });
      return json({ ok: true, code: data[0].report_code });
    }

    // Called hourly by the bot (works without pg_cron, whose availability is unverified).
    case "maintenance": {
      const { data, error } = await db.rpc("purge_old_data");
      if (error) { console.error("maintenance", error.message); throw new HttpError(500, "db_error"); }
      return json({ ok: true, result: data });
    }

    default:
      throw new HttpError(400, "unknown_kind");
  }
}));
