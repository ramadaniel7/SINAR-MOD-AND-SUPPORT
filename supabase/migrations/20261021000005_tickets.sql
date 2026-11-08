-- 0005: Discord ticket reports (/report). Reporter is identified by Discord ID (not a verified Roblox identity).
begin;

-- reports may now come from a Discord ticket
alter table public.reports add column if not exists source text not null default 'ingame'
  check (source in ('ingame','discord_ticket'));

alter table public.report_private alter column reporter_user_id drop not null;
alter table public.report_private add column if not exists reporter_discord_id text
  check (reporter_discord_id ~ '^[0-9]{15,25}$');
alter table public.report_private add constraint report_private_has_reporter
  check (reporter_user_id is not null or reporter_discord_id is not null);
create index if not exists report_private_discord_idx on public.report_private(reporter_discord_id);

create table public.discord_tickets (
  id                  uuid primary key default gen_random_uuid(),
  channel_id          text not null unique check (channel_id ~ '^[0-9]{15,25}$'),
  panel_message_id    text check (panel_message_id ~ '^[0-9]{15,25}$'),
  reporter_discord_id text not null check (reporter_discord_id ~ '^[0-9]{15,25}$'),
  status              text not null default 'drafting' check (status in ('drafting','open','closed','expired','cancelled')),
  category            text check (category in ('cheating','fail_roleplay','harassment','other')),
  reported_user_id    bigint check (reported_user_id > 0),
  reported_username   text check (char_length(reported_username) <= 50),
  description         text check (char_length(description) <= 500),
  evidence            jsonb not null default '[]'::jsonb
                      check (jsonb_typeof(evidence) = 'array' and jsonb_array_length(evidence) <= 10 and octet_length(evidence::text) <= 6000),
  report_id           uuid references public.reports(id) on delete set null,
  created_at          timestamptz not null default now(),
  submitted_at        timestamptz,
  closed_at           timestamptz
);
-- at most ONE unfinished (drafting) ticket per person; limits on open ones are enforced by the bot
create unique index discord_tickets_one_drafting on public.discord_tickets(reporter_discord_id) where status = 'drafting';
create index discord_tickets_status_idx on public.discord_tickets(status, created_at);
create index discord_tickets_report_idx on public.discord_tickets(report_id);

alter table public.discord_tickets enable row level security;  -- no policies: service_role (bot) only
revoke all on public.discord_tickets from anon, authenticated;

-- Submit a ticket report: idempotent (per ticket), rate-limited, duplicate-aware, race-safe.
create or replace function public.submit_ticket_report(
  p_idempotency_key text, p_reporter_discord text, p_reported bigint, p_category text,
  p_description text, p_evidence jsonb, p_max_per_hour int default 5, p_dup_window_minutes int default 30)
returns table (o_report_id uuid, o_report_code text, o_outcome text)
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_code text; v_count int;
begin
  select r.id, r.report_code into v_id, v_code from public.reports r where r.idempotency_key = p_idempotency_key;
  if found then return query select v_id, v_code, 'duplicate_request'::text; return; end if;

  select count(*) into v_count
    from public.reports r join public.report_private rp on rp.report_id = r.id
   where rp.reporter_discord_id = p_reporter_discord and r.created_at > now() - interval '1 hour';
  if v_count >= p_max_per_hour then return query select null::uuid, null::text, 'rate_limited'::text; return; end if;

  select r.id, r.report_code into v_id, v_code
    from public.reports r join public.report_private rp on rp.report_id = r.id
   where rp.reporter_discord_id = p_reporter_discord and r.reported_user_id = p_reported and r.category = p_category
     and r.created_at > now() - make_interval(mins => p_dup_window_minutes)
   limit 1;
  if found then return query select v_id, v_code, 'duplicate_recent'::text; return; end if;

  insert into public.reports (idempotency_key, reported_user_id, category, description, source)
  values (p_idempotency_key, p_reported, p_category, p_description, 'discord_ticket')
  on conflict (idempotency_key) do nothing
  returning id, report_code into v_id, v_code;
  if v_id is null then
    select r.id, r.report_code into v_id, v_code from public.reports r where r.idempotency_key = p_idempotency_key;
    return query select v_id, v_code, 'duplicate_request'::text; return;
  end if;

  insert into public.report_private (report_id, reporter_discord_id, evidence_refs)
  values (v_id, p_reporter_discord, coalesce(p_evidence, '[]'::jsonb));
  perform public.write_audit('discord_ticket', p_reporter_discord, null, 'report.created', 'report', v_id::text, null,
    jsonb_build_object('category', p_category, 'reported_user_id', p_reported, 'evidence_count', jsonb_array_length(coalesce(p_evidence,'[]'::jsonb))));
  return query select v_id, v_code, 'created'::text;
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant  execute on all functions in schema public to service_role;
commit;
