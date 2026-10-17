class_name AutomationRules
extends RefCounted
## 自动化规则（R6）：自动改良/修缮/道路/项目/探索 + 一键集结/回防/立即探索。
##
## 1.0 蓝本：`core/AutomationService.java` + `action/AutomationAction.java`。
##
## 与 1.0 的两处口径差异（已登记 PROTOCOL §11.1 #27）：
## 1. 1.0 的改良/修缮/道路工序在 `AIController.runAutomation` 里（AI 与玩家共用）。2.0 无 AI 控制器
##    （AI 行动归 R7），故本文件自带一套**确定性**工序：修缮 → 改良 → 道路，逐项复用 R3 的
##    `ImprovementAction.build_improvement` / `repair_improvement`，不重写造价与合法性判定。
## 2. 1.0 `rally`/`returnToDefense` 把闲置弟子**静默截断**到 `rallyMaxDisciples`；2.0 超限直接
##    `success:false`（避免「以为全员集结了其实只走了 8 人」），玩家可分批集结。
##
## 全部静态、无状态、只读 `config`；阈值一律取自 `automation` 节（裁决六），不硬编码。

const KEY_IMPROVE: String = "improve"
const KEY_REPAIR: String = "repair"
const KEY_ROAD: String = "road"
const KEY_EXPLORE: String = "explore"
## `setAutomationToggle.key` 合法集合（非法值在 dispatcher 回 `BAD_PARAMS`）。
const TOGGLE_KEYS: Array[String] = [KEY_IMPROVE, KEY_REPAIR, KEY_ROAD, KEY_EXPLORE]

## 开关 -> `automation.defaultAuto*` 兜底键。
const DEFAULT_KEYS: Dictionary = {
	KEY_IMPROVE: "defaultAutoImprove",
	KEY_REPAIR: "defaultAutoRepair",
	KEY_ROAD: "defaultAutoRoad",
	KEY_EXPLORE: "defaultAutoExplore",
}

const LABELS: Dictionary = {
	KEY_IMPROVE: "自动改良",
	KEY_REPAIR: "自动修缮",
	KEY_ROAD: "自动修路",
	KEY_EXPLORE: "自动探索",
}

const ROAD_TYPE: String = "QING_SHI_DAO_LU"


# ---------------------------------------------------------------------------
# 开关读取（缺键 → 跟随 config 默认值）
# ---------------------------------------------------------------------------

static func enabled(config: Dictionary) -> bool:
	return bool(config["automation"].get("enabled", true))


static func toggle_of(_state: GameState, config: Dictionary, sect: Sect, key: String) -> bool:
	if not DEFAULT_KEYS.has(key):
		return false
	if sect != null and sect.automationToggles.has(key):
		return bool(sect.automationToggles[key])
	return bool(config["automation"].get(str(DEFAULT_KEYS[key]), false))


static func auto_project_of(config: Dictionary, sect: Sect, peak: SpiritPeak) -> bool:
	if sect != null and sect.autoProjectByPeak.has(peak.id):
		return bool(sect.autoProjectByPeak[peak.id])
	return bool(config["automation"].get("defaultAutoProject", false))


static func label_of(key: String) -> String:
	return str(LABELS.get(key, key))


# ---------------------------------------------------------------------------
# 开关写入（业务失败 → `{success:false, message}`）
# ---------------------------------------------------------------------------

static func ok_result(message: String) -> Dictionary:
	return {"success": true, "message": message}


static func fail_result(message: String) -> Dictionary:
	return {"success": false, "message": message}


static func set_toggle(state: GameState, config: Dictionary, sect_id: String, key: String, on: bool) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	if not TOGGLE_KEYS.has(key):
		return fail_result("未知自动化开关: " + key)
	sect.automationToggles[key] = on
	state.eventLog.append("[自动] %s %s开关已%s" % [sect.name, label_of(key), "开启" if on else "关闭"])
	return ok_result("%s已%s" % [label_of(key), "开启" if on else "关闭"])


