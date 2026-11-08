-- Parser perintah gaya Kohl's: awalan ";" atau ":", pemisah spasi, kutip untuk argumen berspasi,
-- argumen terakhir bertipe "text" mengambil SISA kalimat. Semua tipe divalidasi di sini (server).
local Players = game:GetService("Players")
local Permissions = require(script.Parent.Parent.Permissions)

local Process = {}

-- ---------- tokenizer ----------
function Process.Tokenize(line)
	local tokens, i, n = {}, 1, #line
	while i <= n do
		while i <= n and line:sub(i, i) == " " do i += 1 end
		if i > n then break end
		local start, text = i, nil
		if line:sub(i, i) == '"' then
			local close = line:find('"', i + 1, true)
			if close then
				text = line:sub(i + 1, close - 1)
				i = close + 1
			end
		end
		if not text then
			local j = line:find(" ", i, true) or (n + 1)
			text = line:sub(i, j - 1)
			i = j
		end
		table.insert(tokens, { text = text, start = start })
	end
	return tokens
end

-- ---------- pemilih pemain ----------
local function matchOne(ctx, token)
	local lower = token:lower():gsub("^@", "")
	local exact, partial = {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		local n, d = p.Name:lower(), p.DisplayName:lower()
		if n == lower or d == lower or tostring(p.UserId) == lower then
			table.insert(exact, p)
		elseif n:sub(1, #lower) == lower or d:sub(1, #lower) == lower then
			table.insert(partial, p)
		end
	end
	local list = #exact > 0 and exact or partial
	if #list == 0 then return nil, ("pemain '%s' tidak ditemukan"):format(token) end
	if #list > 1 then
		local names = {}
		for i = 1, math.min(4, #list) do names[i] = list[i].Name end
		return nil, ("'%s' ambigu: %s"):format(token, table.concat(names, ", "))
	end
	return list[1]
end

function Process.ResolvePlayers(ctx, token)
	local lower = token:lower()
	local out = {}
	if lower == "me" or lower == "@me" then
		out = { ctx.player }
	elseif lower == "all" then
		out = Players:GetPlayers()
	elseif lower == "others" then
		for _, p in ipairs(Players:GetPlayers()) do if p ~= ctx.player then table.insert(out, p) end end
	elseif lower == "random" then
		local all = Players:GetPlayers()
		out = { all[math.random(#all)] }
	elseif lower == "admins" or lower == "nonadmins" then
		for _, p in ipairs(Players:GetPlayers()) do
			if Permissions.IsStaff(p) == (lower == "admins") then table.insert(out, p) end
		end
	else
		local p, err = matchOne(ctx, token)
		if not p then return nil, err end
		out = { p }
	end
	if #out == 0 then return nil, "tidak ada pemain yang cocok" end
	if #out > 25 then out = { table.unpack(out, 1, 25) } end
	return out
end

-- ---------- tipe argumen ----------
local DURATIONS = {
	["1d"] = { seconds = 86400 }, ["1w"] = { seconds = 604800 }, ["30d"] = { seconds = 2592000 },
	["365d"] = { seconds = 31536000 }, ["perm"] = { permanent = true }, ["permanent"] = { permanent = true },
}

-- Mengembalikan (nilai, err, jumlahTokenDipakai)
local function parseArg(ctx, spec, tokens, k, line)
	local tok = tokens[k]
	if not tok then
		if spec.optional then return nil, nil, 0 end
		return nil, ("argumen '%s' wajib diisi"):format(spec.name), 0
	end
	local t = spec.type
	if t == "text" then
		local rest = line:sub(tok.start)
		rest = rest:gsub('^"(.*)"$', "%1")
		if #rest < (spec.min or 1) or #rest > (spec.max or 400) or utf8.len(rest) == nil then
			return nil, ("'%s' harus %d-%d karakter"):format(spec.name, spec.min or 1, spec.max or 400), 0
		end
		return rest, nil, #tokens - k + 1
	elseif t == "players" then
		local list, err = Process.ResolvePlayers(ctx, tok.text)
		return list, err, 1
	elseif t == "player" then
		local list, err = Process.ResolvePlayers(ctx, tok.text)
		if not list then return nil, err, 1 end
		if #list ~= 1 then return nil, "pilih tepat 1 pemain", 1 end
		return list[1], nil, 1
	elseif t == "userid" then -- pemain offline boleh: UserId angka atau username Roblox
		local n = tonumber(tok.text)
		if n and n % 1 == 0 and n > 0 and n < 1e13 then return { userId = n, name = "UserId " .. n }, nil, 1 end
		local inServer = matchOne(ctx, tok.text)
		if inServer then return { userId = inServer.UserId, name = inServer.Name, player = inServer }, nil, 1 end
		if not tok.text:match("^[%w_]{3,20}$") then return nil, "username Roblox tidak valid", 1 end
		local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(tok.text) end)
		if ok and type(id) == "number" then return { userId = id, name = tok.text }, nil, 1 end
		return nil, ("username '%s' tidak ditemukan"):format(tok.text), 1
	elseif t == "duration" then
		local d = DURATIONS[tok.text:lower()]
		if not d then return nil, "durasi harus: 1d, 1w, 30d, 365d, atau perm", 1 end
		return d, nil, 1
	elseif t == "number" then
		local n = tonumber(tok.text)
		if not n or n ~= n or n == math.huge or n == -math.huge then return nil, ("'%s' harus angka"):format(spec.name), 1 end
		if n < (spec.min or -1e9) or n > (spec.max or 1e9) then
			return nil, ("'%s' harus %s s/d %s"):format(spec.name, tostring(spec.min), tostring(spec.max)), 1
		end
		return n, nil, 1
	elseif t == "word" then
		if tok.text:match("^[%w%-]+$") and #tok.text >= 8 and #tok.text <= 64 then return tok.text, nil, 1 end
		return nil, ("'%s' tidak valid"):format(spec.name), 1
	elseif t == "integer" then
		local n = tonumber(tok.text)
		if not n or n ~= n or n % 1 ~= 0 then return nil, ("'%s' harus bilangan bulat"):format(spec.name), 1 end
		if n < (spec.min or 0) or n > (spec.max or 1e10) then
			return nil, ("'%s' harus %s s/d %s"):format(spec.name, tostring(spec.min or 0), tostring(spec.max or 1e10)), 1
		end
		return n, nil, 1
	elseif t == "enum" then
		local v = tok.text:lower()
		for _, allowed in ipairs(spec.values or {}) do if v == allowed then return v, nil, 1 end end
		return nil, ("'%s' harus salah satu: %s"):format(spec.name, table.concat(spec.values or {}, ", ")), 1
	elseif t == "onoff" then
		local v = tok.text:lower()
		if v == "on" or v == "true" or v == "1" then return true, nil, 1 end
		if v == "off" or v == "false" or v == "0" then return false, nil, 1 end
		return nil, "gunakan on atau off", 1
	end
	return nil, "tipe argumen tidak dikenal", 1
end

-- Hasil: { command = def, args = {...} } atau nil, pesanError
function Process.Parse(ctx, line, registry)
	line = line:gsub("^%s*[;:]?%s*", "")
	local tokens = Process.Tokenize(line)
	if #tokens == 0 then return nil, "ketik perintah, mis. ;help" end
	local def = registry.Find(tokens[1].text)
	if not def then return nil, ("perintah '%s' tidak dikenal. Coba ;help"):format(tokens[1].text) end
	local args, k = {}, 2
	for i, spec in ipairs(def.args or {}) do
		local value, err, used = parseArg(ctx, spec, tokens, k, line)
		if err then return nil, ("%s — pemakaian: %s"):format(err, registry.Usage(def)) end
		args[i] = value
		k += used
	end
	return { command = def, args = args }
end

return Process
