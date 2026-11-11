-- ProximityPrompt 路由：每個 Prompt 都有 Action 屬性，觸發時交給對應的處理函式。
-- 處理函式的格式：function(player, prompt) return ok, message end
-- 自動測試可以直接呼叫 Dispatch，傳入一個假的 prompt。

local PromptRouter = {}

local routes = {}
local afterHooks = {}

function PromptRouter.Register(action, handler)
	routes[action] = handler
end

-- hook(player, ok, message)：每次處理完都會呼叫（用來推送狀態、顯示訊息）
function PromptRouter.OnHandled(hook)
	table.insert(afterHooks, hook)
end

function PromptRouter.Dispatch(player, action, prompt)
	local handler = routes[action]
	if not handler then
		return false, nil
	end
	local ok, success, message = pcall(handler, player, prompt)
	if not ok then
		warn("[PromptRouter] " .. tostring(action) .. " 出錯：" .. tostring(success))
		success, message = false, "出了點問題，請再試一次。"
	end
	for _, hook in afterHooks do
		task.spawn(hook, player, success, message)
	end
	return success, message
end

function PromptRouter.Start()
	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local action = prompt:GetAttribute("Action")
		if type(action) == "string" then
			PromptRouter.Dispatch(player, action, prompt)
		end
	end)
end

return PromptRouter
