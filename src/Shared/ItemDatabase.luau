--!strict
-- 物品資料庫：所有可典當的宇宙物品，以及它們的鑑定特徵。
--
-- 新增物品只要在 Items 裡加一筆，不需要改 UI 或議價邏輯。
--
-- 每個物品的 InspectionAttributes：
--   FakeChance  這件物品是假貨的機率（0~1）
--   FakeTell    用哪個工具（Tool）能分辨真假，以及真品 / 假貨時看到的描述
--   Defect      可能的瑕疵：用哪個工具能發現、出現機率、對價值的影響
--
-- 「實例」(ItemInstance) 是某位客人帶來的那一件：它是不是假貨、有沒有瑕疵，
-- 只存在伺服器端，玩家必須靠工具鑑定才知道。
-- Variant（變種）則是公開的：閃亮版價值 ×3、彩虹版價值 ×10，客人開價也會跟著變高。

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type FakeTell = {
	Tool: string,
	RealText: string,
	FakeText: string,
}

export type Defect = {
	Type: string,
	DisplayName: string,
	Tool: string,
	Chance: number,
	ValueMultiplier: number,
	FoundText: string,
	CleanText: string,
}

export type ItemDef = {
	ID: string,
	Name: string,
	Description: string,
	Category: string,
	BaseValue: number,
	Rarity: Rarity,
	MinReputation: number,
	InspectionAttributes: {
		FakeChance: number,
		FakeTell: FakeTell,
		Defect: Defect,
	},
}

export type ItemInstance = {
	ItemId: string,
	IsFake: boolean,
	DefectType: string?,
	Variant: string?,
}

export type Finding = {
	Text: string,
	Tone: string, -- "good" | "bad" | "neutral"
}

local ItemDatabase = {}

ItemDatabase.RarityNames = {
	Common = "普通",
	Rare = "稀有",
	Epic = "史詩",
	Legendary = "傳說",
}

-- 抽客人時各稀有度的權重
ItemDatabase.RarityWeights = {
	Common = 60,
	Rare = 28,
	Epic = 10,
	Legendary = 2,
}

ItemDatabase.CategoryNames = {
	Creature = "生物",
	Weapon = "武器",
	Treasure = "寶藏",
	Tech = "科技",
	Relic = "神秘遺物",
	Food = "美食",
}

-- 變種：Rank 越大越稀有
ItemDatabase.Variants = {
	Normal = { Name = "", Multiplier = 1, Rank = 0 },
	Shiny = { Name = "閃亮", Multiplier = 3, Rank = 1 },
	Rainbow = { Name = "彩虹", Multiplier = 10, Rank = 2 },
}

