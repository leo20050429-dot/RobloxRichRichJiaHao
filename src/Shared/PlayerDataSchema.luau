--!strict
-- 玩家存檔結構。新增欄位時加在 Template 裡，Reconcile 會自動補到舊存檔上。

export type InventoryEntry = {
	Uid: string,
	ItemId: string,
	IsFake: boolean,
	DefectType: string?,
	Variant: string?,
	PaidPrice: number,
	Findings: { string },
}

export type PlayerData = {
	Version: number,
	Credits: number,
	Reputation: number,
	UnlockedTools: { [string]: boolean },
	Inventory: { InventoryEntry },
	Codex: { [string]: any }, -- 物品 ID → 收購過的最高變種（"Normal" / "Shiny" / "Rainbow"）
	Daily: { LastDay: number, Streak: number },
	Achievements: { [string]: boolean },
	RedeemedCodes: { [string]: boolean },
	Insurance: number,
	LastJob: string,
	Stats: {
		DealsMade: number,
		ItemsSold: number,
		FakesSold: number,
		FakesSpotted: number,
		ShiniesFound: number,
		TotalProfit: number,
	},
}

local PlayerDataSchema = {}

PlayerDataSchema.Version = 1

PlayerDataSchema.Template = {
	Version = 1,
	Credits = 300, -- 開店資金
	Reputation = 0,
	UnlockedTools = { Magnifier = true },
	Inventory = {},
	Codex = {}, -- 圖鑑：物品 ID → 收購過的最高變種
	Daily = { LastDay = 0, Streak = 0 }, -- 每日登入獎勵
	Achievements = {}, -- 已達成的成就 ID → true
	RedeemedCodes = {}, -- 已兌換的兌換碼 → true
	Insurance = 0, -- 剩幾次搶劫保險
	LastJob = "", -- 上次選的職業
	Stats = {
		DealsMade = 0,
		ItemsSold = 0,
		FakesSold = 0,
		FakesSpotted = 0, -- 識破假貨後趕走客人的次數
		ShiniesFound = 0, -- 收購過的閃亮 / 彩虹物品數
		TotalProfit = 0,
	},
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

PlayerDataSchema.DeepCopy = deepCopy

function PlayerDataSchema.New(): PlayerData
	return deepCopy(PlayerDataSchema.Template)
end

-- 把 Template 有、舊存檔沒有的欄位補上（不覆蓋已有的值）
function PlayerDataSchema.Reconcile(data: any): PlayerData
	if type(data) ~= "table" then
		return PlayerDataSchema.New()
	end
	local function fill(target: any, template: any)
		for k, v in template do
			if target[k] == nil then
				target[k] = deepCopy(v)
			elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil then
				fill(target[k], v)
			end
		end
	end
	fill(data, PlayerDataSchema.Template)
	data.Version = PlayerDataSchema.Version
	return data
end

return PlayerDataSchema
