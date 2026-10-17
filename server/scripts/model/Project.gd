class_name Project
extends RefCounted
## 项目队列条目（R3）：建造 / 建区 / 开峰 / 洞府 / 加固 等一切"入队后逐回合推进"的差事。
##
## 字段对齐 docs/PROTOCOL_2.0.md §4 `queryProjectQueue.projects[]`
## `{id, type, name, turnsRequired, turnsRemaining, spiritPowerCost, targetId, discipleId, buildingType, districtType}`；
## `materialCost` 为 2.0 只加不删的补充项（建造入队时记下消耗，取消时据此返还）。
##
## 项目队列挂在灵峰（`SpiritPeak.projectQueue`）——与 PROTOCOL §4 的 `queryProjectQueue{peakId,…}` 口径一致；
## 宗门级研究队列（`researchDao`）留到 R4。

## 项目类型常量（与 1.0 `BuildAction` 同名，R3 取 6 种 + R4 补 `RECRUITMENT`）。
const TYPE_FOUND_PEAK: String = "FOUND_PEAK"
const TYPE_BUILD: String = "BUILD"
const TYPE_SUB_PEAK: String = "SUB_PEAK"
const TYPE_CAVE: String = "CAVE"
const TYPE_FORTIFY: String = "FORTIFY"
const TYPE_DISTRICT: String = "DISTRICT"
## R4 新增：收徒大典（`holdRecruitment` 入队，`DaoAction.complete_recruitment` 落成）。
const TYPE_RECRUITMENT: String = "RECRUITMENT"

var id: String = ""
var type: String = ""
var name: String = ""
var turnsRequired: int = 0
var turnsRemaining: int = 0
var spiritPowerCost: int = 0
var targetId: String = ""
var discipleId: String = ""
var buildingType: String = ""
var districtType: String = ""
var materialCost: Dictionary = {}

func to_dict() -> Dictionary:
	return {"id": id, "type": type, "name": name, "turnsRequired": turnsRequired, "turnsRemaining": turnsRemaining, "spiritPowerCost": spiritPowerCost, "targetId": targetId, "discipleId": discipleId, "buildingType": buildingType, "districtType": districtType, "materialCost": materialCost.duplicate(true)}
