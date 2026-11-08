-- Remote jebakan: client sah tidak pernah memanggilnya. Kalau terpanggil = exploit membabi-buta.
-- Tidak pernah menimpa remote yang sudah ada (supaya tidak merusak game RP).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Config)
local Scoring = require(script.Parent.Scoring)
local Util = require(script.Parent.Util)

local Honeypot = {}

function Honeypot.Start()
	for _, name in ipairs(Config.AntiCheat.Honeypots) do
		if ReplicatedStorage:FindFirstChild(name) then
			Util.Warn(("Honeypot '%s' dilewati: sudah ada objek bernama itu di ReplicatedStorage. Ganti nama di Config."):format(name))
		else
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = ReplicatedStorage
			remote.OnServerEvent:Connect(function(player)
				Scoring.Hit(player, "honeypot.remote", 100, 4, { remote = name }, { strong = true })
			end)
		end
	end
end

return Honeypot
