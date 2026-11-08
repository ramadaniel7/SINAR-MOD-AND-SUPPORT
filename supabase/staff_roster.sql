-- DIHASILKAN dari staff_roster.json oleh tools/build_staff.py. Aman dijalankan berulang (sinkronisasi penuh).
-- Jalankan di Supabase SQL Editor SETELAH seed.sql. Staf yang dihapus dari JSON otomatis dinonaktifkan.
begin;

-- bersihkan role lama (moderator/support) bila sempat ter-seed
delete from public.role_permissions where role_key in ('moderator','support');
delete from public.staff_roles r where r.role_key in ('moderator','support') and not exists (select 1 from public.admin_members m where m.role_key = r.role_key);

update public.staff_roles set discord_role_id = '1561412652096430281' where role_key = 'helper';
insert into public.admin_members (roblox_user_id, role_key, note) values (8269411613, 'founder', 'roster:bijibapakmuuuu') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (11411678988, 'founder', 'roster:asterveil_nr') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (9188969905, 'founder', 'roster:villainxxss') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (8780518240, 'management', 'roster:SagaraSkibidiw') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (8850381377, 'management', 'roster:jarsss06') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (8841765649, 'administrator', 'roster:lalalunna8') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (1748614144, 'administrator', 'roster:Memor1es_10') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (8901719751, 'administrator', 'roster:natnuy1') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (7966279377, 'administrator', 'roster:aku_lunareal') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (roblox_user_id, role_key, note) values (7530260164, 'helper', 'roster:cyezvo') on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (discord_user_id, role_key, note) values ('1462111697333518493', 'founder', 'roster:discord Dans') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'ramadnaieloktavianus76@gmail.com' and m.discord_user_id = '1462111697333518493' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('1558438741918355523', 'founder', 'roster:discord aster (akun lain)') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'asterveilnarion@gmail.com' and m.discord_user_id = '1558438741918355523' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('1087381421129216060', 'founder', 'roster:discord Villain') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
insert into public.admin_members (discord_user_id, role_key, note) values ('487307900998385686', 'management', 'roster:discord saga') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'management@sinar.com' and m.discord_user_id = '487307900998385686' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('797431604204142592', 'management', 'roster:discord pajar') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'management1@sinar.com' and m.discord_user_id = '797431604204142592' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('1431703993909903432', 'administrator', 'roster:discord ') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'admin@sinar.com' and m.discord_user_id = '1431703993909903432' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('1513501984953471037', 'administrator', 'roster:discord ') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'admin1@sinar.com' and m.discord_user_id = '1513501984953471037' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('1409035962180173835', 'administrator', 'roster:discord ') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'admin2@sinar.com' and m.discord_user_id = '1409035962180173835' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('1483516730364920155', 'administrator', 'roster:discord ') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'admin3@sinar.com' and m.discord_user_id = '1483516730364920155' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('1298574784388534312', 'helper', 'roster:discord ') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'helper1@sinar.com' and m.discord_user_id = '1298574784388534312' and m.auth_user_id is null;
insert into public.admin_members (discord_user_id, role_key, note) values ('706087430570246167', 'helper', 'roster:discord ') on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;
update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = 'helper@sinar.com' and m.discord_user_id = '706087430570246167' and m.auth_user_id is null;

-- nonaktifkan staf hasil roster yang sudah tidak ada di JSON
update public.admin_members set is_active = false, deactivated_at = now()
 where note like 'roster:%' and is_active and not (coalesce(roblox_user_id = any(array[8269411613,11411678988,9188969905,8780518240,8850381377,8841765649,1748614144,8901719751,7966279377,7530260164]::bigint[]), false) or coalesce(discord_user_id = any(array['1462111697333518493','1558438741918355523','1087381421129216060','487307900998385686','797431604204142592','1431703993909903432','1513501984953471037','1409035962180173835','1483516730364920155','1298574784388534312','706087430570246167']::text[]), false));
commit;
