--!strict
-- 成就：某個統計數字達到目標就發獎勵星幣。
-- Stat 對應玩家存檔的 Stats 欄位；CodexCount 是伺服器另外算好放進來的。

local ItemDatabase = require(script.Parent.ItemDatabase)

export type AchievementDef = {
	Id: string,
	Name: string,
	Description: string,
	Stat: string,
	Goal: number,
	Reward: number,
}

local Achievements = {}

Achievements.List = {
	{ Id = "FirstDeal", Name = "開張大吉", Description = "完成第一筆收購", Stat = "DealsMade", Goal = 1, Reward = 50 },
	{ Id = "Sold10", Name = "小小商人", Description = "賣出 10 件物品", Stat = "ItemsSold", Goal = 10, Reward = 150 },
	{ Id = "Deals25", Name = "生意興隆", Description = "完成 25 筆收購", Stat = "DealsMade", Goal = 25, Reward = 300 },
	{ Id = "Deals100", Name = "百件達人", Description = "完成 100 筆收購", Stat = "DealsMade", Goal = 100, Reward = 1500 },
	{ Id = "Profit1000", Name = "第一桶金", Description = "累積賺到 1,000 星幣的差價", Stat = "TotalProfit", Goal = 1000, Reward = 200 },
	{ Id = "Profit10000", Name = "星際富翁", Description = "累積賺到 10,000 星幣的差價", Stat = "TotalProfit", Goal = 10000, Reward = 2000 },
	{ Id = "Spot5", Name = "火眼金睛", Description = "識破假貨並趕走 5 個騙子", Stat = "FakesSpotted", Goal = 5, Reward = 200 },
	{ Id = "Spot30", Name = "騙子剋星", Description = "識破假貨並趕走 30 個騙子", Stat = "FakesSpotted", Goal = 30, Reward = 1000 },
	{ Id = "Fooled3", Name = "交學費", Description = "被假貨騙了 3 次…送你一點安慰獎", Stat = "FakesSold", Goal = 3, Reward = 100 },
	{ Id = "Shiny1", Name = "閃閃發光", Description = "收購第一件閃亮或彩虹物品", Stat = "ShiniesFound", Goal = 1, Reward = 300 },
	{ Id = "Codex10", Name = "收藏家", Description = "圖鑑收集 10 種物品", Stat = "CodexCount", Goal = 10, Reward = 500 },
	{ Id = "CodexAll", Name = "圖鑑大師", Description = "圖鑑收集全部物品", Stat = "CodexCount", Goal = ItemDatabase.Count(), Reward = 3000 },
} :: { AchievementDef }

function Achievements.GetProgress(def: AchievementDef, stats: { [string]: number }): number
	local value = stats[def.Stat] or 0
	return math.clamp(math.floor(value), 0, def.Goal)
end

-- 回傳這次新達成的成就（done 是已經領過的成就 ID 表）
function Achievements.CheckNew(done: { [string]: boolean }, stats: { [string]: number }): { AchievementDef }
	local newly = {}
	for _, def in Achievements.List do
		if not done[def.Id] and (stats[def.Stat] or 0) >= def.Goal then
			table.insert(newly, def)
		end
	end
	return newly
end

return Achievements
