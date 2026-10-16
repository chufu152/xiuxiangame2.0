class_name Disciple
extends RefCounted

var id: String = ""
var name: String = ""
var sectId: String = ""
var tileId: String = ""
var realm: String = Enums.Realm.LIAN_QI
var position: String = ""
var rootGrade: int = 0
var spiritRoots: Array[String] = []
var unitClass: String = Enums.UnitClass.PU_TONG
var movePoints: int = 0
var attacksRemaining: int = 0
var assignedPeakId: String = ""
var bloodLine: bool = false
var generation: int = 0
var directLine: bool = false
var heartDevil: int = 0
var injured: bool = false
var cultivationProgress: float = 0.0

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "sectId": sectId, "tileId": tileId, "realm": realm, "position": position, "rootGrade": rootGrade, "spiritRoots": spiritRoots.duplicate(), "unitClass": unitClass, "movePoints": movePoints, "attacksRemaining": attacksRemaining, "assignedPeakId": assignedPeakId, "bloodLine": bloodLine, "generation": generation, "directLine": directLine, "heartDevil": heartDevil, "injured": injured, "cultivationProgress": cultivationProgress}
