-- Pemantau ekonomi SINAR RP. Tidak mengubah apa pun di game: hanya membaca Attribute "Uang" & "Saldo"
-- (yang dipantulkan modul Ekonomi) dan MENCATAT sinyal mencurigakan. Tidak pernah menghukum.
local Players = game:GetService("Players")
local Config = require(script.Parent.Parent.Config)
local Permissions = require(script.Parent.Permissions)
local Scoring = require(script.Parent.Scoring)

local Economy = {}

local function watch(player)
	local C = Config.Economy
	local last = nil
	local window = {} -- { {waktu, kenaikan} }

	local function check()
		local u, s = player:GetAttribute("Uang"), player:GetAttribute("Saldo")
		if u == nil or s == nil then return end -- data belum siap
		if type(u) ~= "number" or type(s) ~= "number" or u ~= u or s ~= s or u < 0 or s < 0 or u > 1e13 or s > 1e13 then
			-- Keadaan mustahil (NaN / negatif / raksasa): hampir pasti bug atau manipulasi data.
			Scoring.Hit(player, "economy.invalid_state", 50, 4, { uang = tostring(u), saldo = tostring(s) })
			return
		end
		local total = u + s
		if last ~= nil and total > last then
			local now = os.clock()
			table.insert(window, { now, total - last })
			local sum, keep = 0, {}
			for _, e in ipairs(window) do
				if now - e[1] <= C.WindowSeconds then
					table.insert(keep, e)
					sum += e[2]
				end
			end
			window = keep
			if sum >= C.GainThreshold then
				window = {}
				-- Staf yang memakai /uang sudah diaudit terpisah: beri bobot rendah agar tidak berisik.
				local severity = Permissions.IsStaff(player) and 1 or 2
				Scoring.Hit(player, "economy.large_gain", 15, severity, { gained = sum, window_seconds = C.WindowSeconds, staff = severity == 1 })
			end
		end
		last = total
	end

	player:GetAttributeChangedSignal("Uang"):Connect(check)
	player:GetAttributeChangedSignal("Saldo"):Connect(check)
	check()
end

function Economy.Start()
	if not Config.Economy.Enabled then return end
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(watch, p) end
	Players.PlayerAdded:Connect(watch)
end

return Economy
