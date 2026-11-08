-- Command bar gaya Kohl's: tekan ; untuk membuka, ketik perintah, saran muncul (Tab = lengkapi, ↑/↓ = pilih, Enter = jalankan).
-- Client hanya MENGIRIM teks ke server; server yang mem-parse, mengotorisasi, dan mengeksekusi.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)
local Maid = require(script.Parent.Maid)

local CommandBar = {}
local MAX_ROWS = 6
local SELECTORS = { "me", "all", "others", "random", "admins", "nonadmins" }
local DURATIONS = { "1d", "1w", "30d", "365d", "perm" }

local function stripPrefix(s) return (s:gsub("^%s*[;:]?%s*", "")) end

function CommandBar.new(gui, remote, catalog, onClientAction)
	local self = {}
	local maid = Maid.new()
	local byName = {}
	for _, c in ipairs(catalog) do
		byName[c.name] = c
		for _, a in ipairs(c.aliases) do byName[a] = c end
	end
	local history, histIdx = {}, 0
	local suggestions, sel = {}, 0
	local resultToken = 0
	local busy = false

	-- ---------- kerangka ----------
	local root = UI.Frame({
		Parent = gui, Name = "SmartACBar", Visible = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0.92, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 20,
	}, { UI.New("UISizeConstraint", { MaxSize = Vector2.new(540, 9999) }), UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	maid:Give(root)

	local bar = UI.Frame({ Parent = root, Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.08, LayoutOrder = 1 }, { UI.Corner(12), UI.Stroke(Theme.stroke, 1) })
	UI.Label({ Parent = bar, Text = ";", Font = Theme.fontBold, TextSize = 20, TextColor3 = Theme.accent, Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(0, 14, 1, 0) })
	local box = UI.New("TextBox", {
		Parent = bar, BackgroundTransparency = 1, Position = UDim2.new(0, 32, 0, 0), Size = UDim2.new(1, -44, 1, 0), Font = Enum.Font.RobotoMono, TextSize = 16,
		TextColor3 = Theme.text, PlaceholderText = "ketik perintah… (;help)", PlaceholderColor3 = Theme.sub, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	})

	local list = UI.Frame({ Parent = root, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.08, LayoutOrder = 2, Visible = false }, {
		UI.Corner(12), UI.Stroke(Theme.stroke, 1), UI.Pad(6), UI.New("UIListLayout", { Padding = UDim.new(0, 2) }),
	})
	local rows, rowHints = {}, {}
	for i = 1, MAX_ROWS do
		local r = UI.New("TextButton", { Parent = list, Visible = false, Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, AutoButtonColor = false,
			Font = Theme.fontBold, TextSize = 14, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "", LayoutOrder = i }, { UI.Corner(8), UI.New("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
		local hint = UI.Label({ Parent = r, Size = UDim2.new(0.6, -10, 1, 0), Position = UDim2.new(0.4, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12, TextColor3 = Theme.sub, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		rows[i], rowHints[i] = r, hint
	end

	local resultBox = UI.Frame({ Parent = root, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.08, LayoutOrder = 3, Visible = false },
		{ UI.Corner(12), UI.Stroke(Theme.stroke, 1), UI.Pad(10) })
	local resultLabel = UI.Label({ Parent = resultBox, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", TextSize = 14, RichText = false })

	local function updateVisible()
		root.Visible = bar.Visible or resultBox.Visible
	end

	local function showResult(text, ok, seconds)
		resultToken += 1
		local mine = resultToken
		resultLabel.Text = text
		resultLabel.TextColor3 = ok and Theme.good or Theme.bad
		resultBox.Visible = text ~= ""
		updateVisible()
		task.delay(seconds or 6, function()
			if resultToken == mine then resultBox.Visible = false updateVisible() end
		end)
	end

	-- ---------- saran ----------
	local function render()
		list.Visible = #suggestions > 0 and bar.Visible
		for i = 1, MAX_ROWS do
			local s = suggestions[i]
			local r = rows[i]
			if s then
				r.Visible = true
				r.Text = s.label
				rowHints[i].Text = s.hint or ""
				local on = (i == sel)
				UI.Tween(r, { BackgroundTransparency = on and 0 or 1 })
				r.TextColor3 = on and Color3.new(0, 0, 0) or Theme.text
				rowHints[i].TextColor3 = on and Color3.fromRGB(70, 70, 70) or Theme.sub
			else
				r.Visible = false
			end
		end
	end

	local function currentToken()
		local t = stripPrefix(box.Text)
		local tokens = {}
		for tok in t:gmatch("%S+") do table.insert(tokens, tok) end
		local trailing = t:match("%s$") ~= nil or t == ""
		return t, tokens, trailing
	end

	local function refresh()
		local _, tokens, trailing = currentToken()
		local n = #tokens
		suggestions, sel = {}, 0
		if n == 0 or (n == 1 and not trailing) then
			local q = (tokens[1] or ""):lower()
			for _, c in ipairs(catalog) do
				local hit = q == "" or c.name:sub(1, #q) == q
				if not hit then for _, a in ipairs(c.aliases) do if a:sub(1, #q) == q then hit = true end end end
				if hit then
					table.insert(suggestions, { label = c.name, hint = (c.usage:gsub("^%S+%s*", "")), insert = c.name .. " " })
				end
				if #suggestions >= MAX_ROWS then break end
			end
		else
			local c = byName[tokens[1]:lower()]
			if c then
				local argIdx = trailing and n or (n - 1)
				local spec = c.args[argIdx]
				local cur = (not trailing) and tokens[n]:lower() or ""
				local pool = {}
				if spec then
					if spec.type == "players" or spec.type == "player" or spec.type == "userid" then
						for _, s in ipairs(SELECTORS) do
							if spec.type == "players" or s == "me" or s == "random" then table.insert(pool, { s, "selector" }) end
						end
						for _, p in ipairs(Players:GetPlayers()) do table.insert(pool, { p.Name, p.DisplayName ~= p.Name and p.DisplayName or "pemain" }) end
					elseif spec.type == "duration" then
						for _, d in ipairs(DURATIONS) do table.insert(pool, { d, d == "perm" and "butuh persetujuan" or "durasi" }) end
					elseif spec.type == "onoff" then
						pool = { { "on", "" }, { "off", "" } }
					elseif spec.type == "enum" then
						for _, v in ipairs(spec.values or {}) do table.insert(pool, { v, "pilihan" }) end
					end
				end
				for _, e in ipairs(pool) do
					if cur == "" or e[1]:lower():sub(1, #cur) == cur then
						table.insert(suggestions, { label = e[1], hint = e[2], insert = e[1] .. " ", arg = true })
						if #suggestions >= MAX_ROWS then break end
					end
				end
				if #suggestions == 0 then
					table.insert(suggestions, { label = c.usage, hint = c.desc })
				end
			end
		end
		render()
	end

	local function accept(s)
		if not s or not s.insert then return end
		local t, _, trailing = currentToken()
		if trailing then box.Text = t .. s.insert else box.Text = (t:gsub("%S+$", "")) .. s.insert end
		box.CursorPosition = #box.Text + 1
	end

	-- ---------- eksekusi ----------
	local function submit()
		local text = stripPrefix(box.Text)
		if text == "" or busy then return end
		busy = true
		table.insert(history, text)
		if #history > 30 then table.remove(history, 1) end
		histIdx = #history + 1
		box.Text = ""
		bar.Visible = false
		list.Visible = false
		updateVisible()
		showResult("…", true, 15)
		local ok, res = pcall(function() return remote:InvokeServer("run", { text = text }) end)
		busy = false
		if not ok or type(res) ~= "table" then showResult("Gagal terhubung ke server.", false) return end
		if res.error == "denied" then showResult("Ditolak.", false) return end
		showResult(res.message ~= "" and res.message or (res.ok and "OK" or "Gagal"), res.ok == true, #(res.message or "") > 120 and 14 or 6)
		if res.ok and type(res.client) == "table" and onClientAction then onClientAction(res.client) end
	end

	-- ---------- input ----------
	maid:Give(box:GetPropertyChangedSignal("Text"):Connect(refresh))
	maid:Give(box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		else
			task.delay(0.1, function() if not box:IsFocused() then bar.Visible = false list.Visible = false updateVisible() end end)
		end
	end))
	maid:Give(UserInputService.InputBegan:Connect(function(input)
		if not box:IsFocused() then return end
		local k = input.KeyCode
		if k == Enum.KeyCode.Tab then
			accept(suggestions[math.max(sel, 1)])
		elseif k == Enum.KeyCode.Down or k == Enum.KeyCode.Up then
			local dir = (k == Enum.KeyCode.Down) and 1 or -1
			if #suggestions > 0 and not (k == Enum.KeyCode.Up and sel == 0 and #history > 0 and box.Text == "") then
				sel = ((sel - 1 + dir) % #suggestions) + 1
				render()
			elseif #history > 0 then
				histIdx = math.clamp(histIdx + dir, 1, #history + 1)
				box.Text = history[histIdx] or ""
				box.CursorPosition = #box.Text + 1
			end
		end
	end))
	for i, r in ipairs(rows) do
		maid:Give(r.MouseButton1Click:Connect(function() accept(suggestions[i]) box:CaptureFocus() end))
	end

	function self.Open(prefill)
		bar.Visible = true
		updateVisible()
		task.defer(function()
			box:CaptureFocus()
			task.wait()
			box.Text = prefill or ""
			box.CursorPosition = #box.Text + 1
			refresh()
		end)
	end
	function self.Toggle()
		if bar.Visible then box:ReleaseFocus() bar.Visible = false list.Visible = false updateVisible() else self.Open() end
	end
	function self.Notify(text, ok) showResult(text, ok, 6) end
	function self.Destroy() maid:Destroy() end
	return self
end

return CommandBar
