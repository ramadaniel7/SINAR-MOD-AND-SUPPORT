-- SmartAC: titik masuk server. Tidak perlu diedit.
local root = script.Parent
local Modules = root.Modules

local Bridge = require(Modules.Bridge)
local Util = require(Modules.Util)
local Sessions = require(Modules.Sessions)
local Honeypot = require(Modules.Honeypot)
local Movement = require(Modules.Movement)
local Reports = require(Modules.Reports)
local Admin = require(Modules.Admin)
local Executor = require(Modules.Executor)
local Economy = require(Modules.Economy)
local Integration = require(Modules.Integration)
local Scoring = require(Modules.Scoring)
require(root.Api) -- pastikan API termuat

Bridge.Start()
Sessions.Start()
Honeypot.Start()
Movement.Start()
Reports.Start()
Admin.Start()
Executor.Start()
Economy.Start()

Util.Log(("Aktif. Mode anti-cheat: %s | Backend: %s | SINAR RP: %s"):format(Scoring.Mode, Bridge.Enabled and "dikonfigurasi" or "BELUM dikonfigurasi", Integration.Active() and "terdeteksi (staf dari ConfigOverhead)" or "tidak ada"))
