-- Menampilkan pengumuman (toast) dan peringatan staff (kartu tengah layar). Data dari server divalidasi dulu.
local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)
local Maid = require(script.Parent.Maid)

local Notify = {}
local MAX_TOASTS = 4

function Notify.new(gui, remote)
	local self = {}
	local maid = Maid.new()

	local container = UI.New("Frame", {
		Name = "Toasts", Parent = gui, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(0, 420, 1, -24),
	}, { UI.New("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	maid:Give(container)

	local function toast(title, text, color, seconds)
		local children = container:GetChildren()
		local count = 0
		for _, c in ipairs(children) do if c:IsA("Frame") then count += 1 end end
		if count >= MAX_TOASTS then
			for _, c in ipairs(children) do if c:IsA("Frame") then c:Destroy() break end end
		end
		local card = UI.Frame({ Parent = container, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
			UI.Corner(), UI.Stroke(color, 1.5), UI.Pad(10),
			UI.New("UIListLayout", { Padding = UDim.new(0, 2) }),
		})
		UI.Label({ Parent = card, Text = title, Font = Theme.fontBold, TextColor3 = color, Size = UDim2.new(1, 0, 0, 18), TextTransparency = 1 })
		UI.Label({ Parent = card, Text = text, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextTransparency = 1 })
		UI.Tween(card, { BackgroundTransparency = 0.05 })
		for _, l in ipairs(card:GetChildren()) do if l:IsA("TextLabel") then UI.Tween(l, { TextTransparency = 0 }) end end
		task.delay(seconds, function()
			if card.Parent then
				UI.Tween(card, { BackgroundTransparency = 1 })
				task.delay(0.2, function() if card.Parent then card:Destroy() end end)
			end
		end)
	end

	local function warning(text)
		local overlay = UI.Frame({ Parent = gui, Name = "SmartACWarning", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = 50 })
		local card = UI.Frame({ Parent = overlay, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 400, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 51 }, {
			UI.Corner(12), UI.Stroke(Theme.warn, 2), UI.Pad(16), UI.New("UIListLayout", { Padding = UDim.new(0, 10) }),
		})
		UI.Label({ Parent = card, Text = "⚠ PERINGATAN DARI STAFF", Font = Theme.fontBold, TextSize = 18, TextColor3 = Theme.warn, Size = UDim2.new(1, 0, 0, 24), ZIndex = 52 })
		UI.Label({ Parent = card, Text = text, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 52 })
		local localMaid = Maid.new()
		local close = UI.Button(localMaid, { Parent = card, Text = "Saya mengerti", Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.accent, ZIndex = 52 }, function()
			localMaid:Destroy()
			overlay:Destroy()
		end)
		task.delay(30, function() if overlay.Parent then localMaid:Destroy() overlay:Destroy() end end)
		return close
	end

	maid:Give(remote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or type(data.text) ~= "string" or #data.text > 400 then return end
		if data.kind == "announce" then
			toast("📢 Pengumuman — " .. tostring(data.from or "Staff"):sub(1, 40), data.text, Theme.accent, 9)
		elseif data.kind == "warning" then
			warning(data.text)
		end
	end))

	function self.Toast(title, text, color, seconds) toast(title, text, color or Theme.accent, seconds or 4) end
	function self.Destroy() maid:Destroy() end
	return self
end

return Notify
