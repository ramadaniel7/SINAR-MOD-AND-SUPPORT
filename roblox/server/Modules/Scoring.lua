-- Pipeline: observe -> validate -> record evidence -> korelasi sinyal independen -> mitigasi -> catat hasil.
-- Satu sinyal TIDAK PERNAH cukup untuk menghukum (kecuali honeypot, yang memang tidak pernah dipanggil client asli).
-- Auto-BAN tidak ada sama sekali: yang terparah otomatis hanyalah KICK (mode enforced), ban selalu keputusan manusia.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Config = require(script.Parent.Parent.Config)
local Permissions = require(script.Parent.Permissions)
local Bridge = require(script.Parent.Bridge)
local Util = require(script.Parent.Util)

local Scoring = {}
local C = Config.AntiCheat.Score
local state = {} -- [player] = { score, last, detectors = {[name] = time}, emitted = {[name] = {t, suppressed}}, kicked }

Scoring.Mode = Config.AntiCheat.LockDetectOnly and "detect_only" or Config.AntiCheat.Mode

local function get(player)
	local s = state[player]
	if not s then
		s = { score = 0, last = os.clock(), detectors = {}, emitted = {}, kicked = false }
		state[player] = s
	end
	return s
end

local function distinctRecent(s, now)
	local n = 0
	for _, t in pairs(s.detectors) do
		if now - t <= 60 then n += 1 end
	end
	return n
end

-- options.strong = true  -> sinyal yang cukup kuat sendirian (honeypot)
function Scoring.Hit(player, detector, points, severity, evidence, options)
	if not player or not player.Parent then return end
	-- STAFF KEBAL: tidak dicatat, tidak dihukum (Config.StaffImmune). Hierarki staf tetap berlaku di perintah moderasi.
	if Config.StaffImmune and Permissions.IsStaff(player) then return end
	local now = os.clock()
	local s = get(player)
	s.score = math.max(0, s.score - (now - s.last) * C.DecayPerSecond) + points
	s.last = now
	s.detectors[detector] = now

	-- Catat insiden dengan cooldown per-detector supaya tidak spam (jumlah yang ditahan ikut dicatat).
	local e = s.emitted[detector]
	if e and now - e.t < C.EmitCooldownSeconds then
		e.suppressed += 1
	else
		local suppressed = e and e.suppressed or 0
		s.emitted[detector] = { t = now, suppressed = 0 }
		evidence = evidence or {}
		evidence.suppressed_since_last = suppressed
		evidence.total_score = math.floor(s.score * 10) / 10
		local mitigation = nil

		local kickNow = Scoring.Mode == "enforced" and not s.kicked and (
			(options and options.strong) or
			(s.score >= C.KickScore and distinctRecent(s, now) >= C.DistinctDetectors)
		)
		if kickNow then
			s.kicked = true
			mitigation = "kick"
		end

		Bridge.Enqueue("violations", {
			event_key = HttpService:GenerateGUID(false), -- unik per insiden (36 karakter, batas backend 8-128)
			user_id = player.UserId,
			detector = detector,
			severity = severity,
			score = math.floor(s.score * 100) / 100,
			mode = Scoring.Mode,
			mitigation = mitigation,
			evidence = evidence,
		})
		if mitigation == "kick" then
			task.defer(function()
				if player.Parent then
					player:Kick("Aktivitas mencurigakan terdeteksi. Jika ini kesalahan, hubungi staff di Discord.")
				end
			end)
		end
		if Scoring.Mode == "detect_only" then
			Util.Log(("[detect-only] %s (%d) -> %s sev=%d score=%.1f"):format(player.Name, player.UserId, detector, severity, s.score))
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
end)

return Scoring
