-- Eksekutor perintah dari backend (Discord/dashboard/in-game): ban, unban, kick, warn, announce.
-- Server game yang mengeksekusi. Hasil asli (berhasil/gagal) dilaporkan balik; "tercatat di DB" BUKAN bukti ban berhasil.
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local Config = require(script.Parent.Parent.Config)
local Bridge = require(script.Parent.Bridge)
local Integration = require(script.Parent.Integration)
local Remotes = require(script.Parent.Remotes)
local Scoring = require(script.Parent.Scoring)
local Util = require(script.Parent.Util)

local Executor = {}
local TOPIC = "SmartAC_Announce"

-- ---------------- Pengumuman global (best-effort, dedupe per id) ----------------
local seen, seenOrder = {}, {}
local function showAnnouncement(data)
	if type(data) ~= "table" or type(data.id) ~= "string" or seen[data.id] then return end
	if type(data.message) ~= "string" or #data.message > 200 then return end
	seen[data.id] = true
	table.insert(seenOrder, data.id)
	if #seenOrder > 100 then seen[table.remove(seenOrder, 1)] = nil end
	Remotes.Notify:FireAllClients({ kind = "announce", text = data.message, from = tostring(data.from or "Staff"):sub(1, 40) })
end

function Executor.Announce(id, message, from)
	if Integration.Active() then
		-- Pakai pipeline pengumuman SINAR RP: banner lokal + topic yang sama untuk server lain.
		Integration.Banner(message, from)
		Integration.PublishGlobal(message, from)
		return "published"
	end
	local payload = { id = id, message = message, from = from }
	local ok = pcall(function() MessagingService:PublishAsync(TOPIC, payload) end)
	if not ok then
		showAnnouncement(payload)
		return "local_only"
	end
	task.delay(4, function() showAnnouncement(payload) end) -- cadangan jika langganan lokal tidak menerima
	return "published"
end

-- ---------------- Config dari backend (saklar darurat jarak jauh) ----------------
function Executor.RefreshConfig()
	local ok, res = Bridge.Call("config", {})
	if not ok or type(res.enforcement) ~= "table" then return end
	-- Enforced hanya jika KEDUANYA mengizinkan: Config lokal DAN backend.
	local backendAllows = res.enforcement.mode == "enforced" and res.enforcement.auto_kick_enabled == true
	local effective = (not Config.AntiCheat.LockDetectOnly and Config.AntiCheat.Mode == "enforced" and backendAllows) and "enforced" or "detect_only"
	if effective ~= Scoring.Mode then
		Util.Log("Mode anti-cheat sekarang:", effective)
		Scoring.Mode = effective
	end
end

-- ---------------- Eksekusi satu perintah ----------------
local ACTIONS = { ban = true, unban = true, kick = true, warn = true }

