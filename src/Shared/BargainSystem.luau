--!strict
-- 議價系統：客人帶東西來「賣給」玩家，玩家出價收購。
--
-- 每位客人有：
--   Greed（貪婪度 0~1）：越貪婪，心理底價與開價越高
--   Patience（耐心值 0~100）：出價太低、鑑定太久都會扣，歸零就走人
--
-- 規則（注意方向：玩家是買方）：
--   出價 >= 客人底價 → 成交，以玩家的出價成交
--   出價 <  客人底價 → 依差距扣耐心，客人回一個還價
--   耐心歸零         → DealFailed，客人生氣離開
--
-- 這個模組是純計算、沒有隨機，方便測試與調整數值。

export type NegotiateResult = {
	Success: boolean,
	DealFailed: boolean,
	NewPatience: number,
	NPCResponseText: string,
	FinalPrice: number?,
	CounterOffer: number?,
}

local BargainSystem = {}

-- 數值參數
BargainSystem.FloorBase = 0.55 -- 最不貪婪的客人：底價 = 基礎價值 × 0.55
BargainSystem.FloorGreed = 0.35 -- 最貪婪的客人：底價 = 基礎價值 × 0.90
BargainSystem.AskBase = 1.15 -- 開價 = 基礎價值 × (1.15 ~ 1.50)
BargainSystem.AskGreed = 0.35
BargainSystem.MinPenalty = 8 -- 出價低於底價時至少扣多少耐心
BargainSystem.GapPenalty = 42 -- 差距越大扣越多（最多再加這麼多）

local function clamp01(x: number): number
	if x ~= x then
		return 0
	end
	return math.clamp(x, 0, 1)
end

-- 回傳 (底價, 開價)
function BargainSystem.GetPrices(itemBaseValue: number, customerGreed: number): (number, number)
	local greed = clamp01(customerGreed)
	local floorPrice = math.max(1, math.floor(itemBaseValue * (BargainSystem.FloorBase + BargainSystem.FloorGreed * greed) + 0.5))
	local askingPrice = math.max(floorPrice, math.floor(itemBaseValue * (BargainSystem.AskBase + BargainSystem.AskGreed * greed) + 0.5))
	return floorPrice, askingPrice
end

function BargainSystem.Negotiate(
	playerOffer: number,
	itemBaseValue: number,
	customerPatience: number,
	customerGreed: number
): NegotiateResult
	if type(playerOffer) ~= "number" or playerOffer ~= playerOffer or playerOffer < 1 or playerOffer == math.huge then
		return {
			Success = false,
			DealFailed = false,
			NewPatience = customerPatience,
			NPCResponseText = "你要出多少？說個數字啊。",
		}
	end

	local offer = math.floor(playerOffer)
	local floorPrice, askingPrice = BargainSystem.GetPrices(itemBaseValue, customerGreed)

	if offer >= floorPrice then
		local text
		if offer >= askingPrice then
			text = "成交！你真是個爽快的老闆！"
		elseif offer >= floorPrice * 1.15 then
			text = "成交，合作愉快。"
		else
			text = "唉…好吧，成交。算你厲害。"
		end
		return {
			Success = true,
			DealFailed = false,
			NewPatience = customerPatience,
			NPCResponseText = text,
			FinalPrice = offer,
		}
	end

	local gapRatio = (floorPrice - offer) / floorPrice
	local penalty = math.ceil(BargainSystem.MinPenalty + gapRatio * BargainSystem.GapPenalty)
	local newPatience = math.max(0, customerPatience - penalty)

	if newPatience <= 0 then
		return {
			Success = false,
			DealFailed = true,
			NewPatience = 0,
			NPCResponseText = "你這是在侮辱我！我去別家賣！",
		}
	end

	-- 耐心越少，還價越接近底價（但永遠不會低於底價）
	local counter = floorPrice + math.ceil((askingPrice - floorPrice) * (newPatience / 100))
	counter = math.clamp(counter, floorPrice, askingPrice)

	local text
	if gapRatio < 0.1 then
		text = string.format("就差一點點了…%d 星幣，不能再少了。", counter)
	elseif gapRatio < 0.35 then
		text = string.format("這價格太低了吧…%d 星幣怎麼樣？", counter)
	else
		text = string.format("你在開玩笑嗎？至少也要 %d 星幣！", counter)
	end

	return {
		Success = false,
		DealFailed = false,
		NewPatience = newPatience,
		NPCResponseText = text,
		CounterOffer = counter,
	}
end

return BargainSystem
