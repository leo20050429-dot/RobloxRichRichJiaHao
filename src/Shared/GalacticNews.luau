--!strict
-- 銀河新聞：每隔一段時間換一則，影響某一類物品的市場賣價與假貨機率。
-- 新增新聞只要在 Events 裡加一筆。
--
-- 玩法上的意義：收購價不受新聞影響，但賣價會變，
-- 所以玩家可以把東西囤在倉庫，等對的新聞出現再賣。

export type NewsEvent = {
	Id: string,
	Title: string,
	Description: string,
	Category: string?, -- 影響的物品分類（nil = 沒有影響）
	PriceMultiplier: number, -- 該分類的市場賣價倍率
	FakeChanceBonus: number, -- 該分類的假貨機率加成
	Weight: number,
}

local GalacticNews = {}

GalacticNews.Events = {
	{ Id = "Calm", Title = "平靜的一天", Description = "銀河系今天沒什麼大事，市場價格正常。", Category = nil, PriceMultiplier = 1, FakeChanceBonus = 0, Weight = 3 },
	{ Id = "War", Title = "星際戰爭爆發！", Description = "武器的市場賣價變成 2 倍，但假貨也變多了。", Category = "Weapon", PriceMultiplier = 2, FakeChanceBonus = 0.15, Weight = 2 },
	{ Id = "FoodFest", Title = "銀河美食節開幕", Description = "美食類的市場賣價變成 2 倍！", Category = "Food", PriceMultiplier = 2, FakeChanceBonus = 0, Weight = 2 },
	{ Id = "GoldRush", Title = "小行星淘金熱", Description = "寶藏類的市場賣價變成 1.6 倍，假貨也跟著變多。", Category = "Treasure", PriceMultiplier = 1.6, FakeChanceBonus = 0.1, Weight = 2 },
	{ Id = "TechExpo", Title = "宇宙科技展", Description = "科技類的市場賣價變成 1.7 倍！", Category = "Tech", PriceMultiplier = 1.7, FakeChanceBonus = 0, Weight = 2 },
	{ Id = "MonsterShow", Title = "怪獸選美大賽", Description = "生物類的市場賣價變成 1.8 倍！", Category = "Creature", PriceMultiplier = 1.8, FakeChanceBonus = 0, Weight = 2 },
	{ Id = "CurseBan", Title = "帝國取締詛咒物品", Description = "神秘遺物變得很搶手，市場賣價 1.8 倍，但假貨大增。", Category = "Relic", PriceMultiplier = 1.8, FakeChanceBonus = 0.15, Weight = 2 },
} :: { NewsEvent }

function GalacticNews.Get(id: string): NewsEvent
	for _, event in GalacticNews.Events do
		if event.Id == id then
			return event
		end
	end
	return GalacticNews.Events[1]
end

-- 依權重隨機挑一則新聞（不會連續兩次一樣）
function GalacticNews.Pick(rand: () -> number, excludeId: string?): NewsEvent
	local pool = {}
	local total = 0
	for _, event in GalacticNews.Events do
		if event.Id ~= excludeId then
			table.insert(pool, event)
			total += event.Weight
		end
	end
	if #pool == 0 then
		return GalacticNews.Events[1]
	end
	local roll = rand() * total
	for _, event in pool do
		roll -= event.Weight
		if roll < 0 then
			return event
		end
	end
	return pool[#pool]
end

function GalacticNews.GetPriceMultiplier(event: NewsEvent?, category: string?): number
	if event and event.Category ~= nil and event.Category == category then
		return event.PriceMultiplier
	end
	return 1
end

function GalacticNews.GetFakeChanceBonus(event: NewsEvent?, category: string?): number
	if event and event.Category ~= nil and event.Category == category then
		return event.FakeChanceBonus
	end
	return 0
end

return GalacticNews
