-- 自動測試：只在 Studio 裡執行，結果印在 Output 視窗。
-- 按 Play 後看 Output，應該會出現「[SelfTest] 全部通過」。

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared:WaitForChild("Achievements"))
local Cargo = require(Shared:WaitForChild("Cargo"))
local Crime = require(Shared:WaitForChild("Crime"))
local Jobs = require(Shared:WaitForChild("Jobs"))
local BargainSystem = require(Shared:WaitForChild("BargainSystem"))
local CodexSystem = require(Shared:WaitForChild("CodexSystem"))
local Config = require(Shared:WaitForChild("Config"))
local GalacticNews = require(Shared:WaitForChild("GalacticNews"))
local Progression = require(Shared:WaitForChild("Progression"))
local CustomerGenerator = require(Shared:WaitForChild("CustomerGenerator"))
local ItemDatabase = require(Shared:WaitForChild("ItemDatabase"))
local PlayerDataSchema = require(Shared:WaitForChild("PlayerDataSchema"))
local Tools = require(Shared:WaitForChild("Tools"))

local passed, failed = 0, 0

local function check(name, condition)
	if condition then
		passed += 1
	else
		failed += 1
		warn("[SelfTest] 失敗：" .. name)
	end
end

local function test(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		failed += 1
		warn("[SelfTest] 出錯：" .. name .. " → " .. tostring(err))
	end
end

-- 固定序列的「隨機」函式
local function sequence(values)
	local i = 0
	return function()
		i = i % #values + 1
		return values[i]
	end
end

test("議價：底價與開價", function()
	local floorLow, askLow = BargainSystem.GetPrices(100, 0)
	local floorHigh, askHigh = BargainSystem.GetPrices(100, 1)
	check("不貪婪的底價 = 55", floorLow == 55)
	check("最貪婪的底價 = 90", floorHigh == 90)
	check("不貪婪的開價 = 115", askLow == 115)
	check("最貪婪的開價 = 150", askHigh == 150)
	check("開價 >= 底價", askLow >= floorLow and askHigh >= floorHigh)
end)

test("議價：出價達到底價就成交", function()
	local floorPrice = BargainSystem.GetPrices(200, 0.5)
	local result = BargainSystem.Negotiate(floorPrice, 200, 100, 0.5)
	check("成交", result.Success == true)
	check("成交價 = 出價", result.FinalPrice == floorPrice)
	check("成交不扣耐心", result.NewPatience == 100)
end)

test("議價：出價太低會扣耐心並還價", function()
	local floorPrice, askingPrice = BargainSystem.GetPrices(200, 0.5)
	local result = BargainSystem.Negotiate(floorPrice - 1, 200, 100, 0.5)
	check("不成交", result.Success == false)
	check("沒有破局", result.DealFailed == false)
	check("耐心減少", result.NewPatience < 100)
	check("有還價", result.CounterOffer ~= nil)
	check("還價介於底價與開價", result.CounterOffer >= floorPrice and result.CounterOffer <= askingPrice)
end)

test("議價：亂砍價扣比較多", function()
	local small = BargainSystem.Negotiate(100, 200, 100, 0.5)
	local big = BargainSystem.Negotiate(1, 200, 100, 0.5)
	check("差距越大扣越多", big.NewPatience < small.NewPatience)
end)

test("議價：耐心歸零就破局", function()
	local result = BargainSystem.Negotiate(1, 200, 10, 0.5)
	check("破局", result.DealFailed == true)
	check("耐心 = 0", result.NewPatience == 0)
end)

test("議價：不合法的出價", function()
	local nan = 0 / 0
	for _, bad in { 0, -5, nan, math.huge } do
		local result = BargainSystem.Negotiate(bad, 200, 50, 0.5)
		check("不合法出價不成交：" .. tostring(bad), result.Success == false and result.DealFailed == false)
		check("不合法出價不扣耐心：" .. tostring(bad), result.NewPatience == 50)
	end
end)

test("物品資料庫：每件物品都設定正確", function()
	for _, item in ItemDatabase.GetAll() do
		local attrs = item.InspectionAttributes
		check(item.ID .. " 的 FakeTell 工具存在", Tools.List[attrs.FakeTell.Tool] ~= nil)
		check(item.ID .. " 的 Defect 工具存在", Tools.List[attrs.Defect.Tool] ~= nil)
		check(item.ID .. " 的稀有度有權重", ItemDatabase.RarityWeights[item.Rarity] ~= nil)
		check(item.ID .. " 的機率在 0~1", attrs.FakeChance >= 0 and attrs.FakeChance <= 1 and attrs.Defect.Chance >= 0 and attrs.Defect.Chance <= 1)
		check(item.ID .. " 可以用 Get 找到", ItemDatabase.Get(item.ID) == item)
	end
	check("開店時就有物品可以遇到", #ItemDatabase.GetEligible(0) > 0)
end)

test("物品資料庫：市場價值", function()
	local item = ItemDatabase.Get("Item_002")
	local defect = item.InspectionAttributes.Defect
	check("真品 = 基礎價值", ItemDatabase.GetMarketValue({ ItemId = "Item_002", IsFake = false }) == item.BaseValue)
	check("假貨 = 5%", ItemDatabase.GetMarketValue({ ItemId = "Item_002", IsFake = true }) == math.floor(item.BaseValue * 0.05))
	check("瑕疵品打折", ItemDatabase.GetMarketValue({ ItemId = "Item_002", IsFake = false, DefectType = defect.Type }) == math.floor(item.BaseValue * defect.ValueMultiplier))
	check("未知物品 = 0", ItemDatabase.GetMarketValue({ ItemId = "Nope", IsFake = false }) == 0)
end)

test("物品資料庫：鑑定", function()
	local item = ItemDatabase.Get("Item_002")
	local attrs = item.InspectionAttributes
	local fake = ItemDatabase.Inspect({ ItemId = "Item_002", IsFake = true }, attrs.FakeTell.Tool)
	check("用對的工具會看出假貨", fake[1].Text == attrs.FakeTell.FakeText and fake[1].Tone == "bad")
	local real = ItemDatabase.Inspect({ ItemId = "Item_002", IsFake = false }, attrs.FakeTell.Tool)
	check("用對的工具會確認真品", real[1].Text == attrs.FakeTell.RealText and real[1].Tone == "good")
	local defect = ItemDatabase.Inspect({ ItemId = "Item_002", IsFake = false, DefectType = attrs.Defect.Type }, attrs.Defect.Tool)
	check("用對的工具會看出瑕疵", defect[1].Text == attrs.Defect.FoundText)
	local nothing = ItemDatabase.Inspect({ ItemId = "Item_002", IsFake = true }, "Analyzer")
	check("不相關的工具看不出東西", #nothing == 1 and nothing[1].Tone == "neutral")
end)

test("客人產生器", function()
	local customer = CustomerGenerator.Generate(0, sequence({ 0.1, 0.9, 0.5, 0.3, 0.7 }), "test-id")
	local def = ItemDatabase.Get(customer.Item.ItemId)
	check("物品存在", def ~= nil)
	check("名聲 0 只會遇到門檻 0 的物品", def.MinReputation == 0)
	check("耐心從 100 開始", customer.Patience == 100)
	check("目前開價 = 開價", customer.CurrentAsk == customer.AskingPrice)
	check("使用傳入的 id", customer.Id == "test-id")
	check("假貨不會同時有瑕疵", not (customer.Item.IsFake and customer.Item.DefectType ~= nil))

	-- 極端的隨機值也不會出錯
	for _, value in { 0, 0.999999 } do
		local c = CustomerGenerator.Generate(100, function()
			return value
		end)
		check("極端隨機值也能產生客人：" .. tostring(value), ItemDatabase.Get(c.Item.ItemId) ~= nil)
	end
end)

test("存檔結構", function()
	local fresh = PlayerDataSchema.New()
	check("初始星幣 300", fresh.Credits == 300)
	check("初始有放大鏡", fresh.UnlockedTools.Magnifier == true)
	fresh.Inventory[1] = { Uid = "x" }
	check("New 是深拷貝", #PlayerDataSchema.Template.Inventory == 0)

	local old = { Credits = 42, UnlockedTools = { XRay = true } }
	local reconciled = PlayerDataSchema.Reconcile(old)
	check("Reconcile 保留舊值", reconciled.Credits == 42 and reconciled.UnlockedTools.XRay == true)
	check("Reconcile 補上新欄位", reconciled.Stats ~= nil and reconciled.Stats.DealsMade == 0 and reconciled.Reputation == 0)
	check("Reconcile 補上放大鏡", reconciled.UnlockedTools.Magnifier == true)
	check("Reconcile 處理壞資料", PlayerDataSchema.Reconcile("garbage").Credits == 300)
end)

test("經濟：認真鑑定、照底價收購的真品一定賺", function()
	for _, item in ItemDatabase.GetAll() do
		local floorHigh = BargainSystem.GetPrices(item.BaseValue, 1)
		check(item.ID .. " 最貪婪客人的底價 < 市價", floorHigh < item.BaseValue)
	end
end)

test("變種：閃亮與彩虹", function()
	local base = ItemDatabase.Get("Item_002").BaseValue
	check("閃亮版價值 ×3", ItemDatabase.GetMarketValue({ ItemId = "Item_002", IsFake = false, Variant = "Shiny" }) == base * 3)
	check("彩虹版價值 ×10", ItemDatabase.GetMarketValue({ ItemId = "Item_002", IsFake = false, Variant = "Rainbow" }) == base * 10)
	check("閃亮假貨還是不值錢", ItemDatabase.GetMarketValue({ ItemId = "Item_002", IsFake = true, Variant = "Shiny" }) == math.floor(base * 3 * 0.05))
	check("顯示名稱有變種標記", ItemDatabase.GetDisplayName("Item_002", "Shiny") == "【閃亮】" .. ItemDatabase.Get("Item_002").Name)
	check("普通版名稱不變", ItemDatabase.GetDisplayName("Item_002", "Normal") == ItemDatabase.Get("Item_002").Name)

	-- 第 2 次隨機值決定變種
	local rainbow = CustomerGenerator.Generate(0, sequence({ 0.1, 0.001, 0.9, 0.9, 0.5 }))
	check("隨機值很小時出彩虹版", rainbow.Item.Variant == "Rainbow")
	local shiny = CustomerGenerator.Generate(0, sequence({ 0.1, 0.03, 0.9, 0.9, 0.5 }))
	check("隨機值偏小時出閃亮版", shiny.Item.Variant == "Shiny")
	local normal = CustomerGenerator.Generate(0, sequence({ 0.1, 0.5, 0.9, 0.9, 0.5 }))
	check("一般情況是普通版", normal.Item.Variant == "Normal")
	local shinyFloor = BargainSystem.GetPrices(ItemDatabase.Get(shiny.Item.ItemId).BaseValue * 3, shiny.Greed)
	check("閃亮版的底價跟著變高", shiny.Floor == shinyFloor)

	local patient = CustomerGenerator.Generate(0, sequence({ 0.5 }), nil, { Patience = 125 })
	check("可以指定初始耐心", patient.Patience == 125 and patient.MaxPatience == 125)
end)

test("銀河新聞", function()
	local war = GalacticNews.Get("War")
	check("戰爭讓武器變貴", GalacticNews.GetPriceMultiplier(war, "Weapon") == 2)
	check("戰爭不影響美食", GalacticNews.GetPriceMultiplier(war, "Food") == 1)
	check("戰爭讓武器假貨變多", GalacticNews.GetFakeChanceBonus(war, "Weapon") > 0)
	check("平靜的一天沒有影響", GalacticNews.GetPriceMultiplier(GalacticNews.Get("Calm"), "Weapon") == 1)
	check("沒有新聞也不會出錯", GalacticNews.GetPriceMultiplier(nil, "Weapon") == 1)
	for _, value in { 0, 0.5, 0.999999 } do
		local picked = GalacticNews.Pick(function()
			return value
		end, "War")
		check("挑新聞不會連續重複：" .. tostring(value), picked ~= nil and picked.Id ~= "War")
	end
	local categories = {}
	for _, item in ItemDatabase.GetAll() do
		categories[item.Category] = true
		check(item.ID .. " 的分類有中文名稱", ItemDatabase.CategoryNames[item.Category] ~= nil)
	end
	for _, event in GalacticNews.Events do
		check(event.Id .. " 影響的分類存在", event.Category == nil or categories[event.Category] == true)
	end
end)

test("圖鑑與套裝", function()
	local codex = {}
	local isNew, isUpgrade = CodexSystem.Record(codex, "Item_001", "Normal")
	check("第一次收購是新物品", isNew == true and isUpgrade == false)
	isNew, isUpgrade = CodexSystem.Record(codex, "Item_001", "Normal")
	check("重複收購不算新", isNew == false and isUpgrade == false)
	isNew, isUpgrade = CodexSystem.Record(codex, "Item_001", "Shiny")
	check("閃亮版算升級", isNew == false and isUpgrade == true and codex.Item_001 == "Shiny")
	CodexSystem.Record(codex, "Item_001", "Normal")
	check("普通版不會蓋掉閃亮版", codex.Item_001 == "Shiny")
	check("舊存檔的 true 當成普通版", CodexSystem.VariantRank(true) == 0)
	check("圖鑑數量", CodexSystem.Count(codex) == 1 and CodexSystem.ShinyCount(codex) == 1)

	for _, set in CodexSystem.Sets do
		for _, itemId in set.Items or {} do
			check(set.Id .. " 裡的 " .. itemId .. " 存在", ItemDatabase.Get(itemId) ~= nil)
		end
		check(set.Id .. " 有條件", (set.Items ~= nil and #set.Items > 0) or (set.ShinyCount ~= nil and set.ShinyCount > 0))
	end

	local data = { Codex = {} }
	local bonuses, completed = CodexSystem.CheckSetBonus(data)
	check("空圖鑑沒有加成", bonuses.SellBonus == 0 and bonuses.Patience == 0 and bonuses.Reputation == 0 and next(completed) == nil)
	for _, itemId in { "Item_009", "Item_011", "Item_018" } do
		CodexSystem.Record(data.Codex, itemId, "Normal")
	end
	bonuses, completed = CodexSystem.CheckSetBonus(data)
	check("集齊美食套裝得到耐心加成", completed.Foodie == true and bonuses.Patience == 10)
	local emptyBonuses = CodexSystem.CheckSetBonus(nil)
	check("壞資料不會出錯", emptyBonuses.SellBonus == 0)
end)

test("成就", function()
	local stats = { DealsMade = 1, ItemsSold = 0, TotalProfit = 0 }
	local newly = Achievements.CheckNew({}, stats)
	check("第一筆收購達成開張大吉", #newly == 1 and newly[1].Id == "FirstDeal")
	check("領過的成就不會再發", #Achievements.CheckNew({ FirstDeal = true }, stats) == 0)
	local ids = {}
	for _, def in Achievements.List do
		check(def.Id .. " 沒有重複", ids[def.Id] == nil)
		ids[def.Id] = true
		check(def.Id .. " 的目標與獎勵是正數", def.Goal > 0 and def.Reward > 0)
	end
	check("進度不會超過目標", Achievements.GetProgress(Achievements.List[1], { DealsMade = 99 }) == Achievements.List[1].Goal)
end)

test("稱號與每日獎勵", function()
	local rank, nextRank = Progression.GetRank(0)
	check("名聲 0 是第一個稱號", rank == Config.Ranks[1] and nextRank == Config.Ranks[2])
	rank, nextRank = Progression.GetRank(99999)
	check("名聲很高是最後一個稱號", rank == Config.Ranks[#Config.Ranks] and nextRank == nil)

	local daily = { LastDay = 0, Streak = 0 }
	check("新玩家可以領", Progression.ClaimDaily(daily, 100) == Config.DailyRewards[1] and daily.Streak == 1)
	check("同一天不能再領", Progression.ClaimDaily(daily, 100) == nil)
	check("隔天連續登入", Progression.ClaimDaily(daily, 101) == Config.DailyRewards[2] and daily.Streak == 2)
	check("中斷後重新計算", Progression.ClaimDaily(daily, 105) == Config.DailyRewards[1] and daily.Streak == 1)
	daily = { LastDay = 200, Streak = 50 }
	check("連續很多天維持最高獎勵", Progression.ClaimDaily(daily, 201) == Config.DailyRewards[#Config.DailyRewards])
end)

test("兌換碼設定", function()
	for code, reward in Config.Codes do
		check("兌換碼 " .. code .. " 是大寫英數字", string.upper(code) == code and string.match(code, "^%w+$") ~= nil)
		check("兌換碼 " .. code .. " 的獎勵是正數", type(reward) == "number" and reward > 0)
	end
end)

test("職業", function()
	check("有三個職業", #Jobs.List == 3)
	for _, id in { "Pawnbroker", "Merchant", "Guard" } do
		check("職業存在：" .. id, Jobs.IsValid(id) and Jobs.Get(id) ~= nil)
	end
	check("不存在的職業", not Jobs.IsValid("Ninja") and not Jobs.IsValid(nil) and Jobs.Get(nil) == nil)
end)

test("貨物與收購商", function()
	for pointId, point in Cargo.Points do
		for _, drop in point.Drops do
			check(pointId .. " 掉落的資源存在：" .. drop.Resource, Cargo.Resources[drop.Resource] ~= nil)
		end
		local relic = Cargo.RollDrop(pointId, function()
			return 0
		end)
		check(pointId .. " 隨機值 0 會挖到遺物", relic ~= nil and relic.Kind == "Relic")
		local resource = Cargo.RollDrop(pointId, function()
			return 0.999
		end)
		check(pointId .. " 隨機值很大會拿到資源", resource ~= nil and resource.Kind == "Resource" and Cargo.Resources[resource.Resource] ~= nil)
	end
	check("不存在的採集點", Cargo.RollDrop("Moon", math.random) == nil)

	local ore = { Kind = "Resource", Resource = "StarOre", Stolen = false }
	local stolenOre = { Kind = "Resource", Resource = "StarOre", Stolen = true }
	check("貿易站收星礦", Cargo.Quote("TradingPost", ore) == math.floor(40 * 1.25 + 0.5))
	check("研究院收星礦比較便宜", Cargo.Quote("Institute", ore) < Cargo.Quote("TradingPost", ore))
	check("行情倍率有效", Cargo.Quote("TradingPost", ore, 2) == math.floor(40 * 1.25 * 2 + 0.5))
	check("貿易站不收贓物", Cargo.Quote("TradingPost", stolenOre) == nil)
	check("黑市收贓物", (Cargo.Quote("BlackMarket", stolenOre) or 0) > 0)
	check("黑市比較便宜", Cargo.Quote("BlackMarket", ore) < Cargo.Quote("TradingPost", ore))
	check("不存在的收購商", Cargo.Quote("Nope", ore) == nil)
	local relic = { Kind = "Relic", Item = { ItemId = "Item_002", IsFake = false, Variant = "Normal" }, Stolen = false }
	check("遺物報價 = 基礎價值 3 成", Cargo.Quote("TradingPost", relic) == math.floor(300 * 0.3))
	check("沒有物品的遺物不能賣", Cargo.Quote("TradingPost", { Kind = "Relic", Stolen = false }) == nil)
	check("贓物名稱有標記", string.find(Cargo.DisplayName(stolenOre), "贓物", 1, true) ~= nil)
	check("遺物名稱有標記", string.find(Cargo.DisplayName(relic), "遺物", 1, true) ~= nil)

	-- 每種資源在至少一個正當收購商的價格比黑市好
	for resourceId in Cargo.Resources do
		local item = { Kind = "Resource", Resource = resourceId, Stolen = false }
		local best = math.max(Cargo.Quote("TradingPost", item), Cargo.Quote("Institute", item))
		check(resourceId .. " 正當賣比黑市好", best > Cargo.Quote("BlackMarket", item))
	end
end)

test("犯罪規則", function()
	local base = {
		RobberJob = "Merchant",
		RobberJailed = false,
		RobberOnCooldown = false,
		RobberFreeSlots = 6,
		VictimJailed = false,
		VictimCargo = 4,
		VictimInSafeZone = false,
		VictimNewbie = false,
		VictimEscorted = false,
		RobberInSafeZone = false,
		Distance = 5,
		SameActor = false,
	}
	local function with(changes)
		local ctx = table.clone(base)
		for key, value in changes do
			ctx[key] = value
		end
		return ctx
	end
	check("一般情況可以搶", Crime.CanRob(base) == true)
	check("保鑣不能搶", Crime.CanRob(with({ RobberJob = "Guard" })) == false)
	check("不能搶自己", Crime.CanRob(with({ SameActor = true })) == false)
	check("坐牢不能搶", Crime.CanRob(with({ RobberJailed = true })) == false)
	check("冷卻中不能搶", Crime.CanRob(with({ RobberOnCooldown = true })) == false)
	check("太遠不能搶", Crime.CanRob(with({ Distance = 999 })) == false)
	check("安全區不能搶", Crime.CanRob(with({ VictimInSafeZone = true })) == false)
	check("自己在安全區也不能搶", Crime.CanRob(with({ RobberInSafeZone = true })) == false)
	check("新手保護", Crime.CanRob(with({ VictimNewbie = true })) == false)
	check("保鑣護送", Crime.CanRob(with({ VictimEscorted = true })) == false)
	check("對方沒貨", Crime.CanRob(with({ VictimCargo = 0 })) == false)
	check("自己沒空位", Crime.CanRob(with({ RobberFreeSlots = 0 })) == false)
	check("搶走一半（無條件進位）", Crime.RobCount(5, 10) == 3)
	check("至少搶 1 件", Crime.RobCount(1, 10) == 1)
	check("不超過自己的空位", Crime.RobCount(6, 2) == 2)
	check("通緝有上限", Crime.AddWanted(Config.Town.MaxWanted, 3) == Config.Town.MaxWanted)
	check("通緝會隨時間下降", Crime.DecayWanted(3, Config.Town.WantedDecay * 2 + 1) == 1)
	check("通緝不會變負的", Crime.DecayWanted(1, 99999) == 0)
	check("坐牢時間隨通緝增加", Crime.JailSeconds(3) == 3 * Config.Town.JailPerLevel)
	check("賞金隨通緝增加", Crime.Bounty(2) == 2 * Config.Town.BountyPerLevel)
	check("在方塊裡", Crime.InBox(Vector3.new(1, 1, 1), Vector3.zero, Vector3.new(4, 4, 4)))
	check("不在方塊裡", not Crime.InBox(Vector3.new(3, 0, 0), Vector3.zero, Vector3.new(4, 4, 4)))
end)

if failed == 0 then
	print(string.format("[SelfTest] 全部通過（%d 項檢查）", passed))
else
	warn(string.format("[SelfTest] %d 項通過，%d 項失敗", passed, failed))
end
