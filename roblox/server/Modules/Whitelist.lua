-- Whitelist gerakan sah: alat (Tool), kendaraan, dan lantai khusus (eskalator, lift, trampolin, dll.) yang boleh
-- bergerak cepat / melayang. Ditandai lewat NAMA (Config.Whitelist) atau Attribute/Tag "SmartACWhitelist".
-- Game lain juga bisa menandai karakter: character:SetAttribute("SmartACWhitelist", true) (jangan lupa dimatikan lagi).
local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Parent.Config)

local Whitelist = {}
local W = Config.Whitelist
local TAG = W.Tag

local function set(list)
	local t = {}
	for _, n in ipairs(list or {}) do t[string.lower(n)] = true end
	return t
end
local toolNames, vehicleNames, partNames = set(W.ToolNames), set(W.VehicleNames), set(W.PartNames)

local function marked(inst)
	return inst:GetAttribute(TAG) == true or CollectionService:HasTag(inst, TAG)
end

local function partOk(part)
	-- cek bagian itu dan dua tingkat induknya (mis. lantai eskalator di dalam model "Escalator")
	local node = part
	for _ = 1, 3 do
		if not node or node == workspace then break end
		if marked(node) or partNames[string.lower(node.Name)] then return node.Name end
		node = node.Parent
	end
	return nil
end

-- Mengembalikan alasan (string) bila gerakan pemain ini di-whitelist, atau nil.
function Whitelist.Reason(player, char, hum, hrp, rayParams)
	if char:GetAttribute(TAG) == true or player:GetAttribute(TAG) == true then return "attribute" end

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and (toolNames[string.lower(child.Name)] or marked(child)) then
			return "tool:" .. child.Name
		end
	end

	local seat = hum.SeatPart
	if seat then
		local model = seat:FindFirstAncestorOfClass("Model")
		if marked(seat) or (model and (marked(model) or vehicleNames[string.lower(model.Name)])) then
			return "vehicle:" .. (model and model.Name or seat.Name)
		end
	end

	-- lantai di bawah kaki (eskalator/lift/trampolin/travelator)
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), rayParams)
	if hit then
		local name = partOk(hit.Instance)
		if name then return "floor:" .. name end
	end
	return nil
end

return Whitelist
