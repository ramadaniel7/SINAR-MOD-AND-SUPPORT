-- Pembersih koneksi/instance/tween. Satu Maid per komponen UI; Destroy() membersihkan semuanya.
local Maid = {}
Maid.__index = Maid

function Maid.new()
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
return Maid