static func set_peak_auto_project(state: GameState, config: Dictionary, peak_id: String, on: bool) -> Dictionary:
	var peak: SpiritPeak = CityAction.find_peak(state, peak_id)
	if peak == null:
		return fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = CityAction.find_sect(state, peak.sectId)
	if sect == null:
		return fail_result("灵峰所属宗门不存在")
	sect.autoProjectByPeak[peak.id] = on
	state.eventLog.append("[自动] %s 自动项目已%s" % [peak.name, "开启" if on else "关闭"])
	return ok_result("%s 自动项目已%s" % [peak.name, "开启" if on else "关闭"])


static func set_all_auto_project(state: GameState, config: Dictionary, sect_id: String, on: bool) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	for peak: SpiritPeak in sect.spiritPeaks:
		sect.autoProjectByPeak[peak.id] = on
	state.eventLog.append("[自动] %s 全部%d座灵峰自动项目已%s" % [
		sect.name, sect.spiritPeaks.size(), "开启" if on else "关闭",
	])
	return ok_result("全部灵峰自动项目已%s" % ("开启" if on else "关闭"))


# ---------------------------------------------------------------------------
# TURN_START：每回合自动化
# ---------------------------------------------------------------------------

## `TURN_START` 唯一入口（**回填 R2 留的自动化 TODO**）：只对**玩家宗门**跑，
## 总行动数受 `maxActionsPerTurn` 约束；顺序固定（修缮 → 改良 → 道路 → 项目 → 探索）以保证确定性。
static func run_turn(state: GameState, config: Dictionary) -> Array[String]:
	var before: int = state.eventLog.size()
	if not enabled(config):
		return []
	for sect: Sect in state.sects:
		if not sect.player:
			continue
		var budget: int = int(config["automation"]["maxActionsPerTurn"])
		var do_repair: bool = toggle_of(state, config, sect, KEY_REPAIR)
		var do_improve: bool = toggle_of(state, config, sect, KEY_IMPROVE)
		var do_road: bool = toggle_of(state, config, sect, KEY_ROAD)
		if do_repair or do_improve or do_road:
			budget = _maintenance_pass(state, config, sect, budget, do_repair, do_improve, do_road)
		budget = _project_pass(state, config, sect, budget)
		if toggle_of(state, config, sect, KEY_EXPLORE) and budget > 0:
			var limit: int = mini(budget, int(config["automation"]["autoExploreMaxDisciples"]))
			explore_idle_disciples(state, config, sect, limit)
	return state.eventLog.slice(before)


## 修缮 → 改良 → 道路。每个成功动作耗 1 点预算；建造者须持 `builderChargeCost` 次以上建造次数。
static func _maintenance_pass(state: GameState, config: Dictionary, sect: Sect, budget: int, do_repair: bool, do_improve: bool, do_road: bool) -> int:
	if do_repair:
		budget = _repair_pass(state, config, sect, budget)
	if do_improve:
		budget = _improve_pass(state, config, sect, budget, false)
	if do_road:
		budget = _improve_pass(state, config, sect, budget, true)
	return budget


## 修缮：按改良 id 序遍历本宗破损改良，逐座派建造者前往并修复。
static func _repair_pass(state: GameState, config: Dictionary, sect: Sect, budget: int) -> int:
	var broken: Array[Improvement] = []
	for improvement: Improvement in sect.improvements:
		if improvement.broken:
			broken.append(improvement)
	broken.sort_custom(func(a: Improvement, b: Improvement) -> bool: return a.id < b.id)
	for improvement: Improvement in broken:
		if budget <= 0:
			break
		if not improvement.broken:
			continue
		var builder: Disciple = _builder_for(state, config, sect, improvement.tileId)
		if builder == null:
			continue
		var result: Dictionary = ImprovementAction.repair_improvement(state, config, sect.id, builder.id, improvement.tileId)
		if bool(result["success"]):
			budget -= 1
			state.eventLog.append("[自动] %s 自动修缮: %s" % [sect.name, str(result["message"])])
	return budget


