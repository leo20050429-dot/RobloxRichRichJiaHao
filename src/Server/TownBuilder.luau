-- 用程式碼蓋出「星塵鎮」：廣場、商店街（4 間當舖）、貿易站、研究院、黑市、監獄，
-- 以及城外的隕石礦場、飛碟墜毀點和連接的道路。
--
-- 所有可以互動的東西都是 ProximityPrompt，掛著 Action 屬性，由 Main 的路由交給各個 Service 處理。
-- 美術之後可以在 Studio 裡把這些方塊換成正式模型，只要保留名稱和 Prompt 就好。

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local TownBuilder = {}

local town = nil -- Build() 之後的參考表

local COLORS = {
	Ground = Color3.fromRGB(64, 58, 82),
	Plaza = Color3.fromRGB(96, 98, 120),
	Road = Color3.fromRGB(45, 45, 55),
	Wall = Color3.fromRGB(46, 48, 72),
	Roof = Color3.fromRGB(32, 34, 52),
	Wood = Color3.fromRGB(110, 78, 58),
	Neon = Color3.fromRGB(70, 220, 255),
	Purple = Color3.fromRGB(140, 100, 255),
	Gold = Color3.fromRGB(255, 205, 90),
	Danger = Color3.fromRGB(255, 90, 90),
}

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
	return l
end

