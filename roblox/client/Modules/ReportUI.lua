-- Form laporan pemain. Server yang memvalidasi target, rate limit, dan memfilter teks.
local Players = game:GetService("Players")
local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)
local Maid = require(script.Parent.Maid)

local ReportUI = {}
local CATEGORIES = { { "cheating", "Cheat/Exploit" }, { "fail_roleplay", "Fail RP" }, { "harassment", "Pelecehan" }, { "other", "Lainnya" } }

function ReportUI.new(gui, remote)
	local self = {}
	local maid = Maid.new()
	local target, category, sending = nil, "cheating", false

	local root = UI.Frame({
		Parent = gui, Name = "SmartACReport", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.8, 0), BackgroundColor3 = Theme.bg,
	}, { UI.Corner(12), UI.Stroke(Theme.stroke, 1.5), UI.New("UISizeConstraint", { MaxSize = Vector2.new(460, 460), MinSize = Vector2.new(300, 300) }), UI.Pad(12) })
	maid:Give(root)

	UI.Label({ Parent = root, Text = "Laporkan pemain", Font = Theme.fontBold, TextSize = 18, Size = UDim2.new(1, -40, 0, 24) })
	UI.Button(maid, { Parent = root, Text = "✕", Size = UDim2.new(0, 28, 0, 24), Position = UDim2.new(1, -28, 0, 0) }, function() root.Visible = false end)
	UI.Label({ Parent = root, Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 0, 30), TextSize = 12, TextColor3 = Theme.sub, Text = "Laporan palsu/spam bisa berujung sanksi. Staff akan memverifikasi sebelum bertindak." })

	local list = UI.Scroll({ Parent = root, Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 100) })
	local catRow = UI.New("Frame", { Parent = root, BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 170), Size = UDim2.new(1, 0, 0, 30) }, {
		UI.New("UIGridLayout", { CellSize = UDim2.new(0.25, -4, 1, 0), CellPadding = UDim2.new(0, 4, 0, 0) }),
	})
	local catButtons = {}
	for _, c in ipairs(CATEGORIES) do
		catButtons[c[1]] = UI.Button(maid, { Parent = catRow, Text = c[2], TextSize = 12, BackgroundColor3 = c[1] == category and Theme.accent or Theme.panel2 }, function()
			category = c[1]
			for key, b in pairs(catButtons) do UI.Tween(b, { BackgroundColor3 = key == category and Theme.accent or Theme.panel2 }) end
		end)
	end

	local desc = UI.Box({ Parent = root, PlaceholderText = "Jelaskan kejadiannya (5–300 karakter)", Position = UDim2.new(0, 0, 0, 208), Size = UDim2.new(1, 0, 0, 100),
		MultiLine = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	local status = UI.Label({ Parent = root, Position = UDim2.new(0, 0, 0, 350), Size = UDim2.new(1, 0, 0, 36), TextSize = 13, TextColor3 = Theme.sub, Text = "" })

	local rows, rowConns = {}, {}
	local function renderPlayers()
		for _, c in ipairs(rowConns) do c:Disconnect() end
		table.clear(rowConns)
		for _, r in ipairs(rows) do r:Destroy() end
		table.clear(rows)
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= Players.LocalPlayer then
				local b = UI.New("TextButton", { Parent = list, Size = UDim2.new(1, -4, 0, 26), BackgroundColor3 = (target == p.UserId) and Theme.accent or Theme.panel2, AutoButtonColor = false, BorderSizePixel = 0,
					Font = Theme.font, TextSize = 13, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left, Text = p.DisplayName .. " (@" .. p.Name .. ")" },
					{ UI.Corner(6), UI.New("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
				table.insert(rows, b)
				table.insert(rowConns, b.MouseButton1Click:Connect(function() target = p.UserId renderPlayers() end))
			end
		end
	end

	local submit
	submit = UI.Button(maid, { Parent = root, Text = "Kirim laporan", Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.accent }, function()
		if sending then return end
		if not target then status.Text = "Pilih pemain yang dilaporkan." status.TextColor3 = Theme.warn return end
		if #desc.Text < 5 then status.Text = "Deskripsi minimal 5 karakter." status.TextColor3 = Theme.warn return end
		sending = true
		submit.Text = "Mengirim…"
		local ok, res = pcall(function() return remote:InvokeServer(target, category, string.sub(desc.Text, 1, 300)) end)
		sending = false
		submit.Text = "Kirim laporan"
		if ok and type(res) == "table" and res.ok then
			status.Text = "✓ Laporan terkirim. Kode: " .. tostring(res.code) .. (res.duplicate and " (laporan serupa sudah ada)" or "")
			status.TextColor3 = Theme.good
			desc.Text = ""
		else
			local err = ok and type(res) == "table" and res.error or "gagal"
			status.Text = "✗ " .. (err == "rate_limited" and "Terlalu banyak laporan, coba lagi nanti." or "Laporan gagal dikirim (" .. tostring(err) .. ").")
			status.TextColor3 = Theme.bad
		end
	end)

	maid:Give(Players.PlayerAdded:Connect(function() if root.Visible then renderPlayers() end end))
	maid:Give(Players.PlayerRemoving:Connect(function(p) if p.UserId == target then target = nil end task.defer(function() if root.Visible then renderPlayers() end end) end))

	function self.Toggle()
		root.Visible = not root.Visible
		if root.Visible then status.Text = "" renderPlayers() end
	end
	function self.Destroy() for _, c in ipairs(rowConns) do c:Disconnect() end maid:Destroy() end
	return self
end

return ReportUI
