-- 0004: Discord notification bookkeeping (so the bot never double-posts) + indexes.
begin;
alter table public.violations         add column if not exists discord_notified_at timestamptz;
alter table public.moderation_actions add column if not exists discord_notified_at timestamptz;
alter table public.moderation_actions add column if not exists discord_request_message_id text;
alter table public.appeals            add column if not exists discord_message_id text;

create index if not exists violations_unnotified_idx on public.violations(created_at)
  where discord_notified_at is null;
create index if not exists ma_unnotified_idx on public.moderation_actions(updated_at)
  where discord_notified_at is null and status in ('executed','failed','expired','rejected');
create index if not exists reports_unposted_idx on public.reports(created_at)
  where discord_message_id is null;
commit;
