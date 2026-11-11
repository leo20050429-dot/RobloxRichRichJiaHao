-- 玩家介面：上方資訊列、左邊客人面板、右邊倉庫 / 商店 / 圖鑑面板、下方訊息。
-- 全部用程式碼建立，UI 設計師之後可以換成 Studio 裡做好的 ScreenGui。
--
-- UI.Create(playerGui, actions) 回傳 { Render = function(state), Toast = function(text, ok) }
-- actions 是一組函式：
--   Next / Inspect(toolId) / Offer(amount) / Reject / Sell(uid) / BuyTool(toolId) / ClaimDaily / RedeemCode(code)
--   ChooseJob(jobId) / CloseCounter / BuyInsurance
--
-- 兩種模式：
--   小鎮模式：左邊是職業指南、身上貨物、各地收購價；右邊的背包可以開關。
--   櫃檯模式（當舖老闆在櫃檯營業時）：左邊是客人，右邊是倉庫 / 商店 / 圖鑑。

local TweenService = game:GetService("TweenService")

local UI = {}

local COLORS = {
	Panel = Color3.fromRGB(22, 22, 38),
	PanelSoft = Color3.fromRGB(34, 34, 56),
	Stroke = Color3.fromRGB(90, 80, 170),
	Text = Color3.fromRGB(235, 235, 250),
	Muted = Color3.fromRGB(160, 160, 190),
	Accent = Color3.fromRGB(70, 220, 255),
	Good = Color3.fromRGB(110, 225, 140),
	Bad = Color3.fromRGB(255, 110, 110),
	Gold = Color3.fromRGB(255, 210, 90),
	Button = Color3.fromRGB(95, 80, 230),
	ButtonGold = Color3.fromRGB(215, 150, 30),
	ButtonDanger = Color3.fromRGB(190, 70, 90),
	ButtonDisabled = Color3.fromRGB(70, 70, 90),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(200, 200, 215),
	Rare = Color3.fromRGB(90, 170, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 70),
}

local VARIANT_COLORS = {
	Shiny = Color3.fromRGB(255, 235, 120),
	Rainbow = Color3.fromRGB(255, 130, 220),
}

local VARIANT_BADGES = {
	Shiny = "✨閃亮",
	Rainbow = "🌈彩虹",
}

local FONT = Enum.Font.BuilderSans
local FONT_BOLD = Enum.Font.BuilderSansBold

local function new(className, props, children)
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

local function stroke(color, thickness)
	return new("UIStroke", { Color = color or COLORS.Stroke, Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function padding(px)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function list(direction, gap)
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local function label(props)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = COLORS.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 22),
	}
	for key, value in props do
		base[key] = value
	end
	return new("TextLabel", base)
end

-- 會依內容自動長高的文字
local function textBlock(props)
	local base = {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in props do
		base[key] = value
	end
	return label(base)
end

local function button(text, color, onClick, props)
	local base = {
		Text = text,
		Font = FONT_BOLD,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = color or COLORS.Button,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 36),
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	local b = new("TextButton", base, { corner(8) })
	if onClick then
		b.Activated:Connect(function()
			onClick()
		end)
	end
	return b
end

local function card(parent, order, strokeColor)
	local children = { corner(10), padding(10), list(Enum.FillDirection.Vertical, 4) }
	if strokeColor then
		table.insert(children, stroke(strokeColor, 1.5))
	end
	return new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.PanelSoft,
		LayoutOrder = order,
		Parent = parent,
	}, children)
end

-- 清掉 frame 裡的內容（保留排版用的 UI 元件）
local function clearChildren(frame)
	for _, child in frame:GetChildren() do
		-- UIComponent 包含 layout、padding、圓角、外框、尺寸限制，這些要留著
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

local function toneColor(tone)
	if tone == "good" then
		return COLORS.Good
	elseif tone == "bad" then
		return COLORS.Bad
	end
	return COLORS.Muted
end

local function itemColor(rarity, variant)
	return VARIANT_COLORS[variant] or RARITY_COLORS[rarity] or COLORS.Text
end

