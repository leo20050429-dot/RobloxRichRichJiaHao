-- 當舖的核心邏輯（全部在伺服器端）。
--
-- 客戶端只能透過 ShopAction 這個 RemoteFunction 送出「我想做什麼」，
-- 例如 Inspect / Offer / SellItem。價格、真假、瑕疵、星幣全部由伺服器決定並檢查，
-- 客戶端永遠拿不到物品的真實狀態，只會看到自己鑑定出來的結果。

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared:WaitForChild("Achievements"))
local BargainSystem = require(Shared:WaitForChild("BargainSystem"))
local CodexSystem = require(Shared:WaitForChild("CodexSystem"))
local Config = require(Shared:WaitForChild("Config"))
local CustomerGenerator = require(Shared:WaitForChild("CustomerGenerator"))
local GalacticNews = require(Shared:WaitForChild("GalacticNews"))
local ItemDatabase = require(Shared:WaitForChild("ItemDatabase"))
local Progression = require(Shared:WaitForChild("Progression"))
local Tools = require(Shared:WaitForChild("Tools"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PromptRouter = require(script.Parent:WaitForChild("PromptRouter"))
local TownBuilder = require(script.Parent:WaitForChild("TownBuilder"))
local TownService = require(script.Parent:WaitForChild("TownService"))

local ShopService = {}

local sessions = {} -- [Player] = session
local rng = Random.new()
local stateChangedEvent = nil
local notifyEvent = nil
local openJobPickerEvent = nil
local shops = {} -- [shopId] = { Owner = Player?, Queue = { { Seller, Cargo } }, Info = TownBuilder 的店面資料 }
local pushState -- 前向宣告（下面才定義）

local function notify(player, text, ok)
	if notifyEvent and text and typeof(player) == "Instance" and player:IsA("Player") then
		notifyEvent:FireClient(player, text, ok)
	end
end

local function displayName(actor)
	if typeof(actor) == "Instance" and actor:IsA("Player") then
		return actor.DisplayName
	end
	return type(actor) == "table" and tostring(actor.Name) or "某人"
end

-- 銀河新聞（整個伺服器共用）
local currentNews = GalacticNews.Get("Calm")
local newsEndsAt = 0

local function rand()
	return rng:NextNumber()
end

local function newSession()
	return {
		Customer = nil,
		Findings = {}, -- { { Tool, Text, Tone } }
		ToolsUsed = {}, -- [toolId] = true
		FakeRevealed = false, -- 這位客人的假貨是否已經被鑑定出來
		Passes = {}, -- [passName] = true
		LastRequest = 0,
		ShopId = nil, -- 經營中的店面
		CounterOpen = false, -- 是否在櫃檯營業中
	}
end

local function inventoryLimit(session)
	local limit = Config.InventorySlots
	if session.Passes.ExtraStorage then
		limit += Config.ExtraStorageSlots
	end
	return limit
end

-- sold = true 代表成交；否則如果是玩家商人寄賣的遺物，要還給商人
local function clearCustomer(session, sold)
	local customer = session.Customer
	if customer and customer.SellerCargo and not sold then
		TownService.ReturnRelic(customer.Seller, customer.SellerCargo)
	end
	session.Customer = nil
	session.Findings = {}
	session.ToolsUsed = {}
	session.FakeRevealed = false
end

local function customerStormsOff(data, session)
	data.Reputation = math.max(0, data.Reputation + Config.Reputation.CustomerStormedOff)
	clearCustomer(session)
end

-- 店面 ---------------------------------------------------------------------------

local function shopOwnedBy(actor)
	for id, shop in shops do
		if shop.Owner == actor then
			return id, shop
		end
	end
	return nil, nil
end

local function setSign(shopId)
	local shop = shops[shopId]
	if not shop then
		return
	end
	local info = shop.Info
	if shop.Owner then
		info.SignLabel.Text = displayName(shop.Owner) .. " 的當舖"
	else
		info.SignLabel.Text = "空店面（可經營）"
	end
	local ownerId = 0
	if shop.Owner and typeof(shop.Owner) == "Instance" then
		ownerId = shop.Owner.UserId
	elseif shop.Owner then
		ownerId = -1
	end
	info.Model:SetAttribute("Owner", ownerId)
end

-- 放棄店面：收掉客人、把排隊中的遺物還給商人
local function releaseShop(actor)
	local session = sessions[actor]
	if session then
		clearCustomer(session)
		session.CounterOpen = false
		session.ShopId = nil
	end
	local shopId, shop = shopOwnedBy(actor)
	if shop then
		local queue = shop.Queue
		shop.Queue = {}
		shop.Owner = nil
		setSign(shopId)
		for _, entry in queue do
			TownService.ReturnRelic(entry.Seller, entry.Cargo)
		end
	end
end

local function counterError(session)
	if not session.ShopId then
		return "你還沒有店面。先當「當舖老闆」，再到商店街經營一間當舖。"
	end
	if not session.CounterOpen then
		return "先到你的當舖櫃檯按「打開櫃檯」。"
	end
	return nil
end

-- 新聞對某件物品的賣價倍率
local function newsMultiplierFor(itemId)
	local def = ItemDatabase.Get(itemId)
	return GalacticNews.GetPriceMultiplier(currentNews, def and def.Category or nil)
end

-- 排行榜（玩家列表右上角顯示的數字）
local function syncLeaderstats(player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local credits = Instance.new("IntValue")
		credits.Name = "星幣"
		credits.Parent = stats
		local reputation = Instance.new("IntValue")
		reputation.Name = "名聲"
		reputation.Parent = stats
		stats.Parent = player
	end
	local credits = stats:FindFirstChild("星幣")
	local reputation = stats:FindFirstChild("名聲")
	if credits then
		credits.Value = data.Credits
	end
	if reputation then
		reputation.Value = data.Reputation
	end
end

-- 檢查有沒有新達成的成就，發獎勵並回傳要顯示的文字
local function grantAchievements(data)
	local stats = {}
	for key, value in data.Stats do
		stats[key] = value
	end
	stats.CodexCount = CodexSystem.Count(data.Codex)

	local texts = {}
	for _, def in Achievements.CheckNew(data.Achievements, stats) do
		data.Achievements[def.Id] = true
		data.Credits += def.Reward
		table.insert(texts, string.format("🏆 成就達成：%s（+%d 星幣）", def.Name, def.Reward))
	end
	return texts
end

-- 傳給客戶端看的狀態（不含任何物品真相）
local function buildState(player, session, data)
	local rank, nextRank = Progression.GetRank(data.Reputation)
	local dailyAvailable, dailyStreak, dailyReward = Progression.PeekDaily(data.Daily, Progression.Today())
	local _bonuses, completedSets = CodexSystem.CheckSetBonus(data)

	local state = {
		Title = Config.GameTitle,
		Credits = data.Credits,
		Reputation = data.Reputation,
		Rank = {
			Title = rank.Title,
			NextTitle = nextRank and nextRank.Title or nil,
			NextAt = nextRank and nextRank.MinReputation or nil,
		},
		CodexCount = CodexSystem.Count(data.Codex),
		ItemCount = ItemDatabase.Count(),
		Persistent = DataService.IsPersistent(player),
		InventoryLimit = inventoryLimit(session),
		Passes = session.Passes,
		News = {
			Title = currentNews.Title,
			Description = currentNews.Description,
			SecondsLeft = math.max(0, newsEndsAt - os.time()),
		},
		Daily = {
			Available = dailyAvailable,
			Streak = dailyStreak,
			Reward = dailyReward,
		},
		Tools = {},
		Inventory = {},
		Codex = {},
		Sets = {},
		Achievements = {},
		Customer = nil,
	}

	for _, toolId in Tools.Order do
		local tool = Tools.List[toolId]
		table.insert(state.Tools, {
			Id = toolId,
			Name = tool.Name,
			Price = tool.Price,
			PatienceCost = tool.PatienceCost,
			Description = tool.Description,
			Owned = data.UnlockedTools[toolId] == true,
			UsedOnCustomer = session.ToolsUsed[toolId] == true,
		})
	end

	for _, entry in data.Inventory do
		local def = ItemDatabase.Get(entry.ItemId)
		table.insert(state.Inventory, {
			Uid = entry.Uid,
			Name = ItemDatabase.GetDisplayName(entry.ItemId, entry.Variant),
			Rarity = def and def.Rarity or "Common",
			RarityName = def and ItemDatabase.RarityNames[def.Rarity] or "",
			Variant = entry.Variant or "Normal",
			PaidPrice = entry.PaidPrice,
			Findings = entry.Findings or {},
			NewsMultiplier = newsMultiplierFor(entry.ItemId),
		})
	end

	-- 圖鑑：沒收集過的物品不給名字
	for _, def in ItemDatabase.GetAll() do
		local rankValue = CodexSystem.VariantRank(data.Codex[def.ID])
		local collected = rankValue >= 0
		local variant = "Normal"
		if rankValue == 1 then
			variant = "Shiny"
		elseif rankValue >= 2 then
			variant = "Rainbow"
		end
		table.insert(state.Codex, {
			Collected = collected,
			Name = collected and def.Name or nil,
			Rarity = def.Rarity,
			RarityName = ItemDatabase.RarityNames[def.Rarity],
			Category = ItemDatabase.CategoryNames[def.Category] or "",
			Variant = variant,
			MinReputation = def.MinReputation,
		})
	end

	for _, set in CodexSystem.Sets do
		local have, total = CodexSystem.GetSetProgress(data.Codex, set)
		table.insert(state.Sets, {
			Name = set.Name,
			Description = set.Description,
			Have = have,
			Total = total,
			Done = completedSets[set.Id] == true,
		})
	end

	local stats = {}
	for key, value in data.Stats do
		stats[key] = value
	end
	stats.CodexCount = state.CodexCount
	for _, def in Achievements.List do
		table.insert(state.Achievements, {
			Name = def.Name,
			Description = def.Description,
			Progress = Achievements.GetProgress(def, stats),
			Goal = def.Goal,
			Reward = def.Reward,
			Done = data.Achievements[def.Id] == true,
		})
	end

	state.Town = TownService.GetPublicState(player)
	local shop = session.ShopId and shops[session.ShopId] or nil
	if shop then
		state.Shop = {
			Id = session.ShopId,
			Index = shop.Info.Index,
			CounterOpen = session.CounterOpen,
			QueueCount = #shop.Queue,
		}
	end

	local customer = session.Customer
	if customer then
		local def = ItemDatabase.Get(customer.Item.ItemId)
		local variant = customer.Item.Variant or "Normal"
		state.Customer = {
			Id = customer.Id,
			Name = customer.Name,
			Species = customer.Species,
			Color = customer.Color,
			Line = customer.LastLine,
			ItemName = ItemDatabase.GetDisplayName(customer.Item.ItemId, variant),
			ItemDescription = def and def.Description or "",
			Rarity = def and def.Rarity or "Common",
			RarityName = def and ItemDatabase.RarityNames[def.Rarity] or "",
			Category = def and ItemDatabase.CategoryNames[def.Category] or "",
			Variant = variant,
			VariantMultiplier = ItemDatabase.GetVariantMultiplier(variant),
			AskingPrice = customer.CurrentAsk,
			-- 行情價：這件東西如果是沒瑕疵的真品，在市場上值多少（公開資訊，像價目表）
			MarketPrice = ItemDatabase.GetEffectiveBase(customer.Item),
			IsPlayerSeller = customer.Seller ~= nil,
			Stolen = customer.SellerCargo ~= nil and customer.SellerCargo.Stolen == true,
			Patience = customer.Patience,
			MaxPatience = customer.MaxPatience,
			Findings = session.Findings,
			-- Gamepass 情報
			Floor = session.Passes.Empath and customer.Floor or nil,
			FakeChance = (session.Passes.VIPScanner and def) and def.InspectionAttributes.FakeChance or nil,
		}
	end

	return state
end

local handlers = {}

handlers.GetState = function()
	return true, nil
end

handlers.NextCustomer = function(_player, session, data)
	local counterProblem = counterError(session)
	if counterProblem then
		return false, counterProblem
	end
	if session.Customer then
		return false, "現在已經有客人了。"
	end
	clearCustomer(session)

	-- 救急金：沒貨可賣、錢又不夠買任何東西時，補一筆資金避免卡關
	local message = nil
	if #data.Inventory == 0 and data.Credits < Config.Bailout.Threshold then
		data.Credits = Config.Bailout.Amount
		message = string.format("銀河商會看你快倒店了，借你一筆救急金。星幣補到 %d。", Config.Bailout.Amount)
	end

	-- 玩家商人寄賣的遺物優先
	local shop = shops[session.ShopId]
	if shop and #shop.Queue > 0 then
		local entry = table.remove(shop.Queue, 1)
		local sellerCustomer = CustomerGenerator.FromItem(entry.Cargo.Item, displayName(entry.Seller), "玩家商人", 0.5, HttpService:GenerateGUID(false))
		sellerCustomer.Seller = entry.Seller
		sellerCustomer.SellerCargo = entry.Cargo
		if entry.Cargo.Stolen then
			sellerCustomer.LastLine = "（他一直左顧右盼，看起來很緊張…這可能是贓物。）"
		end
		session.Customer = sellerCustomer
		return true, (message and (message .. "\n") or "") .. "📦 玩家商人" .. displayName(entry.Seller) .. "帶著遺物來了！成交的錢會付給他。"
	end

	local bonuses = CodexSystem.CheckSetBonus(data)
	local customer = CustomerGenerator.Generate(data.Reputation, rand, HttpService:GenerateGUID(false), {
		Patience = 100 + bonuses.Patience,
		FakeChanceBonus = function(def)
			return GalacticNews.GetFakeChanceBonus(currentNews, def.Category)
		end,
	})
	session.Customer = customer

	local variant = customer.Item.Variant
	if variant == "Rainbow" then
		message = (message and (message .. "\n") or "") .. "🌈 哇！客人帶來了超稀有的彩虹版物品（價值 ×10）！"
	elseif variant == "Shiny" then
		message = (message and (message .. "\n") or "") .. "✨ 客人帶來了閃亮版物品（價值 ×3）！"
	end
	return true, message
end

handlers.Inspect = function(_player, session, data, payload)
	local counterProblem = counterError(session)
	if counterProblem then
		return false, counterProblem
	end
	local customer = session.Customer
	if not customer then
		return false, "現在沒有客人。"
	end
	local toolId = payload.ToolId
	local tool = type(toolId) == "string" and Tools.List[toolId] or nil
	if not tool then
		return false, "未知的工具。"
	end
	if not data.UnlockedTools[toolId] then
		return false, "你還沒有這個工具。"
	end
	if session.ToolsUsed[toolId] then
		return false, "這件物品已經用" .. tool.Name .. "檢查過了。"
	end

	session.ToolsUsed[toolId] = true
	for _, finding in ItemDatabase.Inspect(customer.Item, toolId) do
		table.insert(session.Findings, { Tool = tool.Name, Text = finding.Text, Tone = finding.Tone })
	end

	local def = ItemDatabase.Get(customer.Item.ItemId)
	if def and customer.Item.IsFake and def.InspectionAttributes.FakeTell.Tool == toolId then
		session.FakeRevealed = true
	end

	customer.Patience = math.max(0, customer.Patience - tool.PatienceCost)
	if customer.Patience <= 0 then
		local name = customer.Name
		customerStormsOff(data, session)
		return true, name .. "等得不耐煩，直接走掉了。"
	end
	customer.LastLine = "（" .. customer.Name .. "盯著你用" .. tool.Name .. "檢查…）"
	return true, nil
end

handlers.Offer = function(player, session, data, payload)
	local counterProblem = counterError(session)
	if counterProblem then
		return false, counterProblem
	end
	local customer = session.Customer
	if not customer then
		return false, "現在沒有客人。"
	end
	local amount = payload.Amount
	if type(amount) ~= "number" or amount ~= amount or amount < 1 or amount > 1e9 then
		return false, "請輸入正確的價格。"
	end
	amount = math.floor(amount)
	if amount > data.Credits then
		return false, "星幣不夠！"
	end
	if #data.Inventory >= inventoryLimit(session) then
		return false, "倉庫滿了，先賣掉一些東西吧。"
	end

	local def = ItemDatabase.Get(customer.Item.ItemId)
	if not def then
		clearCustomer(session)
		return false, "這位客人的物品資料有誤。"
	end

	local effectiveBase = ItemDatabase.GetEffectiveBase(customer.Item)
	local result = BargainSystem.Negotiate(amount, effectiveBase, customer.Patience, customer.Greed)
	customer.Patience = result.NewPatience

	if result.Success then
		local price = result.FinalPrice
		local variant = customer.Item.Variant or "Normal"
		local itemName = ItemDatabase.GetDisplayName(def.ID, variant)
		local _oldBonuses, oldSets = CodexSystem.CheckSetBonus(data)

		data.Credits -= price
		local findingTexts = {}
		for _, finding in session.Findings do
			table.insert(findingTexts, finding.Tool .. "：" .. finding.Text)
		end
		table.insert(data.Inventory, {
			Uid = HttpService:GenerateGUID(false),
			ItemId = def.ID,
			IsFake = customer.Item.IsFake,
			DefectType = customer.Item.DefectType,
			Variant = variant,
			PaidPrice = price,
			Findings = findingTexts,
		})
		data.Stats.DealsMade += 1
		if variant ~= "Normal" then
			data.Stats.ShiniesFound += 1
		end

		local lines = { string.format("%s：「%s」你花 %d 星幣收購了%s。", customer.Name, result.NPCResponseText, price, itemName) }

		-- 玩家商人寄賣：錢付給商人
		if customer.Seller then
			local sellerData = DataService.Get(customer.Seller)
			if sellerData then
				sellerData.Credits += price
				sellerData.Stats.TotalProfit += price
				notify(customer.Seller, string.format("💰 %s的當舖用 %d 星幣收購了你的%s！", displayName(player), price, itemName), true)
				pushState(customer.Seller)
			end
			if customer.SellerCargo and customer.SellerCargo.Stolen then
				data.Reputation = math.max(0, data.Reputation - 2)
				table.insert(lines, "⚠ 你收了贓物，名聲 -2。")
			end
		end

		local isNew, isUpgrade = CodexSystem.Record(data.Codex, def.ID, variant)
		if isNew then
			table.insert(lines, "📖 圖鑑新增：" .. def.Name)
		elseif isUpgrade then
			table.insert(lines, "📖 圖鑑升級：" .. itemName)
		end

		local _newBonuses, newSets = CodexSystem.CheckSetBonus(data)
		for _, set in CodexSystem.Sets do
			if newSets[set.Id] and not oldSets[set.Id] then
				table.insert(lines, "🎉 套裝完成：" .. set.Name .. "！" .. set.Description)
			end
		end

		clearCustomer(session, true)
		return true, table.concat(lines, "\n")
	end

	if result.DealFailed then
		local message = customer.Name .. "：「" .. result.NPCResponseText .. "」"
		customerStormsOff(data, session)
		return true, message
	end

	if result.CounterOffer then
		customer.CurrentAsk = result.CounterOffer
	end
	customer.LastLine = result.NPCResponseText
	return true, nil
end

handlers.Reject = function(_player, session, data)
	local customer = session.Customer
	if not customer then
		return false, "現在沒有客人。"
	end
	local name = customer.Name
	local caughtFake = customer.Item.IsFake and session.FakeRevealed
	clearCustomer(session)
	if caughtFake then
		data.Stats.FakesSpotted += 1
		return true, "你識破了假貨，把" .. name .. "趕出去了！"
	end
	return true, "你婉拒了" .. name .. "。"
end

handlers.SellItem = function(_player, session, data, payload)
	local uid = payload.Uid
	if type(uid) ~= "string" then
		return false, "找不到這件物品。"
	end
	local index = nil
	for i, entry in data.Inventory do
		if entry.Uid == uid then
			index = i
			break
		end
	end
	if not index then
		return false, "找不到這件物品。"
	end

	local entry = data.Inventory[index]
	local def = ItemDatabase.Get(entry.ItemId)
	local name = ItemDatabase.GetDisplayName(entry.ItemId, entry.Variant)
	local bonuses = CodexSystem.CheckSetBonus(data)
	local newsMultiplier = newsMultiplierFor(entry.ItemId)

	local value = ItemDatabase.GetMarketValue(entry)
	value = math.max(1, math.floor(value * newsMultiplier * (1 + bonuses.SellBonus)))
	local profit = value - entry.PaidPrice

	table.remove(data.Inventory, index)
	data.Credits += value
	data.Stats.ItemsSold += 1
	data.Stats.TotalProfit += profit

	local profitText
	if profit >= 0 then
		profitText = string.format("賺了 %d", profit)
	else
		profitText = string.format("虧了 %d", -profit)
	end
	local newsText = ""
	if newsMultiplier > 1 then
		newsText = "📈 " .. currentNews.Title .. "加成！"
	end

	if entry.IsFake then
		data.Stats.FakesSold += 1
		data.Reputation = math.max(0, data.Reputation + Config.Reputation.SellFake)
		return true, string.format("市場鑑定師：「這個%s是假貨！」只賣到 %d 星幣（%s）。名聲下降了。", name, value, profitText)
	end

	local gain = Config.Reputation.SellReal + bonuses.Reputation
	if session.Passes.DoubleReputation then
		gain *= 2
	end
	local oldRank = Progression.GetRank(data.Reputation)
	data.Reputation += gain
	local newRank = Progression.GetRank(data.Reputation)

	local message
	if def and entry.DefectType == def.InspectionAttributes.Defect.Type then
		message = string.format("%s%s有瑕疵（%s），賣了 %d 星幣（%s）。", newsText, name, def.InspectionAttributes.Defect.DisplayName, value, profitText)
	else
		message = string.format("%s%s是真品！賣了 %d 星幣（%s）。", newsText, name, value, profitText)
	end
	if newRank.Title ~= oldRank.Title then
		message ..= "\n⭐ 升級了！你現在是「" .. newRank.Title .. "」！"
	end
	return true, message
end

handlers.BuyTool = function(_player, _session, data, payload)
	local toolId = payload.ToolId
	local tool = type(toolId) == "string" and Tools.List[toolId] or nil
	if not tool then
		return false, "未知的工具。"
	end
	if data.UnlockedTools[toolId] then
		return false, "你已經有" .. tool.Name .. "了。"
	end
	if data.Credits < tool.Price then
		return false, "星幣不夠！"
	end
	data.Credits -= tool.Price
	data.UnlockedTools[toolId] = true
	return true, "買下了" .. tool.Name .. "！"
end

handlers.ClaimDaily = function(_player, _session, data)
	local reward = Progression.ClaimDaily(data.Daily, Progression.Today())
	if not reward then
		return false, "今天已經領過了，明天再來！"
	end
	data.Credits += reward
	return true, string.format("🎁 每日獎勵：+%d 星幣！（連續登入第 %d 天）", reward, data.Daily.Streak)
end

handlers.RedeemCode = function(_player, _session, data, payload)
	local raw = payload.Code
	if type(raw) ~= "string" or #raw > 64 then
		return false, "兌換碼不正確。"
	end
	local code = string.upper((string.gsub(raw, "[^%w]", "")))
	if code == "" then
		return false, "請輸入兌換碼。"
	end
	local reward = Config.Codes[code]
	if type(reward) ~= "number" then
		return false, "沒有這組兌換碼。"
	end
	if data.RedeemedCodes[code] then
		return false, "這組兌換碼已經用過了。"
	end
	data.RedeemedCodes[code] = true
	data.Credits += reward
	return true, string.format("兌換成功！+%d 星幣", reward)
end

handlers.ChooseJob = function(player, _session, _data, payload)
	return TownService.SetJob(player, payload.JobId)
end

handlers.CloseCounter = function(_player, session)
	if not session.CounterOpen then
		return false, "櫃檯本來就沒開。"
	end
	clearCustomer(session)
	session.CounterOpen = false
	return true, "打烊了，可以出去逛逛。"
end

handlers.BuyInsurance = function(player)
	return TownService.BuyInsurance(player)
end

local function loadPasses(player, session)
	for passName, passId in Config.GamePasses do
		if passId ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			session.Passes[passName] = ok and owns == true
		end
	end
end

pushState = function(player)
	if typeof(player) ~= "Instance" then
		return
	end
	local session = sessions[player]
	local data = DataService.Get(player)
	if session and data and stateChangedEvent then
		syncLeaderstats(player, data)
		stateChangedEvent:FireClient(player, buildState(player, session, data))
	end
end

local function onPlayerAdded(player)
	local session = newSession()
	sessions[player] = session
	task.spawn(function()
		loadPasses(player, session)
		pushState(player)
	end)
end

-- 店面互動（ProximityPrompt）------------------------------------------------------

local function faceCounter(player, shop)
	if typeof(player) ~= "Instance" then
		TownService.Teleport(player, shop.Info.KeeperSpot.Position)
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local from = shop.Info.KeeperSpot.Position
		local to = shop.Info.CustomerSpot.Position
		root.CFrame = CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function onShopCounter(player, prompt)
	local shopId = prompt:GetAttribute("ShopId")
	local shop = shops[shopId]
	local session = sessions[player]
	if not shop or not session then
		return false, "找不到這間店。"
	end
	if TownService.IsJailed(player) then
		return false, "你在坐牢。"
	end
	if shop.Owner == player then
		session.CounterOpen = true
		faceCounter(player, shop)
		return true, "開門營業！按「下一位客人」開始接客。"
	end
	if shop.Owner ~= nil then
		return false, "這是" .. displayName(shop.Owner) .. "的當舖。"
	end
	if TownService.GetJob(player) ~= "Pawnbroker" then
		return false, "只有「當舖老闆」能經營店面。到廣場的職業公告板可以換職業。"
	end
	releaseShop(player)
	shop.Owner = player
	session.ShopId = shopId
	setSign(shopId)
	return true, string.format("你開了 %d 號當舖！再按一次「打開櫃檯」開始營業。", shop.Info.Index)
end

local function onSellRelic(player, prompt)
	local shop = shops[prompt:GetAttribute("ShopId")]
	if not shop then
		return false, "找不到這間店。"
	end
	if not shop.Owner then
		return false, "這間店沒人經營。"
	end
	if shop.Owner == player then
		return false, "不能賣給自己的店。"
	end
	if TownService.IsJailed(player) then
		return false, "你在坐牢。"
	end
	if TownService.RelicCount(player) == 0 then
		return false, "你身上沒有遺物。商人在城外採集時有機會挖到。"
	end
	if #shop.Queue >= Config.Town.MerchantQueueLimit then
		return false, "這間當舖現在很忙，等一下再來。"
	end
	local item = TownService.TakeRelic(player)
	table.insert(shop.Queue, { Seller = player, Cargo = item })
	notify(shop.Owner, "📦 玩家商人" .. displayName(player) .. "寄賣了一件遺物，叫下一位客人就會輪到他。", true)
	pushState(shop.Owner)
	return true, "已經把遺物交給" .. displayName(shop.Owner) .. "的當舖，等店長出價。成交的錢會直接給你。"
end

-- 處理一個客戶端請求（RemoteFunction 與自動測試共用）
local function invoke(player, action, payload, skipCooldown)
	local session = sessions[player]
	local data = DataService.Get(player)
	if not session or not data then
		return { Ok = false, Message = "存檔讀取中，請稍候…" }
	end

	if not skipCooldown then
		local now = os.clock()
		if now - session.LastRequest < Config.RequestCooldown then
			return { Ok = false, Message = "慢一點！" }
		end
		session.LastRequest = now
	end

	local handler = type(action) == "string" and handlers[action] or nil
	if not handler then
		return { Ok = false, Message = "未知的動作。" }
	end
	if type(payload) ~= "table" then
		payload = {}
	end

	local ok, success, message = pcall(handler, player, session, data, payload)
	if not ok then
		warn("[ShopService] " .. tostring(action) .. " 出錯：" .. tostring(success))
		return { Ok = false, Message = "伺服器出錯了，請再試一次。", State = buildState(player, session, data) }
	end

	-- 成就獎勵接在訊息後面
	local achievementTexts = grantAchievements(data)
	if #achievementTexts > 0 then
		local extra = table.concat(achievementTexts, "\n")
		message = message and (message .. "\n" .. extra) or extra
	end

	if typeof(player) == "Instance" then
		syncLeaderstats(player, data)
	end
	return { Ok = success, Message = message, State = buildState(player, session, data) }
end

function ShopService.InvokeForTest(player, action, payload)
	return invoke(player, action, payload or {}, true)
end

function ShopService.GetSession(player)
	return sessions[player]
end

function ShopService.GetShops()
	return shops
end

function ShopService.AddTestActor(actor)
	sessions[actor] = newSession()
end

function ShopService.Start(remotes)
	stateChangedEvent = remotes.StateChanged
	notifyEvent = remotes.Notify
	openJobPickerEvent = remotes.OpenJobPicker
	newsEndsAt = os.time() + Config.NewsInterval

	local town = TownBuilder.Get()
	for id, info in town.Shops do
		shops[id] = { Owner = nil, Queue = {}, Info = info }
	end

	TownService.Configure({
		PushState = function(actor)
			pushState(actor)
		end,
		Notify = notify,
		HasPass = function(actor, passName)
			local session = sessions[actor]
			return session ~= nil and session.Passes[passName] == true
		end,
		OnJobChanged = function(actor, oldJob)
			if oldJob == "Pawnbroker" then
				releaseShop(actor)
			end
		end,
	})

	PromptRouter.Register("JobBoard", function(player)
		if openJobPickerEvent and typeof(player) == "Instance" then
			openJobPickerEvent:FireClient(player)
		end
		return true, nil
	end)
	PromptRouter.Register("ShopCounter", onShopCounter)
	PromptRouter.Register("SellRelic", onSellRelic)
	PromptRouter.OnHandled(function(player, ok, message)
		if message then
			notify(player, message, ok)
		end
		pushState(player)
	end)

	remotes.ShopAction.OnServerInvoke = function(player, action, payload)
		return invoke(player, action, payload, false)
	end

	DataService.OnLoaded(function(player)
		pushState(player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local session = sessions[player]
		if not session then
			return
		end
		for passName, id in Config.GamePasses do
			if id == passId then
				session.Passes[passName] = true
			end
		end
		pushState(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		releaseShop(player)
		sessions[player] = nil
	end)

	-- 店長走離櫃檯就自動打烊
	task.spawn(function()
		while true do
			task.wait(1)
			for actor, session in sessions do
				if session.CounterOpen then
					local shop = session.ShopId and shops[session.ShopId]
					local pos = TownService.GetPosition(actor)
					local tooFar = shop == nil or pos == nil or (pos - shop.Info.KeeperSpot.Position).Magnitude > Config.Town.CounterRange
					if tooFar or TownService.IsJailed(actor) then
						clearCustomer(session)
						session.CounterOpen = false
						notify(actor, "你離開櫃檯，店先打烊了。", true)
						pushState(actor)
					end
				end
			end
		end
	end)

	-- 銀河新聞輪播：開服先平靜一輪，之後每隔一段時間換一則
	task.spawn(function()
		while true do
			task.wait(Config.NewsInterval)
			currentNews = GalacticNews.Pick(rand, currentNews.Id)
			newsEndsAt = os.time() + Config.NewsInterval
			for player in sessions do
				pushState(player)
			end
		end
	end)
end

return ShopService
