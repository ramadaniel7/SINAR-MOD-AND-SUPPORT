-- =============================================================================
-- 20261021000003_rls.sql
-- Row Level Security. Model:
--   * anon: no access to anything.
--   * authenticated: SELECT only, and only through a permission check
--     (private.has_permission). Registration must ALSO be disabled in Supabase
--     Auth (invite-only) - policies already deny non-members, this is defense in depth.
--   * ALL writes go through Edge Functions using service_role (bypasses RLS)
--     after the Edge Function has authorized the human actor. There are
--     intentionally NO insert/update/delete policies for authenticated.
-- =============================================================================
begin;

-- Enable RLS on every table in public.
alter table public.staff_roles               enable row level security;
alter table public.permissions               enable row level security;
alter table public.role_permissions          enable row level security;
alter table public.admin_members             enable row level security;
alter table public.players                   enable row level security;
alter table public.sessions                  enable row level security;
alter table public.violations                enable row level security;
alter table public.moderation_actions        enable row level security;
alter table public.moderation_action_private enable row level security;
alter table public.reports                   enable row level security;
alter table public.report_private            enable row level security;
alter table public.command_queue             enable row level security;
alter table public.appeals                   enable row level security;
alter table public.audit_logs                enable row level security;
alter table public.anticheat_config          enable row level security;
alter table public.config_history            enable row level security;
alter table public.api_nonces                enable row level security;  -- no policies: service_role only

-- Reset, then grant the minimum (RLS is a second gate on top of these grants).
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select on
  public.staff_roles, public.permissions, public.role_permissions, public.admin_members,
  public.players, public.sessions, public.violations,
  public.moderation_actions, public.moderation_action_private,
  public.reports, public.report_private,
  public.command_queue, public.appeals, public.audit_logs,
  public.anticheat_config, public.config_history
to authenticated;
-- api_nonces: deliberately not granted to anyone but service_role.

-- ---- Staff metadata -------------------------------------------------------
create policy staff_roles_select on public.staff_roles for select to authenticated
  using ((select private.is_staff()));
create policy permissions_select on public.permissions for select to authenticated
  using ((select private.is_staff()));
create policy role_permissions_select on public.role_permissions for select to authenticated
  using ((select private.is_staff()));

create policy admin_members_select on public.admin_members for select to authenticated
  using (auth_user_id = (select auth.uid()) or (select private.has_permission('staff.manage')));

-- ---- Players / sessions ---------------------------------------------------
create policy players_select on public.players for select to authenticated
  using ((select private.has_permission('players.read')));
create policy sessions_select on public.sessions for select to authenticated
  using ((select private.has_permission('players.read')));

-- ---- Anti-cheat evidence --------------------------------------------------
create policy violations_select on public.violations for select to authenticated
  using ((select private.has_permission('violations.read')));

-- ---- Moderation -----------------------------------------------------------
create policy mod_actions_select on public.moderation_actions for select to authenticated
  using ((select private.has_permission('players.history.read')));
create policy mod_actions_private_select on public.moderation_action_private for select to authenticated
  using ((select private.has_permission('moderation.read_private')));

-- ---- Reports (reporter identity needs a stronger permission) --------------
create policy reports_select on public.reports for select to authenticated
  using ((select private.has_permission('reports.read')));
create policy report_private_select on public.report_private for select to authenticated
  using ((select private.has_permission('reports.read_reporter')));

-- ---- Queue / appeals / audit / config -------------------------------------
create policy command_queue_select on public.command_queue for select to authenticated
  using ((select private.has_permission('commands.read')));
create policy appeals_select on public.appeals for select to authenticated
  using ((select private.has_permission('appeals.read')));
create policy audit_logs_select on public.audit_logs for select to authenticated
  using ((select private.has_permission('audit.read')));
create policy config_select on public.anticheat_config for select to authenticated
  using ((select private.has_permission('config.read')));
create policy config_history_select on public.config_history for select to authenticated
  using ((select private.has_permission('config.read')));

commit;