local function scrollPanel(props)
	local base = {
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = COLORS.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	for key, value in props do
		base[key] = value
	end
	return new("ScrollingFrame", base, { corner(12), stroke(), padding(12), list(Enum.FillDirection.Vertical, 8) })
end

function UI.Create(playerGui, actions)
	local gui = new("ScreenGui", {
		Name = "PawnShopUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	-- 上方資訊列 --------------------------------------------------------------
	local topBar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.9, 0, 0, 40),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.08,
		Parent = gui,
	}, { corner(12), stroke(), padding(8), list(Enum.FillDirection.Horizontal, 12), new("UISizeConstraint", { MaxSize = Vector2.new(720, 40), MinSize = Vector2.new(300, 40) }) })

	local creditsLabel = label({ Text = "星幣 —", TextColor3 = COLORS.Gold, Font = FONT_BOLD, Size = UDim2.new(0.2, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true, LayoutOrder = 1, Parent = topBar })
	local repLabel = label({ Text = "名聲 —", TextColor3 = COLORS.Accent, Font = FONT_BOLD, Size = UDim2.new(0.3, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true, LayoutOrder = 2, Parent = topBar })
	local jobLabel = label({ Text = "選擇職業", TextColor3 = COLORS.Text, Font = FONT_BOLD, Size = UDim2.new(0.2, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true, LayoutOrder = 3, Parent = topBar })
	local statusLabel = label({ Text = "", TextColor3 = COLORS.Good, Font = FONT_BOLD, Size = UDim2.new(0.22, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true, LayoutOrder = 4, Parent = topBar })
	for _, l in { creditsLabel, repLabel, jobLabel, statusLabel } do
		new("UITextSizeConstraint", { MaxTextSize = 20, Parent = l })
	end

	-- 左邊：客人面板 ------------------------------------------------------------
	local customerPanel = scrollPanel({
		Name = "CustomerPanel",
		Position = UDim2.new(0, 12, 0, 60),
		Size = UDim2.new(0.4, 0, 1, -72),
		Parent = gui,
	})
	new("UISizeConstraint", { MaxSize = Vector2.new(420, 10000), Parent = customerPanel })

	-- 右邊：倉庫 / 商店 / 圖鑑 ---------------------------------------------------
	local rightHolder = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 60),
		Size = UDim2.new(0.34, 0, 1, -72),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(360, 10000) }) })

	local tabRow = new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = rightHolder,
	}, { list(Enum.FillDirection.Horizontal, 6) })

	local rightPanel = scrollPanel({
		Name = "SidePanel",
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		Parent = rightHolder,
	})

	local offerDraft = { Id = nil, Text = "" }
	local codeDraft = ""
	local currentTab = "Inventory"
	local renderedTab = nil
	local lastState = nil
	local renderSide -- 前向宣告

	local tabButtons = {}
	local tabDefs = {
		{ Id = "Inventory", Text = "倉庫" },
		{ Id = "Shop", Text = "商店" },
		{ Id = "Codex", Text = "圖鑑" },
	}
	for i, def in tabDefs do
		tabButtons[def.Id] = button(def.Text, COLORS.PanelSoft, function()
			currentTab = def.Id
			renderSide()
		end, { Size = UDim2.new(1 / 3, -4, 1, 0), LayoutOrder = i, Parent = tabRow })
	end

	local bagButton = button("📒 背包", COLORS.Button, nil, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 60),
		Size = UDim2.new(0, 110, 0, 36),
		TextSize = 15,
		Parent = gui,
	})
	local bagOpen = false
	local function setBagOpen(open)
		bagOpen = open
		rightHolder.Visible = open
		bagButton.Text = open and "✖ 關閉" or "📒 背包"
		-- 背包打開時，按鈕移到背包下方，避免擋住分頁
		bagButton.Position = open and UDim2.new(1, -12, 1, -48) or UDim2.new(1, -12, 0, 60)
	end
	bagButton.Activated:Connect(function()
		setBagOpen(not bagOpen)
	end)

	-- 職業選單（置中的大視窗）
	local jobPicker = new("Frame", {
		Name = "JobPicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0.8, 0),
		BackgroundColor3 = COLORS.Panel,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { corner(16), stroke(COLORS.Gold, 2), padding(16), new("UISizeConstraint", { MaxSize = Vector2.new(720, 520) }) })
	local jobPickerList = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 21,
		Parent = jobPicker,
	}, { list(Enum.FillDirection.Vertical, 10) })

	local function showJobPicker(state)
		local town = state and state.Town
		if not town then
			return
		end
		clearChildren(jobPickerList)
		label({ Text = "選擇你的職業", Font = FONT_BOLD, TextSize = 24, Size = UDim2.new(1, 0, 0, 32), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22, LayoutOrder = 0, Parent = jobPickerList })
		textBlock({ Text = "之後隨時可以到廣場的「職業公告板」換職業。任何人都可以搶劫（保鑣除外），但會扣名聲、被通緝！", TextColor3 = COLORS.Muted, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22, LayoutOrder = 1, Parent = jobPickerList })
		for i, job in town.Jobs do
			local c = job.Color or { 1, 1, 1 }
			local jobColor = Color3.new(c[1], c[2], c[3])
			local jobCard = card(jobPickerList, 10 + i, jobColor)
			jobCard.ZIndex = 22
			label({ Text = job.Icon .. " " .. job.Name, Font = FONT_BOLD, TextSize = 20, TextColor3 = jobColor, Size = UDim2.new(1, 0, 0, 26), ZIndex = 23, LayoutOrder = 1, Parent = jobCard })
			textBlock({ Text = job.Summary, TextColor3 = COLORS.Text, TextSize = 14, ZIndex = 23, LayoutOrder = 2, Parent = jobCard })
			local isCurrent = town.Job == job.Id
			button(isCurrent and "目前的職業" or ("當" .. job.Name), isCurrent and COLORS.ButtonDisabled or COLORS.Button, function()
				if not isCurrent then
					jobPicker.Visible = false
					actions.ChooseJob(job.Id)
				end
			end, { Size = UDim2.new(1, 0, 0, 34), TextSize = 15, ZIndex = 23, LayoutOrder = 3, Parent = jobCard })
		end
		if town.Job then
			button("先不換", COLORS.PanelSoft, function()
				jobPicker.Visible = false
			end, { Size = UDim2.new(1, 0, 0, 34), TextSize = 15, ZIndex = 22, LayoutOrder = 99, Parent = jobPickerList })
		end
		jobPicker.Visible = true
	end

	-- 坐牢畫面
	local jailBanner = label({
		Name = "JailBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(0, 340, 0, 44),
		BackgroundColor3 = Color3.fromRGB(90, 20, 30),
		BackgroundTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = FONT_BOLD,
		TextSize = 20,
		Visible = false,
		ZIndex = 15,
		Parent = gui,
	})
	corner(10).Parent = jailBanner

	-- 下方訊息 -----------------------------------------------------------------
	local toastLabel = textBlock({
		-- 放在上方（坐牢橫幅下面），下方中間留給聊天視窗
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.new(0.4, 0, 0, 0),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = COLORS.Panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = FONT_BOLD,
		TextSize = 17,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	corner(10).Parent = toastLabel
	stroke(COLORS.Accent).Parent = toastLabel
	padding(10).Parent = toastLabel

	local toastToken = 0
	local function toast(text, ok)
		if not text or text == "" then
			return
		end
		toastToken += 1
		local token = toastToken
		toastLabel.Text = text
		toastLabel.TextColor3 = (ok == false) and COLORS.Bad or COLORS.Text
		toastLabel.TextTransparency = 0
		toastLabel.BackgroundTransparency = 0.1
		toastLabel.Visible = true
		-- 訊息越長顯示越久
		local _, lineBreaks = string.gsub(text, "\n", "\n")
		local duration = 3.5 + lineBreaks * 1.5
		task.delay(duration, function()
			if token ~= toastToken then
				return
			end
			local info = TweenInfo.new(0.4)
			TweenService:Create(toastLabel, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.delay(0.45, function()
				if token == toastToken then
					toastLabel.Visible = false
				end
			end)
		end)
	end

	-- 小鎮模式的左邊面板 ------------------------------------------------------
	local function renderTown(state, nextOrder)
		local town = state.Town
		if not state.Persistent then
			textBlock({ Text = "⚠ 存檔未啟用：這次的進度不會被保存。", TextColor3 = COLORS.Gold, TextSize = 13, LayoutOrder = nextOrder(), Parent = customerPanel })
		end
		if state.Daily and state.Daily.Available then
			button(
				string.format("🎁 領取每日獎勵 +%d 星幣", state.Daily.Reward),
				COLORS.ButtonGold,
				actions.ClaimDaily,
				{ Size = UDim2.new(1, 0, 0, 36), TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel }
			)
		end
		if not town then
			return
		end

		if not town.Job then
			label({ Text = "歡迎來到星塵鎮！", Font = FONT_BOLD, TextSize = 20, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Parent = customerPanel })
			button("選擇職業", COLORS.Button, function()
				showJobPicker(state)
			end, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = nextOrder(), Parent = customerPanel })
			return
		end

		-- 職業指南
		label({ Text = town.JobIcon .. " " .. town.JobName, Font = FONT_BOLD, TextSize = 20, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Parent = customerPanel })
		for i, step in town.JobSteps do
			textBlock({ Text = string.format("%d. %s", i, step), TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = nextOrder(), Parent = customerPanel })
		end

		-- 當舖老闆：店面狀態
		if town.Job == "Pawnbroker" then
			if state.Shop then
				local text = string.format("你經營 %d 號當舖。走到櫃檯按「打開櫃檯」開始營業。", state.Shop.Index)
				if state.Shop.QueueCount > 0 then
					text ..= string.format("\n📦 有 %d 位玩家商人在排隊等你出價！", state.Shop.QueueCount)
				end
				textBlock({ Text = text, TextColor3 = COLORS.Accent, Font = FONT_BOLD, TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
			else
				textBlock({ Text = "你還沒有店面。到廣場北邊的商店街，找一間「空店面」經營。", TextColor3 = COLORS.Gold, Font = FONT_BOLD, TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
			end
		end

		-- 身上的貨物
		local cargoCard = card(customerPanel, nextOrder())
		label({ Text = string.format("📦 身上的貨物（%d / %d）", #town.Cargo, town.Capacity), Font = FONT_BOLD, TextSize = 15, LayoutOrder = 1, Parent = cargoCard })
		if #town.Cargo == 0 then
			textBlock({ Text = town.Job == "Merchant" and "空的。出城到礦場或墜毀點採集吧！" or "空的。", TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = 2, Parent = cargoCard })
		else
			-- 同名的貨物合併顯示
			local counts, orderList = {}, {}
			for _, item in town.Cargo do
				if not counts[item.Name] then
					counts[item.Name] = { Count = 0, Stolen = item.Stolen, Relic = item.Kind == "Relic" }
					table.insert(orderList, item.Name)
				end
				counts[item.Name].Count += 1
			end
			for i, name in orderList do
				local info = counts[name]
				local color = info.Stolen and COLORS.Bad or (info.Relic and COLORS.Gold or COLORS.Text)
				textBlock({ Text = string.format("• %s ×%d", name, info.Count), TextColor3 = color, TextSize = 13, LayoutOrder = 1 + i, Parent = cargoCard })
			end
		end

		-- 各地收購價（商人才需要，劫匪銷贓也看得到黑市）
		if town.Job == "Merchant" or #town.Cargo > 0 then
			local priceCard = card(customerPanel, nextOrder())
			label({ Text = "💰 現在的收購價", Font = FONT_BOLD, TextSize = 15, LayoutOrder = 1, Parent = priceCard })
			for i, row in town.Prices do
				local parts = {}
				for _, price in row.Prices do
					table.insert(parts, string.format("%s %d", price.Name, price.Price))
				end
				textBlock({ Text = row.Buyer .. "：" .. table.concat(parts, "　"), TextColor3 = (row.Buyer == "黑市") and COLORS.Bad or COLORS.Muted, TextSize = 13, LayoutOrder = 1 + i, Parent = priceCard })
			end
			textBlock({ Text = "黑市什麼都收（包括贓物），但價格最差。", TextColor3 = COLORS.Muted, TextSize = 12, LayoutOrder = 20, Parent = priceCard })
		end

		-- 保護
		local protectCard = card(customerPanel, nextOrder())
		label({ Text = string.format("🛡️ 搶劫保險：%d / %d 份", town.Insurance, town.InsuranceMax), Font = FONT_BOLD, TextSize = 14, LayoutOrder = 1, Parent = protectCard })
		textBlock({ Text = "被搶時理賠一部分損失。安全區、新手保護、保鑣護送時都不會被搶。", TextColor3 = COLORS.Muted, TextSize = 12, LayoutOrder = 2, Parent = protectCard })
		if town.Insurance < town.InsuranceMax then
			button(string.format("買一份保險（%d 星幣）", town.InsurancePrice), COLORS.PanelSoft, actions.BuyInsurance, { Size = UDim2.new(1, 0, 0, 30), TextSize = 13, LayoutOrder = 3, Parent = protectCard })
		end

		button("換職業", COLORS.PanelSoft, function()
			showJobPicker(state)
		end, { Size = UDim2.new(1, 0, 0, 32), TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
	end

	-- 客人面板內容 ------------------------------------------------------------
	local function renderCustomer(state)
		clearChildren(customerPanel)
		local customer = state.Customer
		local order = 0
		local function nextOrder()
			order += 1
			return order
		end

		local atCounter = state.Shop ~= nil and state.Shop.CounterOpen
		if not atCounter then
			renderTown(state, nextOrder)
			return
		end

		button("🚪 打烊（離開櫃檯）", COLORS.ButtonDanger, actions.CloseCounter, { Size = UDim2.new(1, 0, 0, 34), TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
		if state.Shop.QueueCount > 0 then
			textBlock({ Text = string.format("📦 有 %d 位玩家商人在排隊", state.Shop.QueueCount), TextColor3 = COLORS.Gold, Font = FONT_BOLD, TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
		end

		if not state.Persistent then
			textBlock({ Text = "⚠ 存檔未啟用：這次的進度不會被保存。", TextColor3 = COLORS.Gold, TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
		end

		-- 每日獎勵
		if state.Daily and state.Daily.Available then
			button(
				string.format("🎁 領取每日獎勵 +%d 星幣（連續第 %d 天）", state.Daily.Reward, state.Daily.Streak),
				COLORS.ButtonGold,
				actions.ClaimDaily,
				{ Size = UDim2.new(1, 0, 0, 40), TextSize = 15, LayoutOrder = nextOrder(), Parent = customerPanel }
			)
		end

		-- 銀河新聞
		if state.News then
			local newsCard = card(customerPanel, nextOrder(), COLORS.Accent)
			local minutes = math.max(1, math.ceil(state.News.SecondsLeft / 60))
			label({ Text = "📰 " .. state.News.Title, Font = FONT_BOLD, TextColor3 = COLORS.Accent, TextSize = 15, LayoutOrder = 1, Parent = newsCard })
			textBlock({ Text = string.format("%s（約 %d 分鐘後換新聞）", state.News.Description, minutes), TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = 2, Parent = newsCard })
		end

		if not customer then
			label({ Text = "店裡現在沒有客人", Font = FONT_BOLD, TextSize = 22, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(), Parent = customerPanel })
			textBlock({ Text = "叫下一位客人進來，鑑定他帶來的東西，用比「行情價」低的價格收購，再到右邊的倉庫賣到市場賺差價。小心假貨！", TextColor3 = COLORS.Muted, LayoutOrder = nextOrder(), Parent = customerPanel })
			button("下一位客人", COLORS.Button, actions.Next, { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = nextOrder(), Parent = customerPanel })
			return
		end

		label({ Text = customer.Name .. "（" .. customer.Species .. "）", Font = FONT_BOLD, TextSize = 22, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(), Parent = customerPanel })
		if customer.IsPlayerSeller then
			textBlock({ Text = "這是真的玩家！成交的錢會付給他。", TextColor3 = COLORS.Gold, TextSize = 13, LayoutOrder = nextOrder(), Parent = customerPanel })
		end
		if customer.Stolen then
			textBlock({ Text = "⚠ 這件是贓物。收下會扣 2 點名聲。", TextColor3 = COLORS.Bad, Font = FONT_BOLD, TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
		end

		local bubble = new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = COLORS.PanelSoft,
			LayoutOrder = nextOrder(),
			Parent = customerPanel,
		}, { corner(10), padding(10) })
		textBlock({ Text = "「" .. customer.Line .. "」", Parent = bubble })

		textBlock({ Text = customer.ItemName, Font = FONT_BOLD, TextSize = 18, TextColor3 = itemColor(customer.Rarity, customer.Variant), LayoutOrder = nextOrder(), Parent = customerPanel })
		label({ Text = customer.RarityName .. "　·　" .. customer.Category, TextSize = 14, TextColor3 = RARITY_COLORS[customer.Rarity] or COLORS.Muted, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder(), Parent = customerPanel })
		if VARIANT_BADGES[customer.Variant] then
			textBlock({
				Text = string.format("%s版！價值是普通版的 %d 倍", VARIANT_BADGES[customer.Variant], customer.VariantMultiplier),
				Font = FONT_BOLD,
				TextSize = 15,
				TextColor3 = VARIANT_COLORS[customer.Variant],
				LayoutOrder = nextOrder(),
				Parent = customerPanel,
			})
		end
		textBlock({ Text = customer.ItemDescription, TextColor3 = COLORS.Muted, TextSize = 15, LayoutOrder = nextOrder(), Parent = customerPanel })
		label({ Text = string.format("客人開價：%d 星幣", customer.AskingPrice), Font = FONT_BOLD, TextColor3 = COLORS.Gold, TextSize = 18, LayoutOrder = nextOrder(), Parent = customerPanel })
		if customer.MarketPrice then
			textBlock({
				Text = string.format("行情價：%d 星幣（真品而且沒瑕疵才賣得到這個價）", customer.MarketPrice),
				TextColor3 = COLORS.Accent,
				TextSize = 14,
				LayoutOrder = nextOrder(),
				Parent = customerPanel,
			})
		end

		if customer.Floor then
			label({ Text = string.format("讀心眼鏡：他心裡的底價是 %d", customer.Floor), TextColor3 = COLORS.Good, TextSize = 15, LayoutOrder = nextOrder(), Parent = customerPanel })
		end
		if customer.FakeChance then
			label({ Text = string.format("天眼掃描儀：這類物品約 %d%% 是假貨", math.floor(customer.FakeChance * 100 + 0.5)), TextColor3 = COLORS.Good, TextSize = 15, LayoutOrder = nextOrder(), Parent = customerPanel })
		end

		-- 耐心條
		local maxPatience = math.max(1, customer.MaxPatience or 100)
		label({ Text = string.format("耐心 %d / %d", customer.Patience, maxPatience), TextColor3 = COLORS.Muted, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder(), Parent = customerPanel })
		local barBack = new("Frame", { Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = COLORS.PanelSoft, LayoutOrder = nextOrder(), Parent = customerPanel }, { corner(5) })
		local ratio = math.clamp(customer.Patience / maxPatience, 0, 1)
		new("Frame", {
			Size = UDim2.new(ratio, 0, 1, 0),
			BackgroundColor3 = COLORS.Good:Lerp(COLORS.Bad, 1 - ratio),
			Parent = barBack,
		}, { corner(5) })

		-- 鑑定結果
		label({ Text = "鑑定紀錄", Font = FONT_BOLD, TextSize = 16, LayoutOrder = nextOrder(), Parent = customerPanel })
		if #customer.Findings == 0 then
			textBlock({ Text = "還沒鑑定。用下面的工具檢查看看（會消耗客人的耐心）。", TextColor3 = COLORS.Muted, TextSize = 14, LayoutOrder = nextOrder(), Parent = customerPanel })
		else
			for _, finding in customer.Findings do
				textBlock({ Text = "• " .. finding.Tool .. "：" .. finding.Text, TextColor3 = toneColor(finding.Tone), TextSize = 15, LayoutOrder = nextOrder(), Parent = customerPanel })
			end
		end

		-- 工具按鈕
		local toolGrid = new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
			Parent = customerPanel,
		}, { new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 36), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
		for i, tool in state.Tools do
			if tool.Owned then
				local used = tool.UsedOnCustomer
				local b = button(
					used and (tool.Name .. " ✓") or string.format("%s（-%d）", tool.Name, tool.PatienceCost),
					used and COLORS.ButtonDisabled or COLORS.PanelSoft,
					function()
						if not used then
							actions.Inspect(tool.Id)
						end
					end,
					{ LayoutOrder = i, TextSize = 14, AutoButtonColor = not used, Parent = toolGrid }
				)
				stroke(COLORS.Stroke, 1).Parent = b
			end
		end

		-- 出價
		local offerRow = new("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
			Parent = customerPanel,
		}, { list(Enum.FillDirection.Horizontal, 8) })
		local offerBox = new("TextBox", {
			Size = UDim2.new(0.6, -4, 1, 0),
			BackgroundColor3 = COLORS.PanelSoft,
			TextColor3 = COLORS.Text,
			PlaceholderText = "輸入你的出價",
			PlaceholderColor3 = COLORS.Muted,
			-- 同一位客人重畫介面時，保留剛剛輸入的出價
			Text = (offerDraft.Id == customer.Id) and offerDraft.Text or "",
			Font = FONT_BOLD,
			TextSize = 18,
			ClearTextOnFocus = false,
			LayoutOrder = 1,
			Parent = offerRow,
		}, { corner(8), stroke(COLORS.Stroke, 1) })
		offerBox:GetPropertyChangedSignal("Text"):Connect(function()
			local digits = string.gsub(offerBox.Text, "%D", "")
			if digits ~= offerBox.Text then
				offerBox.Text = digits
				return
			end
			offerDraft.Id = customer.Id
			offerDraft.Text = digits
		end)
		local function submitOffer()
			local amount = tonumber(offerBox.Text)
			if not amount or amount < 1 then
				toast("先輸入一個價格。", false)
				return
			end
			actions.Offer(math.floor(amount))
		end
		button("出價", COLORS.Button, submitOffer, { Size = UDim2.new(0.4, -4, 1, 0), LayoutOrder = 2, Parent = offerRow })
		offerBox.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				submitOffer()
			end
		end)

		local quickRow = new("Frame", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
			Parent = customerPanel,
		}, { list(Enum.FillDirection.Horizontal, 8) })
		-- 快速出價：開價的 50% / 70%
		for i, pct in { 50, 70 } do
			local value = math.max(1, math.floor(customer.AskingPrice * pct / 100))
			button(string.format("%d%%（%d）", pct, value), COLORS.PanelSoft, function()
				offerBox.Text = tostring(value)
			end, { Size = UDim2.new(0.33, -6, 1, 0), TextSize = 14, LayoutOrder = i, Parent = quickRow })
		end
		button("不收了", COLORS.ButtonDanger, actions.Reject, { Size = UDim2.new(0.34, -4, 1, 0), TextSize = 14, LayoutOrder = 3, Parent = quickRow })
	end

	-- 右邊面板內容 ------------------------------------------------------------
	local function renderInventory(state)
		label({ Text = string.format("倉庫（%d / %d）", #state.Inventory, state.InventoryLimit), Font = FONT_BOLD, TextSize = 18, LayoutOrder = 0, Parent = rightPanel })
		if #state.Inventory == 0 then
			textBlock({ Text = "倉庫是空的。收購的東西會出現在這裡，按「賣到市場」就會揭曉真假並換成星幣。", TextColor3 = COLORS.Muted, TextSize = 14, LayoutOrder = 1, Parent = rightPanel })
			return
		end
		for i, item in state.Inventory do
			local itemCard = card(rightPanel, i, VARIANT_COLORS[item.Variant])
			textBlock({ Text = item.Name, Font = FONT_BOLD, TextSize = 16, TextColor3 = itemColor(item.Rarity, item.Variant), LayoutOrder = 1, Parent = itemCard })
			label({ Text = string.format("%s　·　收購價 %d 星幣", item.RarityName, item.PaidPrice), TextColor3 = COLORS.Gold, TextSize = 14, LayoutOrder = 2, Parent = itemCard })
			if item.NewsMultiplier and item.NewsMultiplier > 1 then
				label({ Text = string.format("📈 新聞加成：現在賣價 ×%.1f", item.NewsMultiplier), TextColor3 = COLORS.Good, Font = FONT_BOLD, TextSize = 14, LayoutOrder = 3, Parent = itemCard })
			end
			local notes = #item.Findings > 0 and table.concat(item.Findings, "\n") or "（沒有鑑定紀錄）"
			textBlock({ Text = notes, TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = 4, Parent = itemCard })
			button("賣到市場", COLORS.Button, function()
				actions.Sell(item.Uid)
			end, { Size = UDim2.new(1, 0, 0, 32), TextSize = 15, LayoutOrder = 5, Parent = itemCard })
		end
	end

	local function renderShop(state)
		label({ Text = "工具商店", Font = FONT_BOLD, TextSize = 18, LayoutOrder = 0, Parent = rightPanel })
		for i, tool in state.Tools do
			local toolCard = card(rightPanel, i)
			label({ Text = tool.Name, Font = FONT_BOLD, TextSize = 16, LayoutOrder = 1, Parent = toolCard })
			textBlock({ Text = tool.Description, TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = 2, Parent = toolCard })
			label({ Text = string.format("每次使用 -%d 耐心", tool.PatienceCost), TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = 3, Parent = toolCard })
			if tool.Owned then
				button("已擁有", COLORS.ButtonDisabled, nil, { Size = UDim2.new(1, 0, 0, 32), TextSize = 15, AutoButtonColor = false, LayoutOrder = 4, Parent = toolCard })
			else
				local affordable = state.Credits >= tool.Price
				button(string.format("購買（%d 星幣）", tool.Price), affordable and COLORS.Button or COLORS.ButtonDisabled, function()
					actions.BuyTool(tool.Id)
				end, { Size = UDim2.new(1, 0, 0, 32), TextSize = 15, LayoutOrder = 4, Parent = toolCard })
			end
		end

		-- 兌換碼
		local codeCard = card(rightPanel, 100)
		label({ Text = "兌換碼", Font = FONT_BOLD, TextSize = 16, LayoutOrder = 1, Parent = codeCard })
		local codeRow = new("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = codeCard,
		}, { list(Enum.FillDirection.Horizontal, 6) })
		local codeBox = new("TextBox", {
			Size = UDim2.new(0.62, -3, 1, 0),
			BackgroundColor3 = COLORS.Panel,
			TextColor3 = COLORS.Text,
			PlaceholderText = "輸入兌換碼",
			PlaceholderColor3 = COLORS.Muted,
			Text = codeDraft,
			Font = FONT_BOLD,
			TextSize = 15,
			ClearTextOnFocus = false,
			LayoutOrder = 1,
			Parent = codeRow,
		}, { corner(8), stroke(COLORS.Stroke, 1) })
		codeBox:GetPropertyChangedSignal("Text"):Connect(function()
			codeDraft = string.sub(codeBox.Text, 1, 32)
		end)
		button("兌換", COLORS.ButtonGold, function()
			local code = codeDraft
			if code == "" then
				toast("先輸入兌換碼。", false)
				return
			end
			codeDraft = ""
			actions.RedeemCode(code)
		end, { Size = UDim2.new(0.38, -3, 1, 0), TextSize = 15, LayoutOrder = 2, Parent = codeRow })
	end

	local function renderCodex(state)
		-- 稱號
		local rankCard = card(rightPanel, 1, COLORS.Accent)
		label({ Text = "稱號：" .. state.Rank.Title, Font = FONT_BOLD, TextColor3 = COLORS.Accent, TextSize = 16, LayoutOrder = 1, Parent = rankCard })
		if state.Rank.NextTitle then
			textBlock({ Text = string.format("名聲到 %d 升級為「%s」（目前 %d）", state.Rank.NextAt, state.Rank.NextTitle, state.Reputation), TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = 2, Parent = rankCard })
		else
			label({ Text = "已經是最高稱號！", TextColor3 = COLORS.Gold, TextSize = 13, LayoutOrder = 2, Parent = rankCard })
		end

		-- 套裝
		label({ Text = "套裝加成", Font = FONT_BOLD, TextSize = 18, LayoutOrder = 10, Parent = rightPanel })
		for i, set in state.Sets do
			local setCard = card(rightPanel, 10 + i, set.Done and COLORS.Good or nil)
			label({
				Text = string.format("%s%s（%d / %d）", set.Done and "✅ " or "", set.Name, set.Have, set.Total),
				Font = FONT_BOLD,
				TextSize = 15,
				TextColor3 = set.Done and COLORS.Good or COLORS.Text,
				LayoutOrder = 1,
				Parent = setCard,
			})
			textBlock({ Text = set.Description, TextColor3 = COLORS.Muted, TextSize = 13, LayoutOrder = 2, Parent = setCard })
		end

		-- 物品圖鑑
		label({ Text = string.format("物品圖鑑（%d / %d）", state.CodexCount, state.ItemCount), Font = FONT_BOLD, TextSize = 18, LayoutOrder = 30, Parent = rightPanel })
		local codexCard = card(rightPanel, 31)
		for i, entry in state.Codex do
			local text
			local color
			if entry.Collected then
				local badge = VARIANT_BADGES[entry.Variant]
				text = string.format("%s%s　·　%s", badge and (badge .. " ") or "", entry.Name, entry.RarityName)
				color = itemColor(entry.Rarity, entry.Variant)
			else
				text = string.format("？？？　·　%s %s", entry.RarityName, entry.Category)
				if entry.MinReputation > state.Reputation then
					text ..= string.format("（名聲 %d 出現）", entry.MinReputation)
				end
				color = COLORS.Muted
			end
			textBlock({ Text = text, TextColor3 = color, TextSize = 14, LayoutOrder = i, Parent = codexCard })
		end

		-- 成就
		label({ Text = "成就", Font = FONT_BOLD, TextSize = 18, LayoutOrder = 50, Parent = rightPanel })
		for i, achievement in state.Achievements do
			local achievementCard = card(rightPanel, 50 + i, achievement.Done and COLORS.Gold or nil)
			label({
				Text = string.format("%s%s", achievement.Done and "🏆 " or "", achievement.Name),
				Font = FONT_BOLD,
				TextSize = 15,
				TextColor3 = achievement.Done and COLORS.Gold or COLORS.Text,
				LayoutOrder = 1,
				Parent = achievementCard,
			})
			textBlock({
				Text = string.format("%s（%d / %d）　獎勵 %d 星幣", achievement.Description, achievement.Progress, achievement.Goal, achievement.Reward),
				TextColor3 = COLORS.Muted,
				TextSize = 13,
				LayoutOrder = 2,
				Parent = achievementCard,
			})
		end
	end

	renderSide = function()
		for id, tabButton in tabButtons do
			tabButton.BackgroundColor3 = (id == currentTab) and COLORS.Button or COLORS.PanelSoft
		end
		-- 同一個分頁重畫時保留捲動位置，換分頁就回到最上面
		local scrollPosition = (renderedTab == currentTab) and rightPanel.CanvasPosition or Vector2.zero
		renderedTab = currentTab
		clearChildren(rightPanel)
		if not lastState then
			return
		end
		if currentTab == "Inventory" then
			renderInventory(lastState)
		elseif currentTab == "Shop" then
			renderShop(lastState)
		else
			renderCodex(lastState)
		end
		task.defer(function()
			rightPanel.CanvasPosition = scrollPosition
		end)
	end

	local lastMode = nil
	local function render(state)
		lastState = state
		creditsLabel.Text = string.format("星幣 %d", state.Credits)
		repLabel.Text = string.format("名聲 %d · %s", state.Reputation, state.Rank.Title)
		local town = state.Town
		if town and town.Job then
			jobLabel.Text = town.JobIcon .. " " .. town.JobName
		else
			jobLabel.Text = "還沒選職業"
		end

		-- 櫃檯模式：左邊大面板 + 右邊背包打開；小鎮模式：左邊小面板、背包收起來
		local mode = (state.Shop and state.Shop.CounterOpen) and "Counter" or "Town"
		if mode ~= lastMode then
			lastMode = mode
			if mode == "Counter" then
				customerPanel.Size = UDim2.new(0.4, 0, 1, -72)
				setBagOpen(true)
			else
				customerPanel.Size = UDim2.new(0.3, 0, 0.62, 0)
				setBagOpen(false)
			end
		end

		renderCustomer(state)
		renderSide()

		-- 剛進遊戲還沒選職業：自動打開職業選單
		if town and not town.Job and not jobPicker.Visible then
			showJobPicker(state)
		end
	end

	-- 每半秒用 Player 的 Attribute 更新即時狀態（通緝、保護、坐牢倒數）
	local function updateLive(info)
		if info.Jailed then
			local left = math.max(0, (info.JailedUntilUnix or 0) - os.time())
			jailBanner.Text = string.format("⛓ 坐牢中…還有 %d 秒", left)
			jailBanner.Visible = true
		else
			jailBanner.Visible = false
		end
		if (info.Wanted or 0) > 0 then
			statusLabel.Text = "通緝 " .. string.rep("⭐", info.Wanted)
			statusLabel.TextColor3 = COLORS.Bad
		elseif info.Protection and info.Protection ~= "" then
			statusLabel.Text = "🛡️ " .. info.Protection
			statusLabel.TextColor3 = COLORS.Good
		else
			statusLabel.Text = "⚠ 可能被搶"
			statusLabel.TextColor3 = COLORS.Gold
		end
	end

	label({ Text = "連線中…", TextColor3 = COLORS.Muted, Parent = customerPanel })
	renderSide()

	setBagOpen(false)

	return {
		Render = render,
		Toast = toast,
		UpdateLive = updateLive,
		ShowJobPicker = function()
			if lastState then
				showJobPicker(lastState)
			end
		end,
		IsJobPickerOpen = function()
			return jobPicker.Visible
		end,
		-- 切換右邊的分頁："Inventory" / "Shop" / "Codex"
		SetTab = function(tabId)
			if tabButtons[tabId] then
				currentTab = tabId
				renderSide()
			end
		end,
		Gui = gui,
	}
end

return UI
