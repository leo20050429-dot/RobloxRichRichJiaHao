--!strict
-- 鑑定工具。每次使用都會消耗客人的耐心值（PatienceCost）。

export type ToolDef = {
	Id: string,
	Name: string,
	Price: number,
	PatienceCost: number,
	Description: string,
}

local Tools = {}

Tools.List = {
	Magnifier = {
		Id = "Magnifier",
		Name = "放大鏡",
		Price = 0,
		PatienceCost = 4,
		Description = "看清表面的刮痕、接縫與做工。開店就有。",
	},
	XRay = {
		Id = "XRay",
		Name = "X 光掃描儀",
		Price = 250,
		PatienceCost = 6,
		Description = "看穿外殼，找出內部裂痕與空心假貨。",
	},
	UVLight = {
		Id = "UVLight",
		Name = "紫外線燈",
		Price = 700,
		PatienceCost = 6,
		Description = "照出防偽印記與肉眼看不到的混濁。",
	},
	Analyzer = {
		Id = "Analyzer",
		Name = "成分分析儀",
		Price = 1500,
		PatienceCost = 8,
		Description = "分析材質成分，識破最高明的仿冒品。",
	},
} :: { [string]: ToolDef }

-- UI 顯示順序
Tools.Order = { "Magnifier", "XRay", "UVLight", "Analyzer" }

function Tools.Get(id: string): ToolDef?
	return Tools.List[id]
end

return Tools
