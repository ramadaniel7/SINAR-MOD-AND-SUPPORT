-- RemoteGuard: bungkus RemoteEvent/RemoteFunction dengan rate limit + validasi argumen.
-- Dipakai oleh modul SmartAC sendiri DAN oleh developer RP untuk SEMUA remote sensitif.
--
-- Contoh (developer RP):
--   local Api = require(game.ServerScriptService.SmartAC.Api)
--   local V = Api.Validate
--   Api.Guard.Event(buyRemote, { Args = { V.String(1, 40), V.Integer(1, 10) }, PerSecond = 2, Burst = 4 },
--     function(player, itemId, qty) ... end)  -- harga/uang/stok WAJIB dihitung di server, bukan dari client
local Config = require(script.Parent.Parent.Config)
local RateLimit = require(script.Parent.RateLimit)
local Scoring = require(script.Parent.Scoring)

local Guard = {}
local D = Config.AntiCheat.Remote

local function check(player, remote, opts, ...)
	-- 1) rate limit dulu (paling murah), 2) jumlah arg, 3) tipe/batas tiap arg
	if not RateLimit.Allow("remote:" .. remote.Name, player, opts.PerSecond or D.PerSecond, opts.Burst or D.Burst) then
		Scoring.Hit(player, "remote.spam", 5, 1, { remote = remote.Name })
		return false
	end
	local args = opts.Args or {}
	if select("#", ...) ~= #args then
		Scoring.Hit(player, "remote.invalid_args", 8, 2, { remote = remote.Name, reason = "arg_count" })
		return false
	end
	for i, validator in ipairs(args) do
		local value = select(i, ...)
		if not validator(value) then
			Scoring.Hit(player, "remote.invalid_args", 8, 2, { remote = remote.Name, reason = "arg_" .. i })
			return false
		end
	end
	return true
end

function Guard.Event(remote, opts, handler)
	return remote.OnServerEvent:Connect(function(player, ...)
		if not check(player, remote, opts, ...) then return end
		local ok, err = pcall(handler, player, ...)
		if not ok then warn("[SmartAC] handler error", remote.Name, err) end
	end)
end

function Guard.Invoke(remoteFunction, opts, handler)
	remoteFunction.OnServerInvoke = function(player, ...)
		if not check(player, remoteFunction, opts, ...) then return nil end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn("[SmartAC] handler error", remoteFunction.Name, result)
			return { ok = false, error = "internal_error" }
		end
		return result
	end
end

return Guard
