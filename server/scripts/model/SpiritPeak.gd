class_name SpiritPeak
extends RefCounted
## 灵峰（城市）：R3 起承载人口/粮食/住房/安定、区域、建筑、耕作地块与项目队列。

var id: String = ""
var name: String = ""
var sectId: String = ""
var tileId: String = ""
var capital: bool = true
var level: int = 0
var population: int = 0
var capacity: int = 0
var defense: int = 0
var qiYun: int = 0
var qiYunMax: int = 0
var stability: float = 0.0
var housing: int = 0
var fengZhuId: String = ""
## 已建成建筑：建筑类型名 -> `{id, type, name, level, districtId}`。
var buildings: Dictionary = {}
## 区域列表：`SHOU_FU_QU` 首府区开局自带，其余由 `foundDistrict` 建成。
var districts: Array[District] = []
## R3 新增：粮食存量、粮食累计进度（达阈值涨人口）、空闲人口、被指派耕作的地块 id。
var food: float = 0.0
var foodProgress: float = 0.0
var freeWorkers: int = 0
var workedTileIds: Array[String] = []
## R3 新增：本峰的项目队列（建造/建区/洞府/加固等，逐回合推进）。
var projectQueue: Array[Project] = []
## R5 新增（**内部记账，不下发 view**，见 PROTOCOL §12.5）：
## 围城累计回合数（`UnitRules.update_attrition` 逐回合递增，补给恢复即清零）。
## 城防折减 = `min(maxDefenseCut, defenseCutPerTurn × siegeTurns)`。
var siegeTurns: int = 0

func to_dict() -> Dictionary:
	var district_data: Array = []
	for district: District in districts:
		district_data.append(district.to_dict())
	return {"id": id, "name": name, "sectId": sectId, "tileId": tileId, "capital": capital, "level": level, "population": population, "capacity": capacity, "defense": defense, "qiYun": qiYun, "qiYunMax": qiYunMax, "stability": stability, "housing": housing, "fengZhuId": fengZhuId, "buildings": buildings.duplicate(true), "districts": district_data, "food": food, "foodProgress": foodProgress, "freeWorkers": freeWorkers, "workedTileIds": workedTileIds.duplicate(), "siegeTurns": siegeTurns}
