-- Registry perintah (pola mirip Kohl's: definisi berbasis data -> satu jalur parse/otorisasi/eksekusi).
local Registry = {}
local byName, list = {}, {}

function Registry.Add(def)
	assert(def.name and def.run, "perintah butuh name & run")
	def.group = def.group or "utility"
	def.args = def.args or {}
	table.insert(list, def)
	byName[def.name] = def
	for _, a in ipairs(def.aliases or {}) do byName[a] = def end
end

function Registry.Find(name) return byName[name:lower()] end
function Registry.All() return list end

function Registry.Usage(def)
	local parts = { def.name }
	for _, a in ipairs(def.args) do
		table.insert(parts, a.optional and ("[" .. a.name .. "]") or ("<" .. a.name .. ">"))
	end
	return table.concat(parts, " ")
end

return Registry
