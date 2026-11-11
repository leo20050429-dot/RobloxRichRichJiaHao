-- 多人小鎮的核心：職業、商人採集與賣貨、搶劫、通緝、逮捕、坐牢、護送。
--
-- 「角色」(actor) 通常是 Player；Studio 自動測試會用假的 table 當角色（設定 TestPosition）。
-- 會即時變動的資訊（職業、通緝、身上貨物、是否受保護）寫在 Player 的 Attribute 上，
-- 客戶端直接讀 Attribute 顯示，不用每秒推送整份狀態。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cargo = require(Shared:WaitForChild("Cargo"))
local Config = require(Shared:WaitForChild("Config"))
local Crime = require(Shared:WaitForChild("Crime"))
local CustomerGenerator = require(Shared:WaitForChild("CustomerGenerator"))
local Jobs = require(Shared:WaitForChild("Jobs"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PromptRouter = require(script.Parent:WaitForChild("PromptRouter"))
local TownBuilder = require(script.Parent:WaitForChild("TownBuilder"))

local TownService = {}

local TOWN = Config.Town
local sessions = {} -- [actor] = session
local rng = Random.new()
local demand = { StarOre = 1, AlienParts = 1, EnergyCrystal = 1 }
local demandEndsAt = 0

-- 其他 Service 注入的函式
local hooks = {
	PushState = function(_actor) end,
	Notify = function(_actor, _text, _ok) end,
	HasPass = function(_actor, _passName)
		return false
	end,
	OnJobChanged = function(_actor, _oldJob, _newJob) end,
}

local function now()
	return os.clock()
end

local function rand()
	return rng:NextNumber()
end

local function isPlayer(actor)
	return typeof(actor) == "Instance" and actor:IsA("Player")
end

local function nameOf(actor)
	if isPlayer(actor) then
		return actor.DisplayName
	end
	return tostring(actor.Name or "某人")
end

function TownService.Configure(newHooks)
	for key, fn in newHooks do
		hooks[key] = fn
	end
end

function TownService.GetSession(actor)
	return sessions[actor]
end

function TownService.AddActor(actor, options)
	local session = {
		Job = nil,
		Cargo = {},
		Wanted = 0,
		LastCrimeAt = 0,
		JailedUntil = 0,
		RobCooldownUntil = 0,
		JoinedAt = now(),
		BodyguardReadyAt = 0,
		LastEscortPay = 0,
		TestPosition = nil,
		LastAttributes = {},
	}
	if options then
		for key, value in options do
			session[key] = value
		end
	end
	sessions[actor] = session
	return session
end

function TownService.RemoveActor(actor)
	sessions[actor] = nil
end

-- 位置 -------------------------------------------------------------------------

local function rootPart(actor)
	if not isPlayer(actor) then
		return nil
	end
	local character = actor.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function TownService.GetPosition(actor)
	local session = sessions[actor]
	if session and session.TestPosition then
		return session.TestPosition
	end
	local root = rootPart(actor)
	return root and root.Position or nil
end

function TownService.Teleport(actor, position)
	local session = sessions[actor]
	if session and session.TestPosition then
		session.TestPosition = position
		return
	end
	local root = rootPart(actor)
	if root then
		root.CFrame = CFrame.new(position)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

function TownService.InSafeZone(position)
	if not position then
		return false
	end
	local town = TownBuilder.Get()
	if not town then
		return false
	end
	for _, zone in town.SafeZones do
		if Crime.InBox(position, zone.Center, zone.Size) then
			return true
		end
	end
	return false
end

local function distance(a, b)
	local pa, pb = TownService.GetPosition(a), TownService.GetPosition(b)
	if not pa or not pb then
		return math.huge
	end
	return (pa - pb).Magnitude
end

-- 狀態查詢 ---------------------------------------------------------------------

function TownService.GetJob(actor)
	local session = sessions[actor]
	return session and session.Job or nil
end

function TownService.IsJailed(actor)
	local session = sessions[actor]
	return session ~= nil and session.JailedUntil > now()
end

function TownService.IsNewbie(actor)
	local session = sessions[actor]
	return session ~= nil and (now() - session.JoinedAt) < TOWN.NewbieProtection
end

function TownService.Capacity(actor)
	local capacity = TOWN.CargoCapacity
	if hooks.HasPass(actor, "BigBackpack") then
		capacity += TOWN.BigBackpackBonus
	end
	return capacity
end

function TownService.CargoCount(actor)
	local session = sessions[actor]
	return session and #session.Cargo or 0
end

function TownService.RelicCount(actor)
	local session = sessions[actor]
	local count = 0
	if session then
		for _, item in session.Cargo do
			if item.Kind == "Relic" then
				count += 1
			end
		end
	end
	return count
end

-- 有沒有保鑣在旁邊護送
function TownService.IsEscorted(actor)
	for other, otherSession in sessions do
		if other ~= actor and otherSession.Job == "Guard" and otherSession.JailedUntil <= now() then
			if distance(actor, other) <= TOWN.EscortRange then
				return true
			end
		end
	end
	return false
end

-- 不能被搶的原因（nil = 可以被搶）
function TownService.ProtectionReason(actor)
	if TownService.IsJailed(actor) then
		return "坐牢中"
	end
	if TownService.InSafeZone(TownService.GetPosition(actor)) then
		return "安全區"
	end
	if TownService.IsNewbie(actor) then
		local session = sessions[actor]
		local left = math.ceil(TOWN.NewbieProtection - (now() - session.JoinedAt))
		return string.format("新手保護（剩 %d 分鐘）", math.max(1, math.ceil(left / 60)))
	end
	if TownService.IsEscorted(actor) then
		return "保鑣護送中"
	end
	return nil
end

-- 給客戶端的狀態 -----------------------------------------------------------------

function TownService.GetPublicState(actor)
	local session = sessions[actor]
	if not session then
		return nil
	end
	local data = DataService.Get(actor)
	local job = Jobs.Get(session.Job)

	local cargoList = {}
	for _, item in session.Cargo do
		table.insert(cargoList, { Name = Cargo.DisplayName(item), Stolen = item.Stolen, Kind = item.Kind })
	end

	-- 各收購商目前的價格表
	local prices = {}
	for _, buyerId in { "TradingPost", "Institute", "BlackMarket" } do
		local buyer = Cargo.Buyers[buyerId]
		local row = { Buyer = buyer.Name, Prices = {} }
		for _, resourceId in { "StarOre", "AlienParts", "EnergyCrystal" } do
			local quote = Cargo.Quote(buyerId, { Kind = "Resource", Resource = resourceId, Stolen = false }, demand[resourceId])
			table.insert(row.Prices, { Name = Cargo.ResourceName(resourceId), Price = quote or 0 })
		end
		table.insert(prices, row)
	end

	local jobList = {}
	for _, def in Jobs.List do
		table.insert(jobList, { Id = def.Id, Name = def.Name, Icon = def.Icon, Summary = def.Summary, Color = def.Color })
	end

	return {
		Job = session.Job,
		JobName = job and job.Name or nil,
		JobIcon = job and job.Icon or nil,
		JobSteps = job and job.Steps or {},
		JobSummary = job and job.Summary or nil,
		Jobs = jobList,
		Cargo = cargoList,
		Capacity = TownService.Capacity(actor),
		Wanted = session.Wanted,
		JailSecondsLeft = math.max(0, math.ceil(session.JailedUntil - now())),
		Insurance = data and data.Insurance or 0,
		InsurancePrice = TOWN.Insurance.Price,
		InsuranceMax = TOWN.Insurance.MaxStack,
		Prices = prices,
	}
end

-- 頭上的名牌 & Attribute -----------------------------------------------------------

local function updateTag(actor, session)
	if not isPlayer(actor) then
		return
	end
	local character = actor.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = head:FindFirstChild("TownTag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "TownTag"
		tag.Size = UDim2.fromOffset(200, 44)
		tag.StudsOffset = Vector3.new(0, 3.2, 0)
		tag.MaxDistance = 120
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.BuilderSansBold
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = tag
		tag.Parent = head
	end
	local job = Jobs.Get(session.Job)
	local text = job and (job.Icon .. " " .. job.Name) or "（還沒選職業）"
	if session.Wanted > 0 then
		text ..= "\n" .. string.rep("⭐", session.Wanted)
	elseif #session.Cargo > 0 then
		text ..= "\n📦×" .. #session.Cargo
	end
	if TownService.IsJailed(actor) then
		text = "⛓ 坐牢中"
	end
	tag.Label.Text = text
	tag.Label.TextColor3 = session.Wanted > 0 and Color3.fromRGB(255, 120, 120) or Color3.new(1, 1, 1)
end

function TownService.RefreshAttributes(actor)
	local session = sessions[actor]
	if not session or not isPlayer(actor) then
		return
	end
	local protection = TownService.ProtectionReason(actor)
	local values = {
		Job = session.Job or "",
		Wanted = session.Wanted,
		Cargo = #session.Cargo,
		Relics = TownService.RelicCount(actor),
		Capacity = TownService.Capacity(actor),
		Jailed = TownService.IsJailed(actor),
		JailedUntilUnix = TownService.IsJailed(actor) and (os.time() + math.ceil(session.JailedUntil - now())) or 0,
		Protected = protection ~= nil,
		Protection = protection or "",
	}
	local changed = false
	for key, value in values do
		if session.LastAttributes[key] ~= value then
			session.LastAttributes[key] = value
			actor:SetAttribute(key, value)
			changed = true
		end
	end
	if changed then
		updateTag(actor, session)
	end
end

-- 職業 -------------------------------------------------------------------------

function TownService.SetJob(actor, jobId)
	local session = sessions[actor]
	if not session then
		return false, "資料讀取中。"
	end
	if not Jobs.IsValid(jobId) then
		return false, "沒有這個職業。"
	end
	if TownService.IsJailed(actor) then
		return false, "坐牢中不能換職業。"
	end
	if session.Job == jobId then
		return false, "你已經是這個職業了。"
	end
	if jobId == "Guard" and session.Wanted > 0 then
		return false, "通緝犯不能當保鑣！等通緝消失再來。"
	end
	local oldJob = session.Job
	session.Job = jobId
	local data = DataService.Get(actor)
	if data then
		data.LastJob = jobId
	end
	hooks.OnJobChanged(actor, oldJob, jobId)
	TownService.RefreshAttributes(actor)
	local job = Jobs.Get(jobId)
	return true, string.format("你現在是「%s %s」！%s", job.Icon, job.Name, job.Summary)
end

-- 採集與賣貨 ---------------------------------------------------------------------

local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if parent and typeof(parent) == "Instance" and parent:IsA("BasePart") then
		return parent.Position
	end
	if type(parent) == "table" and parent.Position then
		return parent.Position
	end
	return nil
end

local function nearPrompt(actor, prompt, range)
	local at = promptPosition(prompt)
	local pos = TownService.GetPosition(actor)
	if not at or not pos then
		return false
	end
	return (at - pos).Magnitude <= range
end

function TownService.Collect(actor, pointId, prompt)
	local session = sessions[actor]
	if not session then
		return false, "資料讀取中。"
	end
	if session.Job ~= "Merchant" then
		return false, "只有商人能採集。到廣場的職業公告板可以換職業。"
	end
	if TownService.IsJailed(actor) then
		return false, "坐牢中。"
	end
	local point = Cargo.Points[pointId]
	if not point then
		return false, "這裡沒什麼好採的。"
	end
	if prompt and not nearPrompt(actor, prompt, 16) then
		return false, "離太遠了。"
	end
	if #session.Cargo >= TownService.Capacity(actor) then
		return false, "身上塞滿了！先運回城裡賣掉。"
	end
	local drop = Cargo.RollDrop(pointId, rand)
	if not drop then
		return false, "這裡沒什麼好採的。"
	end
	if drop.Kind == "Relic" then
		local data = DataService.Get(actor)
		local reputation = data and data.Reputation or 0
		drop.Item = CustomerGenerator.Generate(reputation, rand).Item
	end
	table.insert(session.Cargo, drop)
	TownService.RefreshAttributes(actor)
	local message = string.format("採集到：%s（%d / %d）", Cargo.DisplayName(drop), #session.Cargo, TownService.Capacity(actor))
	if drop.Kind == "Relic" then
		message = "✨ 挖到遺物！" .. Cargo.DisplayName(drop) .. "。拿去給玩家當舖鑑定，價格比較好。"
	end
	return true, message
end

-- 在收購商賣掉身上的貨物。
-- 一般收購商：先賣資源；身上只剩遺物時，才會把遺物也賣掉（遺物賣給玩家當舖價格比較好）。
function TownService.SellCargo(actor, buyerId, prompt)
	local session = sessions[actor]
	local data = DataService.Get(actor)
	if not session or not data then
		return false, "資料讀取中。"
	end
	local buyer = Cargo.Buyers[buyerId]
	if not buyer then
		return false, "這裡不收東西。"
	end
	if TownService.IsJailed(actor) then
		return false, "坐牢中。"
	end
	if prompt and not nearPrompt(actor, prompt, 16) then
		return false, "離太遠了。"
	end
	if #session.Cargo == 0 then
		return false, "你身上沒有貨物。"
	end

	local hasResource = false
	for _, item in session.Cargo do
		if item.Kind == "Resource" and Cargo.Quote(buyerId, item, demand[item.Resource]) then
			hasResource = true
		end
	end
	local sellRelics = buyer.AcceptsStolen or not hasResource

	local kept = {}
	local total, sold, refusedStolen = 0, 0, 0
	for _, item in session.Cargo do
		local quote = nil
		if item.Kind == "Resource" or sellRelics then
			quote = Cargo.Quote(buyerId, item, item.Resource and demand[item.Resource] or nil)
		end
		if quote then
			total += quote
			sold += 1
		else
			if item.Stolen and not buyer.AcceptsStolen then
				refusedStolen += 1
			end
			table.insert(kept, item)
		end
	end

	if sold == 0 then
		if refusedStolen > 0 then
			return false, buyer.Name .. "：「這些是贓物吧？我們不收！」（贓物只能拿去黑市）"
		end
		return false, buyer.Name .. "不收你身上的東西。"
	end

	session.Cargo = kept
	data.Credits += total
	if not buyer.AcceptsStolen then
		data.Stats.TotalProfit += total
	end
	TownService.RefreshAttributes(actor)

	local message = string.format("在%s賣了 %d 件貨物，拿到 %d 星幣！", buyer.Name, sold, total)
	local relicsLeft = TownService.RelicCount(actor)
	if relicsLeft > 0 and not buyer.AcceptsStolen then
		message ..= string.format("\n身上還有 %d 件遺物：賣給玩家當舖價格比較好，或再按一次賣給%s。", relicsLeft, buyer.Name)
	end
	if refusedStolen > 0 then
		message ..= string.format("\n%d 件贓物對方不收，只能去黑市。", refusedStolen)
	end
	return true, message
end

-- 從身上拿出第一件遺物（賣給玩家當舖用）
function TownService.TakeRelic(actor)
	local session = sessions[actor]
	if not session then
		return nil
	end
	for i, item in session.Cargo do
		if item.Kind == "Relic" then
			table.remove(session.Cargo, i)
			TownService.RefreshAttributes(actor)
			return item
		end
	end
	return nil
end

-- 遺物沒賣成：還給商人；商人不在或背包滿了，就自動以貿易站的價格賣掉
function TownService.ReturnRelic(actor, item)
	local session = sessions[actor]
	if session and #session.Cargo < TownService.Capacity(actor) then
		table.insert(session.Cargo, item)
		TownService.RefreshAttributes(actor)
		hooks.Notify(actor, "當舖沒收你的" .. Cargo.DisplayName(item) .. "，已經還給你了。", false)
		hooks.PushState(actor)
		return "returned"
	end
	local data = DataService.Get(actor)
	if data then
		local quote = Cargo.Quote("TradingPost", item) or Cargo.Quote("BlackMarket", item) or 0
		data.Credits += quote
		hooks.Notify(actor, string.format("當舖沒收你的遺物，你身上又滿了，自動賣給貿易站拿到 %d 星幣。", quote), true)
		hooks.PushState(actor)
		return "sold"
	end
	return "lost"
end

-- 犯罪 -------------------------------------------------------------------------

local function addWanted(actor, session, amount)
	session.Wanted = Crime.AddWanted(session.Wanted, amount)
	session.LastCrimeAt = now()
end

local function penalize(actor, amount)
	local data = DataService.Get(actor)
	if data then
		data.Reputation = math.max(0, data.Reputation - amount)
	end
end

function TownService.Rob(robber, victim)
	local rs, vs = sessions[robber], sessions[victim]
	if not rs or not vs then
		return false, "找不到對象。"
	end
	local t = now()
	local freeSlots = TownService.Capacity(robber) - #rs.Cargo
	local ok, reason = Crime.CanRob({
		RobberJob = rs.Job,
		RobberJailed = TownService.IsJailed(robber),
		RobberOnCooldown = rs.RobCooldownUntil > t,
		RobberFreeSlots = freeSlots,
		VictimJailed = TownService.IsJailed(victim),
		VictimCargo = #vs.Cargo,
		VictimInSafeZone = TownService.InSafeZone(TownService.GetPosition(victim)),
		RobberInSafeZone = TownService.InSafeZone(TownService.GetPosition(robber)),
		VictimNewbie = TownService.IsNewbie(victim),
		VictimEscorted = TownService.IsEscorted(victim),
		Distance = distance(robber, victim),
		SameActor = robber == victim,
	})
	if not ok then
		return false, reason
	end

	rs.RobCooldownUntil = t + TOWN.RobCooldown

	-- 機器人保鑣擋下
	if hooks.HasPass(victim, "BodyguardBot") and vs.BodyguardReadyAt <= t then
		vs.BodyguardReadyAt = t + TOWN.BodyguardCooldown
		addWanted(robber, rs, 1)
		penalize(robber, math.ceil(TOWN.RobReputationPenalty / 2))
		TownService.RefreshAttributes(robber)
		TownService.RefreshAttributes(victim)
		hooks.Notify(victim, "🤖 你的機器人保鑣擋下了" .. nameOf(robber) .. "的搶劫！", true)
		hooks.PushState(victim)
		return false, "🤖 對方的機器人保鑣把你擋開了！你被通緝了。"
	end

	local count = Crime.RobCount(#vs.Cargo, freeSlots)
	local lostValue = 0
	for _ = 1, count do
		local index = rng:NextInteger(1, #vs.Cargo)
		local item = table.remove(vs.Cargo, index)
		lostValue += Cargo.BaseValue(item)
		item.Stolen = true
		table.insert(rs.Cargo, item)
	end

	addWanted(robber, rs, 1)
	penalize(robber, TOWN.RobReputationPenalty)

	-- 被害人的保險
	local victimData = DataService.Get(victim)
	local victimMessage = string.format("😱 %s搶走了你 %d 件貨物！", nameOf(robber), count)
	if victimData and (victimData.Insurance or 0) > 0 then
		victimData.Insurance -= 1
		local refund = Crime.InsuranceRefund(lostValue)
		victimData.Credits += refund
		victimMessage ..= string.format(" 保險理賠 %d 星幣（剩 %d 次保險）。", refund, victimData.Insurance)
	end
	victimMessage ..= " 他已經被通緝了，快找保鑣！"

	TownService.RefreshAttributes(robber)
	TownService.RefreshAttributes(victim)
	hooks.Notify(victim, victimMessage, false)
	hooks.PushState(victim)

	return true, string.format("你搶到了 %d 件貨物（贓物）！名聲 -%d，通緝 %s。贓物只能去黑市賣。", count, TOWN.RobReputationPenalty, string.rep("⭐", rs.Wanted))
end

-- 關進監獄：沒收贓物、清除通緝
function TownService.Jail(actor, wantedLevel, reason)
	local session = sessions[actor]
	if not session then
		return 0
	end
	local seconds = Crime.JailSeconds(wantedLevel)
	session.JailedUntil = now() + seconds
	session.Wanted = 0
	local kept, confiscated = {}, 0
	for _, item in session.Cargo do
		if item.Stolen then
			confiscated += 1
		else
			table.insert(kept, item)
		end
	end
	session.Cargo = kept
	local town = TownBuilder.Get()
	if town then
		TownService.Teleport(actor, town.JailSpot)
	end
	TownService.RefreshAttributes(actor)
	local message = string.format("⛓ %s 你被關進監獄 %d 秒。", reason or "", seconds)
	if confiscated > 0 then
		message ..= string.format("沒收贓物 %d 件。", confiscated)
	end
	hooks.Notify(actor, message, false)
	hooks.PushState(actor)
	return seconds
end

function TownService.Arrest(guard, target)
	local gs, ts = sessions[guard], sessions[target]
	if not gs or not ts then
		return false, "找不到對象。"
	end
	if guard == target then
		return false, "不能抓自己。"
	end
	if gs.Job ~= "Guard" then
		return false, "只有保鑣能抓人。"
	end
	if TownService.IsJailed(guard) then
		return false, "你在坐牢。"
	end
	if TownService.IsJailed(target) then
		return false, "對方已經在坐牢了。"
	end
	if ts.Wanted <= 0 then
		return false, "對方沒有被通緝。"
	end
	if distance(guard, target) > TOWN.ArrestRange then
		return false, "離太遠了。"
	end
	local level = ts.Wanted
	local bounty = Crime.Bounty(level)
	TownService.Jail(target, level, nameOf(guard) .. "逮捕了你！")
	local data = DataService.Get(guard)
	if data then
		data.Credits += bounty
		data.Reputation += TOWN.ArrestReputationReward
	end
	TownService.RefreshAttributes(guard)
	return true, string.format("🛡️ 抓到通緝犯%s！賞金 %d 星幣，名聲 +%d。", nameOf(target), bounty, TOWN.ArrestReputationReward)
end

function TownService.BuyInsurance(actor)
	local data = DataService.Get(actor)
	if not data then
		return false, "資料讀取中。"
	end
	local insurance = TOWN.Insurance
	if (data.Insurance or 0) >= insurance.MaxStack then
		return false, string.format("保險最多只能存 %d 次。", insurance.MaxStack)
	end
	if data.Credits < insurance.Price then
		return false, "星幣不夠！"
	end
	data.Credits -= insurance.Price
	data.Insurance = (data.Insurance or 0) + 1
	return true, string.format("買了一份搶劫保險（現在有 %d 份）。被搶時會理賠損失的 %d%%。", data.Insurance, math.floor(insurance.Refund * 100))
end

-- 每秒更新 -----------------------------------------------------------------------

function TownService.Tick()
	local t = now()
	local town = TownBuilder.Get()

	-- 市場行情變動
	if t >= demandEndsAt then
		for resourceId in demand do
			demand[resourceId] = math.floor((0.8 + rand() * 0.5) * 100 + 0.5) / 100
		end
		demandEndsAt = t + Config.NewsInterval
	end

	local npcGuardPosition = nil
	if town and town.NpcGuard and town.NpcGuard.PrimaryPart then
		npcGuardPosition = town.NpcGuard.PrimaryPart.Position
	end

	for actor, session in sessions do
		-- 出獄
		if session.JailedUntil > 0 and session.JailedUntil <= t then
			session.JailedUntil = 0
			if town then
				TownService.Teleport(actor, town.SpawnPosition)
			end
			hooks.Notify(actor, "你出獄了。這次要當個好人喔！", true)
			hooks.PushState(actor)
		end

		-- 通緝等級慢慢下降
		if session.Wanted > 0 and t - session.LastCrimeAt >= TOWN.WantedDecay then
			session.Wanted -= 1
			session.LastCrimeAt = t
			if session.Wanted == 0 then
				hooks.Notify(actor, "風頭過了，你不再被通緝。", true)
			end
		end

		-- 通緝犯靠近廣場警衛就會被抓
		if npcGuardPosition and session.Wanted > 0 and not TownService.IsJailed(actor) then
			local pos = TownService.GetPosition(actor)
			if pos and (pos - npcGuardPosition).Magnitude <= TOWN.NpcGuardRange then
				TownService.Jail(actor, session.Wanted, "城鎮警衛認出你了！")
			end
		end

		-- 保鑣的護送費：旁邊有帶貨、不在安全區的商人
		if session.Job == "Guard" and not TownService.IsJailed(actor) and t - session.LastEscortPay >= TOWN.EscortPayInterval then
			for other, otherSession in sessions do
				if other ~= actor and #otherSession.Cargo > 0 and otherSession.Job == "Merchant" then
					local otherPos = TownService.GetPosition(other)
					if otherPos and not TownService.InSafeZone(otherPos) and distance(actor, other) <= TOWN.EscortRange then
						session.LastEscortPay = t
						local data = DataService.Get(actor)
						if data then
							data.Credits += TOWN.EscortPay
						end
						break
					end
				end
			end
		end

		TownService.RefreshAttributes(actor)
	end
end

-- 測試與外部使用 -------------------------------------------------------------------

function TownService.GetDemand()
	return demand
end

function TownService.AddCargoForTest(actor, item)
	local session = sessions[actor]
	if session then
		table.insert(session.Cargo, item)
	end
end

-- 啟動 -------------------------------------------------------------------------

local function addCharacterPrompts(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local function makePrompt(action, text, hold)
		local p = Instance.new("ProximityPrompt")
		p.Name = action .. "Prompt"
		p.ActionText = text
		p.ObjectText = player.DisplayName
		p.HoldDuration = hold
		p.MaxActivationDistance = TOWN.RobRange
		p.RequiresLineOfSight = false
		p:SetAttribute("Action", action)
		p:SetAttribute("TargetUserId", player.UserId)
		p.Parent = root
		CollectionService:AddTag(p, "TownPrompt")
	end
	makePrompt("Rob", "搶劫", 1)
	makePrompt("Arrest", "逮捕", 0.5)
end

local function onPlayerAdded(player)
	TownService.AddActor(player)
	player.CharacterAdded:Connect(function(character)
		local session = sessions[player]
		if session then
			session.LastAttributes = {}
		end
		task.spawn(addCharacterPrompts, player, character)
		task.defer(function()
			local town = TownBuilder.Get()
			if town and TownService.IsJailed(player) then
				character:WaitForChild("HumanoidRootPart", 10)
				TownService.Teleport(player, town.JailSpot)
			end
			TownService.RefreshAttributes(player)
		end)
	end)
	if player.Character then
		task.spawn(addCharacterPrompts, player, player.Character)
	end
	TownService.RefreshAttributes(player)
end

local function targetFromPrompt(prompt)
	local userId = prompt:GetAttribute("TargetUserId")
	if type(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

function TownService.Start()
	PromptRouter.Register("Collect", function(player, prompt)
		return TownService.Collect(player, prompt:GetAttribute("PointId"), prompt)
	end)
	PromptRouter.Register("SellCargo", function(player, prompt)
		return TownService.SellCargo(player, prompt:GetAttribute("BuyerId"), prompt)
	end)
	PromptRouter.Register("Rob", function(player, prompt)
		local target = targetFromPrompt(prompt)
		if not target then
			return false, "找不到對象。"
		end
		return TownService.Rob(player, target)
	end)
	PromptRouter.Register("Arrest", function(player, prompt)
		local target = targetFromPrompt(prompt)
		if not target then
			return false, "找不到對象。"
		end
		return TownService.Arrest(player, target)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(TownService.Tick)
			if not ok then
				warn("[TownService] Tick 出錯：" .. tostring(err))
			end
		end
	end)
end

return TownService
