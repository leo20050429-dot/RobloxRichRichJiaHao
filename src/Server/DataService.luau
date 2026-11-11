-- 玩家存檔讀寫（DataStoreService）。
--
-- 這是一個簡化版本，介面刻意保持小（Get / OnLoaded / IsPersistent），
-- 之後要換成 ProfileStore（有 session lock，防止多伺服器同時寫入造成回檔或刷物品）
-- 只需要改這個檔案。上架前建議一定要換。
--
-- 在 Studio 測試時，如果沒有開啟「Game Settings → Security → Enable Studio Access to API Services」，
-- 讀檔會失敗，這時會使用一份臨時存檔，而且不會寫回，避免覆蓋掉真正的資料。

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlayerDataSchema = require(Shared:WaitForChild("PlayerDataSchema"))

local DataService = {}

local records = {} -- [Player] = { Data = table, Persistent = boolean }
local loadedCallbacks = {}
local store = nil

local function keyFor(player)
	return "Player_" .. tostring(player.UserId)
end

local function isStudioAccessError(err)
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(text, "API Services", 1, true) ~= nil
end

local function load(player)
	local data = nil
	local persistent = false

	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync(keyFor(player))
			end)
			if ok then
				data = result
				persistent = true
				break
			end
			warn(string.format("[DataService] 讀取 %s 的存檔失敗（第 %d 次）：%s", player.Name, attempt, tostring(result)))
			-- Studio 裡讀檔失敗幾乎都是沒開 API 權限或還沒發佈，重試也沒用，直接用臨時存檔
			if RunService:IsStudio() or isStudioAccessError(result) or attempt == 3 then
				break
			end
			task.wait(attempt)
		end
	end

	if data == nil then
		data = PlayerDataSchema.New()
	else
		data = PlayerDataSchema.Reconcile(data)
	end

	if not persistent then
		warn("[DataService] " .. player.Name .. " 使用臨時存檔，這次的進度不會被保存。")
	end

	if player.Parent == nil then
		return -- 讀檔期間玩家已經離開
	end

	records[player] = { Data = data, Persistent = persistent }
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, data)
	end
end

local function save(player)
	local record = records[player]
	if not record or not record.Persistent or not store then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), record.Data, { player.UserId })
	end)
	if not ok then
		warn("[DataService] 儲存 " .. player.Name .. " 的存檔失敗：" .. tostring(err))
	end
end

function DataService.Get(player)
	local record = records[player]
	return record and record.Data or nil
end

-- 只給 Studio 自動測試用：讓假的測試角色也有一份存檔
function DataService.SetTestRecord(key, data)
	if not game:GetService("RunService"):IsStudio() then
		return
	end
	records[key] = { Data = data, Persistent = false }
end

function DataService.IsPersistent(player)
	local record = records[player]
	return record ~= nil and record.Persistent
end

-- callback(player, data)：玩家存檔讀取完成時呼叫
function DataService.OnLoaded(callback)
	table.insert(loadedCallbacks, callback)
end

function DataService.Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] 無法取得 DataStore：" .. tostring(result))
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		records[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in records do
				task.spawn(save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in records do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
