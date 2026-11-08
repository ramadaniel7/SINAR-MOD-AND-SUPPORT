-- Token desain terpusat (warna, tipografi, jarak). Ubah di sini untuk mengganti tampilan seluruh UI.
local theme = {
	bg = Color3.fromRGB(17, 19, 25),
	panel = Color3.fromRGB(26, 29, 38),
	panel2 = Color3.fromRGB(35, 39, 50),
	hover = Color3.fromRGB(48, 54, 69),
	stroke = Color3.fromRGB(58, 64, 80),
	text = Color3.fromRGB(236, 239, 246),
	sub = Color3.fromRGB(150, 158, 176),
	accent = Color3.fromRGB(64, 140, 255),
	good = Color3.fromRGB(70, 200, 130),
	warn = Color3.fromRGB(240, 180, 60),
	bad = Color3.fromRGB(235, 90, 90),
	font = Enum.Font.GothamMedium,
	fontBold = Enum.Font.GothamBold,
	size = 14,
	radius = 8,
	tween = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- Ikuti tema game SINAR RP supaya tampilan seragam (kalau Config.Tema ada).
pcall(function()
	local T = require(game:GetService("ReplicatedStorage").SinarRP.Config).Tema
	if type(T) ~= "table" then return end
	theme.bg = T.Latar or theme.bg
	theme.panel = T.LatarTebal or theme.panel
	theme.panel2 = (T.LatarTebal and T.LatarTebal:Lerp(Color3.new(1, 1, 1), 0.06)) or theme.panel2
	theme.accent = T.Aksen or theme.accent
	theme.text = T.Teks or theme.text
	theme.sub = T.TeksRedup or theme.sub
	theme.good = T.Sukses or theme.good
	theme.bad = T.Bahaya or theme.bad
	theme.warn = T.Peringatan or theme.warn
	theme.font = T.Font or theme.font
end)

return theme
