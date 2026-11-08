-- Membuat remote yang dipakai SmartAC (dibuat oleh server saat start; tidak perlu dibuat manual di Studio).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("SmartACRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "SmartACRemotes"
	folder.Parent = ReplicatedStorage
end

local function make(class, name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local r = Instance.new(class)
	r.Name = name
	r.Parent = folder
	return r
end

return {
	Admin = make("RemoteFunction", "Admin"),
	Notify = make("RemoteEvent", "Notify"),
	SubmitReport = make("RemoteFunction", "SubmitReport"),
}
