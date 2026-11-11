--!strict
-- 商人的貨物：資源種類、採集地點、收購商（不同地方收購價不一樣）。
--
-- 身上的一件貨物（CargoItem）可能是：
--   資源：{ Kind = "Resource", Resource = "StarOre", Stolen = false }
--   遺物：{ Kind = "Relic", Item = ItemInstance, Stolen = false }
--   （遺物就是當舖裡的那些物品，真假不明，可以賣給當舖）

local ItemDatabase = require(script.Parent.ItemDatabase)

export type CargoItem = {
	Kind: string,
	Resource: string?,
	Item: ItemDatabase.ItemInstance?,
	Stolen: boolean,
}

local Cargo = {}

Cargo.Resources = {
	StarOre = { Name = "星礦", BasePrice = 40, Color = { 0.55, 0.6, 0.95 } },
	AlienParts = { Name = "外星零件", BasePrice = 55, Color = { 0.5, 0.95, 0.6 } },
	EnergyCrystal = { Name = "能量水晶", BasePrice = 80, Color = { 1, 0.5, 0.85 } },
}

-- 採集地點：每次採集隨機得到 Drops 其中一種（依權重），另外有 RelicChance 機率挖到遺物
Cargo.Points = {
	Mine = {
		Name = "隕石礦場",
		Drops = { { Resource = "StarOre", Weight = 75 }, { Resource = "EnergyCrystal", Weight = 25 } },
		RelicChance = 0.12,
		HoldDuration = 1.2,
	},
	Crash = {
		Name = "飛碟墜毀點",
		Drops = { { Resource = "AlienParts", Weight = 80 }, { Resource = "EnergyCrystal", Weight = 20 } },
		RelicChance = 0.18,
		HoldDuration = 1.2,
	},
}

-- 收購商：Multipliers 是對各資源基礎價格的倍率；RelicRate 是收遺物時付「基礎價值」的幾成
Cargo.Buyers = {
	TradingPost = {
		Name = "貿易站",
		Multipliers = { StarOre = 1.25, AlienParts = 0.8, EnergyCrystal = 1.0 },
		RelicRate = 0.3,
		AcceptsStolen = false,
	},
	Institute = {
		Name = "研究院",
		Multipliers = { StarOre = 0.7, AlienParts = 1.4, EnergyCrystal = 1.2 },
		RelicRate = 0.3,
		AcceptsStolen = false,
	},
	BlackMarket = {
		Name = "黑市",
		Multipliers = { StarOre = 0.6, AlienParts = 0.6, EnergyCrystal = 0.6 },
		RelicRate = 0.2,
		AcceptsStolen = true,
	},
}

function Cargo.ResourceName(resource: string?): string
	local info = resource and Cargo.Resources[resource] or nil
	return info and info.Name or "貨物"
end

function Cargo.DisplayName(item: CargoItem): string
	local name
	if item.Kind == "Relic" and item.Item then
		name = "遺物：" .. ItemDatabase.GetDisplayName(item.Item.ItemId, item.Item.Variant)
	else
		name = Cargo.ResourceName(item.Resource)
	end
	if item.Stolen then
		name ..= "（贓物）"
	end
	return name
end

-- 決定這次採集得到什麼
function Cargo.RollDrop(pointId: string, rand: () -> number): CargoItem?
	local point = Cargo.Points[pointId]
	if not point then
		return nil
	end
	if rand() < point.RelicChance then
		return { Kind = "Relic", Stolen = false }
	end
	local total = 0
	for _, drop in point.Drops do
		total += drop.Weight
	end
	local roll = rand() * total
	for _, drop in point.Drops do
		roll -= drop.Weight
		if roll < 0 then
			return { Kind = "Resource", Resource = drop.Resource, Stolen = false }
		end
	end
	return { Kind = "Resource", Resource = point.Drops[#point.Drops].Resource, Stolen = false }
end

-- 這件貨物大約值多少（給搶劫保險、顯示用）
function Cargo.BaseValue(item: CargoItem): number
	if item.Kind == "Relic" and item.Item then
		return math.floor(ItemDatabase.GetEffectiveBase(item.Item) * 0.3)
	end
	local info = item.Resource and Cargo.Resources[item.Resource] or nil
	return info and info.BasePrice or 0
end

-- 某個收購商願意出多少（不收的話回傳 nil）
-- demand 是目前這種資源的市場行情倍率（預設 1）
function Cargo.Quote(buyerId: string, item: CargoItem, demand: number?): number?
	local buyer = Cargo.Buyers[buyerId]
	if not buyer then
		return nil
	end
	if item.Stolen and not buyer.AcceptsStolen then
		return nil
	end
	if item.Kind == "Relic" then
		if not item.Item then
			return nil
		end
		local def = ItemDatabase.Get(item.Item.ItemId)
		if not def then
			return nil
		end
		return math.max(1, math.floor(def.BaseValue * ItemDatabase.GetVariantMultiplier(item.Item.Variant) * buyer.RelicRate))
	end
	local info = item.Resource and Cargo.Resources[item.Resource] or nil
	if not info then
		return nil
	end
	local multiplier = buyer.Multipliers[item.Resource :: string] or 1
	return math.max(1, math.floor(info.BasePrice * multiplier * (demand or 1) + 0.5))
end

return Cargo
