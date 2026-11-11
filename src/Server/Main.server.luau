-- 伺服器進入點：蓋小鎮、建立 Remote、啟動各個 Service。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TownBuilder = require(script.Parent:WaitForChild("TownBuilder"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PromptRouter = require(script.Parent:WaitForChild("PromptRouter"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local TownService = require(script.Parent:WaitForChild("TownService"))

TownBuilder.Build()

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"

local function remote(className, name)
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local shopAction = remote("RemoteFunction", "ShopAction") -- 客戶端 → 伺服器：所有按鈕動作
local stateChanged = remote("RemoteEvent", "StateChanged") -- 伺服器 → 客戶端：整份狀態
local notify = remote("RemoteEvent", "Notify") -- 伺服器 → 客戶端：跳出訊息
local openJobPicker = remote("RemoteEvent", "OpenJobPicker") -- 伺服器 → 客戶端：打開職業選單

remotes.Parent = ReplicatedStorage

-- 順序：各 Service 先註冊事件，DataService 最後才開始讀檔
ShopService.Start({
	ShopAction = shopAction,
	StateChanged = stateChanged,
	Notify = notify,
	OpenJobPicker = openJobPicker,
})
TownService.Start()
PromptRouter.Start()
DataService.Start()
