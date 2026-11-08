-- Pengecualian anti-cheat yang SAH. Hanya bisa diberikan oleh kode SERVER:
--   * grace sementara (respawn, teleport game, kursi/kendaraan)
--   * state admin (fly/noclip/teleport) yang hanya diset Admin.lua SETELAH cek izin di server.
-- Tidak ada cara bagi client biasa untuk mengaktifkan bypass.
local Players = game:GetService("Players")

local Exemptions = {}
local grace = {}   -- [player] = expiry (os.clock)
local admin = {}   -- [player] = { fly=bool, noclip=bool }

function Exemptions.Grant(player, seconds, _reason)
	local untilT = os.clock() + seconds
	if (grace[player] or 0) < untilT then
		grace[player] = untilT
	end
end

function Exemptions.SetAdminState(player, key, enabled)
	admin[player] = admin[player] or {}
	admin[player][key] = enabled or nil
end

function Exemptions.GetAdminState(player, key)
	return admin[player] ~= nil and admin[player][key] == true
end

function Exemptions.IsExempt(player, now)
	local g = grace[player]
	if g and g > (now or os.clock()) then return true end
	local a = admin[player]
	return a ~= nil and next(a) ~= nil
end

Players.PlayerRemoving:Connect(function(player)
	grace[player] = nil
	admin[player] = nil
end)

return Exemptions
