-- SmartAC client: report (semua pemain) + command bar & dashboard (hanya jika SERVER bilang lu staf).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Modules = script.Parent:WaitForChild("Modules")
local Theme = require(Modules.Theme)
local UI = require(Modules.UI)
local Maid = require(Modules.Maid)
local Notify = require(Modules.Notify)
local ReportUI = require(Modules.ReportUI)
local CommandBar = require(Modules.CommandBar)
local Dashboard = require(Modules.Dashboard)
local Tools = require(Modules.Tools)

local REPORT_KEY = Enum.KeyCode.F3
local DASH_KEY = Enum.KeyCode.F4
local BAR_KEY = Enum.KeyCode.Semicolon

local remotes = ReplicatedStorage:WaitForChild("SmartACRemotes", 30)
if not remotes then warn("[SmartAC] Remote tidak ditemukan. Pastikan script server SmartAC aktif.") return end

local gui = UI.New("ScreenGui", {
	Name = "SmartACGui", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
local maid = Maid.new()
maid:Give(gui)

local notify = Notify.new(gui, remotes:WaitForChild("Notify"))
local report = ReportUI.new(gui, remotes:WaitForChild("SubmitReport"))
local adminRemote = remotes:WaitForChild("Admin")
local bar, dash = nil, nil
local state = { fly = false, noclip = false, esp = false }

-- Tombol kecil hanya di HP (sentuh); di PC cukup F3 / F4 / ;
local buttons = UI.New("Frame", { Parent = gui, Visible = UserInputService.TouchEnabled, BackgroundTransparency = 1, Position = UDim2.new(0, 8, 0, 64), Size = UDim2.new(0, 250, 0, 30) }, {
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
})
UI.Button(maid, { Parent = buttons, Text = "⚑ Report", Size = UDim2.new(0, 90, 1, 0), BackgroundColor3 = Theme.panel, TextSize = 12 }, function() report.Toggle() end)

-- Aksi sisi-client yang DIMINTA server (fly/noclip/view/esp). Server sudah memberi izin; di sini hanya menjalankan.
local function applyClientAction(a)
	if a.kind == "fly" then state.fly = a.enabled == true; Tools.SetFly(state.fly)
	elseif a.kind == "noclip" then state.noclip = a.enabled == true; Tools.SetNoclip(state.noclip)
	elseif a.kind == "view" then Tools.Spectate(a.userId)
	elseif a.kind == "unview" then Tools.StopSpectate()
	elseif a.kind == "esp" then
		if a.enabled == nil then state.esp = not state.esp else state.esp = a.enabled == true end
		Tools.SetESP(state.esp)
	end
end

task.spawn(function()
	local ok, hello = pcall(function() return adminRemote:InvokeServer("hello", {}) end)
	if not (ok and type(hello) == "table" and hello.ok and hello.role) then return end -- bukan staf: tidak ada UI admin sama sekali
	local okC, cat = pcall(function() return adminRemote:InvokeServer("catalog", {}) end)
	if not (okC and type(cat) == "table" and cat.ok) then return end

	bar = CommandBar.new(gui, adminRemote, cat.commands, applyClientAction)
	dash = Dashboard.new(gui, adminRemote, cat.commands, hello, bar)
	UI.Button(maid, { Parent = buttons, Text = "🛡 Admin", Size = UDim2.new(0, 90, 1, 0), BackgroundColor3 = Theme.panel, TextSize = 12 }, function() dash.Toggle() end)
	UI.Button(maid, { Parent = buttons, Text = "; Cmd", Size = UDim2.new(0, 60, 1, 0), BackgroundColor3 = Theme.panel, TextSize = 12 }, function() bar.Toggle() end)
	notify.Toast("SmartAC", ("Admin aktif (%s). Tekan ; untuk command bar, F4 untuk dashboard."):format(hello.role), Theme.good, 5)

	-- Saat respawn, matikan fly/noclip & sinkronkan ke server supaya state bypass anti-cheat tidak menggantung.
	maid:Give(Players.LocalPlayer.CharacterAdded:Connect(function()
		if state.fly then state.fly = false Tools.SetFly(false) task.spawn(function() adminRemote:InvokeServer("run", { text = "fly off" }) end) end
		if state.noclip then state.noclip = false Tools.SetNoclip(false) task.spawn(function() adminRemote:InvokeServer("run", { text = "noclip off" }) end) end
	end))
end)

maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == REPORT_KEY then report.Toggle()
	elseif input.KeyCode == DASH_KEY and dash then dash.Toggle()
	elseif input.KeyCode == BAR_KEY and bar then bar.Toggle() end
end))
