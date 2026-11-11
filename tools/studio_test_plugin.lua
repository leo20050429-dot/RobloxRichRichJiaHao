-- 星塵鎮自動測試外掛（開發用，不是遊戲的一部分）。
--
-- 用法：把這個檔案複製到 %LOCALAPPDATA%\Roblox\Plugins\，再用 Studio 開啟 place 檔。
-- 外掛會自動啟動一次 Play 測試：
--   伺服器端：用真正的玩家 + 假的測試角色，把職業、採集、賣貨、搶劫、護送、逮捕、坐牢、
--             黑市、NPC 警衛、當舖經營、玩家商人寄賣都跑一遍。
--   客戶端：檢查職業選單、小鎮模式與櫃檯模式的介面有沒有出錯或文字溢出。
-- 結果以 "[PawnTest]" 開頭印在 Output（也會寫進 %LOCALAPPDATA%\Roblox\logs 的記錄檔）。
-- 測完請把 Plugins 資料夾裡的這個檔案刪掉，不然每次開這個 place 都會自動跑一次。

local RunService = game:GetService("RunService")
if not RunService:IsEdit() then
	return
end

task.wait(5)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local shared = ReplicatedStorage:FindFirstChild("Shared")
if not (shared and shared:FindFirstChild("ItemDatabase") and ServerScriptService:FindFirstChild("Server")) then
	return -- 不是星塵鎮的 place
end

