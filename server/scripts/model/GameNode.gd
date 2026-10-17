class_name GameNode
extends RefCounted

var id: String = ""
var type: String = Enums.NodeType.LING_TIAN
var tileId: String = ""
var ownerSectId: String = ""
var level: int = 1
var reserve: float = 0.0
var output: float = 0.0
var cooldown: int = 0
## R5 新增：驻守此节点的弟子 id 列表（`assignGarrison` 写入、`withdrawGarrison` 移除）。
## 驻守己方节点给守方 `warfare.garrisonDefenseBonus`；在守自有灵脉节点补充传送次数。
var garrisonDiscipleIds: Array[String] = []

func to_dict() -> Dictionary:
	return {"id": id, "type": type, "tileId": tileId, "ownerSectId": ownerSectId, "level": level, "reserve": reserve, "output": output, "cooldown": cooldown, "garrisonDiscipleIds": garrisonDiscipleIds.duplicate()}