local function sign(parent, name, text, cframe, size, textColor)
	local board = part(parent, {
		Name = name,
		Size = size,
		CFrame = cframe,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(20, 20, 34),
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.BuilderSansBold
	label.TextColor3 = textColor or COLORS.Neon
	label.Parent = gui
	return board, label
end

-- 頭上浮著的文字
local function floatingLabel(adornee, text, color, offsetY)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, 46)
	billboard.StudsOffset = Vector3.new(0, offsetY or 4, 0)
	billboard.MaxDistance = 140
	billboard.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.BuilderSansBold
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	billboard.Parent = adornee
	return billboard
end

local function prompt(parent, action, actionText, objectText, holdDuration, attributes)
	local p = Instance.new("ProximityPrompt")
	p.Name = action .. "Prompt"
	p.ActionText = actionText
	p.ObjectText = objectText or ""
	p.HoldDuration = holdDuration or 0
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p:SetAttribute("Action", action)
	if attributes then
		for key, value in attributes do
			p:SetAttribute(key, value)
		end
	end
	p.Parent = parent
	CollectionService:AddTag(p, "TownPrompt")
	return p
end

local function safeZone(folder, name, center, size)
	local zone = part(folder, {
		Name = name,
		Size = size,
		Position = center,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	return zone
end

-- 簡單的屋子：地板、三面牆、屋頂，正面（朝 facing 方向）開口
local function building(parent, name, center, size, facing, wallColor)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local w, h, d = size.X, size.Y, size.Z
	local base = CFrame.lookAt(center, center + facing)
	part(model, { Name = "Floor", Size = Vector3.new(w, 0.4, d), CFrame = base * CFrame.new(0, 0.2, 0), Material = Enum.Material.WoodPlanks, Color = COLORS.Wood })
	part(model, { Name = "Back", Size = Vector3.new(w, h, 1), CFrame = base * CFrame.new(0, h / 2, d / 2), Material = Enum.Material.Metal, Color = wallColor or COLORS.Wall })
	part(model, { Name = "Left", Size = Vector3.new(1, h, d), CFrame = base * CFrame.new(-w / 2, h / 2, 0), Material = Enum.Material.Metal, Color = wallColor or COLORS.Wall })
	part(model, { Name = "Right", Size = Vector3.new(1, h, d), CFrame = base * CFrame.new(w / 2, h / 2, 0), Material = Enum.Material.Metal, Color = wallColor or COLORS.Wall })
	part(model, { Name = "Roof", Size = Vector3.new(w + 2, 1, d + 2), CFrame = base * CFrame.new(0, h + 0.5, 0), Material = Enum.Material.Metal, Color = COLORS.Roof })
	part(model, { Name = "RoofGlow", Size = Vector3.new(w + 2, 0.3, 0.3), CFrame = base * CFrame.new(0, h, -d / 2 - 1), Material = Enum.Material.Neon, Color = COLORS.Purple, CanCollide = false })
	return model, base
end

local function lamp(parent, position, color)
	part(parent, { Name = "LampPost", Size = Vector3.new(0.6, 10, 0.6), Position = position + Vector3.new(0, 5, 0), Material = Enum.Material.Metal, Color = COLORS.Roof })
	local bulb = part(parent, { Name = "LampBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = position + Vector3.new(0, 10.5, 0), Material = Enum.Material.Neon, Color = color or COLORS.Neon, CanCollide = false })
	light(bulb, bulb.Color, 28, 1.2)
end

local function road(parent, from, to, width)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	part(parent, {
		Name = "Road",
		Size = Vector3.new(width, 0.2, length),
		CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), to + Vector3.new(0, 0.1, 0)),
		Material = Enum.Material.Asphalt,
		Color = COLORS.Road,
		CanQuery = false,
	})
	-- 路燈
	local steps = math.floor(length / 40)
	for i = 1, steps do
		local t = i / (steps + 1)
		local point = from:Lerp(to, t)
		local side = CFrame.lookAt(point, to).RightVector * (width / 2 + 2)
		lamp(parent, point + side, COLORS.Gold)
	end
end

local function npcFigure(parent, name, position, bodyColor, title)
	local model = Instance.new("Model")
	model.Name = name
	local body = part(model, { Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.4, 2.4), CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.SmoothPlastic, Color = bodyColor, CanCollide = true })
	part(model, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = position + Vector3.new(0, 5, 0), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(230, 220, 255) })
	part(model, { Name = "Visor", Size = Vector3.new(1.6, 0.5, 0.4), Position = position + Vector3.new(0, 5.2, 0.9), Material = Enum.Material.Neon, Color = COLORS.Neon, CanCollide = false })
	model.PrimaryPart = body
	model.Parent = parent
	floatingLabel(body, title, COLORS.Neon, 5)
	return model
end

local function buildShop(shopsFolder, safeFolder, index, x)
	local id = "Shop" .. index
	local center = Vector3.new(x, 0, -72)
	-- 店面開口朝 +Z（朝向廣場）
	local model, base = building(shopsFolder, id, center, Vector3.new(24, 14, 18), Vector3.new(0, 0, 1))
	model:SetAttribute("ShopId", id)
	model:SetAttribute("Owner", 0)

	-- 這裡的 base 是 lookAt(+Z)：local -Z = 世界 +Z（店門口）；local +Z = 世界 -Z（後牆）
	part(model, { Name = "Counter", Size = Vector3.new(12, 3.6, 2), CFrame = base * CFrame.new(0, 1.8, 2), Material = Enum.Material.Wood, Color = COLORS.Wood })
	local counterTop = part(model, { Name = "CounterTop", Size = Vector3.new(12.4, 0.3, 2.4), CFrame = base * CFrame.new(0, 3.75, 2), Material = Enum.Material.Glass, Color = Color3.fromRGB(150, 220, 255), Transparency = 0.3 })
	light(counterTop, Color3.fromRGB(190, 230, 255), 16, 1)

	-- 客人站在櫃檯前（靠門那側），面向店長（後牆方向）
	local spotPos = (base * CFrame.new(0, 3, -1.5)).Position
	part(model, {
		Name = "CustomerSpot",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.lookAt(spotPos, spotPos + Vector3.new(0, 0, -1)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})

	-- 店長站的位置（櫃檯後面）
	local keeperPos = (base * CFrame.new(0, 3, 5)).Position
	part(model, { Name = "KeeperSpot", Size = Vector3.new(1, 1, 1), Position = keeperPos, Transparency = 1, CanCollide = false, CanQuery = false })

	-- 互動點：在櫃檯上
	local promptPart = part(model, { Name = "PromptPart", Size = Vector3.new(1, 1, 1), CFrame = base * CFrame.new(0, 4.5, 2), Transparency = 1, CanCollide = false, CanQuery = false })
	prompt(promptPart, "ShopCounter", "經營這間當舖", "當舖 " .. index, 0, { ShopId = id })
	local relicPrompt = prompt(promptPart, "SellRelic", "把遺物賣給這間當舖", "當舖 " .. index, 0, { ShopId = id })
	relicPrompt.KeyboardKeyCode = Enum.KeyCode.F
	relicPrompt.UIOffset = Vector2.new(0, 70)

	-- 招牌（在門口上方，朝外）
	local signCFrame = CFrame.lookAt((base * CFrame.new(0, 12, -9.6)).Position, (base * CFrame.new(0, 12, -20)).Position)
	local _, signLabel = sign(model, "Sign", "空店面（可經營）", signCFrame, Vector3.new(16, 2.6, 0.4), COLORS.Gold)
	model:SetAttribute("SignText", signLabel.Text)

	safeZone(safeFolder, id .. "Safe", Vector3.new(x, 8, -72), Vector3.new(24, 16, 18))

	return {
		Id = id,
		Index = index,
		Model = model,
		CustomerSpot = model.CustomerSpot,
		KeeperSpot = model.KeeperSpot,
		SignLabel = signLabel,
	}
end

function TownBuilder.Build()
	if town then
		return town
	end

	local existing = workspace:FindFirstChild("Town")
	if existing then
		existing:Destroy()
	end
	local old = workspace:FindFirstChild("Baseplate")
	if old then
		old:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Town"
	local safeFolder = Instance.new("Folder")
	safeFolder.Name = "SafeZones"
	safeFolder.Parent = root
	local shopsFolder = Instance.new("Folder")
	shopsFolder.Name = "Shops"
	shopsFolder.Parent = root
	local deco = Instance.new("Folder")
	deco.Name = "Decor"
	deco.Parent = root

	-- 地面
	part(root, { Name = "Ground", Size = Vector3.new(800, 2, 800), Position = Vector3.new(0, -1, 60), Material = Enum.Material.Slate, Color = COLORS.Ground })

	-- 中央廣場（安全區）--------------------------------------------------------
	part(root, { Name = "Plaza", Size = Vector3.new(96, 0.4, 96), Position = Vector3.new(0, 0.2, 0), Material = Enum.Material.Concrete, Color = COLORS.Plaza })
	safeZone(safeFolder, "PlazaSafe", Vector3.new(0, 12, 0), Vector3.new(96, 30, 96))
	part(deco, { Name = "SafeLineN", Size = Vector3.new(96, 0.3, 0.6), Position = Vector3.new(0, 0.45, -48), Material = Enum.Material.Neon, Color = Color3.fromRGB(110, 225, 140), CanCollide = false })
	part(deco, { Name = "SafeLineS", Size = Vector3.new(96, 0.3, 0.6), Position = Vector3.new(0, 0.45, 48), Material = Enum.Material.Neon, Color = Color3.fromRGB(110, 225, 140), CanCollide = false })
	part(deco, { Name = "SafeLineW", Size = Vector3.new(0.6, 0.3, 96), Position = Vector3.new(-48, 0.45, 0), Material = Enum.Material.Neon, Color = Color3.fromRGB(110, 225, 140), CanCollide = false })
	part(deco, { Name = "SafeLineE", Size = Vector3.new(0.6, 0.3, 96), Position = Vector3.new(48, 0.45, 0), Material = Enum.Material.Neon, Color = Color3.fromRGB(110, 225, 140), CanCollide = false })

	-- 噴泉
	part(deco, { Name = "Fountain", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 16, 16), CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Marble, Color = Color3.fromRGB(200, 200, 220) })
	local core = part(deco, { Name = "FountainCore", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = Vector3.new(0, 5, 0), Material = Enum.Material.Neon, Color = COLORS.Neon, CanCollide = false })
	light(core, COLORS.Neon, 40, 2)
	floatingLabel(core, "星塵鎮", COLORS.Neon, 5)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlazaSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.4, 12)
	spawn.CFrame = CFrame.new(0, 0.6, 22)
	spawn.Material = Enum.Material.Neon
	spawn.Color = COLORS.Purple
	spawn.Transparency = 0.5
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = root

	-- 職業公告板
	local boardCFrame = CFrame.lookAt(Vector3.new(-18, 4.5, 10), Vector3.new(-18, 4.5, 30))
	local board = sign(root, "JobBoard", "職業公告板", boardCFrame, Vector3.new(10, 5, 0.6), COLORS.Gold)
	part(deco, { Name = "JobBoardLegL", Size = Vector3.new(0.5, 4, 0.5), Position = Vector3.new(-22.5, 2, 10), Material = Enum.Material.Metal, Color = COLORS.Roof })
	part(deco, { Name = "JobBoardLegR", Size = Vector3.new(0.5, 4, 0.5), Position = Vector3.new(-13.5, 2, 10), Material = Enum.Material.Metal, Color = COLORS.Roof })
	prompt(board, "JobBoard", "選擇職業", "職業公告板", 0)

	-- 城鎮 NPC 警衛（通緝犯靠近會被抓）
	local npcGuard = npcFigure(root, "NpcGuard", Vector3.new(18, 0, 8), Color3.fromRGB(70, 110, 200), "城鎮警衛（通緝犯別靠近）")

	for _, corner in { Vector3.new(-44, 0, -44), Vector3.new(44, 0, -44), Vector3.new(-44, 0, 44), Vector3.new(44, 0, 44) } do
		lamp(deco, corner, COLORS.Neon)
	end

	-- 商店街：4 間當舖 ------------------------------------------------------------
	part(root, { Name = "ShopStreet", Size = Vector3.new(120, 0.3, 14), Position = Vector3.new(0, 0.15, -56), Material = Enum.Material.Cobblestone, Color = Color3.fromRGB(80, 80, 96) })
	local shops = {}
	for i, x in { -45, -15, 15, 45 } do
		shops["Shop" .. i] = buildShop(shopsFolder, safeFolder, i, x)
	end

	-- 貿易站（西）與研究院（東）-----------------------------------------------
	local _, tradeBase = building(root, "TradingPost", Vector3.new(-70, 0, 12), Vector3.new(20, 12, 16), Vector3.new(1, 0, 0), Color3.fromRGB(80, 60, 40))
	local tradeCounter = part(root, { Name = "TradeCounter", Size = Vector3.new(2, 3.6, 10), CFrame = tradeBase * CFrame.new(0, 1.8, 2), Material = Enum.Material.Wood, Color = COLORS.Wood })
	prompt(tradeCounter, "SellCargo", "賣出貨物", "貿易站", 0, { BuyerId = "TradingPost" })
	sign(root, "TradeSign", "貿易站", CFrame.lookAt((tradeBase * CFrame.new(0, 10, -8.6)).Position, (tradeBase * CFrame.new(0, 10, -20)).Position), Vector3.new(12, 2.4, 0.4), COLORS.Gold)
	npcFigure(root, "Trader", (tradeBase * CFrame.new(0, 0, 5)).Position, Color3.fromRGB(200, 150, 70), "貿易站老闆")
	safeZone(safeFolder, "TradeSafe", Vector3.new(-70, 8, 12), Vector3.new(20, 16, 22))

	local _, instBase = building(root, "Institute", Vector3.new(70, 0, 12), Vector3.new(20, 12, 16), Vector3.new(-1, 0, 0), Color3.fromRGB(50, 70, 100))
	local dome = part(root, { Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.new(14, 14, 14), Position = Vector3.new(70, 13, 12), Material = Enum.Material.Glass, Color = Color3.fromRGB(140, 220, 255), Transparency = 0.4, CanCollide = false })
	light(dome, COLORS.Neon, 30, 1)
	local instCounter = part(root, { Name = "InstituteCounter", Size = Vector3.new(2, 3.6, 10), CFrame = instBase * CFrame.new(0, 1.8, 2), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(220, 230, 255) })
	prompt(instCounter, "SellCargo", "賣出貨物", "研究院", 0, { BuyerId = "Institute" })
	sign(root, "InstituteSign", "研究院", CFrame.lookAt((instBase * CFrame.new(0, 10, -8.6)).Position, (instBase * CFrame.new(0, 10, -20)).Position), Vector3.new(12, 2.4, 0.4), COLORS.Neon)
	npcFigure(root, "Researcher", (instBase * CFrame.new(0, 0, 5)).Position, Color3.fromRGB(230, 230, 240), "研究員")
	safeZone(safeFolder, "InstituteSafe", Vector3.new(70, 8, 12), Vector3.new(20, 16, 22))

	-- 黑市（商店街後面的暗巷，不是安全區）------------------------------------------
	local blackMarket = building(root, "BlackMarket", Vector3.new(0, 0, -105), Vector3.new(12, 8, 10), Vector3.new(0, 0, -1), Color3.fromRGB(30, 20, 30))
	local bmTable = part(blackMarket, { Name = "Table", Size = Vector3.new(6, 3, 2), Position = Vector3.new(0, 1.5, -103), Material = Enum.Material.Wood, Color = Color3.fromRGB(60, 40, 40) })
	prompt(bmTable, "SellCargo", "銷贓（什麼都收）", "黑市", 0, { BuyerId = "BlackMarket" })
	local bmLamp = part(blackMarket, { Name = "RedLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 7, -105), Material = Enum.Material.Neon, Color = COLORS.Danger, CanCollide = false })
	light(bmLamp, COLORS.Danger, 14, 1.5)
	npcFigure(root, "Fence", Vector3.new(0, 0, -101), Color3.fromRGB(40, 40, 40), "黑市商人")

	-- 監獄 ----------------------------------------------------------------------
	local jail = Instance.new("Model")
	jail.Name = "Jail"
	jail.Parent = root
	local jailCenter = Vector3.new(-75, 0, -100)
	part(jail, { Name = "Floor", Size = Vector3.new(18, 0.4, 18), Position = jailCenter + Vector3.new(0, 0.2, 0), Material = Enum.Material.Concrete, Color = Color3.fromRGB(70, 70, 80) })
	part(jail, { Name = "Roof", Size = Vector3.new(18, 1, 18), Position = jailCenter + Vector3.new(0, 14.5, 0), Material = Enum.Material.Metal, Color = COLORS.Roof })
	for _, offset in { Vector3.new(9, 7, 0), Vector3.new(-9, 7, 0), Vector3.new(0, 7, 9), Vector3.new(0, 7, -9) } do
		local size = (offset.X ~= 0) and Vector3.new(1, 14, 18) or Vector3.new(18, 14, 1)
		part(jail, { Name = "Wall", Size = size, Position = jailCenter + offset, Material = Enum.Material.Metal, Color = Color3.fromRGB(90, 90, 100) })
	end
	for i = -3, 3 do
		part(jail, { Name = "Bar", Size = Vector3.new(0.4, 10, 0.4), Position = jailCenter + Vector3.new(i * 2, 6, 9.8), Material = Enum.Material.Metal, Color = Color3.fromRGB(150, 150, 160), CanCollide = false })
	end
	local jailLight = part(jail, { Name = "JailLight", Size = Vector3.new(4, 0.3, 4), Position = jailCenter + Vector3.new(0, 13.8, 0), Material = Enum.Material.Neon, Color = COLORS.Danger, CanCollide = false })
	light(jailLight, COLORS.Danger, 20, 0.8)
	sign(root, "JailSign", "星塵鎮監獄", CFrame.lookAt(jailCenter + Vector3.new(0, 11, 10.2), jailCenter + Vector3.new(0, 11, 20)), Vector3.new(10, 2, 0.4), COLORS.Danger)
	local jailSpot = part(jail, { Name = "JailSpot", Size = Vector3.new(1, 1, 1), Position = jailCenter + Vector3.new(0, 3, 0), Transparency = 1, CanCollide = false, CanQuery = false })

	-- 城外：隕石礦場（南）與飛碟墜毀點（東南）------------------------------------
	road(root, Vector3.new(0, 0, 48), Vector3.new(0, 0, 220), 14)
	road(root, Vector3.new(48, 0, 30), Vector3.new(230, 0, 160), 14)

	local mine = Instance.new("Model")
	mine.Name = "Mine"
	mine.Parent = root
	local mineCenter = Vector3.new(0, 0, 250)
	part(mine, { Name = "Crater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 70, 70), CFrame = CFrame.new(mineCenter + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Basalt, Color = Color3.fromRGB(70, 60, 60) })
	sign(root, "MineSign", "隕石礦場", CFrame.lookAt(Vector3.new(0, 7, 212), Vector3.new(0, 7, 180)), Vector3.new(14, 3, 0.4), COLORS.Gold)
	for i, offset in { Vector3.new(-16, 0, -6), Vector3.new(14, 0, -10), Vector3.new(-8, 0, 16), Vector3.new(18, 0, 12), Vector3.new(0, 0, 0) } do
		local rock = part(mine, {
			Name = "Ore" .. i,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(7, 7, 7),
			Position = mineCenter + offset + Vector3.new(0, 2.5, 0),
			Material = Enum.Material.Rock,
			Color = Color3.fromRGB(120, 125, 170),
		})
		local glow = part(mine, { Name = "OreGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = rock.Position + Vector3.new(0, 3, 0), Material = Enum.Material.Neon, Color = Color3.fromRGB(150, 160, 255), CanCollide = false })
		light(glow, glow.Color, 12, 1)
		local p = prompt(rock, "Collect", "採集", "隕石礦場", 1.2, { PointId = "Mine" })
		p.MaxActivationDistance = 12
	end

	local crash = Instance.new("Model")
	crash.Name = "CrashSite"
	crash.Parent = root
	local crashCenter = Vector3.new(255, 0, 175)
	part(crash, { Name = "Scorch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 60, 60), CFrame = CFrame.new(crashCenter + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.CrackedLava, Color = Color3.fromRGB(60, 40, 40) })
	local saucer = part(crash, { Name = "Saucer", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 30, 30), CFrame = CFrame.new(crashCenter + Vector3.new(0, 4, 0)) * CFrame.Angles(math.rad(18), 0, math.rad(90)), Material = Enum.Material.Metal, Color = Color3.fromRGB(170, 180, 190) })
	part(crash, { Name = "SaucerDome", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), Position = crashCenter + Vector3.new(0, 8, -2), Material = Enum.Material.Glass, Color = Color3.fromRGB(120, 255, 170), Transparency = 0.4, CanCollide = false })
	light(saucer, Color3.fromRGB(120, 255, 170), 40, 1.5)
	sign(root, "CrashSign", "飛碟墜毀點", CFrame.lookAt(Vector3.new(222, 7, 150), Vector3.new(180, 7, 120)), Vector3.new(14, 3, 0.4), COLORS.Gold)
	for i, offset in { Vector3.new(-20, 0, 6), Vector3.new(18, 0, -14), Vector3.new(-6, 0, -22), Vector3.new(22, 0, 16), Vector3.new(-18, 0, 20) } do
		local debris = part(crash, {
			Name = "Debris" .. i,
			Size = Vector3.new(5, 3, 6),
			CFrame = CFrame.new(crashCenter + offset + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, math.rad(i * 37), math.rad(12)),
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(150, 160, 170),
		})
		local p = prompt(debris, "Collect", "搜刮", "飛碟墜毀點", 1.2, { PointId = "Crash" })
		p.MaxActivationDistance = 12
	end

	-- 燈光：太空小鎮的傍晚
	Lighting.ClockTime = 19.5
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(90, 80, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(100, 90, 140)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.6

	root.Parent = workspace

	local safeZones = {}
	for _, zone in safeFolder:GetChildren() do
		table.insert(safeZones, { Center = zone.Position, Size = zone.Size, Name = zone.Name })
	end

	town = {
		Root = root,
		Shops = shops,
		SafeZones = safeZones,
		JailSpot = jailSpot.Position,
		SpawnPosition = spawn.Position + Vector3.new(0, 3, 0),
		NpcGuard = npcGuard,
	}
	return town
end

function TownBuilder.Get()
	return town
end

return TownBuilder
