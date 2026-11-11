--!strict
-- 隨機產生一位客人與他帶來的物品。
-- rand 是一個回傳 [0, 1) 的函式，由伺服器傳入（測試時可以傳固定值）。

local BargainSystem = require(script.Parent.BargainSystem)
local Config = require(script.Parent.Config)
local ItemDatabase = require(script.Parent.ItemDatabase)

export type Customer = {
	Id: string,
	Name: string,
	Species: string,
	Color: { number },
	Greeting: string,
	LastLine: string,
	Item: ItemDatabase.ItemInstance,
	Greed: number,
	Patience: number,
	MaxPatience: number,
	Floor: number,
	AskingPrice: number,
	CurrentAsk: number,
}

export type Options = {
	Patience: number?, -- 客人的初始耐心（預設 100）
	FakeChanceBonus: ((ItemDatabase.ItemDef) -> number)?, -- 額外的假貨機率（例如銀河新聞）
	ShinyChance: number?,
	RainbowChance: number?,
}

local CustomerGenerator = {}

local PROFILES = {
	{ Name = "格洛克", Species = "沼澤星人", Color = { 0.45, 0.8, 0.35 } },
	{ Name = "紅鬍子", Species = "太空海盜", Color = { 0.85, 0.3, 0.25 } },
	{ Name = "奇奇", Species = "流浪商人", Color = { 0.95, 0.75, 0.3 } },
	{ Name = "茲布-札布", Species = "雙頭星人", Color = { 0.6, 0.4, 0.9 } },
	{ Name = "諾娃", Species = "星雲精靈", Color = { 0.4, 0.75, 0.95 } },
	{ Name = "布魯姆", Species = "岩石族", Color = { 0.6, 0.55, 0.5 } },
	{ Name = "嗶嗶-7", Species = "流浪機器人", Color = { 0.75, 0.8, 0.85 } },
	{ Name = "蜜拉", Species = "觸手族", Color = { 0.95, 0.45, 0.7 } },
	{ Name = "噗噗", Species = "果凍星人", Color = { 0.5, 0.95, 0.8 } },
	{ Name = "阿土伯", Species = "太空農夫", Color = { 0.8, 0.6, 0.4 } },
}

local GREETINGS = {
	"嘿，老闆！看看這個寶貝。",
	"我急需星幣，這個便宜賣你。",
	"這可是傳家寶，要不是缺錢我才不賣。",
	"別問我從哪弄來的，你要不要？",
	"我在小行星帶撿到的，應該很值錢吧？",
	"聽說你這裡最識貨，我就直接來了。",
	"我媽叫我把房間清乾淨，所以這個賣你。",
	"噓…小聲一點，這個東西很厲害。",
}

local VARIANT_GREETINGS = {
	"你看你看！這個會發光耶，一定超值錢！",
	"我從來沒看過這麼亮的，你一定要收！",
}

local function pick<T>(list: { T }, rand: () -> number): T
	local index = math.clamp(1 + math.floor(rand() * #list), 1, #list)
	return list[index]
end

local function pickItem(reputation: number, rand: () -> number): ItemDatabase.ItemDef
	local pool = ItemDatabase.GetEligible(reputation)
	if #pool == 0 then
		pool = ItemDatabase.GetAll()
	end
	-- 名聲越高，越容易遇到稀有的客人
	local rareBoost = 1 + reputation / 50
	local weights = {}
	local total = 0
	for i, item in pool do
		local w = ItemDatabase.RarityWeights[item.Rarity] or 1
		if item.Rarity ~= "Common" then
			w *= rareBoost
		end
		weights[i] = w
		total += w
	end
	local roll = rand() * total
	for i, item in pool do
		roll -= weights[i]
		if roll < 0 then
			return item
		end
	end
	return pool[#pool]
end

-- 由指定的物品產生一位客人（例如玩家商人寄賣的遺物）
function CustomerGenerator.FromItem(instance: ItemDatabase.ItemInstance, name: string, species: string, greed: number, id: string?): Customer
	local floorPrice, askingPrice = BargainSystem.GetPrices(ItemDatabase.GetEffectiveBase(instance), greed)
	local greeting = "我在城外挖到這個，你看值多少？"
	return {
		Id = id or tostring(math.random(1, 1e9)),
		Name = name,
		Species = species,
		Color = { 0.95, 0.75, 0.3 },
		Greeting = greeting,
		LastLine = greeting,
		Item = instance,
		Greed = greed,
		Patience = 100,
		MaxPatience = 100,
		Floor = floorPrice,
		AskingPrice = askingPrice,
		CurrentAsk = askingPrice,
	}
end

function CustomerGenerator.Generate(reputation: number, rand: () -> number, id: string?, options: Options?): Customer
	local opts: Options = options or {}
	local def = pickItem(reputation, rand)
	local attrs = def.InspectionAttributes

	-- 稀有變種
	local rainbowChance = opts.RainbowChance or Config.Variants.RainbowChance
	local shinyChance = opts.ShinyChance or Config.Variants.ShinyChance
	local variantRoll = rand()
	local variant = "Normal"
	if variantRoll < rainbowChance then
		variant = "Rainbow"
	elseif variantRoll < rainbowChance + shinyChance then
		variant = "Shiny"
	end

	local fakeChance = attrs.FakeChance
	if opts.FakeChanceBonus then
		fakeChance = math.clamp(fakeChance + opts.FakeChanceBonus(def), 0, 0.9)
	end
	local isFake = rand() < fakeChance
	local defectType: string? = nil
	if not isFake and rand() < attrs.Defect.Chance then
		defectType = attrs.Defect.Type
	end

	local instance: ItemDatabase.ItemInstance = {
		ItemId = def.ID,
		IsFake = isFake,
		DefectType = defectType,
		Variant = variant,
	}

	local greed = rand()
	local floorPrice, askingPrice = BargainSystem.GetPrices(ItemDatabase.GetEffectiveBase(instance), greed)
	local profile = pick(PROFILES, rand)
	local greeting = pick(GREETINGS, rand)
	if variant ~= "Normal" then
		greeting = pick(VARIANT_GREETINGS, rand)
	end
	local patience = opts.Patience or 100

	return {
		Id = id or tostring(math.floor(rand() * 1e9)),
		Name = profile.Name,
		Species = profile.Species,
		Color = profile.Color,
		Greeting = greeting,
		LastLine = greeting,
		Item = instance,
		Greed = greed,
		Patience = patience,
		MaxPatience = patience,
		Floor = floorPrice,
		AskingPrice = askingPrice,
		CurrentAsk = askingPrice,
	}
end

return CustomerGenerator
