-- 0007: tiket v2 (ditutup staf -> DM + review -> channel dihapus), konteks report in-game, penanda notifikasi ban.
begin;

alter table public.reports add column if not exists context jsonb not null default '{}'::jsonb
  check (jsonb_typeof(context) = 'object' and octet_length(context::text) <= 4096);

alter table public.discord_tickets
  add column if not exists closed_by_discord_id text check (closed_by_discord_id ~ '^[0-9]{15,25}$'),
  add column if not exists closed_by_role       text,
  add column if not exists close_outcome        text check (close_outcome in ('resolved','dismissed')),
  add column if not exists close_note           text check (char_length(close_note) <= 1000),
  add column if not exists dm_status            text check (dm_status in ('sent','failed')),
  add column if not exists review_rating        smallint check (review_rating between 1 and 5),
  add column if not exists review_comment       text check (char_length(review_comment) <= 500),
  add column if not exists reviewed_at          timestamptz,
  add column if not exists review_reminded_at   timestamptz;
create index if not exists discord_tickets_review_idx on public.discord_tickets(closed_at)
  where status = 'closed' and review_rating is null and dm_status = 'sent';

-- penanda: pengumuman ban permanen sudah dikirim ke channel "Player Banned"
alter table public.moderation_actions add column if not exists banned_notice_at timestamptz;

commit;