## 改良/道路：按 `aiPriority` 降序（同优先级按类型名升序）尝试，逐类型找本宗空地块。
## `road_only=true` 时只修路（`QING_SHI_DAO_LU`），否则跳过道路（避免与道路开关互相抢占）。
static func _improve_pass(state: GameState, config: Dictionary, sect: Sect, budget: int, road_only: bool) -> int:
	if budget <= 0:
		return budget
	var by_type: Dictionary = config["improvement"]["byType"]
	var types: Array[String] = []
	for type_id: String in by_type.keys():
		var entry: Dictionary = by_type[type_id]
		if not bool(entry.get("buildable", false)):
			continue
		if road_only != (type_id == ROAD_TYPE):
			continue
		types.append(type_id)
	types.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = int((by_type[a] as Dictionary).get("aiPriority", 0))
		var pb: int = int((by_type[b] as Dictionary).get("aiPriority", 0))
		if pa == pb:
			return a < b
		return pa > pb)
	var tiles: Array[HexTile] = []
	for tile: HexTile in state.tiles.values():
		if tile.ownerSectId == sect.id:
			tiles.append(tile)
	tiles.sort_custom(func(a: HexTile, b: HexTile) -> bool: return a.id < b.id)
	for type_id: String in types:
		for tile: HexTile in tiles:
			if budget <= 0:
				return budget
			# 先用地块合法性（跳过建造者校验），再派建造者，避免为不可建地块白跑一趟。
			if not ImprovementRules.can_build_improvement(state, config, sect, null, tile, type_id).is_empty():
				continue
			var builder: Disciple = _builder_for(state, config, sect, tile.id)
			if builder == null:
				continue
			var result: Dictionary = ImprovementAction.build_improvement(state, config, sect.id, builder.id, tile.id, type_id)
			if bool(result["success"]):
				budget -= 1
				state.eventLog.append("[自动] %s 自动施工: %s" % [sect.name, str(result["message"])])
				break
	return budget


## 找一个可用的建造者并使其**站到目标地块**（已在则直接用；否则尝试一次移动）。
## 找不到/走不到返回 null（本项跳过，不耗预算）。
static func _builder_for(state: GameState, config: Dictionary, sect: Sect, tile_id: String) -> Disciple:
	var cost: int = int(config["automation"]["builderChargeCost"])
	var candidates: Array[Disciple] = []
	for disciple: Disciple in sect.disciples:
		if disciple.builderCharges < cost:
			continue
		if not disciple.garrisonNodeId.is_empty() or disciple.injured:
			continue
		candidates.append(disciple)
	candidates.sort_custom(func(a: Disciple, b: Disciple) -> bool:
		if a.movePoints == b.movePoints:
			return a.id < b.id
		return a.movePoints > b.movePoints)
	for disciple: Disciple in candidates:
		if disciple.tileId == tile_id:
			return disciple
	for disciple: Disciple in candidates:
		var moved: Dictionary = MoveAction.move_disciple(state, config, disciple.id, tile_id)
		if bool(moved["success"]) and str(moved["reachedTileId"]) == tile_id:
			return disciple
	return null


## 自动项目：开关开着且队列空时，按 `automation.projectPreference[factionType]` 顺序尝试立项。
static func _project_pass(state: GameState, config: Dictionary, sect: Sect, budget: int) -> int:
	var preferences: Dictionary = config["automation"].get("projectPreference", {})
	var prefs: Array = preferences.get(sect.factionType, [])
	if prefs.is_empty():
		return budget
	for peak: SpiritPeak in sect.spiritPeaks:
		if budget <= 0:
			break
		if not auto_project_of(config, sect, peak) or not peak.projectQueue.is_empty():
			continue
		for entry: Variant in prefs:
			var result: Dictionary = CityAction.construct_building(state, config, peak.id, str(entry))
			if bool(result["success"]):
				budget -= 1
				state.eventLog.append("[自动] %s 自动立项: %s" % [peak.name, str(result["message"])])
				break
	return budget


