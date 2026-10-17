class_name Dao
extends RefCounted
## 道法（R4）：`data/gameConfig.json` 的 `daoTree.daos[]` 条目在规则层的只读视图对象。
##
## 数值与文案**全部**来自配置，本类不做任何计算；`DaoRules` 是唯一读取方。
## 1.0 蓝本：`entity/Dao.java` + `DaoEffect.java`。

var id: String = ""
var name: String = ""
var desc: String = ""
## 所属时代名（∈ `daoTree.eras`）。
var era: String = ""
var iconKey: String = ""
var prerequisiteDaoIds: Array[String] = []
var daoPointCost: int = 0
var spiritPowerCost: int = 0
var turns: int = 0
## 效果条目原样保留：`[{type, amount|key}, …]`，type 语义见 `DaoRules.effect_sum`。
var effects: Array = []
## 流派专属（空串 = 通用）。
var factionOnly: String = ""
var requiresBloodLine: bool = false


static func from_config(entry: Dictionary) -> Dao:
	var dao: Dao = Dao.new()
	dao.id = str(entry.get("id", ""))
	dao.name = str(entry.get("name", dao.id))
	dao.desc = str(entry.get("desc", ""))
	dao.era = str(entry.get("era", ""))
	dao.iconKey = str(entry.get("iconKey", ""))
	dao.prerequisiteDaoIds.clear()
	for prerequisite: Variant in entry.get("prerequisiteDaoIds", []):
		dao.prerequisiteDaoIds.append(str(prerequisite))
	dao.daoPointCost = int(entry.get("daoPointCost", 0))
	dao.spiritPowerCost = int(entry.get("spiritPowerCost", 0))
	dao.turns = int(entry.get("turns", 1))
	dao.effects = (entry.get("effects", []) as Array).duplicate(true)
	dao.factionOnly = str(entry.get("factionOnly", ""))
	dao.requiresBloodLine = bool(entry.get("requiresBloodLine", false))
	return dao


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"desc": desc,
		"era": era,
		"iconKey": iconKey,
		"prerequisiteDaoIds": prerequisiteDaoIds.duplicate(),
		"daoPointCost": daoPointCost,
		"spiritPowerCost": spiritPowerCost,
		"turns": turns,
		"effects": effects.duplicate(true),
		"factionOnly": factionOnly,
		"requiresBloodLine": requiresBloodLine,
	}
