-- Komunikasi ke backend (Supabase Edge Function "roblox-gateway") via HttpService.
-- Aman: payload kecil, batch, timeout, retry + backoff, antrean ber-batas, rahasia tidak pernah di-log.
local HttpService = game:GetService("HttpService")
local Config = require(script.Parent.Parent.Config)
local Util = require(script.Parent.Util)

local Bridge = {}
local cfg = Config.Backend

Bridge.Enabled = not (string.find(cfg.Key, "GANTI", 1, true) or string.find(cfg.Url, "PROJECT_REF", 1, true))
Bridge.JobId = (game.JobId ~= "" and game.JobId) or "studio-test"

local failures = 0
local MAX_QUEUE = 200
local queues = { violations = {}, audit = {} }
local started = false
local lastWarn = -100
local lastReject = {}
local announcedOk = false

function Bridge.Backoff()
	return math.min(60, 2 ^ math.min(failures, 6))
end

-- Mengembalikan (ok:boolean, hasil_atau_kode_error)
function Bridge.Call(kind, data)
	if not Bridge.Enabled then
		return false, "bridge_disabled"
	end
	local body = HttpService:JSONEncode({
		kind = kind,
		nonce = HttpService:GenerateGUID(false),
		ts = DateTime.now():ToIsoDate(),
		job_id = Bridge.JobId,
		place_id = game.PlaceId,
		data = data or {},
	})
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = cfg.Url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["x-sac-key"] = cfg.Key },
			Body = body,
		})
	end)
	if not ok then
		failures += 1
		if os.clock() - lastWarn > 60 then
			lastWarn = os.clock()
			Util.Warn("Request ke backend gagal (cek: Game Settings > Security > Allow HTTP Requests, URL, internet):", tostring(res))
		end
		return false, "http_error"
	end
	local decoded
	pcall(function() decoded = HttpService:JSONDecode(res.Body) end)
	if not res.Success then
		if res.StatusCode >= 500 or res.StatusCode == 429 then failures += 1 end
		local code = (decoded and decoded.error) or ("http_" .. tostring(res.StatusCode))
		-- Jangan gagal diam-diam: tampilkan penolakan backend (maks 1x per 30 dtk per jenis+kode).
		local key = kind .. ":" .. tostring(code)
		if os.clock() - (lastReject[key] or -100) > 30 then
			lastReject[key] = os.clock()
			Util.Warn(("Backend menolak '%s' (HTTP %d): %s"):format(kind, res.StatusCode, tostring(code)))
		end
		return false, code
	end
	failures = 0
	if not announcedOk then
		announcedOk = true
		Util.Log("Terhubung ke backend (request pertama sukses: " .. kind .. ").")
	end
	return true, decoded or {}
end

-- Antrean ber-batas (buang yang paling lama kalau penuh) supaya memori tidak menumpuk saat backend mati.
function Bridge.Enqueue(kind, item)
	local q = queues[kind]
	if #q >= MAX_QUEUE then
		table.remove(q, 1)
	end
	table.insert(q, item)
end

local function flush(kind, batchSize, field)
	local q = queues[kind]
	if #q == 0 then return end
	local batch = {}
	for i = 1, math.min(batchSize, #q) do batch[i] = q[i] end
	local ok, res
	if kind == "violations" then
		ok, res = Bridge.Call("violations", { items = batch })
	else
		ok, res = Bridge.Call("audit", batch[1])
		batch = { batch[1] }
	end
	if ok then
		for _ = 1, #batch do table.remove(q, 1) end
	elseif res == "invalid_violation" or res == "invalid_audit" or res == "invalid_batch" then
		for _ = 1, #batch do table.remove(q, 1) end -- payload buruk: buang, jangan macet selamanya
		Util.Warn("Item dibuang karena ditolak backend:", res)
	end
end

function Bridge.Start()
	if started then return end
	started = true
	if not Bridge.Enabled then
		Util.Warn("Backend BELUM dikonfigurasi (Config.Backend). Anti-cheat tetap jalan lokal, tapi tidak ada Discord/dashboard/ban command.")
		return
	end
	task.spawn(function()
		while true do
			task.wait(cfg.FlushSeconds + Bridge.Backoff() - 1)
			flush("violations", 20)
			for _ = 1, 5 do flush("audit", 1) end
		end
	end)
end

return Bridge