local function execute(cmd)
	local p = cmd.payload
	if cmd.type == "announce_global" then
		if type(p) ~= "table" or type(p.message) ~= "string" then return "rejected", {}, "bad_payload" end
		return "executed", { delivery = Executor.Announce(cmd.id, p.message, p.from) }
	elseif cmd.type == "refresh_config" then
		Executor.RefreshConfig()
		return "executed", {}
	elseif cmd.type ~= "execute_action" then
		return "rejected", {}, "unknown_command_type"
	end

	if type(p) ~= "table" or not ACTIONS[p.action_type] or type(p.target_user_id) ~= "number" or p.target_user_id % 1 ~= 0 or p.target_user_id < 1 then
		return "rejected", {}, "bad_payload"
	end
	local reason = type(p.public_reason) == "string" and p.public_reason or "Pelanggaran aturan"
	local private = (type(p.private_reason) == "string" and #p.private_reason >= 3) and p.private_reason or "Tidak ada catatan"

	if p.action_type == "ban" then
		local duration = p.is_permanent and -1 or p.duration_seconds -- -1 = permanen (terverifikasi di dokumentasi Roblox)
		if type(duration) ~= "number" or (duration ~= -1 and duration < 1) then return "rejected", {}, "bad_duration" end
		local ok, err = pcall(function()
			Players:BanAsync({
				UserIds = { p.target_user_id },
				Duration = duration,
				DisplayReason = reason,
				PrivateReason = private,
				ApplyToUniverse = true,
				ExcludeAltAccounts = false,
			})
		end)
		if not ok then return "failed", {}, "BanAsync: " .. tostring(err):sub(1, 300) end
		return "executed", { duration = duration }

	elseif p.action_type == "unban" then
		local ok, err = pcall(function()
			Players:UnbanAsync({ UserIds = { p.target_user_id }, ApplyToUniverse = true })
		end)
		if not ok then return "failed", {}, "UnbanAsync: " .. tostring(err):sub(1, 300) end
		return "executed", {}

	else -- kick / warn: hanya bisa di server tempat pemain berada
		local target = Players:GetPlayerByUserId(p.target_user_id)
		if not target then return "rejected", {}, "player_not_in_server" end
		if p.action_type == "kick" then
			target:Kick("Kamu dikeluarkan oleh staf.\nAlasan: " .. reason)
		else
			local n = Integration.RecordWarn(target) -- samakan hitungan warn di data SINAR RP
			local text = n and ("PERINGATAN #" .. n .. " dari staf: " .. reason) or reason
			if Integration.Active() then
				Integration.Notif(target, text, "error")
				Integration.Banner(text, "Staff", target)
			else
				Remotes.Notify:FireClient(target, { kind = "warning", text = reason })
			end
		end
		return "executed", {}
	end
end

local doneCache, doneOrder = {}, {}
local function complete(id, outcome, result, err)
	for attempt = 1, 3 do
		local ok, res = Bridge.Call("complete", { id = id, outcome = outcome, result = result or {}, error = err })
		if ok then return true end
		if res == "not_lease_holder" or res == "command_not_found" then return false end
		task.wait(2 ^ attempt)
	end
	return false
end

local function process(cmd)
	if type(cmd) ~= "table" or type(cmd.id) ~= "string" then return end
	-- Pengiriman at-least-once: jika perintah sama datang lagi, JANGAN eksekusi ulang, cukup laporkan hasil lama.
	local cached = doneCache[cmd.id]
	if not cached then
		local ok, outcome, result, err = pcall(execute, cmd)
		if not ok then
			cached = { outcome = "failed", result = {}, err = "exception: " .. tostring(outcome):sub(1, 200) }
		else
			cached = { outcome = outcome, result = result, err = err }
		end
		doneCache[cmd.id] = cached
		table.insert(doneOrder, cmd.id)
		if #doneOrder > 200 then doneCache[table.remove(doneOrder, 1)] = nil end
	end
	Util.Debug("eksekusi", cmd.type, cmd.id:sub(1, 8), "->", cached.outcome, cached.err or "")
	complete(cmd.id, cached.outcome, cached.result, cached.err)
end

function Executor.Start()
	if not Bridge.Enabled then return end
	task.spawn(function()
		pcall(function() MessagingService:SubscribeAsync(TOPIC, function(msg) showAnnouncement(msg.Data) end) end)
	end)
	task.spawn(function()
		local lastCfg = 0
		while true do
			local wait = Config.Backend.PollSeconds
			if os.clock() - lastCfg > 300 then
				lastCfg = os.clock()
				Executor.RefreshConfig()
			end
			local ok, res = Bridge.Call("claim", {})
			if ok then
				local n = #(res.commands or {})
				if n > 0 then Util.Debug("claim: dapat", n, "perintah") end
				for _, cmd in ipairs(res.commands or {}) do process(cmd) end
			else
				wait += Bridge.Backoff()
			end
			task.wait(wait)
		end
	end)
end

return Executor