local Items: { ItemDef } = {
	-- 名聲 0：開店就會遇到 ------------------------------------------------------
	{
		ID = "Item_009",
		Name = "會跳舞的外星香蕉",
		Description = "放在桌上會自己扭來扭去。據說吃了會停不下來一直跳舞。",
		Category = "Food",
		BaseValue = 80,
		Rarity = "Common",
		MinReputation = 0,
		InspectionAttributes = {
			FakeChance = 0.25,
			FakeTell = { Tool = "Magnifier", RealText = "香蕉皮上有細小的外星斑點，而且還在扭動。真貨！", FakeText = "只是普通香蕉貼了一對塑膠眼睛…" },
			Defect = { Type = "Overripe", DisplayName = "熟過頭", Tool = "XRay", Chance = 0.25, ValueMultiplier = 0.6, FoundText = "X 光顯示裡面已經熟到變黑了。", CleanText = "X 光下果肉新鮮飽滿。" },
		},
	},
	{
		ID = "Item_001",
		Name = "虛空巨獸的牙齒",
		Description = "據說來自吞掉整顆衛星的虛空巨獸。牙尖還在微微發光。",
		Category = "Creature",
		BaseValue = 120,
		Rarity = "Common",
		MinReputation = 0,
		InspectionAttributes = {
			FakeChance = 0.25,
			FakeTell = { Tool = "Magnifier", RealText = "齒面有一圈圈天然的生長紋路，是真的牙齒。", FakeText = "牙根有一條模具接縫，這是樹脂倒模出來的！" },
			Defect = { Type = "Crack", DisplayName = "內部裂痕", Tool = "XRay", Chance = 0.25, ValueMultiplier = 0.6, FoundText = "X 光顯示牙齒內部有一道很深的裂痕。", CleanText = "X 光下內部結構完整。" },
		},
	},
	{
		ID = "Item_010",
		Name = "太空貓的毛球",
		Description = "太空貓吐出來的毛球，摸起來軟軟的，聞起來像星塵。",
		Category = "Creature",
		BaseValue = 150,
		Rarity = "Common",
		MinReputation = 0,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "UVLight", RealText = "紫外線下毛球發出星空般的螢光，是太空貓的沒錯。", FakeText = "紫外線下毫無反應，這是地球貓的毛。" },
			Defect = { Type = "Sticky", DisplayName = "黏到口香糖", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.7, FoundText = "毛球裡纏著一塊嚼過的口香糖…", CleanText = "毛球乾淨蓬鬆。" },
		},
	},
	{
		ID = "Item_004",
		Name = "星際帝國金幣",
		Description = "已經滅亡的帝國發行的金幣，收藏家很愛。",
		Category = "Treasure",
		BaseValue = 200,
		Rarity = "Common",
		MinReputation = 0,
		InspectionAttributes = {
			FakeChance = 0.35,
			FakeTell = { Tool = "UVLight", RealText = "紫外線下浮現帝國鷹徽防偽印記，是真幣。", FakeText = "紫外線下一片空白，沒有防偽印記。假幣！" },
			Defect = { Type = "Worn", DisplayName = "嚴重磨損", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.8, FoundText = "幣面圖案幾乎磨平了。", CleanText = "幣面圖案清晰銳利。" },
		},
	},
	{
		ID = "Item_002",
		Name = "古老雷射槍",
		Description = "第三次銀河大戰時期的制式武器。客人說「還能射」。",
		Category = "Weapon",
		BaseValue = 300,
		Rarity = "Common",
		MinReputation = 0,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "XRay", RealText = "X 光下能量線圈完整，是真正的軍用品。", FakeText = "X 光一照，外殼裡面是空的，只塞了一顆燈泡！" },
			Defect = { Type = "Burnt", DisplayName = "槍管燒毀", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.7, FoundText = "槍口有嚴重的燒焦痕跡，槍管可能已經壞了。", CleanText = "槍口乾淨，沒有過熱痕跡。" },
		},
	},
	{
		ID = "Item_003",
		Name = "外星隕石核",
		Description = "從墜落的流星中心挖出來的，摸起來是溫的。",
		Category = "Treasure",
		BaseValue = 500,
		Rarity = "Rare",
		MinReputation = 0,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "Analyzer", RealText = "成分分析：含有地表不存在的超重元素，真品！", FakeText = "成分分析：只是普通玄武岩加上螢光漆。" },
			Defect = { Type = "Chipped", DisplayName = "缺角", Tool = "Magnifier", Chance = 0.25, ValueMultiplier = 0.75, FoundText = "邊緣缺了一大塊，賣相變差了。", CleanText = "表面完整，沒有缺角。" },
		},
	},

	-- 名聲 5 ~ 15 --------------------------------------------------------------
	{
		ID = "Item_011",
		Name = "黑洞口香糖",
		Description = "吹出來的泡泡會把附近的小東西吸進去。請勿在教室使用。",
		Category = "Food",
		BaseValue = 260,
		Rarity = "Common",
		MinReputation = 5,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "XRay", RealText = "X 光竟然被它吸進去了！是真的黑洞口香糖。", FakeText = "X 光下只是一塊普通的葡萄口香糖。" },
			Defect = { Type = "Chewed", DisplayName = "被嚼過", Tool = "Magnifier", Chance = 0.25, ValueMultiplier = 0.5, FoundText = "上面有一排牙印…這塊已經被嚼過了。", CleanText = "包裝完好，沒有被打開過。" },
		},
	},
	{
		ID = "Item_012",
		Name = "電漿水槍",
		Description = "外星小孩的玩具。噴出來的不是水，是會發光的電漿。",
		Category = "Weapon",
		BaseValue = 420,
		Rarity = "Rare",
		MinReputation = 8,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "Magnifier", RealText = "底部刻著外星兵工廠的序號，是真貨。", FakeText = "底部寫著「地球製造，適用 3 歲以上」。" },
			Defect = { Type = "Leak", DisplayName = "電漿槽破裂", Tool = "XRay", Chance = 0.3, ValueMultiplier = 0.7, FoundText = "X 光顯示電漿槽有一道裂縫，會漏。", CleanText = "X 光下電漿槽密封良好。" },
		},
	},
	{
		ID = "Item_005",
		Name = "會唱歌的水晶",
		Description = "放在手心會哼出一段沒人聽過的旋律。",
		Category = "Relic",
		BaseValue = 650,
		Rarity = "Rare",
		MinReputation = 10,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "Magnifier", RealText = "水晶內部純淨，聲音是晶體本身共振發出的。", FakeText = "仔細一看，水晶裡面藏了一個小喇叭！" },
			Defect = { Type = "Cloudy", DisplayName = "內部混濁", Tool = "UVLight", Chance = 0.3, ValueMultiplier = 0.65, FoundText = "紫外線下看到內部有大片混濁，音色會走音。", CleanText = "紫外線下晶體清澈透亮。" },
		},
	},
	{
		ID = "Item_021",
		Name = "迷你 UFO 遙控車",
		Description = "真的會飛的遙控飛碟，還會發出「嗶嗶」的外星語。",
		Category = "Tech",
		BaseValue = 480,
		Rarity = "Rare",
		MinReputation = 12,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "UVLight", RealText = "紫外線下浮現反重力線圈的光紋，是真的 UFO。", FakeText = "紫外線下沒有光紋，只是普通遙控車噴了銀漆。" },
			Defect = { Type = "MissingButton", DisplayName = "遙控器缺按鈕", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.8, FoundText = "遙控器上少了一顆按鈕。", CleanText = "遙控器按鈕齊全。" },
		},
	},
	{
		ID = "Item_013",
		Name = "史萊姆寵物蛋",
		Description = "軟軟 Q Q 的蛋，偶爾會自己晃一下。孵出來是什麼顏色沒人知道。",
		Category = "Creature",
		BaseValue = 700,
		Rarity = "Rare",
		MinReputation = 15,
		InspectionAttributes = {
			FakeChance = 0.3,
			FakeTell = { Tool = "XRay", RealText = "X 光下看到蛋裡有個小東西在動！", FakeText = "X 光下是實心的，這是石膏做的假蛋。" },
			Defect = { Type = "ThinShell", DisplayName = "蛋殼有裂紋", Tool = "UVLight", Chance = 0.3, ValueMultiplier = 0.6, FoundText = "紫外線下看到蛋殼上佈滿細紋，可能孵不出來。", CleanText = "紫外線下蛋殼完整。" },
		},
	},

	-- 名聲 20 ~ 45 -------------------------------------------------------------
	{
		ID = "Item_006",
		Name = "機器人記憶核心",
		Description = "一台退役管家機器人的記憶體，裡面也許還有秘密。",
		Category = "Tech",
		BaseValue = 900,
		Rarity = "Epic",
		MinReputation = 20,
		InspectionAttributes = {
			FakeChance = 0.35,
			FakeTell = { Tool = "Analyzer", RealText = "成分分析：量子矽晶片，是正廠核心。", FakeText = "成分分析：裡面是玩具機器人的塑膠晶片。" },
			Defect = { Type = "DataLoss", DisplayName = "記憶損毀", Tool = "XRay", Chance = 0.35, ValueMultiplier = 0.5, FoundText = "X 光顯示一半的記憶晶格已經燒掉了。", CleanText = "X 光下記憶晶格排列整齊。" },
		},
	},
	{
		ID = "Item_014",
		Name = "海盜船長的金牙",
		Description = "紅鬍子船長打架時掉的。他說誰撿到就是誰的。",
		Category = "Treasure",
		BaseValue = 1000,
		Rarity = "Epic",
		MinReputation = 25,
		InspectionAttributes = {
			FakeChance = 0.35,
			FakeTell = { Tool = "Analyzer", RealText = "成分分析：純度 99% 的星金！", FakeText = "成分分析：鍍金的塑膠。" },
			Defect = { Type = "Cavity", DisplayName = "有蛀洞", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.75, FoundText = "金牙上竟然有一個蛀洞。", CleanText = "金牙表面光滑閃亮。" },
		},
	},
	{
		ID = "Item_015",
		Name = "隱形斗篷",
		Description = "客人雙手捧著一團「空氣」，堅持說這是隱形斗篷。",
		Category = "Relic",
		BaseValue = 1200,
		Rarity = "Epic",
		MinReputation = 30,
		InspectionAttributes = {
			FakeChance = 0.4,
			FakeTell = { Tool = "UVLight", RealText = "紫外線下終於看到斗篷的輪廓了，是真貨！", FakeText = "紫外線下還是什麼都沒有…客人手上根本是空的！" },
			Defect = { Type = "Hole", DisplayName = "破了一個洞", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.7, FoundText = "用手摸得到一個破洞。", CleanText = "摸起來布料完整。" },
		},
	},
	{
		ID = "Item_007",
		Name = "被詛咒的面具",
		Description = "戴上它的人會聽見遠方星球的哭聲。客人急著脫手。",
		Category = "Relic",
		BaseValue = 1500,
		Rarity = "Epic",
		MinReputation = 35,
		InspectionAttributes = {
			FakeChance = 0.4,
			FakeTell = { Tool = "UVLight", RealText = "紫外線下浮現古老的符文，詛咒是真的…", FakeText = "紫外線下什麼都沒有，只是塗了黑漆的木頭。" },
			Defect = { Type = "Crack", DisplayName = "面具裂開", Tool = "XRay", Chance = 0.25, ValueMultiplier = 0.7, FoundText = "X 光顯示面具內側裂成兩半，只是用膠黏著。", CleanText = "X 光下面具完整無裂痕。" },
		},
	},
	{
		ID = "Item_016",
		Name = "火箭溜冰鞋",
		Description = "踩下去就會噴火往前衝。沒有煞車。",
		Category = "Tech",
		BaseValue = 1800,
		Rarity = "Epic",
		MinReputation = 40,
		InspectionAttributes = {
			FakeChance = 0.35,
			FakeTell = { Tool = "XRay", RealText = "X 光下看到鞋底裝著微型火箭引擎。", FakeText = "X 光下鞋底只塞了兩個寶特瓶。" },
			Defect = { Type = "NoFuel", DisplayName = "燃料漏光", Tool = "Analyzer", Chance = 0.3, ValueMultiplier = 0.6, FoundText = "成分分析：燃料槽是空的，燃料早就漏光了。", CleanText = "成分分析：燃料槽是滿的。" },
		},
	},
	{
		ID = "Item_017",
		Name = "迷你恐龍化石",
		Description = "來自恐龍星的小型暴龍骨架，只有手掌大。",
		Category = "Creature",
		BaseValue = 2200,
		Rarity = "Legendary",
		MinReputation = 45,
		InspectionAttributes = {
			FakeChance = 0.4,
			FakeTell = { Tool = "Analyzer", RealText = "成分分析：六千萬年前的骨頭，真品！", FakeText = "成分分析：這是用雞骨頭拼起來的。" },
			Defect = { Type = "Glued", DisplayName = "斷過再黏", Tool = "XRay", Chance = 0.3, ValueMultiplier = 0.6, FoundText = "X 光顯示尾巴斷成兩截，是用膠水黏回去的。", CleanText = "X 光下骨架完整。" },
		},
	},

	-- 名聲 50 以上 --------------------------------------------------------------
	{
		ID = "Item_008",
		Name = "遠古星圖",
		Description = "標示著一條早已被遺忘的超空間航道。",
		Category = "Relic",
		BaseValue = 2500,
		Rarity = "Legendary",
		MinReputation = 50,
		InspectionAttributes = {
			FakeChance = 0.45,
			FakeTell = { Tool = "Analyzer", RealText = "成分分析：墨水是三千年前的星塵墨，真品！", FakeText = "成分分析：墨水是上個星期才出廠的原子筆。" },
			Defect = { Type = "Torn", DisplayName = "破損", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.7, FoundText = "星圖右下角被撕掉了一塊。", CleanText = "星圖邊緣完整。" },
		},
	},
	{
		ID = "Item_018",
		Name = "無限披薩盒",
		Description = "不管拿出幾片，打開永遠還有一片熱騰騰的披薩。",
		Category = "Food",
		BaseValue = 3000,
		Rarity = "Legendary",
		MinReputation = 60,
		InspectionAttributes = {
			FakeChance = 0.4,
			FakeTell = { Tool = "Analyzer", RealText = "成分分析：盒子內部的空間比外面還大，是真的！", FakeText = "成分分析：普通紙盒，裡面只有吃剩的餅皮。" },
			Defect = { Type = "Moldy", DisplayName = "發霉", Tool = "UVLight", Chance = 0.3, ValueMultiplier = 0.6, FoundText = "紫外線下看到盒子角落有發霉的痕跡。", CleanText = "紫外線下盒子乾淨衛生。" },
		},
	},
	{
		ID = "Item_019",
		Name = "時光懷錶",
		Description = "按下按鈕可以回到 5 秒前。客人說他已經按了三次才敢走進來。",
		Category = "Relic",
		BaseValue = 4000,
		Rarity = "Legendary",
		MinReputation = 80,
		InspectionAttributes = {
			FakeChance = 0.45,
			FakeTell = { Tool = "XRay", RealText = "X 光下看到齒輪正在逆時針轉動！", FakeText = "X 光下裡面是便宜的電子錶機芯。" },
			Defect = { Type = "CrackedGlass", DisplayName = "錶面裂開", Tool = "Magnifier", Chance = 0.3, ValueMultiplier = 0.7, FoundText = "錶面玻璃有一道裂痕。", CleanText = "錶面玻璃完好。" },
		},
	},
	{
		ID = "Item_020",
		Name = "銀河之心寶石",
		Description = "傳說中整個銀河系最大的寶石，裡面看得到旋轉的星雲。",
		Category = "Treasure",
		BaseValue = 6000,
		Rarity = "Legendary",
		MinReputation = 100,
		InspectionAttributes = {
			FakeChance = 0.45,
			FakeTell = { Tool = "Analyzer", RealText = "成分分析：凝固的星雲核心，貨真價實！", FakeText = "成分分析：這是彈珠汽水瓶裡的玻璃珠。" },
			Defect = { Type = "Dim", DisplayName = "光芒黯淡", Tool = "UVLight", Chance = 0.3, ValueMultiplier = 0.65, FoundText = "紫外線下星雲幾乎不轉了，光芒很黯淡。", CleanText = "紫外線下星雲轉得很漂亮。" },
		},
	},
}

