--!strict
-- 圖鑑與套裝加成。
--
-- 圖鑑 (codex) 的格式：{ [物品ID] = "Normal" | "Shiny" | "Rainbow" }，記錄收購過的最高變種。
-- （舊存檔裡的 true 會被當成 "Normal"。）
--
-- 套裝：集齊指定物品（或累積指定數量的閃亮 / 彩虹物品）就得到永久加成。
-- 加成種類：
--   SellBonus   市場賣價 +X（0.05 = +5%）
--   Patience    客人初始耐心 +X
--   Reputation  每賣出一件真品額外 +X 名聲

local ItemDatabase = require(script.Parent.ItemDatabase)

export type Bonus = { Type: string, Value: number }

export type SetDef = {
	Id: string,
	Name: string,
	Description: string,
	Items: { string }?,
	ShinyCount: number?,
	Bonus: Bonus,
}

export type Bonuses = {
	SellBonus: number,
	Patience: number,
	Reputation: number,
}

local CodexSystem = {}

CodexSystem.Sets = {
	{
		Id = "MonsterFan",
		Name = "怪獸研究員",
		Description = "集齊所有生物類物品 → 市場賣價 +5%",
		Items = { "Item_001", "Item_010", "Item_013", "Item_017" },
		Bonus = { Type = "SellBonus", Value = 0.05 },
	},
	{
		Id = "Foodie",
		Name = "美食獵人",
		Description = "集齊所有美食類物品 → 客人耐心 +10",
		Items = { "Item_009", "Item_011", "Item_018" },
		Bonus = { Type = "Patience", Value = 10 },
	},
	{
		Id = "Gearhead",
		Name = "軍火與科技迷",
		Description = "集齊所有武器與科技類物品 → 市場賣價 +5%",
		Items = { "Item_002", "Item_012", "Item_006", "Item_016", "Item_021" },
		Bonus = { Type = "SellBonus", Value = 0.05 },
	},
	{
		Id = "TreasureHunter",
		Name = "尋寶專家",
		Description = "集齊所有寶藏類物品 → 賣出真品時名聲 +1",
		Items = { "Item_003", "Item_004", "Item_014", "Item_020" },
		Bonus = { Type = "Reputation", Value = 1 },
	},
	{
		Id = "Mystic",
		Name = "神秘學大師",
		Description = "集齊所有神秘遺物 → 客人耐心 +15",
		Items = { "Item_005", "Item_007", "Item_008", "Item_015", "Item_019" },
		Bonus = { Type = "Patience", Value = 15 },
	},
	{
		Id = "ShinyCollector",
		Name = "閃亮收藏家",
		Description = "收購 5 種閃亮或彩虹物品 → 市場賣價 +10%",
		ShinyCount = 5,
		Bonus = { Type = "SellBonus", Value = 0.1 },
	},
} :: { SetDef }

-- 圖鑑裡這一格的變種等級：沒收集 = -1、普通 = 0、閃亮 = 1、彩虹 = 2
function CodexSystem.VariantRank(value: any): number
	if value == nil or value == false then
		return -1
	end
	if value == true then
		return 0
	end
	local info = ItemDatabase.Variants[value]
	return info and info.Rank or 0
end

-- 把一次收購記進圖鑑。回傳 (是不是新物品, 是不是更高級的變種)
function CodexSystem.Record(codex: { [string]: any }, itemId: string, variant: string?): (boolean, boolean)
	local newValue = variant or "Normal"
	local oldRank = CodexSystem.VariantRank(codex[itemId])
	local newRank = CodexSystem.VariantRank(newValue)
	if oldRank < 0 then
		codex[itemId] = newValue
		return true, newRank > 0
	end
	if newRank > oldRank then
		codex[itemId] = newValue
		return false, true
	end
	return false, false
end

function CodexSystem.Count(codex: { [string]: any }): number
	local count = 0
	for _, item in ItemDatabase.GetAll() do
		if CodexSystem.VariantRank(codex[item.ID]) >= 0 then
			count += 1
		end
	end
	return count
end

function CodexSystem.ShinyCount(codex: { [string]: any }): number
	local count = 0
	for _, item in ItemDatabase.GetAll() do
		if CodexSystem.VariantRank(codex[item.ID]) >= 1 then
			count += 1
		end
	end
	return count
end

-- 回傳 (已收集數, 需要的總數)
function CodexSystem.GetSetProgress(codex: { [string]: any }, set: SetDef): (number, number)
	if set.ShinyCount then
		return math.min(CodexSystem.ShinyCount(codex), set.ShinyCount), set.ShinyCount
	end
	local items = set.Items or {}
	local have = 0
	for _, itemId in items do
		if CodexSystem.VariantRank(codex[itemId]) >= 0 then
			have += 1
		end
	end
	return have, #items
end

function CodexSystem.IsSetComplete(codex: { [string]: any }, set: SetDef): boolean
	local have, total = CodexSystem.GetSetProgress(codex, set)
	return total > 0 and have >= total
end

-- 依玩家存檔算出目前所有套裝加成的總和，以及已完成的套裝 ID
function CodexSystem.CheckSetBonus(playerData: any): (Bonuses, { [string]: boolean })
	local codex = (type(playerData) == "table" and type(playerData.Codex) == "table") and playerData.Codex or {}
	local bonuses: Bonuses = { SellBonus = 0, Patience = 0, Reputation = 0 }
	local completed: { [string]: boolean } = {}
	for _, set in CodexSystem.Sets do
		if CodexSystem.IsSetComplete(codex, set) then
			completed[set.Id] = true
			local bonusType = set.Bonus.Type
			if bonusType == "SellBonus" then
				bonuses.SellBonus += set.Bonus.Value
			elseif bonusType == "Patience" then
				bonuses.Patience += set.Bonus.Value
			elseif bonusType == "Reputation" then
				bonuses.Reputation += set.Bonus.Value
			end
		end
	end
	return bonuses, completed
end

return CodexSystem
