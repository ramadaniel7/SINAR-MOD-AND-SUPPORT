-- Token bucket per (scope, player). Murah: dicek SEBELUM operasi mahal.
local Players = game:GetService("Players")

local RateLimit = {}
local buckets = {} -- [scope] = { [player] = {tokens, last} }

function RateLimit.Allow(scope, player, perSecond, burst)
	local scopeBuckets = buckets[scope]
	if not scopeBuckets then
		scopeBuckets = {}
		buckets[scope] = scopeBuckets
	end
	local now = os.clock()
	local b = scopeBuckets[player]
	if not b then
		b = { tokens = burst, last = now }
		scopeBuckets[player] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * perSecond)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	for _, scopeBuckets in pairs(buckets) do
		scopeBuckets[player] = nil -- tidak ada cache yang menumpuk
	end
end)

return RateLimit