local byId: { [string]: ItemDef } = {}
for _, item in Items do
	byId[item.ID] = item
end

function ItemDatabase.Get(id: string): ItemDef?
	return byId[id]
end

function ItemDatabase.GetAll(): { ItemDef }
	return Items
end

function ItemDatabase.Count(): number
	return #Items
end

-- 目前名聲可以遇到的物品
function ItemDatabase.GetEligible(reputation: number): { ItemDef }
	local result = {}
	for _, item in Items do
		if item.MinReputation <= reputation then
			table.insert(result, item)
		end
	end
	return result
end

function ItemDatabase.GetVariantMultiplier(variant: string?): number
	local info = variant and ItemDatabase.Variants[variant] or nil
	return info and info.Multiplier or 1
end

-- 顯示用名稱，例如「【閃亮】虛空巨獸的牙齒」
function ItemDatabase.GetDisplayName(itemId: string, variant: string?): string
	local def = byId[itemId]
	local name = def and def.Name or "未知物品"
	local info = variant and ItemDatabase.Variants[variant] or nil
	if info and info.Name ~= "" then
		return "【" .. info.Name .. "】" .. name
	end
	return name
end

-- 這件物品「如果是完美真品」的價值（含變種倍率），議價時用這個數字
function ItemDatabase.GetEffectiveBase(instance: ItemInstance): number
	local def = byId[instance.ItemId]
	if not def then
		return 0
	end
	return def.BaseValue * ItemDatabase.GetVariantMultiplier(instance.Variant)
