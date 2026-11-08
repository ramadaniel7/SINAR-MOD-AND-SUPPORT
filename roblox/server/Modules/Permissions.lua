-- Otorisasi staff di server. Sumber kebenaran: modul Roster (dihasilkan dari staff_roster.json), berdasarkan UserId.
-- Client TIDAK pernah dipercaya.
--   founder / management / developer / administrator : SEMUA akses di Roblox (izin web/Discord diatur terpisah di database).
--   helper : warn, kick, ban 1 hari, announce server, + perintah uang/status SINAR (dibatasi); tanpa teleport & VIP.
local Roster = require(script.Parent.Parent.Roster)

local Permissions = {}

local RANK = { founder = 100, management = 80, developer = 70, administrator = 60, helper = 20 }
local FULL_ACCESS = { founder = true, management = true, developer = true, administrator = true }
-- Helper: warn, kick, ban 1 hari, announce server + perintah uang/status SINAR RP (dengan batas di Config.StaffMoney).
-- TIDAK boleh: teleport pemain (to/bring/tp/tarik), on/off VIP, dan semua izin lain.
local HELPER = {
	["moderation.warn"] = true, ["moderation.kick"] = true, ["moderation.ban.temp"] = true, ["announce.server"] = true,
	["sinar.money"] = true, ["sinar.self"] = true,
}
-- Izin yang LEBIH sempit dari "akses penuh": hanya role yang disebut yang boleh (berlaku untuk semua role).
local RESTRICTED = { ["ingame.shutdown"] = { founder = true, developer = true } }
-- Batas durasi ban (detik) per role di Roblox. Role lain tidak dibatasi di sini (backend tetap membatasi maks 365 hari).
local MAX_BAN_SECONDS = { helper = 86400 }

function Permissions.RoleOfId(userId)
	local role = Roster.ByUserId[userId]
	if type(role) == "string" and RANK[role] then return role end
	return nil
end
function Permissions.RoleOf(player) return Permissions.RoleOfId(player.UserId) end
function Permissions.IsStaff(player) return Permissions.RoleOfId(player.UserId) ~= nil end
function Permissions.RankOfId(userId)
	local role = Permissions.RoleOfId(userId)
	return role and RANK[role] or 0
end
function Permissions.Rank(player) return Permissions.RankOfId(player.UserId) end

function Permissions.Has(player, perm)
	local role = Permissions.RoleOf(player)
	if not role then return false end
	if RESTRICTED[perm] then return RESTRICTED[perm][role] == true end
	if FULL_ACCESS[role] then return true end
	return role == "helper" and HELPER[perm] == true
end

-- Hanya boleh menindak yang pangkatnya LEBIH RENDAH (berlaku juga untuk staf yang sedang offline).
function Permissions.CanTarget(actor, target) return Permissions.Rank(actor) > Permissions.Rank(target) end
function Permissions.CanTargetId(actor, userId)
	return actor.UserId ~= userId and Permissions.Rank(actor) > Permissions.RankOfId(userId)
end

function Permissions.MaxBanSeconds(role) return MAX_BAN_SECONDS[role] end

function Permissions.List(player)
	local role = Permissions.RoleOf(player)
	if not role then return {} end
	if FULL_ACCESS[role] then return { "*" } end
	local out = {}
	for p in pairs(HELPER) do table.insert(out, p) end
	table.sort(out)
	return out
end

return Permissions
