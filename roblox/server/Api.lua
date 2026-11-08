--[[
  API untuk developer game RP. Contoh pemakaian dari script server lain:

    local SmartAC = require(game.ServerScriptService.SmartAC.Api)

    -- 1) Setelah game memindahkan pemain (teleport rumah/interior/spawn), beri jeda agar tidak dianggap cheat:
    SmartAC.GrantMovementGrace(player, 3, "teleport_rumah")

    -- 2) Amankan remote sensitif (WAJIB untuk uang, inventory, kendaraan, damage, job):
    local V = SmartAC.Validate
    SmartAC.Guard.Event(BeliBarangRemote, { Args = { V.String(1, 40), V.Integer(1, 10) }, PerSecond = 2, Burst = 4 },
      function(player, itemId, qty)
        -- Harga, stok, dan saldo dihitung di SERVER. Jangan percaya angka dari client.
      end)

    -- 3) Laporkan sinyal custom (mis. uang berubah tidak wajar):
    SmartAC.Flag(player, "economy.impossible_gain", 40, 3, { gained = 1e9 })
]]
local HttpService = game:GetService("HttpService")
local Bridge = require(script.Parent.Modules.Bridge)
local Admin = require(script.Parent.Modules.Admin)
local Integration = require(script.Parent.Modules.Integration)
local Exemptions = require(script.Parent.Modules.Exemptions)
local Guard = require(script.Parent.Modules.Guard)
local Permissions = require(script.Parent.Modules.Permissions)
local Scoring = require(script.Parent.Modules.Scoring)
local Util = require(script.Parent.Modules.Util)

local Api = {}
Api.Guard = Guard
Api.Validate = Util.V
Api.NewMaid = Util.NewMaid

function Api.GrantMovementGrace(player, seconds, reason)
	Exemptions.Grant(player, math.clamp(seconds, 0, 30), reason or "game")
end

function Api.Flag(player, detector, points, severity, evidence)
	assert(type(detector) == "string" and detector:match("^[a-z0-9_.]+$"), "detector harus huruf kecil/angka/titik/underscore")
	Scoring.Hit(player, detector, math.clamp(points, 0, 100), math.clamp(severity, 1, 5), evidence)
end

function Api.IsStaff(player)
	return Permissions.IsStaff(player)
end

-- Catat tindakan staf yang SUDAH dieksekusi game sendiri (mis. aplikasi Staff: warn/kick) ke riwayat moderasi backend.
function Api.RecordStaffAction(admin, kind, target, reason)
	if kind ~= "warn" and kind ~= "kick" then return end
	local role = Permissions.RoleOf(admin)
	if not role or not target then return end
	task.spawn(function()
		Bridge.Call("record_action", {
			actor_user_id = admin.UserId, role_key = role, target_user_id = target.UserId, action_type = kind,
			reason = tostring(reason or "Tindakan staf in-game"):sub(1, 400),
			idempotency_key = HttpService:GenerateGUID(false),
		})
	end)
end

-- Audit perintah chat admin (/uang, /item, /kerja, ...). Dipanggil dari patch Chat.lua.
local ADMIN_COMMANDS = { uang = true, saldo = true, item = true, jam = true, kerja = true, resetktp = true, bintang = true, spawn = true, itemadmin = true, papan = true, pingsan = true }
function Api.AuditCommand(admin, name, args)
	if not ADMIN_COMMANDS[name] then return end
	local shown = {}
	for i = 1, math.min(3, #args) do shown[i] = tostring(args[i]):sub(1, 40) end
	Bridge.Enqueue("audit", {
		actor_user_id = admin.UserId, role_key = Permissions.RoleOf(admin),
		action = "ingame.cmd_" .. name, target_id = tostring(admin.UserId), details = { args = shown },
	})
end

-- Perintah chat SINAR RP ("/setuang", "/tp", ...) diteruskan ke pipeline SmartAC supaya memakai roster, batas role, dan audit yang sama.
local SINAR_ALIAS = { tp = "to", tarik = "bring" } -- nama SINAR -> nama perintah SmartAC
function Api.RunSinarCommand(player, nama, args)
	local name = SINAR_ALIAS[nama] or nama
	local text = name
	if args and #args > 0 then text = text .. " " .. table.concat(args, " ") end
	local res = Admin.Run(player, text)
	if res.message and res.message ~= "" then
		Integration.Notif(player, res.message, res.ok and "sukses" or "error")
	end
	return res
end

return Api
