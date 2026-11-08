-- Daftar perintah (gaya Kohl's: ;perintah argumen...). Setiap perintah dijalankan SETELAH server memeriksa izin
-- (Permissions) dan memvalidasi argumen (Process). Perintah "merugikan" tidak menyentuh diri sendiri / staf setara atau lebih tinggi.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local Config = require(script.Parent.Parent.Parent.Config)
local Bridge = require(script.Parent.Parent.Bridge)
local Executor = require(script.Parent.Parent.Executor)
local Exemptions = require(script.Parent.Parent.Exemptions)
local Integration = require(script.Parent.Parent.Integration)
local Permissions = require(script.Parent.Parent.Permissions)
local Remotes = require(script.Parent.Parent.Remotes)

local Defs = {}
local GRACE = Config.AntiCheat.Grace.Teleport
local DEFAULT_WALK, DEFAULT_JUMP = 16, 50

-- ---------- helper ----------
local function root(p) local c = p.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function hum(p) local c = p.Character return c and c:FindFirstChildOfClass("Humanoid") end

local function harmful(ctx, list, allowSelf)
	local ok, skipped = {}, 0
	for _, p in ipairs(list) do
		if (allowSelf and p == ctx.player) or Permissions.CanTargetId(ctx.player, p.UserId) then table.insert(ok, p) else skipped += 1 end
	end
	return ok, skipped
end

local function names(list)
	local t = {}
	for i, p in ipairs(list) do if i <= 5 then t[i] = p.Name end end
	local s = table.concat(t, ", ")
	return #list > 5 and (s .. (" +%d lainnya"):format(#list - 5)) or s
end

local function summarize(verb, list, skipped)
	if #list == 0 then return false, "Tidak ada target yang boleh ditindak" .. (skipped > 0 and " (staf setara/lebih tinggi dilindungi)." or ".") end
	local msg = ("%s: %s"):format(verb, names(list))
	if skipped > 0 then msg ..= (" (%d dilewati: dilindungi)"):format(skipped) end
	return true, msg
end

local function record(admin, kind, target, reason)
	local role = Permissions.RoleOf(admin)
	if not role or not Bridge.Enabled then return end
	local userId = target.UserId
	task.spawn(function()
		Bridge.Call("record_action", {
			actor_user_id = admin.UserId, role_key = role, target_user_id = userId, action_type = kind,
			reason = reason:sub(1, 400), idempotency_key = HttpService:GenerateGUID(false),
		})
	end)
end

local function requestAction(ctx, kind, target, duration, reason)
	if not Bridge.Enabled then return false, "Backend belum dikonfigurasi (Config.Backend). Ban/unban butuh backend." end
	if kind == "ban" and not Permissions.CanTargetId(ctx.player, target.userId) then
		return false, "Target adalah staf setara/lebih tinggi (atau diri sendiri)."
	end
	if kind == "ban" then
		local cap = Permissions.MaxBanSeconds(ctx.role)
		if cap and (duration.permanent or duration.seconds > cap) then
			return false, ("Role %s hanya boleh ban sampai %d hari."):format(ctx.role, math.floor(cap / 86400))
		end
	end
	local ok, res = Bridge.Call("request_action", {
		actor_user_id = ctx.player.UserId, role_key = ctx.role, target_user_id = target.userId, action_type = kind,
		duration_seconds = duration and duration.seconds or nil, permanent = duration and duration.permanent == true or false,
		public_reason = reason, private_reason = ("In-game ;%s oleh %s"):format(kind, ctx.player.Name),
		idempotency_key = HttpService:GenerateGUID(false),
	})
	if not ok then return false, "Ditolak backend: " .. tostring(res) end
	if res.status == "pending_approval" then
		return true, ("Ban PERMANEN %s dicatat, MENUNGGU persetujuan Management/Founder (orang lain)."):format(target.name)
	end
	return true, ("%s %s diantrekan. Dieksekusi server game dalam ±5–10 detik."):format(kind, target.name)
end

local function setInvisible(char, on)
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			if on then
				if d:GetAttribute("SmartACOrigT") == nil then d:SetAttribute("SmartACOrigT", d.Transparency) end
				d.Transparency = 1
			else
				local o = d:GetAttribute("SmartACOrigT")
				if o ~= nil then d.Transparency = o d:SetAttribute("SmartACOrigT", nil) end
			end
		end
	end
end

local function applyDescription(player, userId)
	local h = hum(player)
	if not h then return false, "Karakter tidak tersedia." end
	local ok, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserIdAsync(userId) end)
	if not ok then ok, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(userId) end) end
	if not ok or not desc then return false, "Avatar tidak bisa diambil." end
	local applied = pcall(function() h:ApplyDescription(desc) end)
	return applied, applied and "Avatar diterapkan." or "Gagal menerapkan avatar."
