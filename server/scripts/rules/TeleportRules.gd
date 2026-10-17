class_name TeleportRules
extends RefCounted
## 传送网络规则（R5，对齐 1.0 `core/TeleportService.java`，数值只取 `data/gameConfig.json`）。
##
## 口径：
##   可用 = `teleport.enabled` **且** 宗门已解锁 `teleport.requiredDaoKey`（`chuan_song`）的 `UNLOCK_TELEPORT`；
##   次数 = `capacityBase` + 在守自有灵脉节点数 × `capacityPerOwnLingMaiNode`，封顶 `capacityMax`；
##   花费 = `baseStones` + 六边距离 × `stonesPerHex`（两峰地块之间）；
##   记账 = `Sect.teleportsUsedThisTurn`，`TURN_START` 清零（回填 R2 留的 TODO）。
##
## **「在守」的判定**：节点属本宗 **且** `garrisonDiscipleIds` 非空——与 1.0 同源，
## 空节点不补充传送次数，这样「驻守」才有战略意义（也正是 R5 的 `assignGarrison` 动因之一）。


## 传送网络是否对**该宗门**开启：全局开关 + 道法解锁。
static func enabled(state: GameState, config: Dictionary, sect: Sect) -> bool:
	if not bool(config["teleport"]["enabled"]): return false
	if sect == null: return false
	var unlocked: Array = DaoRules.effect_sum(state, config, sect).get("UNLOCK_TELEPORT", [])
	return unlocked.has(str(config["teleport"]["requiredDaoKey"]))


## 本回合可用次数上限（不含已用）。
## **未开启传送时返回 0**：否则客户端会看到「enabled=false 但 capacity=1」这种自相矛盾的面板，
## 也会让 `remaining()` 在未开启时给出非 0 值。`blocker()` 仍先报「尚未开启」，提示更准确。
static func capacity(state: GameState, config: Dictionary, sect: Sect) -> int:
	if sect == null: return 0
	if not enabled(state, config, sect): return 0
	var base: int = int(config["teleport"]["capacityBase"])
	var per_node: int = int(config["teleport"]["capacityPerOwnLingMaiNode"])
	var guarded: int = 0
	for node: GameNode in state.nodes.values():
		if node.type != Enums.NodeType.LING_MAI: continue
		if node.ownerSectId != sect.id: continue
		if node.garrisonDiscipleIds.is_empty(): continue
		guarded += 1
	var total: int = base + guarded * per_node
	return mini(total, maxi(base, int(config["teleport"]["capacityMax"])))


## 本回合**剩余**次数。
static func remaining(state: GameState, config: Dictionary, sect: Sect) -> int:
	return maxi(0, capacity(state, config, sect) - sect.teleportsUsedThisTurn)


## 两峰之间的灵石费：`baseStones` + 六边距离 × `stonesPerHex`。
static func cost(state: GameState, config: Dictionary, from_peak: SpiritPeak, to_peak: SpiritPeak) -> int:
	var base: int = int(config["teleport"]["baseStones"])
	if from_peak == null or to_peak == null: return base
	var from_tile: HexTile = state.tiles.get(from_peak.tileId, null)
	var to_tile: HexTile = state.tiles.get(to_peak.tileId, null)
	if from_tile == null or to_tile == null: return base
	var distance: int = Hex.distance(Vector2i(from_tile.q, from_tile.r), Vector2i(to_tile.q, to_tile.r))
	return base + distance * int(config["teleport"]["stonesPerHex"])


## 传送前置校验：返回空串表示可传送，否则返回失败原因（供 `queryTeleportOptions.blocker` 预览）。
static func blocker(state: GameState, config: Dictionary, sect: Sect, from_peak: SpiritPeak, to_peak: SpiritPeak) -> String:
	if not enabled(state, config, sect): return "传送网络尚未开启(需推演「传送」道法)"
	if remaining(state, config, sect) <= 0:
		return "本回合传送次数已用尽(共%d次)" % capacity(state, config, sect)
	var price: int = cost(state, config, from_peak, to_peak)
	if int(sect.resources.get("spiritStones", 0)) < price:
		return "灵石不足, 此次传送需 %d 灵石" % price
	return ""


## 记一次传送消耗（只推进计数，扣灵石由调用方负责）。
static func record_use(sect: Sect) -> void:
	if sect == null: return
	sect.teleportsUsedThisTurn += 1


## 弟子当前所在灵峰（用于算传送起点费）；不在任何灵峰上返回 null。
static func peak_of_disciple(sect: Sect, disciple: Disciple) -> SpiritPeak:
	if sect == null or disciple == null: return null
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.tileId == disciple.tileId: return peak
	return null