## 自动探索：最多 `count` 名闲置弟子各自走向**可达范围内最近**的未探明地块。
## 返回实际外出人数（供 `exploreNow` 文案复用）。
static func explore_idle_disciples(state: GameState, config: Dictionary, sect: Sect, count: int) -> int:
	var sent: int = 0
	for disciple: Disciple in idle_disciples(state, sect):
		if sent >= count:
			break
		var frontier: String = nearest_unexplored_tile(state, config, sect, disciple)
		if frontier.is_empty():
			continue
		sent += 1
		MoveAction.move_disciple(state, config, disciple.id, frontier)
	if sent > 0:
		state.eventLog.append("[自动] %s 自动探索, %d 名弟子向边荒进发" % [sect.name, sent])
	return sent


# ---------------------------------------------------------------------------
# 一键集结 / 回防 / 立即探索
# ---------------------------------------------------------------------------

## 一键集结：闲置弟子按机动降序开赴目标地块，**上限 `rallyMaxDisciples`**。
## 超过上限直接失败（2.0 语义，见文件头第 2 条）。
static func rally(state: GameState, config: Dictionary, sect_id: String, tile_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	if not state.tiles.has(tile_id):
		return fail_result("目标地块不存在: " + tile_id)
	var limit: int = int(config["automation"]["rallyMaxDisciples"])
	var idle: Array[Disciple] = idle_disciples(state, sect)
	if idle.size() > limit:
		return fail_result("集结人数超限: 最多 %d 人(当前 %d 人闲置)" % [limit, idle.size()])
	var arrived: int = 0
	for disciple: Disciple in idle:
		if disciple.tileId == tile_id:
			arrived += 1
			continue
		var moved: Dictionary = MoveAction.move_disciple(state, config, disciple.id, tile_id)
		if bool(moved["success"]) and str(moved["reachedTileId"]) == tile_id:
			arrived += 1
	state.eventLog.append("[自动] %s 一键集结, %d/%d 名弟子抵达 %s" % [sect.name, arrived, idle.size(), tile_id])
	return ok_result("集结: %d/%d 名弟子已抵达" % [arrived, idle.size()])


## 一键回防：闲置弟子返回**原属灵峰**（不在则最近的己方灵峰），上限 `rallyMaxDisciples`。
static func return_to_defense(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	if sect.spiritPeaks.is_empty():
		return fail_result("本宗没有灵峰可回")
	var limit: int = int(config["automation"]["rallyMaxDisciples"])
	var idle: Array[Disciple] = idle_disciples(state, sect)
	if idle.size() > limit:
		return fail_result("回防人数超限: 最多 %d 人(当前 %d 人闲置)" % [limit, idle.size()])
	var arrived: int = 0
	for disciple: Disciple in idle:
		var destination: String = defense_tile_of(state, sect, disciple)
		if destination.is_empty() or destination == disciple.tileId:
			arrived += 1
			continue
		var moved: Dictionary = MoveAction.move_disciple(state, config, disciple.id, destination)
		if bool(moved["success"]) and str(moved["reachedTileId"]) == destination:
			arrived += 1
	state.eventLog.append("[自动] %s 一键回防, %d/%d 名弟子归位" % [sect.name, arrived, idle.size()])
	return ok_result("回防: %d/%d 名弟子已返回灵峰" % [arrived, idle.size()])


## 立即探索：立刻跑一轮自动探索（`autoExploreMaxDisciples` 人）。
static func explore_now(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	var limit: int = int(config["automation"]["autoExploreMaxDisciples"])
	var sent: int = explore_idle_disciples(state, config, sect, limit)
	if sent == 0:
		return fail_result("没有可派出的闲置弟子")
	return ok_result("%d 名弟子已外出探索" % sent)


# ---------------------------------------------------------------------------
# 只读查询：`queryAutomationState`
# ---------------------------------------------------------------------------

static func describe(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return {
			"sectId": sect_id,
			"enabled": enabled(config),
			"found": false,
			"autoImprove": false,
			"autoRepair": false,
			"autoRoad": false,
			"autoExplore": false,
			"summary": "",
			"peaks": [],
		}
	var improve: bool = toggle_of(state, config, sect, KEY_IMPROVE)
	var repair: bool = toggle_of(state, config, sect, KEY_REPAIR)
	var road: bool = toggle_of(state, config, sect, KEY_ROAD)
	var explore: bool = toggle_of(state, config, sect, KEY_EXPLORE)
	var peaks: Array = []
	var auto_peaks: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		var on: bool = auto_project_of(config, sect, peak)
		if on:
			auto_peaks += 1
		peaks.append({"peakId": peak.id, "name": peak.name, "autoProject": on})
	var summary: String = "自动改良%s | 自动修缮%s | 自动修路%s | 自动探索%s | 自动项目%d/%d峰" % [
		mark(improve), mark(repair), mark(road), mark(explore), auto_peaks, sect.spiritPeaks.size(),
	]
	return {
		"sectId": sect.id,
		"enabled": enabled(config),
		"found": true,
		"autoImprove": improve,
		"autoRepair": repair,
		"autoRoad": road,
		"autoExplore": explore,
		"summary": summary,
		"peaks": peaks,
	}


static func mark(on: bool) -> String:
	return "开" if on else "关"


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

## 闲置弟子：未驻守、未受伤、还有移动力。机动降序（弱脚力垫底），同机动按 id 升序保证确定性。
static func idle_disciples(state: GameState, sect: Sect) -> Array[Disciple]:
	var idle: Array[Disciple] = []
	for disciple: Disciple in sect.disciples:
		if not disciple.garrisonNodeId.is_empty() or disciple.injured:
			continue
		if disciple.movePoints <= 0:
			continue
		idle.append(disciple)
	idle.sort_custom(func(a: Disciple, b: Disciple) -> bool:
		if a.movePoints == b.movePoints:
			return a.id < b.id
		return a.movePoints > b.movePoints)
	return idle


## 回防目标：原属灵峰（地块仍归本宗）→ 否则最近的己方灵峰（同距按 peak id 升序）。
static func defense_tile_of(state: GameState, sect: Sect, disciple: Disciple) -> String:
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.id != disciple.assignedPeakId:
			continue
		var tile: HexTile = state.tiles.get(peak.tileId, null)
		if tile != null and tile.ownerSectId == sect.id:
			return peak.tileId
	var from: HexTile = state.tiles.get(disciple.tileId, null)
	var best: String = ""
	var best_distance: int = 2147483647
	for peak: SpiritPeak in sect.spiritPeaks:
		var tile: HexTile = state.tiles.get(peak.tileId, null)
		if tile == null:
			continue
		var distance: int = 0
		if from != null:
			distance = Hex.distance(Hex.coords(from.id), Hex.coords(tile.id))
		if distance < best_distance:
			best_distance = distance
			best = peak.tileId
	return best


## 可达范围内**最近的未探明地块**（1.0 `nearestUnexploredTile`）；没有则空串。
## 未探明 = 不在 `sect.tileSnapshots`（已探明快照集合）里。同距按 tile id 升序保证确定性。
static func nearest_unexplored_tile(state: GameState, config: Dictionary, sect: Sect, disciple: Disciple) -> String:
	var from: HexTile = state.tiles.get(disciple.tileId, null)
	if from == null:
		return ""
	var reach: Dictionary = MoveRangeCalculator.reachable(state, config, disciple)
	var costs: Dictionary = reach["costs"]
	var best: String = ""
	var best_distance: int = 2147483647
	for tile_id: String in costs.keys():
		if sect.tileSnapshots.has(tile_id):
			continue
		var distance: int = Hex.distance(Hex.coords(from.id), Hex.coords(tile_id))
		if distance < best_distance or (distance == best_distance and tile_id < best):
			best_distance = distance
			best = tile_id
	return best