end

-- ---------- registrasi ----------
function Defs.Register(R, env)
	local add = R.Add
	local lastPos = {}          -- posisi sebelum teleport (untuk ;back)
	local locked = false        -- ;slock
	local pendingShutdown = {}  -- konfirmasi 2 langkah

	Players.PlayerRemoving:Connect(function(p) lastPos[p.UserId] = nil pendingShutdown[p.UserId] = nil end)
	Players.PlayerAdded:Connect(function(p)
		if locked and not Permissions.IsStaff(p) then p:Kick("Server sedang dikunci oleh staf. Coba lagi nanti atau masuk server lain.") end
	end)
	local function remember(p) local r = root(p) if r then lastPos[p.UserId] = r.CFrame end end
	local function move(p, cf, why)
		local r = root(p)
		if not r then return false end
		remember(p)
		Exemptions.Grant(p, GRACE, why)
		r.CFrame = cf
		return true
	end

	-- ===== UTILITAS =====
	add({ name = "help", aliases = { "cmds", "commands" }, group = "utility", desc = "Daftar perintah yang bisa lu pakai", run = function(ctx)
		local byGroup, order = {}, {}
		for _, d in ipairs(R.All()) do
			if env.canUse(ctx, d) then
				if not byGroup[d.group] then byGroup[d.group] = {} table.insert(order, d.group) end
				table.insert(byGroup[d.group], d.name)
			end
		end
		local lines = { "Awalan ; — contoh: ;kick budi spam | selector: me, all, others, random, admins, nonadmins, nama" }
		for _, g in ipairs(order) do table.insert(lines, ("[%s] %s"):format(g, table.concat(byGroup[g], ", "))) end
		return true, table.concat(lines, "\n")
	end })

	add({ name = "players", aliases = { "plrs" }, group = "utility", desc = "Daftar pemain di server ini", run = function()
		local t = {}
		for _, p in ipairs(Players:GetPlayers()) do table.insert(t, p.Name .. (Permissions.RoleOf(p) and (" [" .. Permissions.RoleOf(p) .. "]") or "")) end
		return true, ("%d pemain: %s"):format(#t, table.concat(t, ", "))
	end })

	add({ name = "staff", group = "utility", desc = "Staf yang sedang online", run = function()
		local t = {}
		for _, p in ipairs(Players:GetPlayers()) do local r = Permissions.RoleOf(p) if r then table.insert(t, ("%s [%s]"):format(p.Name, r)) end end
		return true, #t > 0 and table.concat(t, ", ") or "Tidak ada staf online di server ini."
	end })

	add({ name = "whoami", aliases = { "myrole" }, group = "utility", desc = "Role & izin lu", run = function(ctx)
		return true, ("Role: %s (rank %d) · %s"):format(ctx.role, ctx.rank, ctx.role == "helper" and "izin: warn, kick, ban 1 hari, announce server, uang/status (dibatasi)" or "akses penuh di Roblox")
	end })

	add({ name = "serverinfo", aliases = { "sinfo" }, group = "utility", desc = "Info server ini", run = function()
		local staff = 0
		for _, p in ipairs(Players:GetPlayers()) do if Permissions.IsStaff(p) then staff += 1 end end
		return true, ("Pemain %d/%d · staf %d · uptime %d menit · versi %d · %s · backend: %s%s"):format(
			#Players:GetPlayers(), Players.MaxPlayers, staff, math.floor(workspace.DistributedGameTime / 60), game.PlaceVersion,
			Bridge.JobId:sub(1, 8), Bridge.Enabled and "ON" or "OFF", locked and " · DIKUNCI" or "")
	end })

	add({ name = "info", group = "utility", perm = "players.read", desc = "Info pemain", args = { { name = "pemain", type = "player" } },
		run = function(_, p)
			return true, ("%s (@%s) · UserId %d · umur akun %d hari · role: %s"):format(p.DisplayName, p.Name, p.UserId, p.AccountAge, Permissions.RoleOf(p) or "pemain")
		end })

	add({ name = "lookup", aliases = { "history" }, group = "utility", perm = "players.history.read", desc = "Riwayat moderasi (backend)", args = { { name = "pemain", type = "userid" } },
		run = function(_, t)
			if not Bridge.Enabled then return false, "Backend belum dikonfigurasi." end
			local ok, res = Bridge.Call("player_history", { user_id = t.userId })
			if not ok then return false, "Gagal: " .. tostring(res) end
			local lines = { ("%s · violation %d · report %d"):format(t.name, res.violations or 0, res.reports or 0) }
			for i, a in ipairs(res.actions or {}) do
				if i > 5 then break end
				table.insert(lines, ("• %s [%s] %s"):format(a.action_type, a.status, tostring(a.public_reason):sub(1, 50)))
			end
			if #lines == 1 then table.insert(lines, "Riwayat bersih.") end
			return true, table.concat(lines, "\n")
		end })

	add({ name = "bans", group = "utility", perm = "players.history.read", desc = "10 ban terbaru (backend)", run = function()
		if not Bridge.Enabled then return false, "Backend belum dikonfigurasi." end
		local ok, res = Bridge.Call("recent_bans", {})
		if not ok then return false, "Gagal: " .. tostring(res) end
		local lines = {}
		for _, b in ipairs(res.bans or {}) do
			table.insert(lines, ("• %d — %s [%s] %s"):format(b.target_user_id, b.is_permanent and "PERMANEN" or ((b.duration_seconds or 0) // 86400 .. " hari"), b.status, tostring(b.public_reason):sub(1, 40)))
		end
		return true, #lines > 0 and table.concat(lines, "\n") or "Belum ada ban."
	end })

	add({ name = "reports", group = "utility", perm = "players.history.read", desc = "Report yang masih terbuka (backend)", run = function()
		if not Bridge.Enabled then return false, "Backend belum dikonfigurasi." end
		local ok, res = Bridge.Call("open_reports", {})
		if not ok then return false, "Gagal: " .. tostring(res) end
		local lines = { ("%d report terbuka"):format(res.total or 0) }
		for _, r in ipairs(res.reports or {}) do table.insert(lines, ("• %s — pemain %d — %s [%s]"):format(r.report_code, r.reported_user_id, r.category, r.status)) end
		return true, table.concat(lines, "\n")
	end })

	add({ name = "logs", group = "utility", perm = "players.read", desc = "Log perintah server ini", run = function()
		local lines = env.recentLogs(12)
		return true, #lines > 0 and table.concat(lines, "\n") or "Belum ada perintah di server ini."
	end })

	-- ===== MODERASI =====
	add({ name = "warn", group = "moderation", perm = "moderation.warn", desc = "Beri peringatan",
		args = { { name = "pemain", type = "players" }, { name = "alasan", type = "text", min = 3, max = 400 } },
		run = function(ctx, targets, reason)
			local list, skipped = harmful(ctx, targets, false)
			for _, t in ipairs(list) do
				local n = Integration.RecordWarn(t)
				local text = n and ("PERINGATAN #" .. n .. " dari staf: " .. reason) or reason
				if Integration.Active() then
					Integration.Notif(t, text, "error") Integration.Banner(text, "Staff", t)
				else
					Remotes.Notify:FireClient(t, { kind = "warning", text = reason })
				end
				record(ctx.player, "warn", t, reason)
			end
			return summarize("Warn terkirim ke", list, skipped)
		end })

	add({ name = "kick", group = "moderation", perm = "moderation.kick", desc = "Keluarkan pemain",
		args = { { name = "pemain", type = "players" }, { name = "alasan", type = "text", min = 3, max = 400 } },
		run = function(ctx, targets, reason)
			local list, skipped = harmful(ctx, targets, false)
			local label = names(list)
			for _, t in ipairs(list) do
				record(ctx.player, "kick", t, reason) -- catat DULU (setelah Kick, objek pemain hilang)
				t:Kick("Kamu dikeluarkan oleh staf.\nAlasan: " .. reason)
			end
			if #list == 0 then return summarize("Kick", list, skipped) end
			return true, ("Kick: %s%s"):format(label, skipped > 0 and (" (%d dilewati: dilindungi)"):format(skipped) or "")
		end })

	add({ name = "ban", group = "moderation", perm = "moderation.ban.temp",
		permFor = function(args) return (args[2] and args[2].permanent) and "moderation.ban.perm.request" or "moderation.ban.temp" end,
		desc = "Ban (1d 1w 30d 365d perm; perm butuh persetujuan orang lain)",
		args = { { name = "pemain", type = "userid" }, { name = "durasi", type = "duration" }, { name = "alasan", type = "text", min = 3, max = 400 } },
		run = function(ctx, target, duration, reason) return requestAction(ctx, "ban", target, duration, reason) end })

	add({ name = "unban", group = "moderation", perm = "moderation.unban", desc = "Cabut ban",
		args = { { name = "pemain", type = "userid" }, { name = "alasan", type = "text", min = 3, max = 400 } },
		run = function(ctx, target, reason) return requestAction(ctx, "unban", target, nil, reason) end })

	-- ===== TELEPORT =====
	add({ name = "to", aliases = { "goto" }, group = "teleport", perm = "ingame.teleport", desc = "Teleport ke pemain", args = { { name = "pemain", type = "player" } },
		run = function(ctx, target)
			local b = root(target)
			if not b or not move(ctx.player, b.CFrame * CFrame.new(0, 0, 4), "cmd_to") then return false, "Karakter tidak tersedia." end
			return true, "Teleport ke " .. target.Name
		end })

	add({ name = "bring", group = "teleport", perm = "ingame.teleport", desc = "Bawa pemain ke lu", args = { { name = "pemain", type = "players" } },
		run = function(ctx, targets)
			local list, skipped = harmful(ctx, targets, false)
			local me = root(ctx.player)
			if not me then return false, "Karakter lu tidak tersedia." end
			for i, t in ipairs(list) do
				move(t, me.CFrame * CFrame.new(((i - 1) % 5 - 2) * 3, 0, -5 - math.floor((i - 1) / 5) * 3), "cmd_bring")
			end
			return summarize("Dibawa ke lu", list, skipped)
		end })

	add({ name = "tp", group = "teleport", perm = "ingame.teleport", desc = "Pindahkan pemain A ke pemain B",
		args = { { name = "pemain", type = "players" }, { name = "tujuan", type = "player" } },
		run = function(ctx, targets, dest)
			local list, skipped = harmful(ctx, targets, true)
			local d = root(dest)
			if not d then return false, "Karakter tujuan tidak tersedia." end
			for _, t in ipairs(list) do move(t, d.CFrame * CFrame.new(0, 0, -4), "cmd_tp") end
			return summarize("Dipindahkan ke " .. dest.Name, list, skipped)
		end })

	add({ name = "back", group = "teleport", perm = "ingame.teleport", desc = "Kembalikan pemain ke posisi sebelum teleport", args = { { name = "pemain", type = "players" } },
		run = function(ctx, targets)
			local list, skipped = harmful(ctx, targets, true)
			local done = {}
			for _, t in ipairs(list) do
				local cf = lastPos[t.UserId]
				local r = root(t)
				if cf and r then Exemptions.Grant(t, GRACE, "cmd_back") r.CFrame = cf lastPos[t.UserId] = nil table.insert(done, t) end
			end
			return summarize("Dikembalikan", done, skipped)
		end })

	add({ name = "goserver", aliases = { "joinserver" }, group = "teleport", perm = "ingame.teleport",
		desc = "Pindah ke server tertentu (JobId dari embed laporan di Discord)", args = { { name = "jobid", type = "word" } },
		run = function(ctx, jobId)
			if jobId == Bridge.JobId then return false, "Lu sudah berada di server itu." end
			local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, ctx.player) end)
			return ok, ok and ("Memindahkan lu ke server " .. jobId:sub(1, 8) .. "…") or ("Gagal: " .. tostring(err):sub(1, 120) .. " (server mungkin sudah tutup)")
		end })

	local function shift(name, sign)
		add({ name = name, group = "teleport", perm = "ingame.teleport", desc = (sign > 0 and "Naikkan" or "Turunkan") .. " pemain (stud)",
			args = { { name = "pemain", type = "players" }, { name = "jarak", type = "number", min = 1, max = 500 } },
			run = function(ctx, targets, dist)
				local list, skipped = harmful(ctx, targets, true)
				for _, t in ipairs(list) do local r = root(t) if r then move(t, r.CFrame + Vector3.new(0, sign * dist, 0), "cmd_" .. name) end end
				return summarize(name, list, skipped)
			end })
	end
	shift("up", 1) shift("down", -1)

	add({ name = "tpos", group = "teleport", perm = "ingame.teleport", desc = "Teleport ke koordinat X Y Z",
		args = { { name = "pemain", type = "players" }, { name = "x", type = "number", min = -100000, max = 100000 }, { name = "y", type = "number", min = -1000, max = 100000 }, { name = "z", type = "number", min = -100000, max = 100000 } },
		run = function(ctx, targets, x, y, z)
			local list, skipped = harmful(ctx, targets, true)
			for _, t in ipairs(list) do move(t, CFrame.new(x, y, z), "cmd_tpos") end
			return summarize(("Ke %d,%d,%d"):format(x, y, z), list, skipped)
		end })

	-- ===== ALAT ADMIN (sisi client diminta lewat hasil "client") =====
	local function selfToggle(key, perm, label)
		add({ name = key, group = "tools", perm = perm, desc = label .. " (on/off)", args = { { name = "status", type = "onoff", optional = true } },
			run = function(ctx, want)
				if want == nil then want = not Exemptions.GetAdminState(ctx.player, key) end
				Exemptions.SetAdminState(ctx.player, key, want)
				return true, label .. (want and " AKTIF" or " MATI"), { kind = key, enabled = want }
			end })
	end
	selfToggle("fly", "ingame.fly", "Fly")
	selfToggle("noclip", "ingame.noclip", "Noclip")

	add({ name = "view", aliases = { "spectate" }, group = "tools", perm = "ingame.spectate", desc = "Pantau pemain", args = { { name = "pemain", type = "player" } },
		run = function(_, t) return true, "Memantau " .. t.Name .. " (;unview untuk berhenti)", { kind = "view", userId = t.UserId } end })
	add({ name = "unview", group = "tools", perm = "ingame.spectate", desc = "Berhenti memantau", run = function() return true, "Pantauan dihentikan", { kind = "unview" } end })
	add({ name = "esp", group = "tools", perm = "ingame.esp", desc = "Highlight semua pemain (on/off)", args = { { name = "status", type = "onoff", optional = true } },
		run = function(_, want) return true, "ESP diubah", { kind = "esp", enabled = want } end })

	add({ name = "copyavatar", aliases = { "char" }, group = "tools", perm = "ingame.copy_avatar", desc = "Salin tampilan avatar pemain", args = { { name = "pemain", type = "userid" } },
		run = function(ctx, t) local ok, m = applyDescription(ctx.player, t.userId) return ok, m end })
	add({ name = "resetavatar", group = "tools", perm = "ingame.copy_avatar", desc = "Kembalikan avatar asli lu",
		run = function(ctx) local ok, m = applyDescription(ctx.player, ctx.player.UserId) return ok, m end })

	add({ name = "invisible", aliases = { "invis" }, group = "tools", perm = "ingame.manage", desc = "Sembunyikan karakter lu (untuk memantau)",
		run = function(ctx) if not ctx.player.Character then return false, "Karakter tidak tersedia." end setInvisible(ctx.player.Character, true) return true, "Lu tidak terlihat." end })
	add({ name = "visible", group = "tools", perm = "ingame.manage", desc = "Tampilkan karakter lu lagi",
		run = function(ctx) if not ctx.player.Character then return false, "Karakter tidak tersedia." end setInvisible(ctx.player.Character, false) return true, "Lu terlihat lagi." end })

	add({ name = "god", group = "tools", perm = "ingame.manage", desc = "ForceField untuk pemain", args = { { name = "pemain", type = "players" } },
		run = function(ctx, targets)
			local list, skipped = harmful(ctx, targets, true)
			for _, t in ipairs(list) do
				local c = t.Character
				if c and not c:FindFirstChild("SmartACGod") then
					local ff = Instance.new("ForceField") ff.Name = "SmartACGod" ff.Visible = false ff.Parent = c
				end
			end
			return summarize("God aktif", list, skipped)
		end })
	add({ name = "ungod", group = "tools", perm = "ingame.manage", desc = "Cabut ForceField", args = { { name = "pemain", type = "players" } },
		run = function(ctx, targets)
			local list, skipped = harmful(ctx, targets, true)
			for _, t in ipairs(list) do local ff = t.Character and t.Character:FindFirstChild("SmartACGod") if ff then ff:Destroy() end end
			return summarize("God dicabut", list, skipped)
		end })

	-- ===== KELOLA PEMAIN =====
	local function manage(name, perm, desc, args, fn, verb, allowSelf)
		add({ name = name, group = "manage", perm = perm, desc = desc, args = args, run = function(ctx, targets, ...)
			local list, skipped = harmful(ctx, targets, allowSelf ~= false)
			for _, t in ipairs(list) do fn(t, ...) end
			return summarize(verb, list, skipped)
		end })
	end
	local P = { name = "pemain", type = "players" }
	manage("speed", "ingame.manage", "Atur WalkSpeed (0-100, normal 16)", { P, { name = "nilai", type = "number", min = 0, max = 100 } },
		function(t, v) local h = hum(t) if h then h.WalkSpeed = v end end, "Speed diubah")
	manage("jump", "ingame.manage", "Atur JumpPower (0-150, normal 50)", { P, { name = "nilai", type = "number", min = 0, max = 150 } },
		function(t, v) local h = hum(t) if h then pcall(function() h.UseJumpPower = true end) h.JumpPower = v end end, "Jump diubah")
	manage("normal", "ingame.manage", "Kembalikan speed & jump ke normal", { P },
		function(t) local h = hum(t) if h then h.WalkSpeed = DEFAULT_WALK pcall(function() h.UseJumpPower = true end) h.JumpPower = DEFAULT_JUMP end end, "Speed/jump direset")
	manage("heal", "ingame.manage", "Pulihkan darah penuh", { P },
		function(t) local h = hum(t) if h and h.Health > 0 then h.Health = h.MaxHealth end end, "Dipulihkan")
	manage("health", "ingame.manage", "Set darah (1-1000)", { P, { name = "nilai", type = "number", min = 1, max = 1000 } },
		function(t, v) local h = hum(t) if h and h.Health > 0 then h.Health = math.min(v, h.MaxHealth) end end, "Darah diubah")
	manage("respawn", "ingame.manage", "Respawn pemain", { P }, function(t) pcall(function() t:LoadCharacter() end) end, "Respawn")
	manage("freeze", "ingame.manage", "Bekukan pemain", { P }, function(t) local r = root(t) if r then r.Anchored = true end end, "Dibekukan")
	manage("unfreeze", "ingame.manage", "Lepas pembekuan", { P }, function(t) local r = root(t) if r then r.Anchored = false end end, "Dilepas")
	manage("sit", "ingame.manage", "Dudukkan pemain", { P }, function(t) local h = hum(t) if h then h.Sit = true end end, "Duduk")
	manage("kill", "ingame.kill", "Matikan pemain (diaudit)", { P }, function(t) local h = hum(t) if h then h.Health = 0 end end, "Dimatikan", false)


	-- ===== PLAYTEST SINAR RP: uang, status, VIP (batas per role dari Config.StaffMoney) =====
	local SM = Config.StaffMoney
	local cooldowns = {}
	local function rp(n)
		local r = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1.")
		r = r:reverse()
		if r:sub(1, 1) == "." then r = r:sub(2) end
		return "Rp" .. r
	end
	-- Perintah grup "playtest": helper kena cooldown per perintah (Config.StaffMoney.HelperCooldownSeconds).
	local function addPlaytest(def)
		local inner = def.run
		def.group = "playtest"
		def.run = function(ctx, ...)
			local key = ctx.player.UserId .. ":" .. def.name
			if ctx.role == "helper" and (cooldowns[key] or 0) > os.clock() then
				return false, ("Cooldown: tunggu %d detik untuk ;%s lagi."):format(math.ceil(cooldowns[key] - os.clock()), def.name)
			end
			local ok, msg, client = inner(ctx, ...)
			if ok and ctx.role == "helper" then cooldowns[key] = os.clock() + SM.HelperCooldownSeconds end
			return ok, msg, client
		end
		add(def)
	end
	local function needEkonomi()
		local E = Integration.Ekonomi()
		if not E then return nil, "Butuh game SINAR RP (modul Ekonomi tidak ditemukan)." end
		return E
	end
	local function capOk(ctx, n)
		local cap = SM.Caps[ctx.role]
		if cap and n > cap then return false, ("Batas role %s: maks %s per perintah."):format(ctx.role, rp(cap)) end
		return true
	end
	local function setMoney(ctx, n, saldo)
		local E, err = needEkonomi()
		if not E then return false, err end
		local okCap, why = capOk(ctx, n)
		if not okCap then return false, why end
		local cur = saldo and E.Saldo(ctx.player) or E.Uang(ctx.player)
		local add_, sub_ = saldo and E.TambahSaldo or E.TambahUang, saldo and E.KurangSaldo or E.KurangUang
		local ok = true
		if n > cur then ok = add_(ctx.player, n - cur, "Playtest staf") elseif n < cur then ok = sub_(ctx.player, cur - n, "Playtest staf") end
		if not ok then return false, "Ekonomi menolak perubahan." end
		return true, (saldo and "Saldo" or "Uang tunai") .. " diatur: " .. rp(n)
	end
	local function giveMoney(ctx, name, target, n, saldo)
		local E, err = needEkonomi()
		if not E then return false, err end
		local okCap, why = capOk(ctx, n)
		if not okCap then return false, why end
		local enforce = ctx.role == "helper" and SM.HelperSameTargetOnce
		local payload = {
			actor_user_id = ctx.player.UserId, role_key = ctx.role, command = name, target_user_id = target.UserId, amount = n,
			enforce = enforce, window_hours = SM.HelperSameTargetWindowHours,
		}
		if enforce then
			-- "Sekali per pemain" harus tahan restart/pindah server -> dicatat di backend (fail-closed untuk helper).
			if not Bridge.Enabled then return false, "Helper butuh backend aktif untuk batas 'sekali per pemain'." end
			local ok, res = Bridge.Call("money_grant", payload)
			if not ok then return false, "Gagal memeriksa batas (backend): " .. tostring(res) end
			if res.outcome == "duplicate" then return false, ("Helper hanya boleh ;%s SEKALI ke pemain yang sama (%s)."):format(name, target.Name) end
		else
			task.spawn(function() Bridge.Call("money_grant", payload) end) -- jejak keuangan (best-effort)
		end
		local fn = saldo and E.TambahSaldo or E.TambahUang
		if not fn(target, n, "Playtest staf") then return false, "Ekonomi menolak (cek pemain/jumlah)." end
		Integration.Notif(target, ("Staf memberi %s %s."):format(rp(n), saldo and "saldo" or "tunai"), "sukses")
		return true, ("Memberi %s %s ke %s"):format(rp(n), saldo and "saldo" or "tunai", target.DisplayName)
	end
	local AMOUNT = { name = "jumlah", type = "integer", min = 0, max = 1e10 }
	local AMOUNT1 = { name = "jumlah", type = "integer", min = 1, max = 1e10 }

	addPlaytest({ name = "setuang", perm = "sinar.money", desc = "Atur uang tunai lu sendiri", args = { AMOUNT },
		run = function(ctx, n) return setMoney(ctx, n, false) end })
	addPlaytest({ name = "setsaldo", perm = "sinar.money", desc = "Atur saldo bank lu sendiri", args = { AMOUNT },
		run = function(ctx, n) return setMoney(ctx, n, true) end })
	addPlaytest({ name = "kasihuang", perm = "sinar.money", desc = "Beri uang tunai ke pemain", args = { { name = "pemain", type = "player" }, AMOUNT1 },
		run = function(ctx, t, n) return giveMoney(ctx, "kasihuang", t, n, false) end })
	addPlaytest({ name = "kasihsaldo", perm = "sinar.money", desc = "Beri saldo bank ke pemain", args = { { name = "pemain", type = "player" }, AMOUNT1 },
		run = function(ctx, t, n) return giveMoney(ctx, "kasihsaldo", t, n, true) end })

	addPlaytest({ name = "cek", perm = "sinar.self", desc = "Lihat uang/saldo/KTP pemain", args = { { name = "pemain", type = "player", optional = true } },
		run = function(ctx, t)
			local E, err = needEkonomi()
			if not E then return false, err end
			t = t or ctx.player
			return true, ("%s | Tunai %s | Saldo %s | KTP %s"):format(t.DisplayName, rp(E.Uang(t)), rp(E.Saldo(t)), t:GetAttribute("KTP") and "punya" or "belum")
		end })
	addPlaytest({ name = "sembuh", perm = "sinar.self", desc = "Pulihkan HP lu penuh",
		run = function(ctx) local h = hum(ctx.player) if not h then return false, "Karakter tidak tersedia." end h.Health = h.MaxHealth return true, "HP dipulihkan penuh." end })
	addPlaytest({ name = "wafat", perm = "sinar.self", desc = "Matikan karakter lu (tes EMS)",
		run = function(ctx) local h = hum(ctx.player) if not h or h.Health <= 0 then return false, "Karakter tidak tersedia." end h.Health = 0 return true, "Karakter dimatikan (tes)." end })
	addPlaytest({ name = "cepat", perm = "sinar.self", desc = "Atur kecepatan jalan lu (default 16)", args = { { name = "angka", type = "integer", min = 0, max = 500, optional = true } },
		run = function(ctx, n) local h = hum(ctx.player) if not h then return false, "Karakter tidak tersedia." end n = n or 16 h.WalkSpeed = n return true, "Kecepatan jalan: " .. n end })
	addPlaytest({ name = "lompat", perm = "sinar.self", desc = "Atur kekuatan lompat lu (default 50)", args = { { name = "angka", type = "integer", min = 0, max = 1000, optional = true } },
		run = function(ctx, n) local h = hum(ctx.player) if not h then return false, "Karakter tidak tersedia." end n = n or 50 pcall(function() h.UseJumpPower = true end) h.JumpPower = n return true, "Kekuatan lompat: " .. n end })
	addPlaytest({ name = "stat", perm = "sinar.self", desc = "Atur status tubuh lu (lapar/haus/mood 0-100)",
		args = { { name = "jenis", type = "enum", values = { "lapar", "haus", "mood" } }, { name = "nilai", type = "integer", min = 0, max = 100 } },
		run = function(ctx, jenis, n)
			ctx.player:SetAttribute(jenis == "lapar" and "Lapar" or jenis == "haus" and "Haus" or "Mood", n)
			return true, ("Status %s = %d"):format(jenis, n)
		end })
	addPlaytest({ name = "reset", perm = "sinar.self", desc = "Respawn karakter lu",
		run = function(ctx)
			local ok = pcall(function() ctx.player:LoadCharacterAsync() end) or pcall(function() ctx.player:LoadCharacter() end)
			return ok, ok and "Respawn." or "Respawn gagal."
		end })
	-- VIP: TIDAK untuk helper (izin sinar.vip hanya founder/management/developer/administrator)
	addPlaytest({ name = "vipon", perm = "sinar.vip", desc = "Aktifkan tampilan VIP (tes)", run = function(ctx) ctx.player:SetAttribute("VIP", true) return true, "Tampilan VIP aktif (tes)." end })
	addPlaytest({ name = "vipoff", perm = "sinar.vip", desc = "Matikan tampilan VIP", run = function(ctx) ctx.player:SetAttribute("VIP", false) return true, "Tampilan VIP mati." end })

	-- ===== SERVER & ANTI-CHEAT =====
	add({ name = "grace", group = "server", perm = "ingame.exempt", desc = "Beri pemain kekebalan gerakan sementara (detik)",
		args = { P, { name = "detik", type = "number", min = 1, max = 300 } },
		run = function(ctx, targets, sec)
			local list, skipped = harmful(ctx, targets, true)
			for _, t in ipairs(list) do Exemptions.Grant(t, sec, "cmd_grace") end
			return summarize(("Kebal %ds"):format(sec), list, skipped)
		end })
	add({ name = "exempt", group = "server", perm = "ingame.exempt", desc = "Kecualikan pemain dari cek gerakan (on/off) — mis. untuk event",
		args = { P, { name = "status", type = "onoff", optional = true } },
		run = function(ctx, targets, want)
			local list, skipped = harmful(ctx, targets, true)
			for _, t in ipairs(list) do Exemptions.SetAdminState(t, "manual", want ~= false) end
			return summarize(want == false and "Pengecualian dicabut" or "Dikecualikan dari cek gerakan", list, skipped)
		end })
	add({ name = "slock", group = "server", perm = "ingame.server", desc = "Kunci server (hanya staf yang bisa masuk)",
		run = function() locked = true return true, "Server DIKUNCI. Pemain baru (non-staf) akan di-kick. ;unslock untuk membuka." end })
	add({ name = "unslock", group = "server", perm = "ingame.server", desc = "Buka kunci server", run = function() locked = false return true, "Server dibuka." end })
	add({ name = "shutdown", group = "server", perm = "ingame.shutdown", desc = "Tutup server ini — HANYA Founder & Developer (konfirmasi 2 langkah)", args = { { name = "alasan", type = "text", min = 3, max = 200 } },
		run = function(ctx, reason)
			local exp = pendingShutdown[ctx.player.UserId]
			if not exp or exp < os.clock() then
				pendingShutdown[ctx.player.UserId] = os.clock() + 20
				return true, "KONFIRMASI: ketik perintah yang SAMA lagi dalam 20 detik untuk menutup server ini."
			end
			pendingShutdown[ctx.player.UserId] = nil
			pcall(Bridge.Call, "audit", { actor_user_id = ctx.player.UserId, role_key = ctx.role, action = "ingame.cmd_shutdown", target_id = "", details = { reason = reason } })
			for _, p in ipairs(Players:GetPlayers()) do p:Kick("Server ditutup oleh staf.\nAlasan: " .. reason) end
			return true, "Server ditutup."
		end })

	-- ===== PENGUMUMAN =====
	add({ name = "announce", aliases = { "m" }, group = "announce", perm = "announce.server", desc = "Pengumuman di server ini", args = { { name = "pesan", type = "text", min = 3, max = 200 } },
		run = function(ctx, text)
			local from = (ctx.role or "Staff") .. " " .. ctx.player.DisplayName
			if not Integration.Banner(text, from) then Remotes.Notify:FireAllClients({ kind = "announce", text = text, from = ctx.player.DisplayName }) end
			return true, "Pengumuman server terkirim."
		end })
	add({ name = "gannounce", aliases = { "gm" }, group = "announce", perm = "announce.global", desc = "Pengumuman ke SEMUA server", args = { { name = "pesan", type = "text", min = 3, max = 200 } },
		run = function(ctx, text)
			local how = Executor.Announce(HttpService:GenerateGUID(false), text, ctx.player.DisplayName)
			return true, "Pengumuman global: " .. how .. " (best-effort)."
		end })
	add({ name = "notify", group = "announce", perm = "ingame.notify", desc = "Pesan pribadi ke pemain", args = { P, { name = "pesan", type = "text", min = 3, max = 200 } },
		run = function(ctx, targets, text)
			for _, t in ipairs(targets) do
				if not Integration.Notif(t, text, "info") then Remotes.Notify:FireClient(t, { kind = "announce", text = text, from = ctx.player.DisplayName }) end
			end
			return true, "Dikirim ke " .. names(targets)
		end })
end

return Defs
