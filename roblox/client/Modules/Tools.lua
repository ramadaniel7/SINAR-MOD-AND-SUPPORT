-- Alat admin sisi client: fly, noclip, spectate, ESP. Semuanya HANYA aktif setelah server menyetujui (lihat AdminPanel).
-- Loop hanya berjalan saat fitur aktif dan semua koneksi dibersihkan saat dimatikan.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)

local LocalPlayer = Players.LocalPlayer
local Tools = {}

local flyConn, noclipConn
local spectateTarget, spectateConn
local espConns, espHighlights = {}, {}

local function character() return LocalPlayer.Character end

-- ---------- Fly ----------
function Tools.SetFly(on)
	if flyConn then flyConn:Disconnect() flyConn = nil end
	local char = character()
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = on end
	if not on then
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
		return
	end
	flyConn = RunService.RenderStepped:Connect(function()
		local c = character()
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		local cam = workspace.CurrentCamera
		if not hrp or not cam then return end
		local dir = Vector3.zero
		if not UserInputService:GetFocusedTextBox() then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
		end
		hrp.AssemblyLinearVelocity = dir.Magnitude > 0 and dir.Unit * 70 or Vector3.zero
	end)
end

-- ---------- Noclip ----------
function Tools.SetNoclip(on)
	if noclipConn then noclipConn:Disconnect() noclipConn = nil end
	if not on then return end
	noclipConn = RunService.Stepped:Connect(function()
		local c = character()
		if not c then return end
		for _, part in ipairs(c:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
		end
	end)
end

-- ---------- Spectate ----------
function Tools.StopSpectate()
	if spectateConn then spectateConn:Disconnect() spectateConn = nil end
	spectateTarget = nil
	local cam = workspace.CurrentCamera
	local hum = character() and character():FindFirstChildOfClass("Humanoid")
	if cam and hum then cam.CameraSubject = hum end
end

function Tools.Spectate(userId)
	Tools.StopSpectate()
	local target = Players:GetPlayerByUserId(userId)
	local hum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	spectateTarget = target
	workspace.CurrentCamera.CameraSubject = hum
	spectateConn = Players.PlayerRemoving:Connect(function(p)
		if p == spectateTarget then Tools.StopSpectate() end
	end)
	return true
end
function Tools.IsSpectating() return spectateTarget ~= nil end

-- ---------- ESP ----------
local function removeHighlight(player)
	local h = espHighlights[player]
	if h then h:Destroy() espHighlights[player] = nil end
end
local function addHighlight(player)
	removeHighlight(player)
	if player == LocalPlayer or not player.Character then return end
	local h = Instance.new("Highlight")
	h.FillColor = Theme.accent
	h.FillTransparency = 0.75
	h.OutlineColor = Theme.good
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = player.Character
	espHighlights[player] = h
end

function Tools.SetESP(on)
	for _, c in ipairs(espConns) do c:Disconnect() end
	table.clear(espConns)
	for p in pairs(espHighlights) do removeHighlight(p) end
	if not on then return end
	local function track(p)
		addHighlight(p)
		table.insert(espConns, p.CharacterAdded:Connect(function() task.wait(0.2) addHighlight(p) end))
	end
	for _, p in ipairs(Players:GetPlayers()) do track(p) end
	table.insert(espConns, Players.PlayerAdded:Connect(track))
	table.insert(espConns, Players.PlayerRemoving:Connect(removeHighlight))
end

function Tools.DisableAll()
	Tools.SetFly(false)
	Tools.SetNoclip(false)
	Tools.StopSpectate()
	Tools.SetESP(false)
end

return Tools
