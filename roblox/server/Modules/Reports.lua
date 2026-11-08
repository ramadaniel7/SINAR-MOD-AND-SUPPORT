-- Laporan pemain. Server memvalidasi target, rate limit, dan memfilter teks sebelum dikirim.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local Bridge = require(script.Parent.Bridge)
local Guard = require(script.Parent.Guard)
local Remotes = require(script.Parent.Remotes)
local Util = require(script.Parent.Util)

local V = Util.V
local Reports = {}

function Reports.Start()
	Guard.Invoke(Remotes.SubmitReport, {
		Args = { V.UserId, V.Enum({ "cheating", "fail_roleplay", "harassment", "other" }), V.String(5, 300) },
		PerSecond = 0.2, Burst = 2,
	}, function(player, targetUserId, category, description)
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target == player then
			return { ok = false, error = "invalid_target" }
		end
		if not Bridge.Enabled then
			return { ok = false, error = "unavailable" }
		end

		-- Filter teks (wajib untuk teks buatan pemain)
		local okF, filtered = pcall(function()
			local result = TextService:FilterStringAsync(description, player.UserId, Enum.TextFilterContext.PublicChat)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if not okF or type(filtered) ~= "string" then
			return { ok = false, error = "filter_failed" }
		end

		local function pos(p)
			local c = p.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if not r then return nil end
			local v = r.Position
			return { math.floor(v.X + 0.5), math.floor(v.Y + 0.5), math.floor(v.Z + 0.5) }
		end
		local ok, res = Bridge.Call("report", {
			idempotency_key = HttpService:GenerateGUID(false),
			reporter_user_id = player.UserId,
			reported_user_id = target.UserId,
			category = category,
			description = filtered,
			-- konteks agar staf bisa langsung menemukan kejadian: nama, posisi, server
			context = {
				reporter_name = player.Name, reported_name = target.Name,
				reporter_pos = pos(player), reported_pos = pos(target),
				players = #Players:GetPlayers(), max_players = Players.MaxPlayers, place_version = game.PlaceVersion,
			},
		})
		if not ok then return { ok = false, error = "unavailable" } end
		if res.outcome == "created" then
			return { ok = true, code = res.code }
		elseif res.outcome == "duplicate_recent" or res.outcome == "duplicate_request" then
			return { ok = true, code = res.code, duplicate = true }
		end
		return { ok = false, error = res.outcome or "failed" }
	end)
end

return Reports
