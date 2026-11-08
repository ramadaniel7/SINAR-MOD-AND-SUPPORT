-- =============================================================================
-- 20261021000002_functions_triggers.sql
-- Helpers used by RLS (schema private) and trusted operations (schema public,
-- executable ONLY by service_role - i.e. our Edge Functions after they have
-- authenticated the caller). All SECURITY DEFINER functions pin search_path.
-- =============================================================================
begin;

-- ---------------------------------------------------------------------------
-- Generic triggers
-- ---------------------------------------------------------------------------
create or replace function private.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger trg_admin_members_updated   before update on public.admin_members
  for each row execute function private.set_updated_at();
create trigger trg_reports_updated         before update on public.reports
  for each row execute function private.set_updated_at();
create trigger trg_mod_actions_updated     before update on public.moderation_actions
  for each row execute function private.set_updated_at();
create trigger trg_command_queue_updated   before update on public.command_queue
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS helpers (private schema; callable by authenticated for policy evaluation)
-- ---------------------------------------------------------------------------
create or replace function private.has_permission(p_permission text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
      from public.admin_members m
      join public.role_permissions rp on rp.role_key = m.role_key
     where m.auth_user_id = (select auth.uid())
       and m.is_active
       and rp.permission_key = p_permission);
$$;

create or replace function private.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.admin_members m
     where m.auth_user_id = (select auth.uid()) and m.is_active);
$$;

