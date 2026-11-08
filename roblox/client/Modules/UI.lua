-- Komponen UI reusable yang dibuat 100% lewat script. Tween dikelola (tidak numpuk), koneksi lewat Maid.
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)

local UI = {}
local activeTweens = setmetatable({}, { __mode = "k" }) -- [instance] = tween (weak: tidak menahan memori)

function UI.New(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	inst.Parent = parent
	return inst
end

-- Satu tween aktif per instance: tween lama dibatalkan sebelum yang baru.
function UI.Tween(inst, goal, info)
	local old = activeTweens[inst]
	if old then old:Cancel() end
	local tw = TweenService:Create(inst, info or Theme.tween, goal)
	activeTweens[inst] = tw
	tw.Completed:Connect(function()
		if activeTweens[inst] == tw then activeTweens[inst] = nil end
		tw:Destroy()
	end)
	tw:Play()
	return tw
end

function UI.Corner(r) return UI.New("UICorner", { CornerRadius = UDim.new(0, r or Theme.radius) }) end
function UI.Stroke(color, t) return UI.New("UIStroke", { Color = color or Theme.stroke, Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
function UI.Pad(n) return UI.New("UIPadding", { PaddingTop = UDim.new(0, n), PaddingBottom = UDim.new(0, n), PaddingLeft = UDim.new(0, n), PaddingRight = UDim.new(0, n) }) end

function UI.Frame(props, children)
	local p = { BackgroundColor3 = Theme.panel, BorderSizePixel = 0 }
	for k, v in pairs(props or {}) do p[k] = v end
	local f = UI.New("Frame", p, children)
	return f
end

function UI.Label(props)
	local p = { BackgroundTransparency = 1, TextColor3 = Theme.text, Font = Theme.font, TextSize = Theme.size, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }
	for k, v in pairs(props or {}) do p[k] = v end
	return UI.New("TextLabel", p)
end

-- Tombol dengan hover + debounce klik. onClick dipanggil di thread terpisah (boleh yield).
function UI.Button(maid, props, onClick)
	local base = props.BackgroundColor3 or Theme.panel2
	local p = { BackgroundColor3 = base, TextColor3 = Theme.text, Font = Theme.font, TextSize = Theme.size, AutoButtonColor = false, BorderSizePixel = 0 }
	for k, v in pairs(props) do p[k] = v end
	local b = UI.New("TextButton", p, { UI.Corner(6) })
	maid:Give(b.MouseEnter:Connect(function() UI.Tween(b, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }) end))
	maid:Give(b.MouseLeave:Connect(function() UI.Tween(b, { BackgroundColor3 = base }) end))
	local clicking = false
	maid:Give(b.MouseButton1Click:Connect(function()
		if clicking then return end
		clicking = true
		local ok, err = pcall(onClick)
		if not ok then warn("[SmartAC UI]", err) end
		clicking = false
	end))
	return b
end

function UI.Box(props)
	local p = { BackgroundColor3 = Theme.bg, TextColor3 = Theme.text, PlaceholderColor3 = Theme.sub, Font = Theme.font, TextSize = Theme.size, ClearTextOnFocus = false, BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in pairs(props or {}) do p[k] = v end
	return UI.New("TextBox", p, { UI.Corner(6), UI.Stroke(), UI.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
end

function UI.Scroll(props)
	local p = { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarImageColor3 = Theme.stroke }
	for k, v in pairs(props or {}) do p[k] = v end
	return UI.New("ScrollingFrame", p, { UI.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
end

-- Object pool sederhana untuk baris list yang sering di-refresh (hindari buat/hancurkan instance berulang).
function UI.NewPool(create)
	local free = {}
	local pool = {}
	function pool.Acquire() return table.remove(free) or create() end
	function pool.Release(x) x.Parent = nil; table.insert(free, x) end
	function pool.Destroy() for _, x in ipairs(free) do x:Destroy() end table.clear(free) end
	return pool
end

return UI
