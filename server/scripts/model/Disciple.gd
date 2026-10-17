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
var maxMovePoints: int = 0
var attacksRemaining: int = 0
var turnsInSect: int = 0
var assignedPeakId: String = ""
var bloodLine: bool = false
var generation: int = 0
var directLine: bool = false
var heartDevil: int = 0
var injured: bool = false
var cultivationProgress: float = 0.0
## R3 新增：建造者差事的剩余建造次数（`appointBuilder` 赋予 `improvement.builderCharges`）。
var builderCharges: int = 0
## R4 新增（**内部记账，不下发 view**，见 PROTOCOL §12.5）：
## 境界等级（`Enums.Realm.ALL` 下标 +1，由 `realm` 派生并随突破/渡劫同步）。
var realmLevel: int = 1
## 修为已满、等待突破判定（`DiscipleRules.try_breakthrough` 前置）。
var breakthroughPending: bool = false
## 渡劫中（`DiscipleRules.tribulate` 期间置位；命令本体归 R7）。
var tribulating: bool = false
## 最近一次收徒大典产出此弟子的回合（繁衍冷却记账）。
var lastReproduceTurn: int = 0

## R5 新增：战功经验（`warfare.xpPer*` 累加，`UnitRules.level_for_xp` 换算等级）。
var battleXp: int = 0
## R5 新增：战功等级（`warfare.levelThresholds` 下标，0 起）。
var battleLevel: int = 0
## R5 新增：可支配晋升点（每升 1 级给 `warfare.promotionPointsPerLevel` 点）。
var promotionPoints: int = 0
## R5 新增：已习得的晋升项 id（`warfare.promotions[].id`，`promote` 写入）。
var promotions: Array[String] = []
## R5 新增：转职冷却剩余回合（`reclass` 后置为 `reclassCooldownTurns`，回合开始递减）。
var reclassCooldown: int = 0
## R5 新增：驻守的节点 id（`assignGarrison` 写入，`withdrawGarrison` 清空）。
var garrisonNodeId: String = ""
## R5 新增：被俘前的原宗门 id（`captureChanceOnLoss` 命中时记账）。
var capturedFromSectId: String = ""
## R6 新增：正在执行探索任务的节点 id（机缘/秘境；任务结束清空）。
## 对齐 `queryDiscipleDetail.missionNodeId`；驻守用 `garrisonNodeId`，两者互斥。
var missionNodeId: String = ""

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "sectId": sectId, "tileId": tileId, "realm": realm, "position": position, "rootGrade": rootGrade, "spiritRoots": spiritRoots.duplicate(), "unitClass": unitClass, "movePoints": movePoints, "maxMovePoints": maxMovePoints, "attacksRemaining": attacksRemaining, "turnsInSect": turnsInSect, "assignedPeakId": assignedPeakId, "bloodLine": bloodLine, "generation": generation, "directLine": directLine, "heartDevil": heartDevil, "injured": injured, "cultivationProgress": cultivationProgress, "builderCharges": builderCharges, "battleXp": battleXp, "battleLevel": battleLevel, "promotionPoints": promotionPoints, "promotions": promotions.duplicate(), "reclassCooldown": reclassCooldown, "garrisonNodeId": garrisonNodeId}


## 由 `realm` 反推境界等级（1..5）；`realmLevel` 与 `realm` 必须同步。
static func level_of(realm: String) -> int:
	var index: int = Enums.Realm.ALL.find(realm)
	return index + 1 if index >= 0 else 1
