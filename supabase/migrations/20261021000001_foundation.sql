-- =============================================================================
-- 20261021000001_foundation.sql
-- Smart Anticheat & Admin Panel - Phase 2: schema foundation
--
-- Principles:
--   * Deny by default: anon/authenticated get NO privileges unless granted in 0003.
--   * Invariants live in the database (CHECK constraints), not only in app code.
--   * Sensitive data (reporter identity, private reasons, evidence refs) lives in
--     separate *_private tables so RLS can protect it independently.
-- Rollback: see docs/PHASE2.md.
-- =============================================================================
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;  -- needed by RLS helper functions

-- Deny-by-default for everything created from here on (Supabase grants broadly by default).
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema private revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- Staff, roles, permissions
-- ---------------------------------------------------------------------------
create table public.staff_roles (
  role_key        text primary key check (role_key ~ '^[a-z_]{3,32}$'),
  display_name    text not null check (char_length(display_name) between 1 and 64),
  rank            smallint not null unique check (rank between 1 and 100),
  discord_role_id text unique check (discord_role_id ~ '^[0-9]{15,25}$'),
  created_at      timestamptz not null default now()
);

create table public.permissions (
  permission_key text primary key check (permission_key ~ '^[a-z_]+(\.[a-z_]+)+$'),
  description    text not null,
  is_sensitive   boolean not null default false
);

create table public.role_permissions (
  role_key       text not null references public.staff_roles(role_key) on delete cascade,
  permission_key text not null references public.permissions(permission_key) on delete cascade,
  primary key (role_key, permission_key)
);

