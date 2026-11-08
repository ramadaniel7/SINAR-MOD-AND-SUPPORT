-- Utilitas: Maid (pembersih koneksi), validator argumen, logger.
local Util = {}

-- ---------- Maid ----------
local Maid = {}
Maid.__index = Maid

function Util.NewMaid()
	return setmetatable({ _items = {} }, Maid)
end
function Maid:Give(item)
	table.insert(self._items, item)
	return item
end
function Maid:Destroy()
	for _, item in ipairs(self._items) do
		local t = typeof(item)
		if t == "RBXScriptConnection" then
			item:Disconnect()
		elseif t == "Instance" then
			item:Destroy()
		elseif t == "function" then
			pcall(item)
		elseif t == "table" and item.Destroy then
			pcall(item.Destroy, item)
		end
	end
	table.clear(self._items)
end

-- ---------- Validator (semua mengembalikan true/false) ----------
local V = {}
function V.Number(min, max)
	return function(v)
		return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= min and v <= max
	end
end
function V.Integer(min, max)
	local n = V.Number(min, max)
	return function(v) return n(v) and v % 1 == 0 end
end
function V.String(minLen, maxLen)
	return function(v)
		return typeof(v) == "string" and #v >= minLen and #v <= maxLen and utf8.len(v) ~= nil
	end
end
function V.Enum(list)
	local set = {}
	for _, x in ipairs(list) do set[x] = true end
	return function(v) return typeof(v) == "string" and set[v] == true end
end
function V.Optional(check)
	return function(v) return v == nil or check(v) end
end
V.Boolean = function(v) return typeof(v) == "boolean" end
V.UserId = V.Integer(1, 1e13)
Util.V = V

function Util.Log(...)
	print("[SmartAC]", ...)
end
function Util.Debug(...)
	local ok, Config = pcall(require, script.Parent.Parent.Config)
	if ok and Config.Debug then print("[SmartAC:debug]", ...) end
end
function Util.Warn(...)
	warn("[SmartAC]", ...)
end

return Util
