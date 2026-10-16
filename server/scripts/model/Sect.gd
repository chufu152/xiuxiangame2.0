class_name Sect
extends RefCounted

var id: String = ""
var name: String = ""
var factionType: String = Enums.FactionType.ZONG_MEN
var player: bool = false
var resources: Dictionary = {}
var disciples: Array[Disciple] = []
var spiritPeaks: Array[SpiritPeak] = []
var visibleTiles: Array[String] = []
var exploredTiles: Array[String] = []
var tileSnapshots: Dictionary = {}
var nodeSnapshots: Dictionary = {}
var peakSnapshots: Dictionary = {}
## R3 新增：改良「最后可见快照」缓存（改良 id -> `Improvement.to_dict()`），供 `view.improvements{}`
## 在 explored-but-not-visible 格按迷雾规则冻结下发（见 PROTOCOL §12.6）。
var improvementSnapshots: Dictionary = {}
## R3 新增：本宗已修筑的改良（`queryImprovementOptions`、道路网刷新、`view.improvements{}` 的来源）。
## 项目队列放在灵峰上（`SpiritPeak.projectQueue`），与 PROTOCOL §4 `queryProjectQueue{peakId,…}` 口径一致；
## 宗门级研究队列（`researchDao`）留到 R4，故不在此声明 `projects`。
var improvements: Array[Improvement] = []

func public_info() -> Dictionary:
	return {"id": id, "name": name, "factionType": factionType, "player": player}