-- Dashboard identities. Discord staff are resolved live from Discord roles
-- (staff_roles.discord_role_id); in-game staff come from the Luau UserId list.
create table public.admin_members (
  id              uuid primary key default gen_random_uuid(),
  auth_user_id    uuid unique references auth.users(id) on delete set null,
  roblox_user_id  bigint unique check (roblox_user_id > 0),
  discord_user_id text unique check (discord_user_id ~ '^[0-9]{15,25}$'),
  role_key        text not null references public.staff_roles(role_key),
  is_active       boolean not null default true,
  note            text check (char_length(note) <= 500),
  created_by      uuid references public.admin_members(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deactivated_at  timestamptz,
  constraint admin_has_identity check (
    auth_user_id is not null or roblox_user_id is not null or discord_user_id is not null)
);
create index admin_members_role_idx on public.admin_members(role_key) where is_active;

-- ---------------------------------------------------------------------------
-- Players and sessions
-- ---------------------------------------------------------------------------
create table public.players (
  roblox_user_id bigint primary key check (roblox_user_id > 0),
  username       text not null check (char_length(username) between 1 and 50),
  display_name   text check (char_length(display_name) <= 50),
  first_seen_at  timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  session_count  integer not null default 0 check (session_count >= 0)
);

create table public.sessions (
  id             uuid primary key default gen_random_uuid(),
  session_key    text not null unique check (char_length(session_key) between 8 and 128), -- idempotency
  roblox_user_id bigint not null references public.players(roblox_user_id) on delete cascade,
  place_id       bigint not null,
  job_id         text not null check (char_length(job_id) between 1 and 64),
  started_at     timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  ended_at       timestamptz,
  exit_reason    text check (char_length(exit_reason) <= 64)
);
create index sessions_user_started_idx on public.sessions(roblox_user_id, started_at desc);
create index sessions_online_idx on public.sessions(roblox_user_id) where ended_at is null;
create index sessions_job_online_idx on public.sessions(job_id) where ended_at is null;

-- ---------------------------------------------------------------------------
-- Anti-cheat violations (evidence trail)
-- ---------------------------------------------------------------------------
create table public.violations (
  id             uuid primary key default gen_random_uuid(),
  event_key      text not null unique check (char_length(event_key) between 8 and 128), -- idempotency
  roblox_user_id bigint not null references public.players(roblox_user_id) on delete restrict,
  session_id     uuid references public.sessions(id) on delete set null,
  detector       text not null check (detector ~ '^[a-z0-9_.]{2,48}$'),
  severity       smallint not null check (severity between 1 and 5),
  score          numeric(7,2) not null check (score >= 0),
  mode           text not null check (mode in ('detect_only','enforced')),
  mitigation     text check (char_length(mitigation) <= 64),
  evidence       jsonb not null default '{}'::jsonb
                 check (jsonb_typeof(evidence) = 'object' and octet_length(evidence::text) <= 8192),
  status         text not null default 'open' check (status in ('open','reviewed','dismissed','confirmed')),
  reviewed_by    text,
  reviewed_at    timestamptz,
  place_id       bigint,
  job_id         text check (char_length(job_id) <= 64),
  created_at     timestamptz not null default now(),
  constraint violation_review_pair check ((reviewed_by is null) = (reviewed_at is null))
);
create index violations_user_idx   on public.violations(roblox_user_id, created_at desc);
create index violations_status_idx on public.violations(status, created_at desc);

-- ---------------------------------------------------------------------------
-- Moderation actions (requested action != executed action)
-- ---------------------------------------------------------------------------
create table public.moderation_actions (
  id                uuid primary key default gen_random_uuid(),
  idempotency_key   text not null unique check (char_length(idempotency_key) between 8 and 128),
  target_user_id    bigint not null check (target_user_id > 0),
  action_type       text not null check (action_type in ('warn','kick','ban','unban')),
  duration_seconds  bigint check (duration_seconds is null or duration_seconds between 3600 and 31536000),
  is_permanent      boolean not null default false,
  public_reason     text not null check (char_length(public_reason) between 3 and 400), -- BanAsync DisplayReason max 400
  source            text not null check (source in ('anticheat','discord','dashboard','ingame','appeal')),
  actor_type        text not null check (actor_type in ('staff_dashboard','staff_discord','staff_ingame','system')),
  actor_id          text not null check (char_length(actor_id) between 1 and 128),
  actor_role_key    text,
  status            text not null default 'pending_approval' check (status in (
                      'pending_approval','approved','queued','executed','failed','rejected','revoked','expired')),
  approved_by_actor text,
  approved_at       timestamptz,
  queued_at         timestamptz,
  execution_status  text not null default 'not_attempted'
                    check (execution_status in ('not_attempted','succeeded','failed')),
  executed_at       timestamptz,
  executed_job_id   text,
  execution_error   text check (char_length(execution_error) <= 500),
  expires_at        timestamptz,            -- when a temp ban ends (set on successful execution)
  report_id         uuid,                   -- FK added after reports
  violation_ids     uuid[] not null default '{}' check (cardinality(violation_ids) <= 50),
  revoked_at        timestamptz,
  revoked_by_actor  text,
  revoke_reason     text check (char_length(revoke_reason) <= 400),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- bans need exactly one of {duration, permanent}; nothing else may carry a duration
  constraint ma_duration_shape check (
    (action_type = 'ban' and ((is_permanent and duration_seconds is null)
                           or (not is_permanent and duration_seconds is not null)))
    or (action_type <> 'ban' and not is_permanent and duration_seconds is null)),
  constraint ma_approval_pair check ((approved_by_actor is null) = (approved_at is null)),
  -- FOUR-EYES: a permanent ban can never proceed without a DIFFERENT approver
  -- (this also blocks the anti-cheat from approving its own permanent bans).
  constraint ma_perm_requires_second_approver check (
    not (is_permanent and status in ('approved','queued','executed'))
    or (approved_by_actor is not null and approved_by_actor <> actor_id)),
  constraint ma_executed_consistency check (status <> 'executed' or execution_status = 'succeeded')
);
create index ma_target_idx on public.moderation_actions(target_user_id, created_at desc);
create index ma_open_idx   on public.moderation_actions(status) where status in ('pending_approval','queued');

create table public.moderation_action_private (
  action_id      uuid primary key references public.moderation_actions(id) on delete cascade,
  private_reason text not null check (char_length(private_reason) between 3 and 2000),
  evidence_refs  jsonb not null default '[]'::jsonb
                 check (jsonb_typeof(evidence_refs) = 'array' and octet_length(evidence_refs::text) <= 4096)
);

-- ---------------------------------------------------------------------------
-- Player reports (reporter identity isolated for privacy)
-- ---------------------------------------------------------------------------
create table public.reports (
  id               uuid primary key default gen_random_uuid(),
  report_code      text not null unique default ('RPT-' || upper(substr(md5(gen_random_uuid()::text), 1, 8))),
  idempotency_key  text not null unique check (char_length(idempotency_key) between 8 and 128),
  reported_user_id bigint not null check (reported_user_id > 0),
  category         text not null check (category in ('cheating','fail_roleplay','harassment','other')),
  description      text not null check (char_length(description) between 1 and 500), -- filtered by the game server first
  place_id         bigint,
  job_id           text check (char_length(job_id) <= 64),
  status           text not null default 'open' check (status in ('open','in_review','resolved','dismissed','duplicate')),
  assigned_to      text,
  resolution       text check (char_length(resolution) <= 1000),
  resolved_by      text,
  resolved_at      timestamptz,
  resolution_action_id uuid references public.moderation_actions(id) on delete set null,
  discord_message_id text check (discord_message_id ~ '^[0-9]{15,25}$'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint report_resolution_pair check (
    (status in ('resolved','dismissed','duplicate')) = (resolved_at is not null and resolved_by is not null))
);
create index reports_status_idx on public.reports(status, created_at desc);
create index reports_reported_idx on public.reports(reported_user_id, created_at desc);

create table public.report_private (
  report_id        uuid primary key references public.reports(id) on delete cascade,
  reporter_user_id bigint not null check (reporter_user_id > 0),
  evidence_refs    jsonb not null default '[]'::jsonb
                   check (jsonb_typeof(evidence_refs) = 'array' and octet_length(evidence_refs::text) <= 4096)
);
create index report_private_reporter_idx on public.report_private(reporter_user_id);

alter table public.moderation_actions
  add constraint ma_report_fk foreign key (report_id) references public.reports(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Durable command queue (external request -> Roblox server execution)
-- ---------------------------------------------------------------------------
create table public.command_queue (
  id               uuid primary key default gen_random_uuid(),
  command_type     text not null check (command_type in
                     ('execute_action','announce_global','announce_server','refresh_config')),
  idempotency_key  text not null unique check (char_length(idempotency_key) between 8 and 160),
  action_id        uuid references public.moderation_actions(id) on delete set null,
  payload          jsonb not null check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 8192),
  target_job_id    text check (char_length(target_job_id) <= 64),  -- null = any server may claim
  status           text not null default 'pending'
                   check (status in ('pending','processing','executed','failed','expired','rejected')),
  attempts         smallint not null default 0 check (attempts >= 0),
  max_attempts     smallint not null default 5 check (max_attempts between 1 and 10),
  available_at     timestamptz not null default now(),             -- backoff gate
  lease_until      timestamptz,
  claimed_by       text,
  expires_at       timestamptz not null,
  result           jsonb check (result is null or octet_length(result::text) <= 4096),
  last_error       text check (char_length(last_error) <= 500),
  created_by_actor text not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  completed_at     timestamptz,
  constraint cq_expiry_after_creation check (expires_at > created_at)
);
create index cq_claim_idx on public.command_queue(available_at, created_at)
  where status in ('pending','processing');

-- ---------------------------------------------------------------------------
-- Appeals
-- ---------------------------------------------------------------------------
create table public.appeals (
  id                uuid primary key default gen_random_uuid(),
  appeal_code       text not null unique default ('APL-' || upper(substr(md5(gen_random_uuid()::text), 1, 8))),
  action_id         uuid not null references public.moderation_actions(id) on delete restrict,
  roblox_user_id    bigint not null check (roblox_user_id > 0),
  message           text not null check (char_length(message) between 10 and 1000),
  status            text not null default 'open' check (status in ('open','in_review','accepted','denied','withdrawn')),
  reviewed_by_actor text,
  review_note       text check (char_length(review_note) <= 1000),
  reviewed_at       timestamptz,
  created_at        timestamptz not null default now(),
  constraint appeal_review_pair check (
    (status in ('accepted','denied')) = (reviewed_at is not null and reviewed_by_actor is not null))
);
create unique index appeals_one_active_per_action on public.appeals(action_id)
  where status in ('open','in_review');

-- ---------------------------------------------------------------------------
-- Audit log (append-only; enforced by triggers in 0002)
-- ---------------------------------------------------------------------------
create table public.audit_logs (
  id             bigint generated always as identity primary key,
  occurred_at    timestamptz not null default now(),
  actor_type     text not null,
  actor_id       text not null,
  actor_role_key text,
  action         text not null check (action ~ '^[a-z_]+(\.[a-z_]+)+$'),
  target_type    text,
  target_id      text,
  correlation_id uuid,
  details        jsonb not null default '{}'::jsonb check (octet_length(details::text) <= 8192)
);
create index audit_time_idx   on public.audit_logs(occurred_at desc);
create index audit_actor_idx  on public.audit_logs(actor_id, occurred_at desc);
create index audit_target_idx on public.audit_logs(target_type, target_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Configuration (+ history) and replay-protection nonces
-- ---------------------------------------------------------------------------
create table public.anticheat_config (
  key        text primary key check (key ~ '^[a-z0-9_.]{2,64}$'),
  value      jsonb not null check (octet_length(value::text) <= 16384),
  version    bigint not null default 1,
  updated_by text,
  updated_at timestamptz not null default now()
);
create table public.config_history (
  id         bigint generated always as identity primary key,
  key        text not null,
  version    bigint not null,
  old_value  jsonb,
  new_value  jsonb,
  changed_by text not null,
  changed_at timestamptz not null default now()
);
create index config_history_key_idx on public.config_history(key, changed_at desc);

create table public.api_nonces (
  nonce   text primary key check (char_length(nonce) between 16 and 128),
  job_id  text not null check (char_length(job_id) <= 64),
  seen_at timestamptz not null default now()
);
create index api_nonces_seen_idx on public.api_nonces(seen_at);

commit;
