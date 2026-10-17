class_name ResearchProject
extends RefCounted
## 研究队列条目（R4）：`researchDao` 入队后的道法研究进度。
##
## 字段对齐 `docs/PROTOCOL_2.0.md` §4 `queryProjectQueue.researchQueue[]`：
## `{id, daoId, name, turnsRequired, turnsRemaining, daoPointCost, spiritPowerCost}`。
## 研究队列挂在宗门（`Sect.researchQueue`）——道法是宗门级解锁，与灵峰无关；
## 建造项目队列仍挂在灵峰（`SpiritPeak.projectQueue`），两池**不混**（R4 提示词裁决二）。

var id: String = ""
var daoId: String = ""
var name: String = ""
var turnsRequired: int = 0
var turnsRemaining: int = 0
var daoPointCost: int = 0
var spiritPowerCost: int = 0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"daoId": daoId,
		"name": name,
		"turnsRequired": turnsRequired,
		"turnsRemaining": turnsRemaining,
		"daoPointCost": daoPointCost,
		"spiritPowerCost": spiritPowerCost,
	}
