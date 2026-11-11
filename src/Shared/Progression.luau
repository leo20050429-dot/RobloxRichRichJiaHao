--!strict
-- 稱號（依名聲）與每日登入獎勵。純計算，數值都在 Config。

local Config = require(script.Parent.Config)

export type Rank = { MinReputation: number, Title: string }
export type Daily = { LastDay: number, Streak: number }

local Progression = {}

-- 回傳 (目前稱號, 下一個稱號或 nil)
function Progression.GetRank(reputation: number): (Rank, Rank?)
	local ranks = Config.Ranks
	local current = ranks[1]
	local nextRank = nil
	for i, rank in ranks do
		if reputation >= rank.MinReputation then
			current = rank
			nextRank = ranks[i + 1]
		end
	end
	return current, nextRank
end

-- 今天是第幾天（UTC，從 1970 年算起）
function Progression.Today(): number
	return math.floor(os.time() / 86400)
end

-- 查看每日獎勵：回傳 (今天能不能領, 領了之後是連續第幾天, 獎勵星幣)
function Progression.PeekDaily(daily: Daily, today: number): (boolean, number, number)
	if today <= daily.LastDay then
		return false, daily.Streak, 0
	end
	local streak = 1
	if today == daily.LastDay + 1 then
		streak = daily.Streak + 1
	end
	local rewards = Config.DailyRewards
	local reward = rewards[math.min(streak, #rewards)]
	return true, streak, reward
end

-- 領取每日獎勵：成功回傳獎勵星幣，今天已經領過回傳 nil
function Progression.ClaimDaily(daily: Daily, today: number): number?
	local available, streak, reward = Progression.PeekDaily(daily, today)
	if not available then
		return nil
	end
	daily.LastDay = today
	daily.Streak = streak
	return reward
end

return Progression
