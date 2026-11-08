-- Layanan perintah admin (SERVER) bergaya Kohl's: satu pintu "Admin" (RemoteFunction) dengan op:
--   hello | catalog | players | logs | run{text}
-- Alur "run": cek staf -> parse & validasi argumen -> cek izin -> eksekusi -> catat log + audit backend.
-- Client hanya MEMINTA. UI yang menyembunyikan perintah bukan otorisasi; semua dicek ulang di sini.
local Players = game:GetService("Players")
local Bridge = require(script.Parent.Bridge)
local Guard = require(script.Parent.Guard)
local Permissions = require(script.Parent.Permissions)
local Process = require(script.Parent.Cmd.Process)
local Registry = require(script.Parent.Cmd.Registry)
local Defs = require(script.Parent.Cmd.Defs)
local Remotes = require(script.Parent.Remotes)
local Scoring = require(script.Parent.Scoring)
local Util = require(script.Parent.Util)

local V = Util.V
local Admin = {}

local LOG, LOG_MAX = {}, 200

local function log(ctx, text, ok, message)
	table.insert(LOG, { t = os.time(), who = ctx.player.Name, text = text:sub(1, 120), ok = ok, msg = tostring(message):sub(1, 80) })
	if #LOG > LOG_MAX then table.remove(LOG, 1) end
end

local function recentLogs(n)
	local out = {}
	for i = math.max(1, #LOG - n + 1), #LOG do
		local e = LOG[i]
		table.insert(out, ("%s  %s  %s %s"):format(os.date("!%H:%M:%S", e.t), e.who, e.ok and "✓" or "✗", e.text))
	end
	return out
end

-- Izin: perm bisa string; permFor(args) menimpa untuk perintah yang izinnya tergantung argumen (mis. ban permanen).
local function permFor(def, args)
	if def.permFor and args then return def.permFor(args) end
	return def.perm
end
local function canUse(ctx, def)
	local perm = def.perm
	return perm == nil or Permissions.Has(ctx.player, perm)
end

local function catalog(ctx)
	local out = {}
	for _, d in ipairs(Registry.All()) do
		if canUse(ctx, d) then
			local args = {}
			for _, a in ipairs(d.args) do table.insert(args, { name = a.name, type = a.type, optional = a.optional == true, values = a.values }) end
			table.insert(out, { name = d.name, aliases = d.aliases or {}, group = d.group, desc = d.desc or "", usage = Registry.Usage(d), args = args })
		end
	end
	table.sort(out, function(a, b) if a.group ~= b.group then return a.group < b.group end return a.name < b.name end)
	return out
end

local function makeCtx(player)
	return { player = player, role = Permissions.RoleOf(player), rank = Permissions.Rank(player) }
end

local function run(player, text)
	local ctx = makeCtx(player)
	local parsed, err = Process.Parse(ctx, text, Registry)
	if not parsed then return { ok = false, message = err } end
	local def = parsed.command

	local perm = permFor(def, parsed.args)
	if perm and not Permissions.Has(player, perm) then
		log(ctx, text, false, "ditolak: izin")
		Bridge.Enqueue("audit", { actor_user_id = player.UserId, role_key = ctx.role, action = "ingame.denied", target_id = "", details = { command = def.name, perm = perm } })
		return { ok = false, message = ("Role lu (%s) tidak punya izin untuk ;%s"):format(ctx.role or "?", def.name) }
	end

	local ok, a, b, c = pcall(def.run, ctx, table.unpack(parsed.args, 1, #def.args))
	if not ok then
		warn("[SmartAC] perintah error:", def.name, a)
		log(ctx, text, false, "error internal")
		return { ok = false, message = "Perintah gagal (error internal). Cek Output server." }
	end
	log(ctx, text, a == true, b)
	if def.group ~= "utility" and a == true then
		-- Semua perintah berdampak diaudit ke backend (siapa, apa, kapan).
		Bridge.Enqueue("audit", {
			actor_user_id = player.UserId, role_key = ctx.role, action = "ingame.cmd_" .. def.name,
			target_id = "", details = { text = text:sub(1, 150) },
		})
	end
	return { ok = a == true, message = tostring(b or ""), client = c }
end

-- Dipakai Api.RunSinarCommand: chat "/setuang ..." milik SINAR RP diteruskan ke pipeline yang SAMA (izin, batas, audit).
function Admin.Run(player, text)
	if not Permissions.IsStaff(player) then return { ok = false, message = "Perintah ini khusus staf." } end
	return run(player, text)
end

function Admin.Start()
	Defs.Register(Registry, { canUse = canUse, recentLogs = recentLogs })

	Guard.Invoke(Remotes.Admin, {
		Args = { V.String(2, 24), function(v) return typeof(v) == "table" end },
		PerSecond = 8, Burst = 15,
	}, function(player, op, data)
		if not Permissions.IsStaff(player) then
			-- Jangan bocorkan apa pun; catat sebagai sinyal (bisa exploiter yang mencoba remote admin).
			Scoring.Hit(player, "admin.unauthorized", 20, 3, { op = op })
			return { ok = false, error = "denied" }
		end
		if op == "hello" then
			return { ok = true, role = Permissions.RoleOf(player), rank = Permissions.Rank(player), perms = Permissions.List(player) }
		elseif op == "catalog" then
			return { ok = true, commands = catalog(makeCtx(player)) }
		elseif op == "players" then
			local out = {}
			for _, p in ipairs(Players:GetPlayers()) do
				table.insert(out, { userId = p.UserId, name = p.Name, displayName = p.DisplayName, staff = Permissions.RoleOf(p) })
				if #out >= 100 then break end
			end
			return { ok = true, players = out }
		elseif op == "logs" then
			return { ok = true, lines = recentLogs(30) }
		elseif op == "run" then
			if not V.String(1, 300)(data.text) then return { ok = false, message = "Teks perintah tidak valid." } end
			return run(player, data.text)
		end
		return { ok = false, error = "unknown_op" }
	end)
end

return Admin
