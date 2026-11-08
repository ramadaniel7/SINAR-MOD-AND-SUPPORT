-- 0006: jejak pemberian uang oleh staf in-game (;kasihuang / ;kasihsaldo) + aturan "helper sekali per pemain".
begin;

create table public.staff_money_grants (
  id                    bigint generated always as identity primary key,
  actor_roblox_user_id  bigint not null check (actor_roblox_user_id > 0),
  actor_role            text   not null,
  command               text   not null check (command in ('kasihuang','kasihsaldo')),
  target_user_id        bigint not null check (target_user_id > 0),
  amount                bigint not null check (amount between 1 and 10000000000),
  created_at            timestamptz not null default now()
);
create index staff_money_grants_pair_idx on public.staff_money_grants(actor_roblox_user_id, target_user_id, command, created_at desc);
create index staff_money_grants_time_idx on public.staff_money_grants(created_at desc);

alter table public.staff_money_grants enable row level security; -- tanpa policy: hanya service_role (gateway)
revoke all on public.staff_money_grants from anon, authenticated;

-- Mengembalikan 'recorded' atau 'duplicate'. p_enforce_once=true: tolak bila pasangan (pemberi, penerima, perintah) sudah ada
-- (dalam p_window_hours jam terakhir; NULL = selamanya). Kunci advisory mencegah balapan dua permintaan bersamaan.
create or replace function public.record_money_grant(
  p_actor bigint, p_role text, p_command text, p_target bigint, p_amount bigint,
  p_enforce_once boolean default false, p_window_hours int default null)
returns text language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text || ':' || p_target::text || ':' || p_command, 0));
  if p_enforce_once and exists (
    select 1 from public.staff_money_grants g
     where g.actor_roblox_user_id = p_actor and g.target_user_id = p_target and g.command = p_command
       and (p_window_hours is null or g.created_at > now() - make_interval(hours => p_window_hours))) then
    return 'duplicate';
  end if;
  insert into public.staff_money_grants (actor_roblox_user_id, actor_role, command, target_user_id, amount)
  values (p_actor, p_role, p_command, p_target, p_amount);
  perform public.write_audit('staff_ingame', p_actor::text, p_role, 'money.granted', 'player', p_target::text, null,
    jsonb_build_object('command', p_command, 'amount', p_amount));
  return 'recorded';
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant  execute on all functions in schema public to service_role;
commit;
