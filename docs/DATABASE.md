# Catatan Database (migrasi 0001–0007)

## Files
| File | Purpose |
|---|---|
| `supabase/migrations/20261021000001_foundation.sql` | Tables, constraints, indexes |
| `supabase/migrations/20261021000002_functions_triggers.sql` | RLS helpers, audit, queue state machine, replay protection, retention |
| `supabase/migrations/20261021000003_rls.sql` | Enable RLS, minimal grants, permission-based SELECT policies |
| `supabase/migrations/20261021000004_notifications.sql` | Kolom penanda notifikasi Discord |
| `supabase/migrations/20261021000005_tickets.sql` | Tabel `discord_tickets`, kolom pelapor Discord, fungsi `submit_ticket_report` |
| `supabase/seed.sql` | Staff roles (with your Discord role IDs), permission matrix, safe default config |
| `supabase/tests/01_invariants_and_rls.test.sql` | 27 pgTAP tests |
| `.env.example` | Placeholder variable names only |

## Security model (what is enforced where)
- **anon**: zero access. **authenticated**: SELECT only, each table gated by `private.has_permission(...)`.
  There are no INSERT/UPDATE/DELETE policies: every write goes through an Edge Function using `service_role`
  *after* it authorizes the human actor.
- **Four-eyes on permanent bans is a DB constraint** (`ma_perm_requires_second_approver`): not bypassable by a buggy
  Edge Function, and the anti-cheat (`actor_id = 'anticheat:…'`) can never approve its own permanent ban.
- **Reporter identity** (`report_private`) and **private reasons / evidence refs** (`moderation_action_private`) are
  separate tables with stronger permissions (`reports.read_reporter`, `moderation.read_private`).
- **Audit log is append-only** (triggers block UPDATE/DELETE/TRUNCATE). Table owner/superuser can still drop triggers —
  restrict DB access and export audit logs periodically.
- **Replay protection**: `consume_nonce()` (fresh timestamp + single-use nonce). The HMAC check itself happens in the Edge Function (Phase 3).
- **Command queue**: `pending → processing → executed / failed / expired / rejected`, claimed with `FOR UPDATE SKIP LOCKED`,
  lease + exponential backoff, only the lease holder can complete. Delivery is **at-least-once** → the Roblox worker must be idempotent per command id.
- **Requested ≠ executed**: `moderation_actions.status` and `execution_status` are separate; they change together with the command in one transaction.
- Every function in `public` is executable by `service_role` only (they are PostgREST-visible but unreachable for anon/authenticated).

## Deploy (Supabase)
1. Create the project. In **Auth → Settings: disable public sign-ups** (invite staff only). Require strong passwords; enable MFA for staff if available on your plan (unverified).
2. `supabase link --project-ref <ref>` then `supabase db push` (applies the 3 migrations in order).
3. Apply `seed.sql` (`psql`/SQL editor). Re-running is safe.
4. Run tests locally: `supabase start && supabase db reset && supabase test db`.
5. Create the first dashboard user (Auth → invite), then insert their `admin_members` row with `role_key = 'founder'` using the SQL editor (one-time bootstrap).

## Rollback
Migrations are additive on an empty project. To roll back everything (DESTROYS DATA):
```sql
drop table if exists public.api_nonces, public.config_history, public.anticheat_config, public.audit_logs,
  public.appeals, public.command_queue, public.report_private, public.reports,
  public.moderation_action_private, public.moderation_actions, public.violations,
  public.sessions, public.players, public.admin_members, public.role_permissions,
  public.permissions, public.staff_roles cascade;
drop function if exists public.write_audit, public.consume_nonce, public.submit_report,
  public.queue_action_execution, public.claim_commands, public.complete_command, public.purge_old_data cascade;
drop schema if exists private cascade;
```
For a live system, prefer forward-fix migrations plus a backup (`supabase db dump`) taken before each push.

## Assumptions to confirm
1. **Developer role** = Administrator + `config.write` + `announce.global` (no permanent-ban approval, no staff management). Confirm.
2. **Support Tim** can warn and review reports, but not kick/ban or see reporter identity or evidence.
3. **Moderator** can ban temporarily up to 7 days (`policy.ban_max_seconds_by_role`); longer needs Administrator.
4. Permanent bans: requested by Administrator+, approved by **Management or Founder** (a different person).
5. Roblox in-game staff = manual UserId list in a server-only Luau module; the **DB role matrix is the reference**, and the Luau list must stay consistent (Phase 6 will generate/verify it).

## Known limits / not yet verified
- **Not executed**: no Postgres was available in the authoring environment. Migrations and tests have not been run; expect small fixes on first run.
- `pg_cron` availability/scheduling on the free tier is unverified → schedule `purge_old_data()` from a scheduled Edge Function or the bot as a fallback.
- Supabase Free pauses after 1 week of inactivity and is limited to 500 MB (verified from Supabase pricing); keep evidence small (`violations.evidence` ≤ 8 KB, enforced).
- **Vercel Hobby is non-commercial only** (verified). If the game earns Robux or anyone profits, host the dashboard elsewhere (decide in Phase 5).
- Permanent-ban `Duration` value for `BanAsync` is **unverified** (verify before Phase 3 code).
- **Banned players cannot join the game**, so appeals cannot be filed in-game. Appeals need an off-platform path (Discord modal or web form) with a way to prove the Roblox identity. Design decision needed in Phase 4.
