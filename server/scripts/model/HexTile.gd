class_name HexTile
extends RefCounted

var id: String = ""
var q: int = 0
var r: int = 0
var baseTerrain: String = Enums.BaseTerrain.SPIRIT_PLAIN
var relief: String = Enums.Relief.FLAT
var features: Array[String] = []
var riverEdges: Array[int] = []
var danger: bool = false
var ownerSectId: String = ""
var nodeId: String = ""
var districtId: String = ""
var workedByPeakId: String = ""
var improvementId: String = ""
var luxuryType: String = ""

func to_dict() -> Dictionary:
	return {"id": id, "q": q, "r": r, "baseTerrain": baseTerrain, "relief": relief, "features": features.duplicate(), "riverEdges": riverEdges.duplicate(), "danger": danger, "ownerSectId": ownerSectId, "nodeId": nodeId, "districtId": districtId, "workedByPeakId": workedByPeakId, "improvementId": improvementId, "luxuryType": luxuryType}
