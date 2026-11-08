-- =============================================================================
-- seed.sql  (idempotent: aman dijalankan ulang)
-- Role: founder, management, developer, administrator (Admin), helper.
-- DAFTAR ORANG (UserId Roblox & ID Discord) TIDAK di sini: lihat staff_roster.json -> supabase/staff_roster.sql.
-- Izin di file ini = izin WEB DASHBOARD & DISCORD. Izin di dalam Roblox diatur terpisah (roblox/server/Modules/Permissions.lua).
-- =============================================================================
begin;

-- bersihkan role lama (moderator/support) bila pernah ter-seed
delete from public.role_permissions where role_key in ('moderator','support');
delete from public.staff_roles r where r.role_key in ('moderator','support') and not exists (select 1 from public.admin_members m where m.role_key = r.role_key);

insert into public.staff_roles (role_key, display_name, rank, discord_role_id) values
  ('founder',       'Founder',       100, '1560622074949533736'),
  ('management',    'Management',     80, '1561412416246521896'),
  ('developer',     'Developer',      70, '1561412474492821575'),
  ('administrator', 'Admin',          60, '1561412560132112545'),
  ('helper',        'Helper',         20, '1561412652096430281')
on conflict (role_key) do update set display_name = excluded.display_name, rank = excluded.rank;

insert into public.permissions (permission_key, description, is_sensitive) values
  ('players.read',                'View player profiles and sessions',                 false),
  ('players.history.read',        'View moderation history of a player',               false),
  ('reports.read',                'View reports (without reporter identity)',          false),
  ('reports.read_reporter',       'View who filed a report',                           true),
  ('reports.review',              'Change report status / resolve reports',            false),
  ('violations.read',             'View anti-cheat violations and evidence',           true),
  ('violations.review',           'Mark violations reviewed/dismissed/confirmed',      false),
  ('moderation.warn',             'Warn a player',                                     false),
  ('moderation.kick',             'Kick a player',                                     false),
  ('moderation.ban.temp',         'Issue a temporary ban (limited by role policy)',    true),
  ('moderation.ban.perm.request', 'Request a permanent ban (needs second approver)',   true),
  ('moderation.ban.perm.approve', 'Approve a permanent ban requested by someone else', true),
  ('moderation.unban',            'Unban a player',                                    true),
  ('moderation.read_private',     'View private reasons / evidence refs',              true),
  ('appeals.read',                'View appeals',                                      false),
  ('appeals.decide',              'Accept or deny appeals',                            true),
  ('announce.server',             'Send a server-local announcement',                  false),
  ('announce.global',             'Send a global announcement',                        true),
  ('audit.read',                  'Read the audit log',                                true),
  ('config.read',                 'Read anti-cheat configuration',                     true),
  ('config.write',                'Change anti-cheat configuration',                   true),
  ('commands.read',               'View the command queue',                            false),
  ('commands.cancel',             'Cancel a pending command',                          true),
  ('system.health.read',          'View backend health and queue status',              false),
  ('staff.manage',                'Request staff role / membership changes',           true),
  ('staff.approve',               'Approve staff role / privilege changes',            true),
  ('tickets.close',               'Review & close Discord report tickets',             false)
on conflict (permission_key) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;

-- ---- Matriks izin WEB + DISCORD ---------------------------------------------
delete from public.role_permissions where role_key in ('moderator','support','helper','administrator');

-- Helper: warn, kick, ban sementara (maks 1 hari), announce server + menutup tiket report Discord.
insert into public.role_permissions (role_key, permission_key)
select 'helper', k from unnest(array['moderation.warn','moderation.kick','moderation.ban.temp','announce.server','tickets.close']) k
on conflict do nothing;

-- Admin: akses web TERBATAS (tanpa audit log, konfigurasi, pengaturan staf, ban permanen, announce global, identitas pelapor).
insert into public.role_permissions (role_key, permission_key)
select 'administrator', k from unnest(array[
  'players.read','players.history.read','reports.read','reports.review','violations.read','violations.review',
  'moderation.warn','moderation.kick','moderation.ban.temp','moderation.unban','moderation.read_private',
  'appeals.read','announce.server','commands.read','system.health.read','tickets.close']) k
on conflict do nothing;

-- Developer, Management, Founder: SEMUA izin, tanpa batasan.
insert into public.role_permissions (role_key, permission_key)
select r.role_key, p.permission_key from (values ('developer'), ('management'), ('founder')) r(role_key), public.permissions p
on conflict do nothing;

-- ---- Konfigurasi default (AMAN: detect-only, tanpa auto-hukuman) --------------
insert into public.anticheat_config (key, value, updated_by) values
  ('enforcement.mode',   '{"mode":"detect_only","auto_kick_enabled":false,"auto_ban_enabled":false}', 'seed'),
  ('command.defaults',   '{"ttl_seconds":600,"max_attempts":5,"lease_seconds":30,"poll_interval_seconds":5}', 'seed'),
  ('report.limits',      '{"max_per_hour":5,"duplicate_window_minutes":30,"max_description_chars":500}', 'seed'),
  ('ban.durations_seconds', '{"1d":86400,"1w":604800,"30d":2592000,"365d":31536000,"permanent":null}', 'seed'),
  -- Batas durasi ban sementara per role (Helper hanya 1 hari). Ban permanen SELALU butuh orang kedua.
  ('policy.ban_max_seconds_by_role',
     '{"helper":86400,"administrator":31536000,"developer":31536000,"management":31536000,"founder":31536000}', 'seed'),
  ('discord.channels',
     '{"moderation_log":"1560408305887612979","public_log":"1561411539758747688","incident_report":"1560408337441497118","player_report":"1560409797147496568","bot_commands":"1560409018487406632","player_banned":"1562268825297231882"}', 'seed')
on conflict (key) do nothing;

-- DB lama (seed sudah pernah dijalankan): paksa mapping channel terbaru (menimpa kunci yang sama, kunci lain tetap).
update public.anticheat_config
   set value = (value - 'anticheat_log') || jsonb_build_object(
         'moderation_log','1560408305887612979', 'public_log','1561411539758747688', 'incident_report','1560408337441497118',
         'player_report','1560409797147496568', 'bot_commands','1560409018487406632', 'player_banned','1562268825297231882'),
       updated_by = 'seed'
 where key = 'discord.channels';

commit;
