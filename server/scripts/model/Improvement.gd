class_name Improvement
extends RefCounted
## 地块改良（R3）：建造者修筑、叠加在六边形地块上的设施。
##
## 字段对齐 docs/PROTOCOL_2.0.md §4 `queryImprovementOptions.broken`（`{id,type,displayName}`）
## 与 §6.5 `view.improvements{}`（键为改良 id）。
##
## `broken` 破损后产出归零、被动加成失效（青石道路掉网、聚灵阵失效、洞府不计住房），
## 需 `repairImprovement` 花 40 工力修缮。`charges` 为预留字段（R3 未使用，恒 0）。

var id: String = ""
var type: String = ""
var tileId: String = ""
var sectId: String = ""
var broken: bool = false
var charges: int = 0
## R3 新增：青石道路网络等级（0 未成网 / 1 支线 / 2 干线），由 `RoadNetworkService.refresh` 写回。
var networkLevel: int = 0

func to_dict() -> Dictionary:
	return {"id": id, "type": type, "tileId": tileId, "sectId": sectId, "broken": broken, "charges": charges, "networkLevel": networkLevel}
