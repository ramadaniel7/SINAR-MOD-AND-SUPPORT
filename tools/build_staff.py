#!/usr/bin/env python3
"""staff_roster.json -> roblox/server/Roster.lua  +  supabase/staff_roster.sql  (satu sumber, tidak ada daftar ganda)."""
import json, os, re, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ROLES = ["founder", "management", "developer", "administrator", "helper"]
data = json.load(open(os.path.join(ROOT, "staff_roster.json"), encoding="utf-8"))

def fail(msg): print("ERROR:", msg); sys.exit(1)
seen_r, seen_d = {}, {}
rb, dc = [], []
for role in ROLES:
    entry = data["roles"].get(role, {"roblox": [], "discord": []})
    for m in entry.get("roblox", []):
        uid = m["userId"]
        if not isinstance(uid, int) or uid <= 0: fail(f"userId tidak valid: {m}")
        if uid in seen_r: fail(f"userId {uid} dobel ({seen_r[uid]} & {role})")
        seen_r[uid] = role; rb.append((role, m["username"].strip(), uid))
    for m in entry.get("discord", []):
        did = str(m["id"]).strip()
        if not re.fullmatch(r"\d{15,25}", did): fail(f"Discord ID tidak valid: {m}")
        if did in seen_d: fail(f"Discord ID {did} dobel ({seen_d[did]} & {role})")
        seen_d[did] = role; dc.append((role, did, (m.get("note") or "").strip(), (m.get("email") or "").strip()))
for k in data["roles"]:
    if k not in ROLES: fail(f"role tidak dikenal: {k}")

# ---------- Roster.lua (server-only ModuleScript) ----------
lua = ["-- DIHASILKAN dari staff_roster.json oleh tools/build_staff.py. JANGAN edit manual (edit JSON lalu build ulang).",
       "-- Hanya ada di server (ServerScriptService). Identitas staff = UserId, bukan nama.", "return {", "\tByUserId = {"]
for role, name, uid in rb:
    lua.append(f"\t\t[{uid}] = \"{role}\", -- {name}")
lua += ["\t},", "}"]
open(os.path.join(ROOT, "roblox/server/Roster.lua"), "w", encoding="utf-8").write("\n".join(lua) + "\n")

# ---------- staff_roster.sql ----------
def sql_str(s): return "'" + s.replace("'", "''") + "'"
sql = ["-- DIHASILKAN dari staff_roster.json oleh tools/build_staff.py. Aman dijalankan berulang (sinkronisasi penuh).",
       "-- Jalankan di Supabase SQL Editor SETELAH seed.sql. Staf yang dihapus dari JSON otomatis dinonaktifkan.", "begin;", "",
       "-- bersihkan role lama (moderator/support) bila sempat ter-seed",
       "delete from public.role_permissions where role_key in ('moderator','support');",
       "delete from public.staff_roles r where r.role_key in ('moderator','support') and not exists (select 1 from public.admin_members m where m.role_key = r.role_key);", ""]
hid = (data.get("discord_role_ids") or {}).get("helper")
if hid:
    sql.append(f"update public.staff_roles set discord_role_id = {sql_str(hid)} where role_key = 'helper';")
for role, name, uid in rb:
    sql.append(f"insert into public.admin_members (roblox_user_id, role_key, note) values ({uid}, {sql_str(role)}, {sql_str('roster:' + name)}) "
               f"on conflict (roblox_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;")
for role, did, note, email in dc:
    sql.append(f"insert into public.admin_members (discord_user_id, role_key, note) values ({sql_str(did)}, {sql_str(role)}, {sql_str('roster:discord ' + note)}) "
               f"on conflict (discord_user_id) do update set role_key = excluded.role_key, is_active = true, deactivated_at = null, note = excluded.note;")
    if email:
        sql.append(f"update public.admin_members m set auth_user_id = u.id from auth.users u where u.email = {sql_str(email)} and m.discord_user_id = {sql_str(did)} and m.auth_user_id is null;")
rlist = ",".join(str(u) for _, _, u in rb) or ""
dlist = ",".join(sql_str(d) for _, d, _, _ in dc) or ""
sql += ["", "-- nonaktifkan staf hasil roster yang sudah tidak ada di JSON",
        "update public.admin_members set is_active = false, deactivated_at = now()",
        f" where note like 'roster:%' and is_active and not (coalesce(roblox_user_id = any(array[{rlist}]::bigint[]), false) or coalesce(discord_user_id = any(array[{dlist}]::text[]), false));",
        "commit;"]
open(os.path.join(ROOT, "supabase/staff_roster.sql"), "w", encoding="utf-8").write("\n".join(sql) + "\n")
print(f"OK: {len(rb)} akun Roblox, {len(dc)} akun Discord -> Roster.lua + staff_roster.sql")