-- ---------------------------------------------------------------------------
-- Audit log: writer + append-only enforcement
-- ---------------------------------------------------------------------------
create or replace function public.write_audit(
  p_actor_type text, p_actor_id text, p_actor_role text, p_action text,
  p_target_type text, p_target_id text, p_correlation_id uuid default null,
  p_details jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into public.audit_logs (actor_type, actor_id, actor_role_key, action,
                                 target_type, target_id, correlation_id, details)
  values (p_actor_type, p_actor_id, p_actor_role, p_action,
          p_target_type, p_target_id, p_correlation_id, coalesce(p_details, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

create or replace function private.audit_logs_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'audit_logs is append-only' using errcode = '42501';
end $$;

create trigger audit_logs_no_update_delete before update or delete on public.audit_logs
  for each row execute function private.audit_logs_immutable();
create trigger audit_logs_no_truncate before truncate on public.audit_logs
  for each statement execute function private.audit_logs_immutable();
-- NOTE: the table owner/superuser can still drop these triggers. That is an
-- infrastructure-level control (restrict DB access, export logs off-platform).

-- Safety-net audit for privilege-bearing tables (Edge Functions ALSO write a
-- richer app-level audit entry with the real human actor).
create or replace function private.audit_row_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  perform public.write_audit(
    'db_trigger',
    coalesce((select auth.uid())::text, 'service_role'),
    null,
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    coalesce(v_row ->> 'id',
             (v_row ->> 'role_key') || ':' || (v_row ->> 'permission_key'),
             v_row ->> 'role_key', v_row ->> 'key'),
    null,
    jsonb_build_object(
      'old', case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
      'new', case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end));
  return null;
end $$;

create trigger trg_audit_admin_members after insert or update or delete on public.admin_members
  for each row execute function private.audit_row_change();
create trigger trg_audit_role_permissions after insert or update or delete on public.role_permissions
  for each row execute function private.audit_row_change();
create trigger trg_audit_staff_roles after insert or update or delete on public.staff_roles
  for each row execute function private.audit_row_change();

create or replace function private.audit_action_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.write_audit(new.actor_type, new.actor_id, new.actor_role_key,
      'moderation_action.created', 'moderation_action', new.id::text, null,
      jsonb_build_object('action_type', new.action_type, 'target_user_id', new.target_user_id,
                         'is_permanent', new.is_permanent, 'duration_seconds', new.duration_seconds,
                         'source', new.source, 'status', new.status));
  elsif new.status is distinct from old.status then
    perform public.write_audit('db_trigger', coalesce(new.approved_by_actor, new.executed_job_id, 'system'), null,
      'moderation_action.status_changed', 'moderation_action', new.id::text, null,
      jsonb_build_object('from', old.status, 'to', new.status,
                         'execution_status', new.execution_status));
  end if;
  return null;
end $$;

create trigger trg_audit_mod_actions after insert or update on public.moderation_actions
  for each row execute function private.audit_action_change();

-- ---------------------------------------------------------------------------
-- Config versioning: every change is versioned, attributed, and kept in history
-- ---------------------------------------------------------------------------
create or replace function private.config_versioning()
returns trigger language plpgsql as $$
begin
  -- Every change must name who made it.
  if new.updated_by is null then
    raise exception 'anticheat_config.updated_by is required' using errcode = '23502';
  end if;
  -- A no-op rewrite is not versioned.
  if new.value is distinct from old.value then
    new.version := old.version + 1;
    new.updated_at := now();
    insert into public.config_history (key, version, old_value, new_value, changed_by)
    values (old.key, new.version, old.value, new.value, new.updated_by);
  end if;
  return new;
end $$;

create trigger trg_config_versioning before update on public.anticheat_config
  for each row execute function private.config_versioning();

-- ---------------------------------------------------------------------------
-- Replay protection for Roblox -> backend requests
-- Returns true exactly once per nonce, and only if the timestamp is fresh.
-- ---------------------------------------------------------------------------
create or replace function public.consume_nonce(
  p_nonce text, p_job_id text, p_request_ts timestamptz, p_max_skew_seconds int default 60)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if abs(extract(epoch from (now() - p_request_ts))) > p_max_skew_seconds then
    return false;
  end if;
  insert into public.api_nonces (nonce, job_id) values (p_nonce, p_job_id)
  on conflict (nonce) do nothing;
  return found;
end $$;

-- ---------------------------------------------------------------------------
-- Report submission: idempotent, rate-limited, duplicate-aware, race-safe
-- ---------------------------------------------------------------------------
create or replace function public.submit_report(
  p_idempotency_key text, p_reporter bigint, p_reported bigint, p_category text,
  p_description text, p_place_id bigint, p_job_id text,
  p_max_per_hour int default 5, p_dup_window_minutes int default 30)
returns table (o_report_id uuid, o_report_code text, o_outcome text)
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_code text; v_count int;
begin
  if p_reporter = p_reported then
    raise exception 'self_report_not_allowed' using errcode = '22023';
  end if;

  -- 1. Same request replayed -> return the original.
  select r.id, r.report_code into v_id, v_code
    from public.reports r where r.idempotency_key = p_idempotency_key;
  if found then
    return query select v_id, v_code, 'duplicate_request'::text; return;
  end if;

  -- 2. Per-reporter hourly rate limit.
  select count(*) into v_count
    from public.reports r join public.report_private rp on rp.report_id = r.id
   where rp.reporter_user_id = p_reporter and r.created_at > now() - interval '1 hour';
  if v_count >= p_max_per_hour then
    return query select null::uuid, null::text, 'rate_limited'::text; return;
  end if;

  -- 3. Same reporter, same target, same category recently -> duplicate.
  select r.id, r.report_code into v_id, v_code
    from public.reports r join public.report_private rp on rp.report_id = r.id
   where rp.reporter_user_id = p_reporter and r.reported_user_id = p_reported
     and r.category = p_category
     and r.created_at > now() - make_interval(mins => p_dup_window_minutes)
   limit 1;
  if found then
    return query select v_id, v_code, 'duplicate_recent'::text; return;
  end if;

  insert into public.reports (idempotency_key, reported_user_id, category, description, place_id, job_id)
  values (p_idempotency_key, p_reported, p_category, p_description, p_place_id, p_job_id)
  on conflict (idempotency_key) do nothing
  returning id, report_code into v_id, v_code;

  if v_id is null then  -- lost a race with an identical request
    select r.id, r.report_code into v_id, v_code
      from public.reports r where r.idempotency_key = p_idempotency_key;
    return query select v_id, v_code, 'duplicate_request'::text; return;
  end if;

  insert into public.report_private (report_id, reporter_user_id) values (v_id, p_reporter);
  perform public.write_audit('roblox_server', coalesce(p_job_id, 'unknown'), null,
    'report.created', 'report', v_id::text, null,
    jsonb_build_object('category', p_category, 'reported_user_id', p_reported));
  return query select v_id, v_code, 'created'::text;
end $$;

-- ---------------------------------------------------------------------------
-- Command state machine: approved action -> queued command
-- ---------------------------------------------------------------------------
create or replace function public.queue_action_execution(p_action_id uuid, p_ttl_seconds int default 600)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  a public.moderation_actions;
  v_job text; v_cmd uuid; v_payload jsonb; v_key text;
begin
  select * into a from public.moderation_actions where id = p_action_id for update;
  if not found then raise exception 'action_not_found' using errcode = 'P0002'; end if;
  if a.status <> 'approved' then
    raise exception 'action_not_approved (status=%)', a.status using errcode = '55000';
  end if;

  -- warn/kick can only be executed by the server that holds the player.
  if a.action_type in ('warn','kick') then
    select s.job_id into v_job
      from public.sessions s
     where s.roblox_user_id = a.target_user_id and s.ended_at is null
       and s.last_seen_at > now() - interval '2 minutes'
     order by s.last_seen_at desc limit 1;
    if v_job is null then raise exception 'target_not_online' using errcode = '55000'; end if;
  end if;

  select jsonb_build_object(
           'action_id', a.id, 'action_type', a.action_type,
           'target_user_id', a.target_user_id,
           'duration_seconds', a.duration_seconds, 'is_permanent', a.is_permanent,
           'public_reason', a.public_reason,
           'private_reason', left(coalesce(p.private_reason, ''), 1000))
    into v_payload
    from (select 1) x left join public.moderation_action_private p on p.action_id = a.id;

  v_key := 'action:' || a.id::text;
  insert into public.command_queue (command_type, idempotency_key, action_id, payload,
                                    target_job_id, expires_at, created_by_actor)
  values ('execute_action', v_key, a.id, v_payload, v_job,
          now() + make_interval(secs => p_ttl_seconds), a.actor_id)
  on conflict (idempotency_key) do nothing
  returning id into v_cmd;
  if v_cmd is null then
    select id into v_cmd from public.command_queue where idempotency_key = v_key;
  end if;

  update public.moderation_actions set status = 'queued', queued_at = now() where id = a.id;
  return v_cmd;
end $$;

-- ---------------------------------------------------------------------------
-- Claim (lease) commands. SKIP LOCKED = safe with many concurrent servers.
-- A lease that expires makes the command claimable again (at-least-once);
-- the Roblox worker MUST be idempotent per command id.
-- ---------------------------------------------------------------------------
create or replace function public.claim_commands(
  p_job_id text, p_limit int default 5, p_lease_seconds int default 30)
returns setof public.command_queue
language plpgsql security definer set search_path = '' as $$
begin
  -- Expire stale commands (and their still-queued actions).
  with expired as (
    update public.command_queue c
       set status = 'expired', completed_at = now(), lease_until = null
     where c.status in ('pending','processing') and c.expires_at <= now()
    returning c.action_id)
  update public.moderation_actions a set status = 'expired'
    from expired e where a.id = e.action_id and a.status = 'queued';

  -- Fail commands that exhausted their attempts without completing.
  with exhausted as (
    update public.command_queue c
       set status = 'failed', last_error = 'max_attempts_exceeded',
           completed_at = now(), lease_until = null
     where c.status = 'processing' and c.lease_until < now() and c.attempts >= c.max_attempts
    returning c.action_id)
  update public.moderation_actions a
     set status = 'failed', execution_status = 'failed', execution_error = 'max_attempts_exceeded'
    from exhausted e where a.id = e.action_id and a.status = 'queued';

  return query
  with picked as (
    select c.id from public.command_queue c
     where ((c.status = 'pending' and c.available_at <= now())
         or (c.status = 'processing' and c.lease_until < now()))
       and c.expires_at > now()
       and c.attempts < c.max_attempts
       and (c.target_job_id is null or c.target_job_id = p_job_id)
     order by c.created_at
     limit least(greatest(p_limit, 1), 20)
     for update skip locked)
  update public.command_queue q
     set status = 'processing', attempts = q.attempts + 1, claimed_by = p_job_id,
         lease_until = now() + make_interval(secs => p_lease_seconds)
    from picked where q.id = picked.id
  returning q.*;
end $$;

-- ---------------------------------------------------------------------------
-- Complete a command. Only the current lease holder may complete it.
-- The command AND its moderation action change state in ONE transaction.
-- Execution status is recorded separately from the requested action.
-- ---------------------------------------------------------------------------
create or replace function public.complete_command(
  p_id uuid, p_job_id text, p_outcome text,
  p_result jsonb default '{}'::jsonb, p_error text default null, p_retry_seconds int default 15)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.command_queue; v_wait double precision;
begin
  if p_outcome not in ('executed','failed','rejected') then
    raise exception 'invalid_outcome' using errcode = '22023';
  end if;
  select * into c from public.command_queue where id = p_id for update;
  if not found then raise exception 'command_not_found' using errcode = 'P0002'; end if;

  -- Idempotent completion by the same server.
  if c.status in ('executed','failed','rejected','expired') and c.claimed_by = p_job_id then
    return c.status;
  end if;
  if c.status <> 'processing' or c.claimed_by is distinct from p_job_id then
    raise exception 'not_lease_holder' using errcode = '55000';
  end if;

  -- Transient failure -> retry with exponential backoff (capped at 300s).
  if p_outcome = 'failed' and c.attempts < c.max_attempts and c.expires_at > now() then
    v_wait := least(p_retry_seconds * power(2, c.attempts - 1), 300);
    update public.command_queue
       set status = 'pending', available_at = now() + make_interval(secs => v_wait),
           lease_until = null, claimed_by = null, last_error = left(p_error, 500)
     where id = p_id;
    return 'pending';
  end if;

  update public.command_queue
     set status = p_outcome, result = p_result, last_error = left(p_error, 500),
         completed_at = now(), lease_until = null
   where id = p_id;

  if c.action_id is not null then
    update public.moderation_actions a
       set status = case p_outcome when 'executed' then 'executed'
                                   when 'failed'   then 'failed' else 'rejected' end,
           execution_status = case p_outcome when 'executed' then 'succeeded' else 'failed' end,
           executed_at = case when p_outcome = 'executed' then now() end,
           executed_job_id = p_job_id,
           execution_error = left(p_error, 500),
           expires_at = case when p_outcome = 'executed' and a.duration_seconds is not null
                             then now() + make_interval(secs => a.duration_seconds) end
     where a.id = c.action_id and a.status = 'queued';
  end if;

  perform public.write_audit('roblox_server', p_job_id, null, 'command.completed', 'command', p_id::text, null,
    jsonb_build_object('outcome', p_outcome, 'attempts', c.attempts, 'action_id', c.action_id,
                       'error', left(p_error, 200)));
  return p_outcome;
end $$;

-- ---------------------------------------------------------------------------
-- Retention (free tier = 500 MB). Moderation actions, appeals, audit logs and
-- confirmed violations are NEVER purged here.
-- Scheduling (pg_cron vs scheduled Edge Function) is NOT yet verified - see docs.
-- ---------------------------------------------------------------------------
create or replace function public.purge_old_data(
  p_sessions_days int default 30, p_nonce_hours int default 24,
  p_commands_days int default 30, p_dismissed_violations_days int default 90)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n_stale int; n_sess int; n_nonce int; n_cmd int; n_viol int;
begin
  update public.sessions set ended_at = last_seen_at, exit_reason = 'stale'
   where ended_at is null and last_seen_at < now() - interval '10 minutes';
  get diagnostics n_stale = row_count;

  delete from public.sessions
   where ended_at is not null and ended_at < now() - make_interval(days => p_sessions_days);
  get diagnostics n_sess = row_count;

  delete from public.api_nonces where seen_at < now() - make_interval(hours => p_nonce_hours);
  get diagnostics n_nonce = row_count;

  delete from public.command_queue
   where status in ('executed','failed','expired','rejected')
     and completed_at < now() - make_interval(days => p_commands_days);
  get diagnostics n_cmd = row_count;

  delete from public.violations
   where status = 'dismissed' and created_at < now() - make_interval(days => p_dismissed_violations_days);
  get diagnostics n_viol = row_count;

  return jsonb_build_object('stale_sessions_closed', n_stale, 'sessions_deleted', n_sess,
    'nonces_deleted', n_nonce, 'commands_deleted', n_cmd, 'violations_deleted', n_viol);
end $$;

-- ---------------------------------------------------------------------------
-- Privileges: everything in `public` that is a function is service_role-only.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
grant  execute on all functions in schema public to service_role;

revoke execute on all functions in schema private from public, anon, authenticated;
grant  execute on function private.has_permission(text), private.is_staff() to authenticated, service_role;
grant  execute on all functions in schema private to service_role;

commit;
