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

func to_dict() -> Dictionary:
	return {"id": id, "type": type, "tileId": tileId, "ownerSectId": ownerSectId, "level": level, "reserve": reserve, "output": output, "cooldown": cooldown}
