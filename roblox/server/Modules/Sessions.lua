-- Sinkronisasi sesi pemain ke backend (batch, bukan per-event). Diperlukan agar kick/warn tahu pemain ada di server mana.
local Players = game:GetService("Players")
local Config = require(script.Parent.Parent.Config)
local Bridge = require(script.Parent.Bridge)

local Sessions = {}
local keys = {}     -- [player] = session_key
local joined, left = {}, {}

local function onAdded(player)
	local key = string.format("%s:%d:%d", Bridge.JobId, player.UserId, os.time())
	keys[player] = key
	table.insert(joined, { session_key = key, user_id = player.UserId, username = player.Name, display_name = player.DisplayName })
end

local function onRemoving(player)
	local key = keys[player]
	keys[player] = nil
	if key then table.insert(left, { session_key = key, reason = "left" }) end
end

local function sync()
	local online = {}
	for _, key in pairs(keys) do table.insert(online, key) end
	local j, l = joined, left
	joined, left = {}, {}
	local ok = Bridge.Call("players_sync", { joined = j, left = l, online = online })
	if not ok then
		-- kembalikan ke antrean (dengan batas) supaya tidak hilang saat backend sempat mati
		for _, x in ipairs(j) do if #joined < 100 then table.insert(joined, x) end end
		for _, x in ipairs(l) do if #left < 100 then table.insert(left, x) end end
	end
end

function Sessions.Start()
	if not Bridge.Enabled then return end
	for _, p in ipairs(Players:GetPlayers()) do onAdded(p) end
	Players.PlayerAdded:Connect(onAdded)
	Players.PlayerRemoving:Connect(onRemoving)
	task.spawn(function()
		local lastBeat = 0
		while true do
			task.wait(Config.Backend.FlushSeconds + Bridge.Backoff() - 1)
			if #joined > 0 or #left > 0 or os.clock() - lastBeat >= Config.Backend.HeartbeatSeconds then
				lastBeat = os.clock()
				-- batas 50 join/left per request sesuai batas backend
				while #joined > 50 do table.remove(joined) end
				while #left > 50 do table.remove(left) end
				sync()
			end
		end
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do onRemoving(p) end
		pcall(sync)
	end)
end

return Sessions