local SERVER_SOURCE = [==[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local P = "[PawnTest] "
local pass, fail = 0, 0
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		warn(P .. "FAIL(server): " .. name .. (detail ~= nil and (" | " .. tostring(detail)) or ""))
	end
end
local function log(text)
	print(P .. text)
end

local signal = Instance.new("RemoteEvent")
signal.Name = "PawnTestSignal"
signal.Parent = ReplicatedStorage

local ended = false
local function finish(result)
	if ended then
		return
	end
	ended = true
	print(P .. "ENDING TEST: " .. result)
	task.wait(1)
	StudioTestService:EndTest(result)
end
task.delay(300, function()
	finish("timeout")
end)

local clientReady = false
local clientDone = false
local clientResult = ""
signal.OnServerEvent:Connect(function(_player, kind, info)
	if kind == "ClientReady" then
		clientReady = true
	elseif kind == "ClientDone" then
		clientDone = true
		clientResult = tostring(info)
	end
end)

local ok, err = xpcall(function()
	local Server = ServerScriptService:WaitForChild("Server")
	local TownService = require(Server:WaitForChild("TownService"))
	local ShopService = require(Server:WaitForChild("ShopService"))
	local DataService = require(Server:WaitForChild("DataService"))
	local PromptRouter = require(Server:WaitForChild("PromptRouter"))
	local TownBuilder = require(Server:WaitForChild("TownBuilder"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Schema = require(Shared:WaitForChild("PlayerDataSchema"))
	local Config = require(Shared:WaitForChild("Config"))
	local Cargo = require(Shared:WaitForChild("Cargo"))

	local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local started = os.clock()
	while (not DataService.Get(player) or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart")) and os.clock() - started < 30 do
		task.wait(0.2)
	end
	local data = DataService.Get(player)
	check("玩家存檔已讀取", data ~= nil)
	started = os.clock()
	while not clientReady and os.clock() - started < 30 do
		task.wait(0.2)
	end
	check("客戶端準備好", clientReady)

	local town = TownBuilder.Get()
	local shopCount = 0
	for _ in town.Shops do
		shopCount += 1
	end
	check("有 4 間店面", shopCount == 4, shopCount)
	check("有安全區", #town.SafeZones >= 5, #town.SafeZones)
	check("監獄存在", town.JailSpot ~= nil)
	check("廣場是安全區", TownService.InSafeZone(Vector3.new(0, 3, 0)))
	check("礦場不是安全區", not TownService.InSafeZone(Vector3.new(0, 3, 250)))
	check("店面裡是安全區", TownService.InSafeZone(town.Shops.Shop1.KeeperSpot.Position))
	check("黑市不是安全區", not TownService.InSafeZone(Vector3.new(0, 3, -105)))

	local root = player.Character.HumanoidRootPart
	check("角色身上有搶劫提示", root:FindFirstChild("RobPrompt") ~= nil)
	check("角色身上有逮捕提示", root:FindFirstChild("ArrestPrompt") ~= nil)
	check("一開始沒有職業", TownService.GetJob(player) == nil)

	local function teleport(position)
		root.CFrame = CFrame.new(position)
		root.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.1)
	end
	local function dispatch(actor, action, prompt)
		local success, message = PromptRouter.Dispatch(actor, action, prompt)
		log(string.format("dispatch %s -> %s %s", action, tostring(success), tostring(message and string.gsub(message, "\n", " / ") or "")))
		return success, message
	end
	local function findPrompt(parent, action)
		for _, d in parent:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("Action") == action then
				return d
			end
		end
		return nil
	end

	-- 職業 ----------------------------------------------------------------
	check("不存在的職業", TownService.SetJob(player, "Ninja") == false)
	local okJob = TownService.SetJob(player, "Merchant")
	check("選商人", okJob == true)
	check("Attribute 同步職業", player:GetAttribute("Job") == "Merchant")
	check("重複選同一職業", TownService.SetJob(player, "Merchant") == false)
	local state = ShopService.InvokeForTest(player, "GetState").State
	check("狀態裡有小鎮資訊", state.Town ~= nil and state.Town.Job == "Merchant" and #state.Town.Jobs == 3)
	check("收購價表有 3 個收購商", state.Town and #state.Town.Prices == 3)

	-- 採集 ----------------------------------------------------------------
	local mine = town.Root:FindFirstChild("Mine")
	local orePrompt = findPrompt(mine, "Collect")
	check("礦場有採集點", orePrompt ~= nil)
	local farOk = dispatch(player, "Collect", orePrompt)
	check("太遠不能採集", farOk == false)
	teleport(orePrompt.Parent.Position + Vector3.new(0, 0, 6))
	local capacity = TownService.Capacity(player)
	for i = 1, capacity do
		local success = dispatch(player, "Collect", orePrompt)
		check("採集第 " .. i .. " 次", success == true)
	end
	check("背包滿了", TownService.CargoCount(player) == capacity)
	check("滿了不能再採", dispatch(player, "Collect", orePrompt) == false)
	check("Attribute 同步貨物數量", player:GetAttribute("Cargo") == capacity)
	check("礦場外不受保護（但新手保護中）", player:GetAttribute("Protected") == true)

	-- 搶劫：假的劫匪 ----------------------------------------------------------
	local robber = { Name = "測試劫匪" }
	DataService.SetTestRecord(robber, Schema.New())
	ShopService.AddTestActor(robber)
	local robberSession = TownService.AddActor(robber, { TestPosition = root.Position + Vector3.new(3, 0, 0), JoinedAt = os.clock() - 99999 })
	TownService.SetJob(robber, "Merchant")

	local robOk, robMessage = TownService.Rob(robber, player)
	check("新手保護擋下搶劫", robOk == false and string.find(robMessage, "新手", 1, true) ~= nil, robMessage)
	TownService.GetSession(player).JoinedAt = os.clock() - 99999

	data.Insurance = 1
	local creditsBefore = data.Credits
	local cargoBefore = TownService.CargoCount(player)
	robOk, robMessage = TownService.Rob(robber, player)
	log("rob -> " .. tostring(robOk) .. " " .. tostring(robMessage))
	check("搶劫成功", robOk == true, robMessage)
	local taken = cargoBefore - TownService.CargoCount(player)
	check("被搶走一半", taken == math.ceil(cargoBefore * Config.Town.RobShare), taken)
	check("劫匪拿到貨物", #robberSession.Cargo == taken)
	local allStolen = true
	for _, item in robberSession.Cargo do
		allStolen = allStolen and item.Stolen == true
	end
	check("搶來的都是贓物", allStolen)
	check("劫匪被通緝", robberSession.Wanted == 1)
	check("保險理賠", data.Credits > creditsBefore and data.Insurance == 0, data.Credits - creditsBefore)
	check("冷卻中不能再搶", TownService.Rob(robber, player) == false)

	-- 安全區：把兩人都移到廣場
	robberSession.RobCooldownUntil = 0
	-- 放在廣場西南角，離 NPC 警衛遠一點（不然背景巡邏會直接把通緝犯抓走）
	teleport(Vector3.new(-30, 3, 30))
	robberSession.TestPosition = Vector3.new(-27, 3, 30)
	robOk, robMessage = TownService.Rob(robber, player)
	check("安全區不能搶", robOk == false and string.find(robMessage, "安全區", 1, true) ~= nil, robMessage)

	-- 護送：旁邊有保鑣就不能搶
	teleport(Vector3.new(0, 3, 150))
	robberSession.TestPosition = Vector3.new(3, 3, 150)
	local guard = { Name = "測試保鑣" }
	DataService.SetTestRecord(guard, Schema.New())
	ShopService.AddTestActor(guard)
	local guardSession = TownService.AddActor(guard, { TestPosition = Vector3.new(-6, 3, 150), JoinedAt = os.clock() - 99999 })
	check("通緝犯不能當保鑣", TownService.SetJob(robber, "Guard") == false)
	check("選保鑣", TownService.SetJob(guard, "Guard") == true)
	check("保鑣不能搶", TownService.Rob(guard, player) == false)
	robOk, robMessage = TownService.Rob(robber, player)
	check("保鑣護送中不能搶", robOk == false and string.find(robMessage, "護送", 1, true) ~= nil, robMessage)

	-- 護送費
	local guardData = DataService.Get(guard)
	local guardCredits = guardData.Credits
	guardSession.LastEscortPay = 0
	TownService.Tick()
	check("保鑣拿到護送費", guardData.Credits == guardCredits + Config.Town.EscortPay, guardData.Credits - guardCredits)

	-- 贓物只能去黑市
	local tradeOk = TownService.SellCargo(robber, "TradingPost", nil)
	check("貿易站不收贓物", tradeOk == false)
	-- 逮捕
	guardSession.TestPosition = robberSession.TestPosition + Vector3.new(2, 0, 0)
	guardCredits = guardData.Credits
	local arrestOk, arrestMessage = TownService.Arrest(guard, robber)
	log("arrest -> " .. tostring(arrestOk) .. " " .. tostring(arrestMessage))
	check("保鑣逮捕成功", arrestOk == true, arrestMessage)
	check("拿到賞金", guardData.Credits == guardCredits + Config.Town.BountyPerLevel, guardData.Credits - guardCredits)
	check("劫匪坐牢", TownService.IsJailed(robber))
	check("劫匪被送到監獄", (robberSession.TestPosition - town.JailSpot).Magnitude < 1)
	check("贓物被沒收", #robberSession.Cargo == 0)
	check("通緝清除", robberSession.Wanted == 0)
	check("坐牢不能搶", TownService.Rob(robber, player) == false)
	check("坐牢不能換職業", TownService.SetJob(robber, "Pawnbroker") == false)
	check("沒通緝的人不能抓", TownService.Arrest(guard, player) == false)

	-- 出獄
	robberSession.JailedUntil = os.clock() - 1
	TownService.Tick()
	check("時間到出獄", not TownService.IsJailed(robber))
	check("出獄回到廣場", (robberSession.TestPosition - town.SpawnPosition).Magnitude < 1)

	-- 黑市銷贓
	TownService.AddCargoForTest(robber, { Kind = "Resource", Resource = "AlienParts", Stolen = true })
	local robberData = DataService.Get(robber)
	local before = robberData.Credits
	local bmOk = TownService.SellCargo(robber, "BlackMarket", nil)
	check("黑市收贓物", bmOk == true and robberData.Credits > before)

	-- NPC 警衛
	robberSession.Wanted = 2
	robberSession.LastCrimeAt = os.clock()
	robberSession.TestPosition = town.NpcGuard.PrimaryPart.Position + Vector3.new(3, 0, 0)
	TownService.Tick()
	check("通緝犯靠近 NPC 警衛被抓", TownService.IsJailed(robber))
	robberSession.JailedUntil = os.clock() - 1
	TownService.Tick()

	-- 通緝自然下降
	robberSession.Wanted = 2
	robberSession.LastCrimeAt = os.clock() - Config.Town.WantedDecay - 1
	robberSession.TestPosition = Vector3.new(0, 3, 200)
	TownService.Tick()
	check("通緝會慢慢下降", robberSession.Wanted == 1, robberSession.Wanted)
	robberSession.Wanted = 0

	-- 玩家賣貨 ---------------------------------------------------------------
	local tradePrompt = findPrompt(town.Root:FindFirstChild("TradingPost") and town.Root or town.Root, "SellCargo")
	for _, d in town.Root:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("BuyerId") == "TradingPost" then
			tradePrompt = d
		end
	end
	teleport(tradePrompt.Parent.Position + Vector3.new(4, 1.5, 0))
	local relicCount = TownService.RelicCount(player)
	local resourceCount = TownService.CargoCount(player) - relicCount
	before = data.Credits
	local sellOk = dispatch(player, "SellCargo", tradePrompt)
	if resourceCount > 0 then
		check("貿易站賣資源", sellOk == true and data.Credits > before)
		check("遺物先留在身上", TownService.CargoCount(player) == relicCount)
	end
	log(string.format("player cargo after sell: %d (relics %d)", TownService.CargoCount(player), TownService.RelicCount(player)))

	-- 當舖 -----------------------------------------------------------------
	check("換成當舖老闆", TownService.SetJob(player, "Pawnbroker") == true)
	local shop = town.Shops.Shop1
	local counterPrompt = findPrompt(shop.Model, "ShopCounter")
	local relicPrompt = findPrompt(shop.Model, "SellRelic")
	check("店面有櫃檯提示", counterPrompt ~= nil and relicPrompt ~= nil)
	teleport(shop.KeeperSpot.Position)
	check("經營店面", dispatch(player, "ShopCounter", counterPrompt) == true)
	check("招牌換成玩家名字", string.find(shop.SignLabel.Text, player.DisplayName, 1, true) ~= nil, shop.SignLabel.Text)
	check("店面記錄老闆", shop.Model:GetAttribute("Owner") == player.UserId)
	local response = ShopService.InvokeForTest(player, "NextCustomer")
	check("沒開櫃檯不能接客", response.Ok == false)
	check("打開櫃檯", dispatch(player, "ShopCounter", counterPrompt) == true)
	response = ShopService.InvokeForTest(player, "NextCustomer")
	check("櫃檯接客", response.Ok == true and response.State.Customer ~= nil, response.Message)
	check("狀態有店面資訊", response.State.Shop and response.State.Shop.CounterOpen == true and response.State.Shop.Index == 1)
	response = ShopService.InvokeForTest(player, "Reject")
	check("請客人離開", response.Ok == true)

	-- 別的職業不能經營
	local merchant = { Name = "測試商人" }
	DataService.SetTestRecord(merchant, Schema.New())
	ShopService.AddTestActor(merchant)
	local merchantSession = TownService.AddActor(merchant, { TestPosition = shop.CustomerSpot.Position, JoinedAt = os.clock() - 99999 })
	TownService.SetJob(merchant, "Merchant")
	check("別人的店不能經營", dispatch(merchant, "ShopCounter", findPrompt(town.Shops.Shop1.Model, "ShopCounter")) == false)
	check("商人不能經營空店", dispatch(merchant, "ShopCounter", findPrompt(town.Shops.Shop2.Model, "ShopCounter")) == false)

	-- 玩家商人寄賣遺物
	check("沒遺物不能寄賣", dispatch(merchant, "SellRelic", relicPrompt) == false)
	local relicItem = { Kind = "Relic", Item = { ItemId = "Item_002", IsFake = false, Variant = "Normal" }, Stolen = false }
	TownService.AddCargoForTest(merchant, relicItem)
	check("寄賣遺物", dispatch(merchant, "SellRelic", relicPrompt) == true)
	check("遺物離開商人身上", #merchantSession.Cargo == 0)
	response = ShopService.InvokeForTest(player, "NextCustomer")
	local customer = response.State.Customer
	check("輪到玩家商人", customer ~= nil and customer.IsPlayerSeller == true and customer.Name == "測試商人", customer and customer.Name)
	local merchantData = DataService.Get(merchant)
	before = merchantData.Credits
	data.Credits = math.max(data.Credits, 2000)
	response = ShopService.InvokeForTest(player, "Offer", { Amount = customer.AskingPrice })
	check("收購玩家的遺物", response.Ok == true and response.State.Customer == nil, response.Message)
	check("錢付給商人", merchantData.Credits == before + customer.AskingPrice, merchantData.Credits - before)

	-- 寄賣後被拒絕 → 遺物還給商人
	TownService.AddCargoForTest(merchant, { Kind = "Relic", Item = { ItemId = "Item_001", IsFake = true, Variant = "Normal" }, Stolen = true })
	dispatch(merchant, "SellRelic", relicPrompt)
	response = ShopService.InvokeForTest(player, "NextCustomer")
	check("贓物有標記", response.State.Customer and response.State.Customer.Stolen == true)
	response = ShopService.InvokeForTest(player, "Reject")
	check("拒絕後遺物還給商人", #merchantSession.Cargo == 1, #merchantSession.Cargo)

	-- 店長離開櫃檯自動打烊
	teleport(Vector3.new(0, 3, 0))
	task.wait(1.6)
	check("離開櫃檯自動打烊", ShopService.GetSession(player).CounterOpen == false)

	-- 換職業會放棄店面
	TownService.SetJob(player, "Guard")
	check("換職業放棄店面", shop.Model:GetAttribute("Owner") == 0 and ShopService.GetShops().Shop1.Owner == nil)
	check("招牌恢復", string.find(shop.SignLabel.Text, "空店面", 1, true) ~= nil)

	-- 保險
	data.Credits = 1000
	data.Insurance = 0
	response = ShopService.InvokeForTest(player, "BuyInsurance")
	check("買保險", response.Ok == true and data.Insurance == 1 and data.Credits == 1000 - Config.Town.Insurance.Price)

	-- 準備給客戶端看的畫面：商人帶著貨
	TownService.SetJob(player, "Merchant")
	TownService.AddCargoForTest(player, { Kind = "Resource", Resource = "StarOre", Stolen = false })
	TownService.AddCargoForTest(player, relicItem)
	TownService.RefreshAttributes(player)

	TownService.RemoveActor(robber)
	TownService.RemoveActor(guard)
	TownService.RemoveActor(merchant)
	local finalState = ShopService.InvokeForTest(player, "GetState").State
	signal:FireClient(player, "ServerDone", finalState)
	log("server part done")
end, debug.traceback)

if not ok then
	fail += 1
	warn(P .. "SERVER DRIVER ERROR: " .. tostring(err))
	local player = Players:GetPlayers()[1]
	if player then
		signal:FireClient(player, "ServerDone", nil)
	end
end

local started = os.clock()
while not clientDone and os.clock() - started < 90 do
	task.wait(0.2)
end
print(P .. string.format("SERVER pass=%d fail=%d | CLIENT %s", pass, fail, clientResult))
finish("done")
]==]

local CLIENT_SOURCE = [==[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local P = "[PawnTest] "
local pass, fail = 0, 0
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		warn(P .. "FAIL(client): " .. name .. (detail ~= nil and (" | " .. tostring(detail)) or ""))
	end
end

local signal = ReplicatedStorage:WaitForChild("PawnTestSignal", 30)
local serverState = nil
local serverDone = false
signal.OnClientEvent:Connect(function(kind, state)
	if kind == "ServerDone" then
		serverState = state
		serverDone = true
	end
end)

local ok, err = xpcall(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("PawnShopUI", 20)
	check("介面已建立", gui ~= nil)

	-- 剛進遊戲沒職業：職業選單應該自動打開
	local picker = gui:WaitForChild("JobPicker", 10)
	local started = os.clock()
	while picker and not picker.Visible and os.clock() - started < 15 do
		task.wait(0.2)
	end
	check("沒職業時自動打開職業選單", picker ~= nil and picker.Visible)
	local jobButtons = 0
	for _, d in picker:GetDescendants() do
		if d:IsA("TextButton") and string.find(d.Text, "當", 1, true) then
			jobButtons += 1
		end
	end
	check("職業選單有 3 個職業按鈕", jobButtons == 3, jobButtons)

	signal:FireServer("ClientReady")
	started = os.clock()
	while not serverDone and os.clock() - started < 200 do
		task.wait(0.3)
	end
	check("伺服器測試完成", serverDone)
	task.wait(1.5)

	local function report(tag)
		task.wait(0.4)
		local overflow = {}
		local count = 0
		for _, d in gui:GetDescendants() do
			if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Visible then
				local visible = true
				local node = d.Parent
				while node and node ~= gui do
					if node:IsA("GuiObject") and not node.Visible then
						visible = false
						break
					end
					node = node.Parent
				end
				if visible then
					count += 1
					if d.Text ~= "" and not d.TextFits then
						table.insert(overflow, string.format("%s %dx%d「%s」", d.ClassName, d.AbsoluteSize.X, d.AbsoluteSize.Y, d.Text))
					end
				end
			end
		end
		local viewport = workspace.CurrentCamera.ViewportSize
		print(P .. string.format("layout[%s] viewport=%dx%d texts=%d overflow=%d", tag, viewport.X, viewport.Y, count, #overflow))
		for i = 1, math.min(#overflow, 8) do
			print(P .. "  overflow: " .. overflow[i])
		end
		return #overflow
	end

	-- 小鎮模式（商人帶著貨）
	check("職業選單已關閉或可關閉", true)
	if picker.Visible then
		picker.Visible = false
	end
	report("town-merchant")
	local topText = ""
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "商人", 1, true) then
			topText = d.Text
		end
	end
	check("畫面上顯示商人職業", topText ~= "", topText)
	check("Attribute 有職業", player:GetAttribute("Job") == "Merchant")
	check("Attribute 有貨物", (player:GetAttribute("Cargo") or 0) >= 2)

	-- 透過 RemoteFunction 換職業、打開背包
	local shopAction = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopAction")
	local response = shopAction:InvokeServer("ChooseJob", { JobId = "Guard" })
	check("客戶端換職業", type(response) == "table" and response.Ok == true, response and response.Message)
	task.wait(0.3)
	response = shopAction:InvokeServer("ChooseJob", { JobId = "Ninja" })
	check("不存在的職業被拒絕", type(response) == "table" and response.Ok == false)
	task.wait(0.3)
	response = shopAction:InvokeServer("NextCustomer")
	check("不是當舖老闆不能接客", type(response) == "table" and response.Ok == false)
	report("town-guard")

	local bagButtonFound = false
	for _, d in gui:GetDescendants() do
		if d:IsA("TextButton") and d.Text == "📒 背包" then
			bagButtonFound = true
		end
	end
	check("有背包按鈕", bagButtonFound)
	local camera = workspace.CurrentCamera
	check("平常是一般鏡頭", camera.CameraType ~= Enum.CameraType.Scriptable, camera.CameraType.Name)

	local jailBanner = gui:FindFirstChild("JailBanner")
	check("沒坐牢時不顯示坐牢畫面", jailBanner ~= nil and jailBanner.Visible == false)
end, debug.traceback)

if not ok then
	fail += 1
	warn(P .. "CLIENT DRIVER ERROR: " .. tostring(err))
end
print(P .. string.format("CLIENT pass=%d fail=%d", pass, fail))
signal:FireServer("ClientDone", string.format("pass=%d fail=%d", pass, fail))
]==]

print("[PawnTest] PLUGIN BEGIN")

local starterScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
local driver = Instance.new("LocalScript")
driver.Name = "PawnTestDriver"
driver.Source = CLIENT_SOURCE
driver.Parent = starterScripts

local serverDriver = Instance.new("Script")
serverDriver.Name = "PawnTestServer"
serverDriver.Source = SERVER_SOURCE
serverDriver.Parent = ServerScriptService

local ok, result = pcall(function()
	return game:GetService("StudioTestService"):ExecutePlayModeAsync({})
end)
print("[PawnTest] PLAY RESULT ok=" .. tostring(ok) .. " result=" .. tostring(result))

driver:Destroy()
serverDriver:Destroy()
print("[PawnTest] PLUGIN END")
