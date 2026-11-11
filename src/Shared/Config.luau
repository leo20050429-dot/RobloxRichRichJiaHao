--!strict
-- 遊戲的全域設定。數值平衡、Gamepass ID 都集中在這裡，改數字不用動邏輯。

local Config = {
	-- 暫定名稱，正式上架前可以再改
	GameTitle = "星塵當舖",

	-- 倉庫格數（ExtraStorage Gamepass 會再加上 ExtraStorageSlots）
	InventorySlots = 12,
	ExtraStorageSlots = 12,

	-- 救急金：倉庫空了、星幣又低於 Threshold 時，叫下一位客人會自動把星幣補到 Amount，
	-- 避免玩家買到假貨後連最便宜的東西都買不起而卡關。
	Bailout = {
		Threshold = 70,
		Amount = 150,
	},

	-- 固定鏡頭：true 時鏡頭永遠固定在櫃檯後方（單人版用）。
	-- 多人小鎮版設 false：平常是一般第三人稱鏡頭，只有在櫃檯營業時才固定。
	FixedCamera = false,

	-- 稀有變種出現的機率（閃亮版價值 ×3、彩虹版價值 ×10）
	Variants = {
		ShinyChance = 0.06,
		RainbowChance = 0.01,
	},

	-- 每日登入獎勵（星幣）：連續第 1、2、3… 天，超過之後維持最後一個數字
	DailyRewards = { 100, 150, 200, 300, 400, 500, 1000 },

	-- 稱號：名聲達到 MinReputation 就升級（要照名聲由小到大排）
	Ranks = {
		{ MinReputation = 0, Title = "菜鳥店員" },
		{ MinReputation = 10, Title = "見習鑑定師" },
		{ MinReputation = 25, Title = "老練店長" },
		{ MinReputation = 50, Title = "星際古董商" },
		{ MinReputation = 100, Title = "銀河鑑定大師" },
		{ MinReputation = 200, Title = "宇宙傳奇當舖王" },
	},

	-- 銀河新聞多久換一則（秒）
	NewsInterval = 240,

	-- 兌換碼 → 星幣。每個玩家每組碼只能用一次。可以拿來做宣傳（影片、Discord）。
	-- 一律用大寫英數字。
	Codes = {
		STARDUST = 200,
		WELCOME = 100,
	},

	-- 名聲變化
	Reputation = {
		SellReal = 2, -- 賣出真品
		SellFake = -3, -- 賣出假貨被市場拆穿
		CustomerStormedOff = -1, -- 把客人氣走
	},

	-- 在 Roblox Creator Hub 建好 Gamepass 後，把 ID 填進來。0 代表尚未建立（視為沒有購買）。
	GamePasses = {
		VIPScanner = 0, -- 高級天眼掃描儀：顯示物品的假貨機率
		Empath = 0, -- 讀心眼鏡：顯示客人的心理底價
		ExtraStorage = 0, -- 宇宙倉庫擴建：倉庫 +12 格
		DoubleReputation = 0, -- 雙倍名聲
		BodyguardBot = 0, -- 私人機器人保鑣：每 5 分鐘自動擋下一次搶劫
		BigBackpack = 0, -- 大背包：可以多帶 6 件貨物
	},

	-- 多人小鎮 ------------------------------------------------------------------
	Town = {
		MaxPlayers = 20, -- 每個伺服器的人數（要在 Game Settings 裡設定，這裡只是記錄）
		NewbieProtection = 600, -- 剛進遊戲幾秒內不會被搶
		CargoCapacity = 6, -- 每個人身上最多帶幾件貨物
		BigBackpackBonus = 6,

		-- 搶劫
		RobRange = 10, -- 要離目標多近才能搶
		RobCooldown = 20, -- 搶完要等幾秒才能再搶
		RobShare = 0.5, -- 一次搶走身上幾成的貨物
		RobReputationPenalty = 5, -- 每搶一次扣多少名聲
		BodyguardCooldown = 300, -- 機器人保鑣擋下一次後要冷卻幾秒

		-- 通緝與坐牢
		MaxWanted = 5,
		WantedDecay = 90, -- 多少秒沒做壞事，通緝等級降一級
		JailPerLevel = 20, -- 每一級通緝要關幾秒
		BountyPerLevel = 100, -- 保鑣抓到人，每一級通緝拿多少賞金
		ArrestRange = 10,
		ArrestReputationReward = 2,
		NpcGuardRange = 14, -- 通緝犯靠近廣場 NPC 警衛多近會被抓

		-- 護送
		EscortRange = 25, -- 保鑣在多近的距離內算護送中（護送中不會被搶）
		EscortPayInterval = 10, -- 每幾秒發一次護送費
		EscortPay = 6,

		-- 用星幣買的保險：被搶時拿回這次損失的幾成，用一次就沒了
		Insurance = { Price = 250, Refund = 0.6, MaxStack = 3 },

		-- 店面
		CounterRange = 18, -- 店長離開櫃檯多遠就自動打烊
		MerchantQueueLimit = 3, -- 每間當舖最多排幾件玩家商人寄賣的遺物
	},

	-- 存檔
	DataStoreName = "PlayerData_v1",
	AutosaveInterval = 120, -- 秒

	-- 每位玩家兩次請求之間的最短間隔（秒），防止腳本狂刷
	RequestCooldown = 0.15,
}

return Config
