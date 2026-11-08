-- =============================================================================
-- 01_invariants_and_rls.test.sql   (pgTAP; run with `supabase test db`)
-- STATUS: WRITTEN BUT NOT YET RUN (no Postgres available where this was authored).
-- Requires the migrations AND seed.sql to be applied (roles/permissions).
-- The auth.users fixture insert assumes the standard Supabase auth schema;
-- adjust columns if your Supabase version requires more.
-- =============================================================================
begin;
select plan(27);

-- ---- Fixtures (as superuser) ----------------------------------------------
insert into public.players (roblox_user_id, username) values (1001,'target_player'), (1002,'reporter_player');

insert into auth.users (id, instance_id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','mod@test.local'),
  ('00000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','support@test.local');
insert into public.admin_members (auth_user_id, role_key, note) values
  ('00000000-0000-0000-0000-0000000000a2','administrator','test'),
  ('00000000-0000-0000-0000-0000000000a3','helper','test');

insert into public.violations (event_key, roblox_user_id, detector, severity, score, mode)
values ('evt-test-0001', 1001, 'movement.speed', 2, 10, 'detect_only');

insert into public.moderation_actions
  (id, idempotency_key, target_user_id, action_type, duration_seconds, public_reason, source, actor_type, actor_id, status)
values ('00000000-0000-0000-0000-0000000000b1','test-ban-b1-0001',1001,'ban',86400,'test temp ban','dashboard','staff_dashboard','admin-1','approved');
insert into public.moderation_action_private (action_id, private_reason)
values ('00000000-0000-0000-0000-0000000000b1','secret moderator-only reason');

-- ---- Structural security --------------------------------------------------
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
          0, '1. RLS is enabled on every public table');

select is((select count(*)::int from information_schema.role_table_grants
            where grantee = 'anon' and table_schema = 'public'),
          0, '2. anon has no table privileges in public');

-- ---- Database-level invariants ---------------------------------------------
select throws_ok($$ insert into public.moderation_actions
  (idempotency_key,target_user_id,action_type,is_permanent,public_reason,source,actor_type,actor_id,status)
  values ('test-perm-0001',1001,'ban',true,'perm ban test','dashboard','staff_dashboard','admin-1','approved') $$,
  '23514', null, '3. permanent ban cannot be approved without an approver');

select throws_ok($$ insert into public.moderation_actions
  (idempotency_key,target_user_id,action_type,is_permanent,public_reason,source,actor_type,actor_id,status,approved_by_actor,approved_at)
  values ('test-perm-0002',1001,'ban',true,'perm ban test','dashboard','staff_dashboard','admin-1','approved','admin-1',now()) $$,
  '23514', null, '4. permanent ban cannot be self-approved (four-eyes)');

select lives_ok($$ insert into public.moderation_actions
  (idempotency_key,target_user_id,action_type,is_permanent,public_reason,source,actor_type,actor_id,status,approved_by_actor,approved_at)
  values ('test-perm-0003',1001,'ban',true,'perm ban test','dashboard','staff_dashboard','admin-1','approved','admin-2',now()) $$,
  '5. permanent ban with a different approver is accepted');

select throws_ok($$ insert into public.moderation_actions
  (idempotency_key,target_user_id,action_type,is_permanent,public_reason,source,actor_type,actor_id,status)
  values ('test-temp-0001',1001,'ban',false,'temp ban without duration','dashboard','staff_dashboard','admin-1','approved') $$,
  '23514', null, '6. temporary ban requires a duration');

-- ---- Audit log is append-only ------------------------------------------------
select throws_ok($$ update public.audit_logs set actor_id = 'tamper' $$, '42501', null, '7. audit_logs cannot be updated');
select throws_ok($$ delete from public.audit_logs $$, '42501', null, '8. audit_logs cannot be deleted');

-- ---- Replay protection ---------------------------------------------------------
select is(public.consume_nonce('nonce-fresh-000000001','job-a', now(), 60), true,  '9. fresh nonce accepted once');
select is(public.consume_nonce('nonce-fresh-000000001','job-a', now(), 60), false, '10. replayed nonce rejected');
select is(public.consume_nonce('nonce-stale-000000001','job-a', now() - interval '10 minutes', 60), false,
          '11. stale timestamp rejected');

-- ---- Reports -----------------------------------------------------------------------
select is((select o_outcome from public.submit_report('rep-key-0000001',1002,1001,'cheating','speed hacking',1,'job-a')),
          'created', '12. report created');
select is((select o_outcome from public.submit_report('rep-key-0000001',1002,1001,'cheating','speed hacking',1,'job-a')),
          'duplicate_request', '13. same idempotency key returns the original report');
select throws_ok($$ select * from public.submit_report('rep-key-0000002',1002,1002,'other','self report',1,'job-a') $$,
          '22023', null, '14. reporting yourself is rejected');

-- ---- Command state machine -------------------------------------------------------
select ok(public.queue_action_execution('00000000-0000-0000-0000-0000000000b1') is not null,
          '15. approved action is queued as a command');
select is((select count(*)::int from public.claim_commands('job-a', 5, 30)), 1, '16. job-a claims the command');
select is((select count(*)::int from public.claim_commands('job-b', 5, 30)), 0, '17. leased command is not claimable by another server');
select throws_ok($$ select public.complete_command(
    (select id from public.command_queue where action_id = '00000000-0000-0000-0000-0000000000b1'),
    'job-b', 'executed') $$, '55000', null, '18. non-lease-holder cannot complete a command');
select is(public.complete_command(
    (select id from public.command_queue where action_id = '00000000-0000-0000-0000-0000000000b1'),
    'job-a', 'executed', '{"ban":"ok"}'::jsonb), 'executed', '19. lease holder completes the command');
select is((select status || '/' || execution_status from public.moderation_actions
            where id = '00000000-0000-0000-0000-0000000000b1'),
          'executed/succeeded', '20. action execution status recorded separately and consistently');

-- ---- Config versioning -----------------------------------------------------------------
select throws_ok($$ update public.anticheat_config set value = '{"x":1}'::jsonb, updated_by = null
                    where key = 'command.defaults' $$, '23502', null, '21. config change without an author is rejected');
update public.anticheat_config set value = '{"ttl_seconds":300}'::jsonb, updated_by = 'tester' where key = 'command.defaults';
select is((select version::int from public.anticheat_config where key = 'command.defaults'), 2, '22. config version incremented');

-- ---- RLS behaviour as real roles ---------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
select is((select count(*)::int from public.violations), 0, '23. helper cannot read violations');
select is((select count(*)::int from public.moderation_action_private), 0, '24. helper cannot read private reasons');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
select is((select count(*)::int from public.violations), 1, '25. administrator can read violations');
select is((select count(*)::int from public.moderation_action_private), 1, '26. administrator can read private reasons');

reset role;
set local role anon;
select throws_ok($$ select count(*) from public.players $$, '42501', null, '27. anon cannot read players');
reset role;

select * from finish();
rollback;
