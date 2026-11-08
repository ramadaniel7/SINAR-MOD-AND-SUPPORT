-- Deteksi gerakan di SERVER: speed, fly, teleport tak sah, noclip.
-- Satu loop untuk SEMUA pemain (bukan satu loop per pemain). Data posisi tidak dikirim ke backend, hanya ringkasan insiden.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.Parent.Config)
local Exemptions = require(script.Parent.Exemptions)
local Scoring = require(script.Parent.Scoring)
local Permissions = require(script.Parent.Permissions)
local Whitelist = require(script.Parent.Whitelist)

local Movement = {}
local C = Config.AntiCheat
local state = {} -- [player] = per-player state

local PHYSICS_STATES = {
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Dead] = true,
}
local NOT_FLYING_STATES = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
}

local function round1(n) return math.floor(n * 10 + 0.5) / 10 end

local function hookPlayer(player)
	player.CharacterAdded:Connect(function(char)
		Exemptions.Grant(player, C.Grace.Respawn, "respawn")
		state[player] = nil
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Seated:Connect(function()
				Exemptions.Grant(player, C.Grace.Seat, "seat")
			end)
		end
	end)
end

local function analyse(player, st, hum, hrp, now, rayParams)
	local dt = now - st.t
	local delta = hrp.Position - st.pos
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local vy = delta.Y / dt
	local seated = hum.SeatPart ~= nil
	local total = delta.Magnitude

	-- Pengecualian penuh sementara: respawn, grace game, state admin, ragdoll/pingsan/PlatformStand, dsb.
	local nonSeatPhysics = PHYSICS_STATES[hum:GetState()] == true and hum:GetState() ~= Enum.HumanoidStateType.Seated
	if Exemptions.IsExempt(player, now) or nonSeatPhysics then
		st.speedStrikes, st.airTime = 0, 0
		return
	end

	-- 1) Teleport mustahil: SELALU dicek (kendaraan/whitelist hanya diberi ambang lebih tinggi).
	local tpLimit = C.Teleport.StudsPerSecond
	if seated then tpLimit = C.Teleport.VehicleStudsPerSecond end
	if total > C.Teleport.MinStuds and total / dt > tpLimit then
		Scoring.Hit(player, "movement.teleport", 30, 3, { studs = round1(total), dt = round1(dt), seated = seated })
		return
	end

	-- Whitelist: duduk di kendaraan, memegang alat, atau berdiri di lantai khusus -> lewati speed/fly/noclip.
	local wl = seated and "seated" or Whitelist.Reason(player, st.char, hum, hrp, rayParams)
	if wl then
		st.speedStrikes, st.airTime = 0, 0
		return
	end

	-- 2) Speed horizontal
	local allowed = math.max(hum.WalkSpeed, 16) * C.Speed.Tolerance + C.Speed.FlatBonus
	local speed = horizontal / dt
	if speed > allowed then
		st.speedStrikes += 1
		if st.speedStrikes >= C.Speed.StrikesNeeded then
			st.speedStrikes = 0
			Scoring.Hit(player, "movement.speed", 20, 2, { speed = round1(speed), allowed = round1(allowed), walkspeed = hum.WalkSpeed })
		end
	else
		st.speedStrikes = math.max(0, st.speedStrikes - 1)
	end

	-- 3) Fly: melayang lama tanpa jatuh, atau naik terlalu cepat
	local airborne = hum.FloorMaterial == Enum.Material.Air and not NOT_FLYING_STATES[hum:GetState()]
	st.airTime = airborne and (st.airTime + dt) or 0
	if st.airTime > C.Fly.AirSeconds and vy > -C.Fly.MaxFallSpeed then
		st.airTime = 0
		Scoring.Hit(player, "movement.fly", 25, 3, { vy = round1(vy), air_seconds = C.Fly.AirSeconds })
	elseif vy > C.Fly.MaxUpSpeed then
		Scoring.Hit(player, "movement.fly", 15, 2, { vy = round1(vy), kind = "fast_ascent" })
	end

	-- 4) Noclip (heuristik; bobot rendah, tidak pernah cukup sendirian)
	if horizontal > C.Noclip.MinMove then
		local hit = workspace:Raycast(st.pos, delta, rayParams)
		local part = hit and hit.Instance
		if part and part.CanCollide and part.Anchored and math.min(part.Size.X, part.Size.Y, part.Size.Z) >= 1 then
			table.insert(st.noclip, now)
			while #st.noclip > 0 and now - st.noclip[1] > C.Noclip.WindowSeconds do table.remove(st.noclip, 1) end
			if #st.noclip >= C.Noclip.StrikesNeeded then
				st.noclip = {}
				Scoring.Hit(player, "movement.noclip", 10, 1, { through = part.Name, moved = round1(horizontal) })
			end
		end
	end
end

function Movement.Start()
	for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(p) state[p] = nil end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < C.Speed.SampleSeconds then return end
		acc = 0
		local now = os.clock()

		local chars = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(chars, p.Character) end
		end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = chars

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 and not (Config.StaffImmune and Permissions.IsStaff(player)) then
				local st = state[player]
				if not st or st.char ~= char then
					state[player] = { char = char, pos = hrp.Position, t = now, speedStrikes = 0, airTime = 0, noclip = {} }
				else
					local ok, err = pcall(analyse, player, st, hum, hrp, now, rayParams)
					if not ok then warn("[SmartAC] movement error:", err) end
					st.pos, st.t = hrp.Position, now
				end
			else
				state[player] = nil
			end
		end
	end)
end

return Movement
