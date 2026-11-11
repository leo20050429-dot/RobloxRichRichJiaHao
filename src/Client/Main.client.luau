-- 客戶端進入點：建立介面、把按鈕接到伺服器、收到狀態就重畫。
-- 客戶端只負責顯示與送出請求，所有判定都在伺服器。

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UI = require(script.Parent:WaitForChild("UI"))
local CustomerModel = require(script.Parent:WaitForChild("CustomerModel"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shopAction = remotes:WaitForChild("ShopAction")
local stateChanged = remotes:WaitForChild("StateChanged")
local notifyEvent = remotes:WaitForChild("Notify")
local openJobPicker = remotes:WaitForChild("OpenJobPicker")

-- 聊天視窗預設在左上角，會蓋住左邊面板（簽到按鈕），移到下方中間
task.spawn(function()
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local window = TextChatService:WaitForChild("ChatWindowConfiguration", 10)
		if window then
			window.HorizontalAlignment = Enum.HorizontalAlignment.Center
			window.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	end)
	if not ok then
		warn("[Client] 移動聊天視窗失敗：" .. tostring(err))
	end
end)

local ui
local busy = false
local lastState = nil -- 最近一次收到的狀態

-- 鏡頭 -----------------------------------------------------------------------
-- 櫃檯營業時把鏡頭固定在店長身後、越過櫃檯看著客人；其他時候是一般第三人稱鏡頭。

local cameraBound = false

local function findSpot(shopId)
	local town = workspace:FindFirstChild("Town")
	local shops = town and town:FindFirstChild("Shops")
	local shop = shopId and shops and shops:FindFirstChild(shopId)
	if shop then
		return shop:FindFirstChild("CustomerSpot")
	end
	local single = workspace:FindFirstChild("PawnShop")
	return single and single:FindFirstChild("CustomerSpot") or nil
end

local function setCounterCamera(shopId)
	local spot = shopId and findSpot(shopId) or nil
	if Config.FixedCamera and not spot then
		spot = findSpot(nil)
	end
	if spot then
		-- CustomerSpot 的正前方（LookVector）朝向店長
		local eye = (spot.CFrame * CFrame.new(0, 3.5, -5)).Position
		local target = (spot.CFrame * CFrame.new(0, 0.5, 0)).Position
		local cameraCFrame = CFrame.lookAt(eye, target)
		if cameraBound then
			RunService:UnbindFromRenderStep("ShopCamera")
		end
		cameraBound = true
		RunService:BindToRenderStep("ShopCamera", Enum.RenderPriority.Camera.Value + 1, function()
			local camera = workspace.CurrentCamera
			if camera then
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CFrame = cameraCFrame
			end
		end)
	elseif cameraBound then
		cameraBound = false
		RunService:UnbindFromRenderStep("ShopCamera")
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end

-- 狀態 -----------------------------------------------------------------------

local function applyState(state)
	if not state then
		return
	end
	lastState = state
	ui.Render(state)
	local atCounter = state.Shop ~= nil and state.Shop.CounterOpen
	CustomerModel.Show(atCounter and state.Customer or nil, state.Shop and state.Shop.Id or nil)
	setCounterCamera(atCounter and state.Shop.Id or nil)
end

local function request(action, payload)
	if busy then
		return
	end
	busy = true
	local ok, response = pcall(function()
		return shopAction:InvokeServer(action, payload)
	end)
	busy = false
	if not ok or type(response) ~= "table" then
		ui.Toast("連線出錯，請再試一次。", false)
		return
	end
	if response.Message then
		ui.Toast(response.Message, response.Ok)
	end
	applyState(response.State)
end

ui = UI.Create(playerGui, {
	Next = function()
		request("NextCustomer")
	end,
	Inspect = function(toolId)
		request("Inspect", { ToolId = toolId })
	end,
	Offer = function(amount)
		request("Offer", { Amount = amount })
	end,
	Reject = function()
		request("Reject")
	end,
	Sell = function(uid)
		request("SellItem", { Uid = uid })
	end,
	BuyTool = function(toolId)
		request("BuyTool", { ToolId = toolId })
	end,
	ClaimDaily = function()
		request("ClaimDaily")
	end,
	RedeemCode = function(code)
		request("RedeemCode", { Code = code })
	end,
	ChooseJob = function(jobId)
		request("ChooseJob", { JobId = jobId })
	end,
	CloseCounter = function()
		request("CloseCounter")
	end,
	BuyInsurance = function()
		request("BuyInsurance")
	end,
})

stateChanged.OnClientEvent:Connect(applyState)
notifyEvent.OnClientEvent:Connect(function(text, ok)
	ui.Toast(text, ok)
end)
openJobPicker.OnClientEvent:Connect(function()
	ui.ShowJobPicker()
end)

-- 互動提示：依自己的職業與對方狀態，只顯示用得到的 Prompt（伺服器還是會再檢查一次）---

local function promptShop(prompt)
	local shopId = prompt:GetAttribute("ShopId")
	local town = workspace:FindFirstChild("Town")
	local shops = town and town:FindFirstChild("Shops")
	return shopId and shops and shops:FindFirstChild(shopId) or nil
end

local function refreshPrompts()
	local myJob = player:GetAttribute("Job")
	local jailed = player:GetAttribute("Jailed") == true
	for _, prompt in CollectionService:GetTagged("TownPrompt") do
		if prompt:IsA("ProximityPrompt") then
			local action = prompt:GetAttribute("Action")
			local enabled = not jailed
			if action == "Collect" then
				-- 不是商人也顯示提示，按下去伺服器會說明要換職業，避免新手以為這裡什麼都沒有
				local original = prompt:GetAttribute("OriginalActionText")
				if not original then
					original = prompt.ActionText
					prompt:SetAttribute("OriginalActionText", original)
				end
				local text = myJob == "Merchant" and original or "只有商人能採集"
				if prompt.ActionText ~= text then
					prompt.ActionText = text
				end
				local hold = myJob == "Merchant" and 1.2 or 0
				if prompt.HoldDuration ~= hold then
					prompt.HoldDuration = hold
				end
			elseif action == "Rob" or action == "Arrest" then
				local target = Players:GetPlayerByUserId(prompt:GetAttribute("TargetUserId") or 0)
				if not target or target == player then
					enabled = false
				elseif action == "Rob" then
					enabled = enabled and myJob ~= "Guard" and (target:GetAttribute("Cargo") or 0) > 0 and target:GetAttribute("Protected") ~= true
				else
					enabled = enabled and myJob == "Guard" and (target:GetAttribute("Wanted") or 0) > 0 and target:GetAttribute("Jailed") ~= true
				end
			elseif action == "ShopCounter" then
				local shop = promptShop(prompt)
				local owner = shop and shop:GetAttribute("Owner") or 0
				if owner == player.UserId then
					prompt.ActionText = "打開櫃檯"
				elseif owner == 0 then
					prompt.ActionText = "經營這間當舖"
					enabled = enabled and myJob == "Pawnbroker"
				else
					enabled = false
				end
			elseif action == "SellRelic" then
				local shop = promptShop(prompt)
				local owner = shop and shop:GetAttribute("Owner") or 0
				enabled = enabled and owner ~= 0 and owner ~= player.UserId and (player:GetAttribute("Relics") or 0) > 0
			elseif action == "SellCargo" then
				enabled = enabled and (player:GetAttribute("Cargo") or 0) > 0
			end
			if prompt.Enabled ~= enabled then
				prompt.Enabled = enabled
			end
		end
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(refreshPrompts)
		if not ok then
			warn("[Client] refreshPrompts：" .. tostring(err))
		end
		ui.UpdateLive({
			Wanted = player:GetAttribute("Wanted") or 0,
			Protection = player:GetAttribute("Protection") or "",
			Jailed = player:GetAttribute("Jailed") == true,
			JailedUntilUnix = player:GetAttribute("JailedUntilUnix") or 0,
		})
		task.wait(0.5)
	end
end)

-- 存檔可能比腳本先讀好，主動要一次狀態；還沒讀好的話伺服器會之後用 StateChanged 推過來
task.defer(function()
	local ok, response = pcall(function()
		return shopAction:InvokeServer("GetState")
	end)
	if ok and type(response) == "table" and response.State then
		applyState(response.State)
	end
end)