end

-- 這件物品在市場上的真實價值（假貨幾乎不值錢、瑕疵品打折）
function ItemDatabase.GetMarketValue(instance: ItemInstance): number
	local def = byId[instance.ItemId]
	if not def then
		return 0
	end
	local base = ItemDatabase.GetEffectiveBase(instance)
	if instance.IsFake then
		return math.max(1, math.floor(base * 0.05))
	end
	local defect = def.InspectionAttributes.Defect
	if instance.DefectType ~= nil and instance.DefectType == defect.Type then
		return math.floor(base * defect.ValueMultiplier)
	end
	return base
end

-- 用某個工具鑑定這件物品，回傳看到的結果
function ItemDatabase.Inspect(instance: ItemInstance, toolId: string): { Finding }
	local def = byId[instance.ItemId]
	local findings: { Finding } = {}
	if not def then
		return findings
	end

	local attrs = def.InspectionAttributes

	if attrs.FakeTell.Tool == toolId then
		if instance.IsFake then
			table.insert(findings, { Text = attrs.FakeTell.FakeText, Tone = "bad" })
		else
			table.insert(findings, { Text = attrs.FakeTell.RealText, Tone = "good" })
		end
	end

	if attrs.Defect.Tool == toolId then
		if instance.DefectType == attrs.Defect.Type then
			table.insert(findings, { Text = attrs.Defect.FoundText, Tone = "bad" })
		else
			table.insert(findings, { Text = attrs.Defect.CleanText, Tone = "good" })
		end
	end

	if #findings == 0 then
		table.insert(findings, { Text = "用這個工具看不出什麼特別的。", Tone = "neutral" })
	end

	return findings
end

return ItemDatabase
