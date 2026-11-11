--!strict
-- 犯罪規則（純計算）：能不能搶、搶走多少、通緝、坐牢、賞金。
-- 所有數值都在 Config.Town。

local Config = require(script.Parent.Config)

export type RobContext = {
	RobberJob: string?,
	RobberJailed: boolean,
	RobberOnCooldown: boolean,
	RobberFreeSlots: number,
	VictimJailed: boolean,
	VictimCargo: number,
	VictimInSafeZone: boolean,
	VictimNewbie: boolean,
	VictimEscorted: boolean,
	RobberInSafeZone: boolean,
	Distance: number,
	SameActor: boolean,
}

local Crime = {}

-- 回傳 (可以搶嗎, 不行的原因)
function Crime.CanRob(ctx: RobContext): (boolean, string?)
	local town = Config.Town
	if ctx.SameActor then
		return false, "不能搶自己。"
	end
	if ctx.RobberJailed then
		return false, "你在坐牢，乖一點。"
	end
	if ctx.RobberJob == "Guard" then
		return false, "保鑣不能搶劫，先去廣場換職業。"
	end
	if ctx.RobberOnCooldown then
		return false, "剛搶完，等一下再動手。"
	end
	if ctx.Distance > town.RobRange then
		return false, "離太遠了。"
	end
	if ctx.VictimJailed then
		return false, "對方在坐牢。"
	end
	if ctx.VictimInSafeZone or ctx.RobberInSafeZone then
		return false, "這裡是安全區，不能搶劫。"
	end
	if ctx.VictimNewbie then
		return false, "對方還在新手保護期。"
	end
	if ctx.VictimEscorted then
		return false, "對方有保鑣護送，不敢下手。"
	end
	if ctx.VictimCargo <= 0 then
		return false, "對方身上沒有貨物。"
	end
	if ctx.RobberFreeSlots <= 0 then
		return false, "你身上已經塞滿了。"
	end
	return true, nil
end

-- 會被搶走幾件（至少 1 件，不超過搶劫者身上的空位）
function Crime.RobCount(victimCargo: number, robberFreeSlots: number): number
	local count = math.max(1, math.ceil(victimCargo * Config.Town.RobShare))
	return math.min(count, victimCargo, robberFreeSlots)
end

function Crime.AddWanted(current: number, amount: number): number
	return math.clamp(current + amount, 0, Config.Town.MaxWanted)
end

-- 經過 elapsed 秒沒犯罪後，通緝等級會變成多少
function Crime.DecayWanted(current: number, elapsed: number): number
	if current <= 0 then
		return 0
	end
	local drop = math.floor(elapsed / Config.Town.WantedDecay)
	return math.max(0, current - drop)
end

function Crime.JailSeconds(wanted: number): number
	return math.max(1, wanted) * Config.Town.JailPerLevel
end

function Crime.Bounty(wanted: number): number
	return math.max(0, wanted) * Config.Town.BountyPerLevel
end

function Crime.InsuranceRefund(lostValue: number): number
	return math.floor(lostValue * Config.Town.Insurance.Refund)
end

-- 點是否在某個方塊區域裡（區域用中心點、大小表示，不考慮旋轉）
function Crime.InBox(point: Vector3, center: Vector3, size: Vector3): boolean
	local d = point - center
	return math.abs(d.X) <= size.X / 2 and math.abs(d.Y) <= size.Y / 2 and math.abs(d.Z) <= size.Z / 2
end

return Crime
