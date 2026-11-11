-- 在櫃檯前生成客人的外星人模型（只在這位玩家的畫面上出現）。
-- 之後美術做好正式模型，可以換成從 ReplicatedStorage 複製 Model。

local RunService = game:GetService("RunService")

local CustomerModel = {}

local currentModel = nil
local currentId = nil
local bobConnection = nil

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	return p
end

local function clear()
	if bobConnection then
		bobConnection:Disconnect()
		bobConnection = nil
	end
	if currentModel then
		currentModel:Destroy()
		currentModel = nil
	end
	currentId = nil
end

-- 找店面的 CustomerSpot：多人版在 workspace.Town.Shops.<ShopId>，單人版在 workspace.PawnShop
local function getSpot(shopId)
	local town = workspace:FindFirstChild("Town")
	local shops = town and town:FindFirstChild("Shops")
	if shopId and shops then
		local shop = shops:FindFirstChild(shopId)
		return shop and shop:FindFirstChild("CustomerSpot") or nil
	end
	local single = workspace:FindFirstChild("PawnShop")
	return single and single:FindFirstChild("CustomerSpot") or nil
end

local function build(customer, spotCFrame)
	local c = customer.Color or { 0.6, 0.6, 0.6 }
	local bodyColor = Color3.new(c[1] or 0.6, c[2] or 0.6, c[3] or 0.6)

	local model = Instance.new("Model")
	model.Name = "Customer"

	-- 局部座標：-Z 是客人的正前方（面向玩家）
	local pieces = {
		{ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2), Offset = CFrame.new(0, -1, 0), Color = bodyColor, Material = Enum.Material.SmoothPlastic },
		{ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), Offset = CFrame.new(0, 1.4, 0), Color = bodyColor, Material = Enum.Material.SmoothPlastic },
		{ Name = "EyeL", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), Offset = CFrame.new(-0.45, 1.6, -1.0), Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic },
		{ Name = "EyeR", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), Offset = CFrame.new(0.45, 1.6, -1.0), Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic },
		{ Name = "PupilL", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Offset = CFrame.new(-0.45, 1.6, -1.3), Color = Color3.new(0.05, 0.05, 0.1), Material = Enum.Material.SmoothPlastic },
		{ Name = "PupilR", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Offset = CFrame.new(0.45, 1.6, -1.3), Color = Color3.new(0.05, 0.05, 0.1), Material = Enum.Material.SmoothPlastic },
		{ Name = "Antenna", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 0.15, 0.15), Offset = CFrame.new(0, 3.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.3), Material = Enum.Material.SmoothPlastic },
		{ Name = "AntennaTip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), Offset = CFrame.new(0, 3.9, 0), Color = Color3.fromRGB(255, 240, 120), Material = Enum.Material.Neon },
	}

	local offsets = {}
	for _, piece in pieces do
		local p = makePart({
			Name = piece.Name,
			Shape = piece.Shape,
			Size = piece.Size,
			Color = piece.Color,
			Material = piece.Material,
		})
		p.CFrame = spotCFrame * piece.Offset
		p.Parent = model
		offsets[p] = piece.Offset
		if piece.Name == "Body" then
			model.PrimaryPart = p
		end
	end

	-- 頭上的名牌
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 50)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = customer.Name .. "（" .. customer.Species .. "）"
	label.TextScaled = true
	label.Font = Enum.Font.BuilderSansBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard
	billboard.Parent = model

	model.Parent = workspace

	-- 上下浮動
	local started = os.clock()
	bobConnection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local base = spotCFrame * CFrame.new(0, math.sin(t * 2) * 0.25, 0) * CFrame.Angles(0, math.sin(t * 0.8) * 0.15, 0)
		for p, offset in offsets do
			p.CFrame = base * offset
		end
	end)

	return model
end

local latestCustomer = nil
local latestShopId = nil
local waitingForSpot = false

-- customer 為 nil 時移除模型；shopId 是客人站在哪一間店
function CustomerModel.Show(customer, shopId)
	latestCustomer = customer
	latestShopId = shopId
	if customer == nil then
		clear()
		return
	end
	if customer.Id == currentId and currentModel then
		return
	end
	local spot = getSpot(shopId)
	if not spot then
		-- 場景可能還沒載入到這台裝置，等它出現再生成
		if not waitingForSpot then
			waitingForSpot = true
			task.spawn(function()
				local started = os.clock()
				while os.clock() - started < 30 and not getSpot(latestShopId) do
					task.wait(0.5)
				end
				waitingForSpot = false
				if latestCustomer and getSpot(latestShopId) then
					CustomerModel.Show(latestCustomer, latestShopId)
				end
			end)
		end
		return
	end
	clear()
	currentId = customer.Id
	currentModel = build(customer, spot.CFrame)
end

return CustomerModel
