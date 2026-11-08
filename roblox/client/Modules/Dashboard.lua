-- Dashboard gaya Kohl's: jendela dengan tab Perintah / Pemain / Log / Info. Semua aksi lewat command bar (satu jalur otorisasi di server).
local Players = game:GetService("Players")
local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)
local Maid = require(script.Parent.Maid)

local Dashboard = {}

function Dashboard.new(gui, remote, catalog, info, bar)
	local self = {}
	local maid = Maid.new()
	local has = {}
	for _, c in ipairs(catalog) do has[c.name] = true end

	local root = UI.Frame({
		Parent = gui, Name = "SmartACDashboard", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.82, 0), BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.08, ZIndex = 10,
	}, { UI.Corner(12), UI.Stroke(Theme.stroke, 1), UI.New("UISizeConstraint", { MaxSize = Vector2.new(720, 460), MinSize = Vector2.new(320, 300) }) })
	maid:Give(root)

	UI.Label({ Parent = root, Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(1, -60, 0, 24), Font = Theme.fontBold, TextSize = 16, Text = ("Smart Anticheat · %s"):format(info.role or "?") })
	UI.Button(maid, { Parent = root, Text = "✕", Size = UDim2.new(0, 30, 0, 26), Position = UDim2.new(1, -40, 0, 8), BackgroundColor3 = Theme.panel2 }, function() root.Visible = false end)

	-- sidebar
	local side = UI.Frame({ Parent = root, Position = UDim2.new(0, 8, 0, 42), Size = UDim2.new(0, 108, 1, -50), BackgroundTransparency = 1 }, { UI.New("UIListLayout", { Padding = UDim.new(0, 4) }) })
	local pages, tabButtons = {}, {}
	local function show(name)
		for key, p in pairs(pages) do p.Visible = key == name end
		for key, b in pairs(tabButtons) do
			local on = key == name
			UI.Tween(b, { BackgroundTransparency = on and 0 or 1 })
			b.TextColor3 = on and Color3.new(0, 0, 0) or Theme.text
		end
	end
	local function page()
		return UI.Frame({ Parent = root, Position = UDim2.new(0, 124, 0, 42), Size = UDim2.new(1, -132, 1, -50), BackgroundTransparency = 1, Visible = false })
	end
	local function tab(key, label)
		local b = UI.New("TextButton", { Parent = side, Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, AutoButtonColor = false,
			Font = Theme.fontBold, TextSize = 14, TextColor3 = Theme.text, Text = label, LayoutOrder = #side:GetChildren() }, { UI.Corner(8) })
		tabButtons[key] = b
		maid:Give(b.MouseButton1Click:Connect(function() show(key) end))
		pages[key] = page()
		return pages[key]
	end

	-- ===== Perintah =====
	local pc = tab("cmd", "Perintah")
	local search = UI.Box({ Parent = pc, PlaceholderText = "Cari perintah…", Size = UDim2.new(1, 0, 0, 30), Text = "" })
	local cmdList = UI.Scroll({ Parent = pc, Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 1, -36) })
	local function renderCommands()
		for _, c in ipairs(cmdList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
		local q = search.Text:lower()
		for i, c in ipairs(catalog) do
			if q == "" or c.name:find(q, 1, true) or c.group:find(q, 1, true) or c.desc:lower():find(q, 1, true) then
				local b = UI.New("TextButton", { Parent = cmdList, LayoutOrder = i, Size = UDim2.new(1, -6, 0, 44), BackgroundColor3 = Theme.panel, BackgroundTransparency = 0.3, AutoButtonColor = false,
					Font = Theme.fontBold, TextSize = 14, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "", }, { UI.Corner(8), UI.New("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
				UI.Label({ Parent = b, Size = UDim2.new(1, -10, 0, 22), Text = ";" .. c.usage, Font = Enum.Font.RobotoMono, TextSize = 13, TextWrapped = false })
				UI.Label({ Parent = b, Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, -10, 0, 18), Text = ("[%s] %s"):format(c.group, c.desc), TextSize = 12, TextColor3 = Theme.sub, TextWrapped = false })
				b.MouseButton1Click:Connect(function() root.Visible = false bar.Open(c.name .. " ") end)
			end
		end
	end
	maid:Give(search:GetPropertyChangedSignal("Text"):Connect(renderCommands))

	-- ===== Pemain =====
	local pp = tab("plr", "Pemain")
	local plrList = UI.Scroll({ Parent = pp, Size = UDim2.new(1, 0, 1, 0) })
	local function renderPlayers()
		local ok, res = pcall(function() return remote:InvokeServer("players", {}) end)
		for _, c in ipairs(plrList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		if not ok or type(res) ~= "table" or not res.ok then return end
		for i, p in ipairs(res.players) do
			local card = UI.Frame({ Parent = plrList, LayoutOrder = i, Size = UDim2.new(1, -6, 0, 70), BackgroundColor3 = Theme.panel, BackgroundTransparency = 0.3 }, { UI.Corner(8), UI.Pad(6) })
			UI.Label({ Parent = card, Size = UDim2.new(1, 0, 0, 20), Font = Theme.fontBold, Text = ("%s (@%s)%s"):format(p.displayName, p.name, p.staff and ("  [" .. p.staff .. "]") or ""), TextWrapped = false })
			local actions = UI.Frame({ Parent = card, Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, { UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }) })
			for _, a in ipairs({ { "to", "Goto", "to %s" }, { "bring", "Bring", "bring %s" }, { "view", "View", "view %s" }, { "warn", "Warn", "warn %s " }, { "kick", "Kick", "kick %s " }, { "ban", "Ban", "ban %s 1d " } }) do
				if has[a[1]] and p.userId ~= Players.LocalPlayer.UserId then
					UI.Button(maid, { Parent = actions, Text = a[2], Size = UDim2.new(0, 50, 1, 0), TextSize = 12, BackgroundColor3 = Theme.panel2 }, function()
						root.Visible = false
						bar.Open(a[3]:format(p.name))
					end)
				end
			end
		end
	end

	-- ===== Log =====
	local lp = tab("log", "Log")
	local logLabel = UI.Label({ Parent = lp, Size = UDim2.new(1, 0, 1, -34), Position = UDim2.new(0, 0, 0, 34), Font = Enum.Font.RobotoMono, TextSize = 12, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	local function renderLogs()
		local ok, res = pcall(function() return remote:InvokeServer("logs", {}) end)
		logLabel.Text = (ok and type(res) == "table" and res.ok and #res.lines > 0) and table.concat(res.lines, "\n") or "Belum ada perintah di server ini."
	end
	UI.Button(maid, { Parent = lp, Text = "Segarkan", Size = UDim2.new(0, 100, 0, 28), BackgroundColor3 = Theme.panel2 }, renderLogs)

	-- ===== Info =====
	local ip = tab("info", "Info")
	UI.Label({ Parent = ip, Size = UDim2.new(1, 0, 1, 0), TextYAlignment = Enum.TextYAlignment.Top, TextSize = 14, Text = table.concat({
		("Role: %s  (rank %s)"):format(tostring(info.role), tostring(info.rank)),
		(info.perms and info.perms[1] == "*") and "Izin: SEMUA (akses penuh di Roblox)" or ("Izin aktif: %d (%s)"):format(#(info.perms or {}), table.concat(info.perms or {}, ", ")),
		"",
		"Pintasan:",
		"  ;  = buka command bar     F4 = dashboard ini",
		"  Tab = lengkapi saran   ↑/↓ = pilih / riwayat   Enter = jalankan",
		"",
		"Selector pemain: me, all, others, random, admins, nonadmins, atau nama (sebagian)",
		"Durasi ban: 1d, 1w, 30d, 365d, perm (perm butuh persetujuan orang lain)",
		"",
		"Semua perintah berdampak dicatat (audit) ke backend.",
	}, "\n") })

	function self.Toggle()
		root.Visible = not root.Visible
		if root.Visible then renderCommands() renderPlayers() renderLogs() show("cmd") end
	end
	function self.Destroy() maid:Destroy() end
	show("cmd")
	return self
end

return Dashboard
