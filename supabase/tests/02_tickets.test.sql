-- 02_tickets.test.sql (pgTAP) - STATUS: ditulis, BELUM dijalankan.
begin;
select plan(6);

select is((select o_outcome from public.submit_ticket_report('ticket:test-0001','111111111111111111',2001,'cheating','speed hack','[{"name":"a.png","kind":"image","size":1,"url":"https://discord.com/channels/1/2/3"}]'::jsonb)),
  'created', '1. ticket report created');
select is((select o_outcome from public.submit_ticket_report('ticket:test-0001','111111111111111111',2001,'cheating','speed hack','[]'::jsonb)),
  'duplicate_request', '2. same ticket key is idempotent');
select is((select o_outcome from public.submit_ticket_report('ticket:test-0002','111111111111111111',2001,'cheating','again','[]'::jsonb)),
  'duplicate_recent', '3. same reporter+target+category within window is a duplicate');
select is((select o_outcome from public.submit_ticket_report('ticket:test-0003','111111111111111111',2002,'other','x','[]'::jsonb, 1)),
  'rate_limited', '4. hourly limit enforced');
select throws_ok($$ insert into public.report_private (report_id, reporter_user_id, reporter_discord_id)
  select id, null, null from public.reports limit 1 $$, '23514', null, '5. a report must have some reporter identity');

insert into public.discord_tickets (channel_id, reporter_discord_id) values ('222222222222222222','333333333333333333');
select throws_ok($$ insert into public.discord_tickets (channel_id, reporter_discord_id) values ('222222222222222223','333333333333333333') $$,
  '23505', null, '6. only one drafting ticket per person');

select * from finish();
rollback;
