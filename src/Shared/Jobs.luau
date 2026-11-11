--!strict
-- 職業。第一階段有當舖老闆、商人、保鑣；店家和科學家之後再加。
-- 任何職業都可以搶劫（保鑣除外），做壞事會扣名聲、增加通緝等級。

export type JobDef = {
	Id: string,
	Name: string,
	Icon: string,
	Color: { number },
	Summary: string,
	Steps: { string },
}

local Jobs = {}

Jobs.List = {
	{
		Id = "Pawnbroker",
		Name = "當舖老闆",
		Icon = "🏪",
		Color = { 0.55, 0.45, 1 },
		Summary = "在商店街開一間當舖，鑑定真假、殺價收購，再轉賣賺差價。",
		Steps = {
			"到商店街找一間空的當舖，按「經營這間當舖」",
			"按「打開櫃檯」開始接客人",
			"玩家商人也會把挖到的遺物拿來賣你",
		},
	},
	{
		Id = "Merchant",
		Name = "商人",
		Icon = "📦",
		Color = { 0.95, 0.75, 0.3 },
		Summary = "到城外的礦場和墜毀點採集貨物，運回城鎮賣錢。路上小心劫匪！",
		Steps = {
			"出城到「隕石礦場」或「飛碟墜毀點」採集貨物",
			"運回城裡賣給「貿易站」或「研究院」（兩邊收購價不一樣）",
			"挖到的遺物可以賣給玩家當舖，價格比較好",
			"找保鑣護送就不會被搶",
		},
	},
	{
		Id = "Guard",
		Name = "保鑣",
		Icon = "🛡️",
		Color = { 0.4, 0.75, 1 },
		Summary = "保護商人、抓通緝犯拿賞金。保鑣不能搶劫。",
		Steps = {
			"跟在帶貨的商人旁邊就算護送，會自動拿到護送費",
			"頭上有⭐的是通緝犯，靠近按「逮捕」拿賞金",
			"通緝等級越高，賞金越多",
		},
	},
} :: { JobDef }

local byId: { [string]: JobDef } = {}
for _, job in Jobs.List do
	byId[job.Id] = job
end

function Jobs.Get(id: string?): JobDef?
	if id == nil then
		return nil
	end
	return byId[id]
end

function Jobs.IsValid(id: any): boolean
	return type(id) == "string" and byId[id] ~= nil
end

return Jobs
