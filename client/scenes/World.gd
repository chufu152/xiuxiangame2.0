extends Node3D
## 世界场景（表现层）。R1 起：分层渲染 + 三态迷雾 + 侧栏；R2 加：点选弟子 → 移动高亮 → 移动 → 顶部 TopBar。
##
## 职责：把服务端下发的 view 交给 HexMap / UnitView / SectView 分层渲染，配置三态迷雾，
## 维护极简侧栏（选中格地形 / 选中弟子）与顶部 TopBar（回合、阶段、资源、结束回合）。
##
## 硬约束（§8.4）：
##   - 只读 view，不推导任何玩法规则；迷雾可见集合与移动可达性**完全来自服务端**。
##   - 相机由常驻的 Session.camera_rig 提供；本场景**只做一次**首帧取景（frame_once），
##     view 刷新、点选、移动、结束回合、再开一局都不得重置相机角度与缩放。
##   - 占位资源缺失只由 AssetLibrary 告警回退，本场景不崩溃。

const SIDEBAR_WIDTH: float = 320.0
const TOPBAR_HEIGHT: float = 46.0
## R3 城市面板（左下角，覆盖在地图之上，不改相机）。
const CITY_PANEL_WIDTH: float = 400.0
const CITY_PANEL_MAX_HEIGHT: float = 360.0
## R4 道统树面板（左侧竖排，与城市面板/队列面板互斥，不改相机）。
const DAO_PANEL_WIDTH: float = 440.0
## R4 项目/研究队列面板（左下角，两列并排，不改相机）。
const QUEUE_PANEL_WIDTH: float = 620.0
const QUEUE_PANEL_HEIGHT: float = 320.0
## R5 战斗预览/结算面板（右下角，紧贴侧栏左侧，不改相机）。
const COMBAT_PANEL_WIDTH: float = 360.0
const COMBAT_PANEL_HEIGHT: float = 300.0
## R5 弟子详情面板（左下角，与城市面板互斥，不改相机）。
const UNIT_PANEL_WIDTH: float = 400.0
const UNIT_PANEL_HEIGHT: float = 400.0

var map: HexMap = null
var fog: Fog = null
var units: UnitView = null
var sects: SectView = null
var sidebar: RichTextLabel = null
var status_label: Label = null

## 顶部 TopBar（第 N 回合 / 阶段 / 玩家资源 / 结束回合）。
var topbar: CanvasLayer = null
var topbar_turn_label: Label = null
var topbar_phase_label: Label = null
var topbar_resource_label: Label = null
var end_turn_button: Button = null

## R3 城市面板。
var city_panel: CanvasLayer = null
var city_title_label: Label = null
var city_info_label: Label = null
var city_status_label: Label = null
var city_list: VBoxContainer = null
## 当前选中的己方灵峰 id（空串 = 未选中）。
var selected_peak_id: String = ""
## 最近一次 `queryCityDetail` 回包（只读，客户端不推导）。
var city_detail: Dictionary = {}
## 最近一次 `queryBuildOptions` 回包。
var build_options: Dictionary = {}
## 最近一次 `queryImprovementOptions` 回包。
var improvement_options: Dictionary = {}
## 城市选址/指派模式：""（无）/ "district"（区域选址）/ "worker"（劳力指派）。
var city_mode: String = ""
## 当前城市模式下的候选地块（服务端权威，客户端不本地推导）。
var city_candidate_ids: Array[String] = []
## 区域选址模式下待落成的区域类型。
var city_pending_district_type: String = ""
## 改良查询所针对的地块（来自最近一次点选的普通地块）。
var city_improvement_tile: String = ""

## R4 道统树面板（左）。数据全部来自 `view.sects[player].daoOptions`（服务端算好三态与 blocker）。
var dao_panel: CanvasLayer = null
var dao_title_label: Label = null
var dao_info_label: Label = null
var dao_list: VBoxContainer = null
var dao_status_label: Label = null
var dao_open: bool = false
## 最近一次 view 里的 `daoOptions`（21 条，客户端零规则）。
var dao_options: Array = []
## 最近一次 view 里的 `unlockedDaoIds`。
var unlocked_dao_ids: Array = []

## R4 项目/研究队列面板（左下）。`projects[]` 属灵峰、`researchQueue[]` 属宗门，两列不混。
var queue_panel: CanvasLayer = null
var queue_title_label: Label = null
var queue_build_list: VBoxContainer = null
var queue_research_list: VBoxContainer = null
var queue_status_label: Label = null
var queue_open: bool = false
## 最近一次 `queryProjectQueue` 回包（只读，客户端不推导）。
var project_queue: Dictionary = {}
## 队列面板当前针对的灵峰（打开面板时锁定，避免中途切换导致回包错位）。
var queue_peak_id: String = ""

## 当前选中格的文字描述（供 UI 与自动验收断言）。
var selection_text: String = ""
## 最近一次 view 里的势力数量。
var sect_count: int = 0

## 当前选中的己方弟子 id（空串 = 未选中）。
var selected_disciple_id: String = ""
## 是否处于移动模式（已选中弟子且有非空可达集）。
var move_mode: bool = false
## 最近一次 queryMoveRange 的可达格（服务端权威，客户端不本地推导）。
var reachable_ids: Array[String] = []
## 最近一次 queryMoveRange 的逐格累计代价（侧栏 / 验收用）。
var reachable_costs: Dictionary = {}
## 移动高亮起点（`HexMap.render_view` 会清空高亮层，重绘时需据此还原起点色）。
var reachable_origin: String = ""
## 移动模式下光标所在高亮格及其累计代价（-1 = 不在高亮内）。
var hover_tile_id: String = ""
var hover_cost: int = -1

# --- R5 战斗 / 单位操作 ---
## 攻击态：已选中弟子且已拿到服务端可攻击集（与移动态**并存**，两层高亮互不覆盖）。
var attack_mode: bool = false
## 最近一次 queryAttackable 的可攻击格（服务端权威；判定复用 preview().attackable）。
var attackable_ids: Array[String] = []
## 该弟子的射程（服务端下发，客户端不查表）。
var attack_range: int = 0
## 最近一次 queryAttackPreview 回包（悬停预览数据源）。
var attack_preview: Dictionary = {}
## 预览对应的目标格（避免回包错位到新悬停格）。
var preview_tile_id: String = ""
## 多选集合（Shift+点选己方弟子）；≥2 时点击可达格改走 batchMove。
var selected_ids: Array[String] = []
## 最近一次 queryDiscipleDetail 回包（详情面板数据源）。
var disciple_detail: Dictionary = {}
## 最近一次 queryTeleportOptions 回包。
var teleport_options: Dictionary = {}
## 弟子操作模式：""（无）/ "retreat"（选撤退目标格）。
var unit_mode: String = ""
## 撤退模式下的候选格（相邻且服务端判定可达者）。
var unit_retreat_ids: Array[String] = []
## 战斗/单位操作结果提示（战斗面板底部）。
var combat_feedback: String = ""
## 战斗面板 / 弟子详情面板。
var combat_panel: CanvasLayer = null
var combat_title_label: Label = null
var combat_info_label: Label = null
var combat_list: VBoxContainer = null
var combat_status_label: Label = null
var unit_panel: CanvasLayer = null
var unit_title_label: Label = null
var unit_info_label: Label = null
var unit_list: VBoxContainer = null
var unit_status_label: Label = null

var _selected: String = ""


func _ready() -> void:
	map = get_node("HexMap") as HexMap
	fog = get_node("Fog") as Fog
	units = get_node("UnitView") as UnitView
	sects = get_node("SectView") as SectView
	_build_lighting()
	_build_sidebar()
	_build_topbar()
	_build_city_panel()
	_build_dao_panel()
	_build_queue_panel()
	_build_combat_panel()
	_build_unit_panel()
	_build_explore_panel()
	_build_policy_panel()
	_build_automation_panel()
	Session.camera_rig.set_active(true)
	Session.view_changed.connect(_on_view_changed)
	Session.move_range_received.connect(_on_move_range_received)
	Session.move_result_received.connect(_on_move_result_received)
	Session.city_detail_received.connect(_on_city_detail_received)
	Session.build_options_received.connect(_on_build_options_received)
	Session.district_sites_received.connect(_on_district_sites_received)
	Session.assignable_tiles_received.connect(_on_assignable_tiles_received)
	Session.improvement_options_received.connect(_on_improvement_options_received)
	Session.r3_result_received.connect(_on_r3_result_received)
	Session.project_queue_received.connect(_on_project_queue_received)
	Session.r4_result_received.connect(_on_r4_result_received)
	Session.attackable_received.connect(_on_attackable_received)
	Session.attack_preview_received.connect(_on_attack_preview_received)
	Session.teleport_options_received.connect(_on_teleport_options_received)
	Session.disciple_detail_received.connect(_on_disciple_detail_received)
	Session.r5_result_received.connect(_on_r5_result_received)
	Session.ji_yuan_info_received.connect(_on_ji_yuan_info_received)
	Session.mi_jing_info_received.connect(_on_mi_jing_info_received)
	Session.policy_options_received.connect(_on_policy_options_received)
	Session.automation_state_received.connect(_on_automation_state_received)
	Session.r6_result_received.connect(_on_r6_result_received)
	if not Session.current_view.is_empty():
		_render(Session.current_view)
	else:
		_set_selection("")
		_refresh_status()
		_refresh_topbar()
		_render_city_panel()
		_render_dao_panel()
		_render_queue_panel()
		_render_combat_panel()
		_render_unit_panel()
		_render_explore_panel()
		_render_policy_panel()
		_render_automation_panel()


func _process(_delta: float) -> void:
	# busy 期间禁用「结束回合」，避免 finishTurn/beginPlayerTurn 序列被重入。
	if end_turn_button != null:
		end_turn_button.disabled = Session.busy or not Session.supports(Commands.FINISH_TURN)


func _on_view_changed(view: Dictionary) -> void:
	_render(view)


# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------

func _render(view: Dictionary) -> void:
	var assets: AssetLibrary = Session.assets
	fog.configure(view)
	map.render_view(view, assets, fog)
	# `HexMap.render_view` 会清空全部子节点（含两层高亮），故按缓存数据原样重绘，
	# 保证「刷新 view / 移动后重查」不会让高亮凭空消失而选中态仍在。
	_redraw_highlights()
	units.render_view(view, map, assets, fog, selected_disciple_id)
	sects.render_view(view, map, assets, fog)
	sect_count = (view.get("sects", []) as Array).size()
	_cache_dao_data(view)
	var bounds: Dictionary = _view_bounds(view)
	Session.camera_rig.frame_once(bounds["center"], bounds["span"])
	if not _selected.is_empty():
		_set_selection(_selected)
	elif not selected_disciple_id.is_empty():
		_set_selection(_describe_disciple(selected_disciple_id, {}))
	_refresh_status()
	_refresh_topbar()
	_render_city_panel()
	_render_dao_panel()
	_render_queue_panel()
	_render_combat_panel()
	_render_unit_panel()
	_render_explore_panel()
	_render_policy_panel()
	_render_automation_panel()


## 按缓存数据重绘两层高亮（移动 / 攻击），二者独立并存。
func _redraw_highlights() -> void:
	if map == null:
		return
	if move_mode and not reachable_ids.is_empty():
		map.show_move_range(reachable_ids, reachable_costs, reachable_origin)
	if attack_mode and not attackable_ids.is_empty():
		map.show_attack_range(attackable_ids, _disciple_tile_id(selected_disciple_id))


## 从 view 缓存己方 `daoOptions` / `unlockedDaoIds`（客户端不推导任何道法规则）。
func _cache_dao_data(view: Dictionary) -> void:
	dao_options.clear()
	unlocked_dao_ids.clear()
	for sect: Dictionary in view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		for entry: Variant in sect.get("daoOptions", []):
			dao_options.append(entry)
		for dao_id: Variant in sect.get("unlockedDaoIds", []):
			unlocked_dao_ids.append(str(dao_id))
		return


func _view_bounds(view: Dictionary) -> Dictionary:
	var tiles: Dictionary = view.get("tiles", {})
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for tile_id: String in tiles:
		var tile: Dictionary = tiles[tile_id]
		var point: Vector3 = Hex.to_world(int(tile.get("q", 0)), int(tile.get("r", 0)))
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	if min_x > max_x:
		return {"center": Vector3.ZERO, "span": 24.0}
	return {
		"center": Vector3((min_x + max_x) / 2.0, 0.0, (min_z + max_z) / 2.0),
		"span": maxf(max_x - min_x, max_z - min_z) + 4.0,
	}


# ---------------------------------------------------------------------------
# 选中格
# ---------------------------------------------------------------------------

func select_tile(tile_id: String) -> void:
	_selected = tile_id
	_set_selection(tile_id)


func _set_selection(tile_id: String) -> void:
	selection_text = _describe(tile_id)
	if sidebar != null:
		sidebar.text = selection_text


func _describe(tile_id: String) -> String:
	if tile_id.is_empty():
		return "点击地块查看详情"
	if map == null or not map.tiles.has(tile_id):
		return "地块 %s\n（尚未载入）" % tile_id
	if fog.state_for(tile_id) == Fog.State.UNEXPLORED:
		# 未探索格绝不泄露任何地形/归属字段。
		return "地块 %s\n未探索" % tile_id
	var data: Dictionary = (map.tiles[tile_id] as Node3D).get_meta("display_data")
	return "\n".join(PackedStringArray([
		"地块 %s" % tile_id,
		"基底 %s" % _text_of(data, "baseTerrain"),
		"海拔 %s" % _text_of(data, "relief"),
		"地貌 %s" % _list_of(data, "features"),
		"河流 %s" % ("是" if not (data.get("riverEdges", []) as Array).is_empty() else "无"),
		"险地 %s" % ("是" if bool(data.get("danger", false)) else "否"),
		"节点 %s" % _text_of(data, "nodeId"),
		"资源 %s" % _text_of(data, "luxuryType"),
		"归属 %s" % _text_of(data, "ownerSectId"),
	]))


static func _text_of(data: Dictionary, key: String) -> String:
	var value: Variant = data.get(key)
	if value == null or str(value).is_empty():
		return "无"
	return str(value)


static func _list_of(data: Dictionary, key: String) -> String:
	var values: Array = data.get(key, [])
	var parts: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		parts.append(str(value))
	if parts.is_empty():
		return "无"
	return "、".join(parts)


# ---------------------------------------------------------------------------
# R2：点选 → 高亮 → 移动
# ---------------------------------------------------------------------------

## 左键点击优先级：① 撤退模式下点候选格 → retreat；② 攻击模式下点可攻击格 → attack；
## ③ 多选（≥2）且点可达格 → batchMove；④ 移动模式下点可达格 → moveDisciple；
## ⑤ 城市选址/指派模式下点候选格 → foundDistrict/assignWorker；
## ⑥ 点机缘/秘境节点所在格 → 打开探索面板（按住 Shift 跳过，改为选中格上弟子）；
## ⑦ 点己方弟子所在格 → 选中并 queryMoveRange（按住 Shift 追加多选）；⑧ 点己方灵峰所在格 → 打开城市面板；
## ⑨ 否则回到 R1 的地块选择。
##
## 攻击与移动不冲突：服务端 `MoveRules.step_cost` 对敌方占据格返回 `IMPASSABLE`，
## 故敌方格永不出现在可达集里，先判攻击不会抢占移动。
func on_tile_clicked(tile_id: String) -> void:
	if unit_mode == "retreat" and unit_retreat_ids.has(tile_id):
		Session.request_retreat(selected_disciple_id, tile_id)
		return
	if attack_mode and attackable_ids.has(tile_id):
		Session.request_attack(selected_disciple_id, tile_id)
		return
	if move_mode and reachable_ids.has(tile_id):
		if selected_ids.size() >= 2:
			Session.request_batch_move(player_sect_id(), selected_ids, tile_id)
		else:
			Session.request_move_disciple(selected_disciple_id, tile_id)
		return
	if city_mode == "district" and city_candidate_ids.has(tile_id):
		Session.request_found_district(player_sect_id(), selected_peak_id, city_pending_district_type, tile_id)
		return
	if city_mode == "worker" and city_candidate_ids.has(tile_id):
		Session.request_assign_worker(selected_peak_id, tile_id)
		return
	# R6：机缘/秘境节点 → 探索面板（优先于「选中格上弟子」：秘境要求弟子站在节点格上，
	# 若先选弟子就再也点不开探索面板。需要选格上弟子时按住 Shift 点选）。
	var node_id: String = _node_id_at(tile_id)
	if not node_id.is_empty() and not Input.is_key_pressed(KEY_SHIFT):
		var node_type: String = node_type_of(node_id)
		if node_type == Enums.NodeType.JI_YUAN or node_type == Enums.NodeType.MI_JING:
			_exit_city_mode()
			_exit_unit_mode()
			_clear_move_state()
			open_explore_panel(node_id)
			return
	var disciple: Dictionary = _player_disciple_at(tile_id)
	if not disciple.is_empty():
		select_disciple(str(disciple.get("id", "")), Input.is_key_pressed(KEY_SHIFT))
		return
	var peak_id: String = _player_peak_at(tile_id)
	if not peak_id.is_empty():
		select_peak(peak_id)
		return
	_exit_city_mode()
	_exit_unit_mode()
	_clear_move_state()
	select_tile(tile_id)
	city_improvement_tile = tile_id


## 选中己方弟子。`additive=true`（Shift+点选）只把该弟子追加进 `selected_ids`，
## 不改主选中、也不重拉服务端数据——多选仅用于 batchMove。
func select_disciple(disciple_id: String, additive: bool = false) -> void:
	if additive:
		if not selected_ids.has(disciple_id):
			selected_ids.append(disciple_id)
		_render_unit_panel()
		_render_combat_panel()
		return
	selected_peak_id = ""
	_close_r4_panels()
	_exit_city_mode()
	_exit_unit_mode()
	# 弟子详情面板与城市面板同占左下角，互斥显示。
	if city_panel != null:
		city_panel.visible = false
	selected_disciple_id = disciple_id
	selected_ids.clear()
	selected_ids.append(disciple_id)
	move_mode = false
	reachable_ids.clear()
	reachable_costs.clear()
	reachable_origin = ""
	attack_mode = false
	attackable_ids.clear()
	attack_range = 0
	attack_preview.clear()
	preview_tile_id = ""
	hover_tile_id = ""
	hover_cost = -1
	_selected = ""
	if map != null:
		map.clear_move_range()
		map.clear_attack_range()
	if units != null:
		units.set_selected(disciple_id)
	_set_selection(_describe_disciple(disciple_id, {}))
	# 串行链①：可达集 →（回包后）可攻击集 →（回包后）弟子详情。
	# `Session._request` 是单请求语义，`busy` 期间并发请求会被直接丢弃，故只能链式触发。
	Session.request_query_move_range(disciple_id)


## 清空移动 + 攻击 + 多选态（选中灵峰、点空地、切换面板时调用）。
func _clear_move_state() -> void:
	move_mode = false
	attack_mode = false
	selected_disciple_id = ""
	selected_ids.clear()
	reachable_ids.clear()
	reachable_costs.clear()
	reachable_origin = ""
	attackable_ids.clear()
	attack_range = 0
	attack_preview.clear()
	preview_tile_id = ""
	hover_tile_id = ""
	hover_cost = -1
	if map != null:
		map.clear_move_range()
		map.clear_attack_range()
	if units != null:
		units.set_selected("")
	unit_mode = ""
	unit_retreat_ids.clear()
	_render_combat_panel()
	_render_unit_panel()


func _on_move_range_received(result: Dictionary) -> void:
	if str(result.get("discipleId", "")) != selected_disciple_id:
		return
	var ids: Array = result.get("tileIds", [])
	reachable_ids.clear()
	for value: Variant in ids:
		reachable_ids.append(str(value))
	reachable_costs = (result.get("costs", {}) as Dictionary).duplicate()
	reachable_origin = str(result.get("originTileId", ""))
	move_mode = not reachable_ids.is_empty()
	map.show_move_range(ids, result.get("costs", {}), reachable_origin)
	_set_selection(_describe_disciple(selected_disciple_id, result))
	# 串行链②：可达集到齐后再拉可攻击集（同一次点选内的第二步）。
	Session.request_query_attackable(selected_disciple_id)


func _on_move_result_received(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		# 业务失败（不可达 / 移动力不足）：只提示，不移动。
		_set_selection(str(result.get("message", "移动失败")))
		return
	if int(result.get("turnsRemaining", 0)) > 0:
		# 仍有移动力：重新查询，高亮随之更新（并再次链式拉可攻击集）。
		Session.request_query_move_range(selected_disciple_id)
	else:
		move_mode = false
		reachable_ids.clear()
		reachable_costs.clear()
		reachable_origin = ""
		map.clear_move_range()
		_set_selection(_describe_disciple(selected_disciple_id, {}))


func _player_disciple_at(tile_id: String) -> Dictionary:
	for sect: Dictionary in Session.current_view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		for disciple: Dictionary in sect.get("disciples", []):
			if str(disciple.get("tileId", "")) == tile_id:
				return disciple
	return {}


func _find_disciple(disciple_id: String) -> Dictionary:
	for sect: Dictionary in Session.current_view.get("sects", []):
		for disciple: Dictionary in sect.get("disciples", []):
			if str(disciple.get("id", "")) == disciple_id:
				return disciple
	return {}


func _describe_disciple(disciple_id: String, range_result: Dictionary) -> String:
	var disciple: Dictionary = _find_disciple(disciple_id)
	if disciple.is_empty():
		return "弟子 %s\n（已不在视野）" % disciple_id
	var move_points: int = int(disciple.get("movePoints", 0))
	var lines: PackedStringArray = PackedStringArray([
		"弟子 %s" % str(disciple.get("name", disciple_id)),
		"境界 %s" % str(disciple.get("realm", "?")),
		"灵根 %s" % _list_of(disciple, "spiritRoots"),
		"灵根品阶 %d" % int(disciple.get("rootGrade", 0)),
		"兵种 %s" % str(disciple.get("unitClass", "?")),
		"移动力 %d/%d" % [move_points, int(disciple.get("maxMovePoints", 0))],
	])
	# R4 弟子详情（字段全部来自 view，客户端不推导修炼/心魔规则）。
	lines.append("修为进度 %d" % int(disciple.get("cultivationProgress", 0)))
	lines.append("心魔 %d" % int(disciple.get("heartDevil", 0)))
	lines.append("伤势 %s" % ("受伤" if bool(disciple.get("injured", false)) else "无恙"))
	lines.append("入门 %d 回合" % int(disciple.get("turnsInSect", 0)))
	if int(disciple.get("builderCharges", 0)) > 0:
		lines.append("建造次数 %d" % int(disciple.get("builderCharges", 0)))
	# R5 战绩/晋升/驻守（字段全部来自 view，客户端不推导战斗规则）。
	lines.append("战功 %d · 战阶 %d · 晋升点 %d" % [
		int(disciple.get("battleXp", 0)),
		int(disciple.get("battleLevel", 0)),
		int(disciple.get("promotionPoints", 0)),
	])
	var promotions: Array = disciple.get("promotions", [])
	if not promotions.is_empty():
		lines.append("晋升 %s" % _list_of(disciple, "promotions"))
	if not str(disciple.get("garrisonNodeId", "")).is_empty():
		lines.append("驻守 %s" % str(disciple.get("garrisonNodeId", "")))
	if int(disciple.get("reclassCooldown", 0)) > 0:
		lines.append("转职冷却 %d 回合" % int(disciple.get("reclassCooldown", 0)))
	if not range_result.is_empty():
		lines.append("可达格 %d" % int(range_result.get("tileCount", 0)))
	if attack_mode:
		lines.append("可攻击格 %d（射程 %d）" % [attackable_ids.size(), attack_range])
	if hover_cost >= 0:
		lines.append("光标格 %s 代价 %d" % [hover_tile_id, hover_cost])
	if move_points <= 0:
		lines.append("（本回合已无移动力，可选中但无可达格）")
	return "\n".join(lines)


## 某弟子当前所在地块（供攻击高亮层标注起点色）。
func _disciple_tile_id(disciple_id: String) -> String:
	if disciple_id.is_empty():
		return ""
	return str(_find_disciple(disciple_id).get("tileId", ""))


## 当前移动高亮格数（供自动验收断言）。
func highlight_count() -> int:
	if map == null:
		return 0
	return map.highlight_ids.size()


# ---------------------------------------------------------------------------
# 顶部 TopBar
# ---------------------------------------------------------------------------

func _build_topbar() -> void:
	topbar = CanvasLayer.new()
	topbar.name = "TopBar"
	topbar.layer = 2
	add_child(topbar)
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 0.0
	panel.offset_right = -SIDEBAR_WIDTH
	panel.offset_top = 0.0
	panel.offset_bottom = TOPBAR_HEIGHT
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.16, 0.15, 0.90)
	style.border_color = Color("4d5f57")
	style.border_width_bottom = 1
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	topbar.add_child(panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)

	topbar_turn_label = _topbar_label(row, "第 ? 回合")
	topbar_phase_label = _topbar_label(row, "阶段 ?")
	topbar_resource_label = _topbar_label(row, "")
	topbar_resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# R4：道统树 / 项目队列入口（两面板互斥，均不触碰相机）。
	var dao_button: Button = Button.new()
	dao_button.text = "道统"
	dao_button.tooltip_text = "打开道统树（21 条道法，三态由服务端判定）；相机角度与缩放保持不变"
	dao_button.pressed.connect(func() -> void: toggle_dao_panel())
	row.add_child(dao_button)
	var queue_button: Button = Button.new()
	queue_button.text = "队列"
	queue_button.tooltip_text = "打开项目/研究队列（projects[] 与 researchQueue[] 两列不混）；相机角度与缩放保持不变"
	queue_button.pressed.connect(func() -> void: open_queue_panel())
	row.add_child(queue_button)

	# R6：政令 / 自动化入口（与探索面板互斥，均不触碰相机）。
	var policy_button: Button = Button.new()
	policy_button.text = "政令"
	policy_button.tooltip_text = "打开政令面板（政体/政令卡/槽位/时代门控均由服务端判定）；相机角度与缩放保持不变"
	policy_button.pressed.connect(func() -> void: open_policy_panel())
	row.add_child(policy_button)
	var automation_button: Button = Button.new()
	automation_button.text = "自动"
	automation_button.tooltip_text = "打开自动化面板（开关/自动项目/立即探索/集结/回防）；相机角度与缩放保持不变"
	automation_button.pressed.connect(func() -> void: open_automation_panel())
	row.add_child(automation_button)

	end_turn_button = Button.new()
	end_turn_button.text = "结束回合"
	end_turn_button.tooltip_text = "先 finishTurn 再 beginPlayerTurn；期间相机角度与缩放保持不变"
	end_turn_button.pressed.connect(func() -> void: Session.request_end_turn_sequence())
	row.add_child(end_turn_button)


func _topbar_label(parent: Node, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("e9e2ce"))
	parent.add_child(label)
	return label


func _refresh_topbar() -> void:
	var view: Dictionary = Session.current_view
	var meta: Dictionary = view.get("metadata", {})
	var turn: int = int(meta.get("turn", view.get("turn", 0)))
	var phase: String = str(meta.get("phase", view.get("phase", "?")))
	if topbar_turn_label != null:
		topbar_turn_label.text = "第 %d 回合" % turn
	if topbar_phase_label != null:
		topbar_phase_label.text = "阶段 %s" % phase
	if topbar_resource_label != null:
		topbar_resource_label.text = _resource_text(view)


func _resource_text(view: Dictionary) -> String:
	for sect: Dictionary in view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		var resources: Dictionary = sect.get("resources", {})
		var materials: Dictionary = resources.get("materials", {})
		return "灵力 %d · 灵石 %d · 工力 %d · 声望 %d · 粮 %d · 气运 %d · 道点 %d · 天晶 %d · 玄铁 %d · 灵木 %d" % [
			int(resources.get("spiritPower", 0)),
			int(resources.get("spiritStones", 0)),
			int(resources.get("workPower", 0)),
			int(resources.get("prestige", 0)),
			int(resources.get("food", 0)),
			int(resources.get("qiYun", 0)),
			int(resources.get("daoPoints", 0)),
			int(materials.get("tian_jing", 0)),
			int(materials.get("xuan_tie", 0)),
			int(materials.get("ling_mu", 0)),
		]
	return ""


# ---------------------------------------------------------------------------
# R3 城市面板（灵峰 / 建造 / 区域选址 / 劳力指派 / 改良）
# ---------------------------------------------------------------------------

func _build_city_panel() -> void:
	city_panel = CanvasLayer.new()
	city_panel.name = "CityPanel"
	city_panel.layer = 3
	add_child(city_panel)

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_right = CITY_PANEL_WIDTH
	panel.offset_top = -CITY_PANEL_MAX_HEIGHT
	panel.offset_bottom = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.94)
	style.border_color = Color("b6ad8b")
	style.border_width_top = 2
	style.border_width_right = 2
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	city_panel.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	city_title_label = Label.new()
	city_title_label.text = "城市面板（点选己方灵峰）"
	city_title_label.add_theme_font_size_override("font_size", 17)
	city_title_label.add_theme_color_override("font_color", Color("294e48"))
	city_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(city_title_label)
	var close: Button = Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: _clear_city_state())
	header.add_child(close)

	city_info_label = Label.new()
	city_info_label.add_theme_font_size_override("font_size", 13)
	city_info_label.add_theme_color_override("font_color", Color("3c4b45"))
	city_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(city_info_label)

	column.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 150)
	column.add_child(scroll)
	city_list = VBoxContainer.new()
	city_list.add_theme_constant_override("separation", 4)
	city_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(city_list)

	city_status_label = Label.new()
	city_status_label.add_theme_font_size_override("font_size", 12)
	city_status_label.add_theme_color_override("font_color", Color("7a5a2c"))
	city_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(city_status_label)


## 选中己方灵峰：清移动态，拉取城市面板（只读）。
## 注意：`Session._request` 是「单请求串行」语义——`busy` 期间再次 `_request` 会被直接丢弃。
## 故 `queryBuildOptions` 不能与 `queryCityDetail` 连发，改为在详情回包后链式触发
## （见 `_on_city_detail_received`）。
func select_peak(peak_id: String) -> void:
	# 城市面板与 R4 道统/队列面板互斥（同一屏幕区域），选中灵峰即收起 R4 面板。
	_close_r4_panels()
	if city_panel != null:
		city_panel.visible = true
	_clear_move_state()
	_exit_city_mode()
	selected_peak_id = peak_id
	_selected = ""
	city_improvement_tile = ""
	Session.request_query_city_detail(peak_id)


func player_sect_id() -> String:
	return str(Session.current_view.get("playerSectId", ""))


func _player_peak_at(tile_id: String) -> String:
	for sect: Dictionary in Session.current_view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		for peak: Dictionary in sect.get("spiritPeaks", []):
			if str(peak.get("tileId", "")) == tile_id:
				return str(peak.get("id", ""))
	return ""


func _clear_city_state() -> void:
	_exit_city_mode()
	selected_peak_id = ""
	city_detail.clear()
	build_options.clear()
	improvement_options.clear()
	city_improvement_tile = ""
	_render_city_panel()


func _exit_city_mode() -> void:
	if city_mode.is_empty():
		return
	city_mode = ""
	city_candidate_ids.clear()
	city_pending_district_type = ""
	if map != null:
		map.clear_move_range()


func _enter_city_mode(mode: String, candidates: Array) -> void:
	city_mode = mode
	city_candidate_ids.clear()
	for value: Variant in candidates:
		city_candidate_ids.append(str(value))
	if map != null:
		map.show_move_range(city_candidate_ids, {}, "")
	_render_city_panel()


# --- 服务端回包 ---

func _on_city_detail_received(result: Dictionary) -> void:
	if str(result.get("peakId", "")) != selected_peak_id:
		return
	city_detail = result.duplicate(true)
	_render_city_panel()
	# 串行链：城市详情到齐后再拉可建建筑（单请求语义，见 `select_peak`）。
	Session.request_query_build_options(player_sect_id())


func _on_build_options_received(result: Dictionary) -> void:
	build_options = result.duplicate(true)
	_render_city_panel()


func _on_district_sites_received(result: Dictionary) -> void:
	if str(result.get("peakId", "")) != selected_peak_id:
		return
	var ids: Array = []
	for site: Dictionary in result.get("sites", []):
		ids.append(str(site.get("tileId", "")))
	_enter_city_mode("district", ids)
	city_status_label.text = "区域选址：%d 个候选格，点击高亮格落成" % ids.size()


func _on_assignable_tiles_received(result: Dictionary) -> void:
	if str(result.get("peakId", "")) != selected_peak_id:
		return
	var ids: Array = []
	for tile: Dictionary in result.get("tiles", []):
		ids.append(str(tile.get("tileId", "")))
	_enter_city_mode("worker", ids)
	city_status_label.text = "劳力指派：%d 个可指派格，点击高亮格指派" % ids.size()


func _on_improvement_options_received(result: Dictionary) -> void:
	improvement_options = result.duplicate(true)
	_render_city_panel()


func _on_r3_result_received(command: String, result: Dictionary) -> void:
	if city_status_label == null:
		return
	# 只读 `query*` 的 result 不带 `success`（形状见 PROTOCOL §4，由各自 `*_received` 信号处理），
	# 此处只接管写命令，避免把查询回包误判为「操作失败」并覆盖选址/指派提示。
	if not result.has("success"):
		return
	var message: String = str(result.get("message", ""))
	if not bool(result.get("success", false)):
		city_status_label.text = "✗ " + (message if not message.is_empty() else "操作失败")
		# 失败后退出选址/指派模式，避免残留高亮。
		if command == Commands.FOUND_DISTRICT or command == Commands.ASSIGN_WORKER:
			_exit_city_mode()
		return
	city_status_label.text = "✓ " + message
	# 写命令成功后刷新城市面板（详情回包会再链式拉一次可建建筑，见 `_on_city_detail_received`）。
	if command in [
		Commands.CONSTRUCT_BUILDING, Commands.OPEN_CAVE, Commands.FORTIFY_PEAK,
		Commands.FOUND_DISTRICT, Commands.ASSIGN_WORKER, Commands.UNASSIGN_WORKER,
		Commands.BUILD_IMPROVEMENT, Commands.REPAIR_IMPROVEMENT,
	]:
		if not selected_peak_id.is_empty():
			Session.request_query_city_detail(selected_peak_id)
		if command == Commands.FOUND_DISTRICT or command == Commands.ASSIGN_WORKER:
			_exit_city_mode()


# --- 面板渲染 ---

func _render_city_panel() -> void:
	if city_title_label == null or city_info_label == null or city_list == null:
		return
	for child: Node in city_list.get_children():
		city_list.remove_child(child)
		child.queue_free()
	if selected_peak_id.is_empty() or city_detail.is_empty():
		city_title_label.text = "城市面板（点选己方灵峰）"
		city_info_label.text = "点击己方灵峰所在格以查看城市详情。"
		return
	if not bool(city_detail.get("found", false)):
		city_title_label.text = "城市面板 · 灵峰不存在"
		city_info_label.text = "peakId=%s 未找到。" % selected_peak_id
		return
	city_title_label.text = "城市面板 · %s" % str(city_detail.get("name", selected_peak_id))
	city_info_label.text = _city_info_text(city_detail)
	_populate_city_buttons()


func _city_info_text(detail: Dictionary) -> String:
	var yield_text: String = _yield_text(detail.get("cityYield", {}))
	return "\n".join(PackedStringArray([
		"等级 %d · %s · 防御 %d" % [int(detail.get("level", 0)), "主峰" if bool(detail.get("capital", false)) else "副峰", int(detail.get("defense", 0))],
		"人口 %d · 空闲劳力 %d · 住房 %d" % [int(detail.get("population", 0)), int(detail.get("freeWorkers", 0)), int(detail.get("housing", 0))],
		"粮食 %d · 粮收支 %d · 安定 %d" % [int(detail.get("food", 0)), int(detail.get("foodBalance", 0)), int(detail.get("stability", 0))],
		"气运 %d/%d · 产出倍率 %.2f" % [int(detail.get("qiYun", 0)), int(detail.get("qiYunMax", 0)), float(detail.get("outputMultiplier", 1.0))],
		"工作格 %d · 区域 %d · 产出 %s" % [
			(detail.get("workedTileIds", []) as Array).size(),
			int(detail.get("builtDistrictCount", 0)),
			yield_text if not yield_text.is_empty() else "无",
		],
	]))


static func _yield_text(yields: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["food", "spiritPower", "spiritStones", "daoPoints", "qiYun"]:
		var amount: int = int(yields.get(key, 0))
		if amount != 0:
			parts.append("%s%d" % [_resource_label(key), amount])
	return "/".join(parts)


static func _resource_label(key: String) -> String:
	match key:
		"food": return "粮"
		"spiritPower": return "灵"
		"spiritStones": return "石"
		"daoPoints": return "道"
		"qiYun": return "气运"
	return key


func _populate_city_buttons() -> void:
	# 建造：queryBuildOptions 的可建建筑清单（allowed/blocker/cost/turns/affordable）。
	var options: Array = build_options.get("options", [])
	if not options.is_empty():
		city_list.add_child(_city_section_label("建造（灵力/材料）"))
		for option: Dictionary in options:
			var label: String = "%s（灵%d · %d回合）" % [
				str(option.get("displayName", option.get("type", "?"))),
				int(option.get("cost", 0)),
				int(option.get("turns", 0)),
			]
			var button: Button = Button.new()
			button.text = label
			button.tooltip_text = "已建满/材料不足时置灰；blocker：%s" % str(option.get("blocker", "无"))
			button.disabled = not bool(option.get("allowed", false)) or not bool(option.get("affordable", true))
			var building_type: String = str(option.get("type", ""))
			button.pressed.connect(func() -> void: Session.request_construct_building(selected_peak_id, building_type))
			city_list.add_child(button)
	# 区域：districtTypes → 选址。
	var district_types: Array = city_detail.get("districtTypes", [])
	if not district_types.is_empty():
		city_list.add_child(_city_section_label("区域（选址落成）"))
		for entry: Dictionary in district_types:
			var district_type: String = str(entry.get("id", ""))
			if district_type == Enums.DistrictType.SHOU_FU_QU:
				continue
			var button: Button = Button.new()
			button.text = "选址建区：%s" % str(entry.get("name", district_type))
			button.pressed.connect(func() -> void: _begin_district_sites(district_type))
			city_list.add_child(button)
	# 劳力：指派 / 撤下。
	city_list.add_child(_city_section_label("劳力（工作半径内）"))
	var assign_button: Button = Button.new()
	assign_button.text = "指派劳力（列出可指派格）"
	assign_button.pressed.connect(func() -> void: Session.request_query_assignable_tiles(selected_peak_id))
	city_list.add_child(assign_button)
	for tile_id: Variant in city_detail.get("workedTileIds", []):
		var unassign: Button = Button.new()
		unassign.text = "撤下劳力：%s" % str(tile_id)
		var target: String = str(tile_id)
		unassign.pressed.connect(func() -> void: Session.request_unassign_worker(selected_peak_id, target))
		city_list.add_child(unassign)
	# 改良：查询本格 / 建 / 修缮。
	city_list.add_child(_city_section_label("改良（需建造者身处本格）"))
	if city_improvement_tile.is_empty():
		var hint: Label = Label.new()
		hint.text = "先点选一块己方地块，再查询改良。"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color("6d7470"))
		city_list.add_child(hint)
	else:
		var query_button: Button = Button.new()
		query_button.text = "查询改良选项（%s）" % city_improvement_tile
		query_button.pressed.connect(func() -> void: Session.request_query_improvement_options(player_sect_id(), city_improvement_tile))
		city_list.add_child(query_button)
		for option: Dictionary in improvement_options.get("options", []):
			var option_button: Button = Button.new()
			option_button.text = "%s（工力%d · %s）" % [
				str(option.get("displayName", option.get("type", "?"))),
				int(option.get("cost", 0)),
				str(option.get("yieldText", "")),
			]
			option_button.tooltip_text = str(option.get("rejection", ""))
			option_button.disabled = not bool(option.get("buildable", false))
			var improvement_type: String = str(option.get("type", ""))
			option_button.pressed.connect(func() -> void: _build_improvement(improvement_type))
			city_list.add_child(option_button)


func _begin_district_sites(district_type: String) -> void:
	city_pending_district_type = district_type
	Session.request_query_district_sites(player_sect_id(), selected_peak_id, district_type)


func _build_improvement(improvement_type: String) -> void:
	var disciple_id: String = _first_builder_id()
	if disciple_id.is_empty():
		city_status_label.text = "✗ 无可用建造者：请先 appointBuilder 任命低阶弟子"
		return
	Session.request_build_improvement(player_sect_id(), disciple_id, city_improvement_tile, improvement_type)


## 取己方首个有建造次数的弟子（appointBuilder 后的建造者）；无则回退首个弟子。
func _first_builder_id() -> String:
	var fallback: String = ""
	for sect: Dictionary in Session.current_view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		for disciple: Dictionary in sect.get("disciples", []):
			if fallback.is_empty():
				fallback = str(disciple.get("id", ""))
			if int(disciple.get("builderCharges", 0)) > 0:
				return str(disciple.get("id", ""))
	return fallback


func _city_section_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("294e48"))
	return label


# --- 供自动验收断言 ---

func city_panel_visible() -> bool:
	return city_panel != null and not selected_peak_id.is_empty()

func city_info_text() -> String:
	return city_info_label.text if city_info_label != null else ""

func city_button_count() -> int:
	return city_list.get_child_count() if city_list != null else 0

func city_candidate_count() -> int:
	return city_candidate_ids.size()


# ---------------------------------------------------------------------------
# R4 道统树面板（21 条道法 · 5 个时代 · 三态由服务端判定）
# ---------------------------------------------------------------------------

func _build_dao_panel() -> void:
	dao_panel = CanvasLayer.new()
	dao_panel.name = "DaoPanel"
	dao_panel.layer = 3
	dao_panel.visible = false
	add_child(dao_panel)

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_right = DAO_PANEL_WIDTH
	panel.offset_top = TOPBAR_HEIGHT
	panel.offset_bottom = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.96)
	style.border_color = Color("b6ad8b")
	style.border_width_right = 2
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	dao_panel.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	dao_title_label = Label.new()
	dao_title_label.text = "道统树"
	dao_title_label.add_theme_font_size_override("font_size", 17)
	dao_title_label.add_theme_color_override("font_color", Color("294e48"))
	dao_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(dao_title_label)
	var close: Button = Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: close_dao_panel())
	header.add_child(close)

	dao_info_label = Label.new()
	dao_info_label.add_theme_font_size_override("font_size", 13)
	dao_info_label.add_theme_color_override("font_color", Color("3c4b45"))
	dao_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(dao_info_label)

	column.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)
	column.add_child(scroll)
	dao_list = VBoxContainer.new()
	dao_list.add_theme_constant_override("separation", 3)
	dao_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(dao_list)

	dao_status_label = Label.new()
	dao_status_label.add_theme_font_size_override("font_size", 12)
	dao_status_label.add_theme_color_override("font_color", Color("7a5a2c"))
	dao_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(dao_status_label)


## 打开道统树：与城市面板/队列面板互斥（同一片屏幕区域），纯读 view，不请求服务端。
func open_dao_panel() -> void:
	_close_r4_panels()
	city_panel.visible = false
	dao_open = true
	dao_panel.visible = true
	_render_dao_panel()


func close_dao_panel() -> void:
	dao_open = false
	if dao_panel != null:
		dao_panel.visible = false
	if city_panel != null:
		city_panel.visible = true


func toggle_dao_panel() -> void:
	if dao_open:
		close_dao_panel()
	else:
		open_dao_panel()


func _close_r4_panels() -> void:
	dao_open = false
	queue_open = false
	if dao_panel != null:
		dao_panel.visible = false
	if queue_panel != null:
		queue_panel.visible = false


func _render_dao_panel() -> void:
	if dao_title_label == null or dao_list == null:
		return
	for child: Node in dao_list.get_children():
		dao_list.remove_child(child)
		child.queue_free()
	if not dao_open:
		return
	if dao_options.is_empty():
		dao_title_label.text = "道统树（未开局）"
		dao_info_label.text = "开局后显示 21 条道法、三态与阻塞原因。"
		dao_status_label.text = ""
		return
	var available: int = 0
	var researching: int = 0
	for entry: Dictionary in dao_options:
		match str(entry.get("state", "")):
			"AVAILABLE": available += 1
			"RESEARCHING": researching += 1
	dao_title_label.text = "道统树 · 已解锁 %d / %d" % [unlocked_dao_ids.size(), dao_options.size()]
	dao_info_label.text = "可研究 %d · 推演中 %d（三态与 blocker 由服务端判定）" % [available, researching]
	# 按 eraIndex 分列（时代名取自 view，客户端不内置任何道法表）。
	var era_order: Array[int] = []
	for entry: Dictionary in dao_options:
		var era_index: int = int(entry.get("eraIndex", 0))
		if not era_order.has(era_index):
			era_order.append(era_index)
	era_order.sort()
	for era_index: int in era_order:
		var era_name: String = ""
		for entry: Dictionary in dao_options:
			if int(entry.get("eraIndex", 0)) == era_index:
				era_name = str(entry.get("era", ""))
				break
		dao_list.add_child(_city_section_label("【%s】" % era_name))
		for entry: Dictionary in dao_options:
			if int(entry.get("eraIndex", 0)) != era_index:
				continue
			dao_list.add_child(_dao_button(entry))


func _dao_button(entry: Dictionary) -> Button:
	var state: String = str(entry.get("state", "BLOCKED"))
	var dao_id: String = str(entry.get("id", ""))
	var button: Button = Button.new()
	button.name = "Dao_" + dao_id
	button.text = "%s %s（道点%d · 工力%d · %d回合）" % [
		_dao_state_mark(state),
		str(entry.get("name", dao_id)),
		int(entry.get("daoPointCost", 0)),
		int(entry.get("spiritPowerCost", 0)),
		int(entry.get("turns", 0)),
	]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var tooltip: PackedStringArray = PackedStringArray()
	var desc: String = str(entry.get("desc", ""))
	if not desc.is_empty():
		tooltip.append(desc)
	var prerequisites: Array = entry.get("prerequisiteDaoIds", [])
	if not prerequisites.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for prerequisite: Variant in prerequisites:
			names.append(_dao_name(str(prerequisite)))
		tooltip.append("前置：" + "、".join(names))
	if not str(entry.get("factionOnly", "")).is_empty():
		tooltip.append("流派专属：%s" % str(entry.get("factionOnly", "")))
	if bool(entry.get("requiresBloodLine", false)):
		tooltip.append("需血脉")
	var blocker: String = str(entry.get("blocker", ""))
	if not blocker.is_empty():
		tooltip.append("阻塞：%s" % blocker)
	button.tooltip_text = "\n".join(tooltip)
	button.disabled = state != "AVAILABLE"
	match state:
		"UNLOCKED": button.add_theme_color_override("font_color", Color("1f6b3a"))
		"RESEARCHING": button.add_theme_color_override("font_color", Color("8a5a12"))
		"BLOCKED": button.add_theme_color_override("font_color", Color("8b8f8c"))
		_: button.add_theme_color_override("font_color", Color("294e48"))
	button.pressed.connect(func() -> void: Session.request_research_dao(player_sect_id(), dao_id))
	return button


static func _dao_state_mark(state: String) -> String:
	match state:
		"UNLOCKED": return "✓"
		"RESEARCHING": return "⏳"
		"AVAILABLE": return "◻"
		"BLOCKED": return "✗"
	return "?"


func _dao_name(dao_id: String) -> String:
	for entry: Dictionary in dao_options:
		if str(entry.get("id", "")) == dao_id:
			return str(entry.get("name", dao_id))
	return dao_id


# ---------------------------------------------------------------------------
# R4 项目 / 研究队列面板（projects[] 属灵峰、researchQueue[] 属宗门，两列不混）
# ---------------------------------------------------------------------------

func _build_queue_panel() -> void:
	queue_panel = CanvasLayer.new()
	queue_panel.name = "QueuePanel"
	queue_panel.layer = 4
	queue_panel.visible = false
	add_child(queue_panel)

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_right = QUEUE_PANEL_WIDTH
	panel.offset_top = -QUEUE_PANEL_HEIGHT
	panel.offset_bottom = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.96)
	style.border_color = Color("b6ad8b")
	style.border_width_top = 2
	style.border_width_right = 2
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	queue_panel.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	queue_title_label = Label.new()
	queue_title_label.text = "项目队列"
	queue_title_label.add_theme_font_size_override("font_size", 17)
	queue_title_label.add_theme_color_override("font_color", Color("294e48"))
	queue_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(queue_title_label)
	var recruit: Button = Button.new()
	recruit.text = "收徒大典"
	recruit.tooltip_text = "holdRecruitment：扣工力入项目队列，落成后新增外门弟子"
	recruit.pressed.connect(func() -> void: Session.request_hold_recruitment(active_peak_id()))
	header.add_child(recruit)
	var refresh: Button = Button.new()
	refresh.text = "刷新"
	refresh.pressed.connect(func() -> void: Session.request_query_project_queue(queue_peak_id))
	header.add_child(refresh)
	var close: Button = Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: close_queue_panel())
	header.add_child(close)

	column.add_child(HSeparator.new())

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)

	queue_build_list = _queue_column(columns, "建造项目 projects[]（灵峰）")
	queue_research_list = _queue_column(columns, "道法研究 researchQueue[]（宗门）")

	queue_status_label = Label.new()
	queue_status_label.add_theme_font_size_override("font_size", 12)
	queue_status_label.add_theme_color_override("font_color", Color("7a5a2c"))
	queue_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(queue_status_label)


func _queue_column(parent: Node, title: String) -> VBoxContainer:
	var wrapper: VBoxContainer = VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 4)
	parent.add_child(wrapper)
	wrapper.add_child(_city_section_label(title))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	wrapper.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


## 队列面板定位用的灵峰：优先当前选中灵峰，否则回退己方主峰（服务端权威字段 `capital`）。
func active_peak_id() -> String:
	if not selected_peak_id.is_empty():
		return selected_peak_id
	for sect: Dictionary in Session.current_view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		for peak: Dictionary in sect.get("spiritPeaks", []):
			if bool(peak.get("capital", false)):
				return str(peak.get("id", ""))
		for peak: Dictionary in sect.get("spiritPeaks", []):
			return str(peak.get("id", ""))
	return ""


func open_queue_panel() -> void:
	_close_r4_panels()
	city_panel.visible = false
	queue_open = true
	queue_panel.visible = true
	queue_peak_id = active_peak_id()
	project_queue.clear()
	_render_queue_panel()
	if not queue_peak_id.is_empty():
		Session.request_query_project_queue(queue_peak_id)
	else:
		queue_status_label.text = "✗ 己方无灵峰，无法查询项目队列"


func close_queue_panel() -> void:
	queue_open = false
	if queue_panel != null:
		queue_panel.visible = false
	if city_panel != null:
		city_panel.visible = true


func _render_queue_panel() -> void:
	if queue_title_label == null or queue_build_list == null:
		return
	for list: VBoxContainer in [queue_build_list, queue_research_list]:
		for child: Node in list.get_children():
			list.remove_child(child)
			child.queue_free()
	if not queue_open:
		return
	if project_queue.is_empty():
		queue_title_label.text = "项目队列（查询中…）"
		return
	if not bool(project_queue.get("found", false)):
		queue_title_label.text = "项目队列 · 灵峰不存在"
		return
	queue_title_label.text = "项目队列 · %s" % str(project_queue.get("peakName", queue_peak_id))
	var projects: Array = project_queue.get("projects", [])
	var research: Array = project_queue.get("researchQueue", [])
	if projects.is_empty():
		queue_build_list.add_child(_queue_hint("（无建造项目）"))
	else:
		for entry: Dictionary in projects:
			queue_build_list.add_child(_queue_row(entry, false))
	if research.is_empty():
		queue_research_list.add_child(_queue_hint("（无研究项目）"))
	else:
		for entry: Dictionary in research:
			queue_research_list.add_child(_queue_row(entry, true))


func _queue_hint(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("6d7470"))
	return label


## 单条队列行：`名称（剩 N/M 回合）` + 回合数输入 + 加速 + 取消。
func _queue_row(entry: Dictionary, research: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label: Label = Label.new()
	label.text = "%s（剩 %d/%d 回合）" % [
		str(entry.get("name", entry.get("id", "?"))),
		int(entry.get("turnsRemaining", 0)),
		int(entry.get("turnsRequired", 0)),
	]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("3c4b45"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var turns_input: SpinBox = SpinBox.new()
	turns_input.min_value = 1.0
	turns_input.max_value = 99.0
	turns_input.step = 1.0
	turns_input.value = 1.0
	turns_input.custom_minimum_size = Vector2(64, 0)
	turns_input.tooltip_text = "加速回合数（accelerateProject.turns）"
	row.add_child(turns_input)
	var project_id: String = str(entry.get("id", ""))
	var accelerate: Button = Button.new()
	accelerate.text = "加速"
	accelerate.tooltip_text = "消耗 accelerateStonePerTurn × 回合数 灵石；剩 0 回合即刻完成"
	accelerate.pressed.connect(func() -> void: Session.request_accelerate_project(queue_peak_id, project_id, int(turns_input.value), research))
	row.add_child(accelerate)
	var cancel: Button = Button.new()
	cancel.text = "取消"
	cancel.tooltip_text = "按 building.refundRate 返还已支付代价"
	cancel.pressed.connect(func() -> void: Session.request_cancel_project(queue_peak_id, project_id))
	row.add_child(cancel)
	return row


# --- R4 服务端回包 ---

func _on_project_queue_received(result: Dictionary) -> void:
	if str(result.get("peakId", "")) != queue_peak_id:
		return
	project_queue = result.duplicate(true)
	_render_queue_panel()


func _on_r4_result_received(command: String, result: Dictionary) -> void:
	# 只读 `query*` 的 result 不带 `success`（由各自 `*_received` 信号处理）。
	if not result.has("success"):
		return
	var message: String = str(result.get("message", ""))
	var text: String = ("✓ " if bool(result.get("success", false)) else "✗ ") + (message if not message.is_empty() else "操作失败")
	if dao_status_label != null:
		dao_status_label.text = text
	if queue_status_label != null:
		queue_status_label.text = text
	if not bool(result.get("success", false)):
		return
	# 写命令成功后重查队列（单请求语义：回包到达时 busy 已释放）。
	if queue_open and command in [
		Commands.RESEARCH_DAO, Commands.HOLD_RECRUITMENT,
		Commands.CANCEL_PROJECT, Commands.ACCELERATE_PROJECT,
	]:
		if not queue_peak_id.is_empty():
			Session.request_query_project_queue(queue_peak_id)


# ---------------------------------------------------------------------------
# R5 战斗面板（悬停攻击预览 + 战斗结算反馈）
# ---------------------------------------------------------------------------

func _build_combat_panel() -> void:
	combat_panel = CanvasLayer.new()
	combat_panel.name = "CombatPanel"
	combat_panel.layer = 3
	add_child(combat_panel)

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -SIDEBAR_WIDTH - COMBAT_PANEL_WIDTH
	panel.offset_right = -SIDEBAR_WIDTH
	panel.offset_top = -COMBAT_PANEL_HEIGHT
	panel.offset_bottom = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.94)
	style.border_color = Color("b6ad8b")
	style.border_width_top = 2
	style.border_width_left = 2
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	combat_panel.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	combat_title_label = Label.new()
	combat_title_label.text = "战斗预览"
	combat_title_label.add_theme_font_size_override("font_size", 17)
	combat_title_label.add_theme_color_override("font_color", Color("294e48"))
	column.add_child(combat_title_label)

	combat_info_label = Label.new()
	combat_info_label.add_theme_font_size_override("font_size", 13)
	combat_info_label.add_theme_color_override("font_color", Color("3c4b45"))
	combat_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(combat_info_label)

	column.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 90)
	column.add_child(scroll)
	combat_list = VBoxContainer.new()
	combat_list.add_theme_constant_override("separation", 3)
	combat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(combat_list)

	combat_status_label = Label.new()
	combat_status_label.add_theme_font_size_override("font_size", 12)
	combat_status_label.add_theme_color_override("font_color", Color("7a5a2c"))
	combat_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(combat_status_label)


## 战斗面板纯读缓存，不发任何请求。
func _render_combat_panel() -> void:
	if combat_title_label == null or combat_info_label == null or combat_list == null:
		return
	for child: Node in combat_list.get_children():
		combat_list.remove_child(child)
		child.queue_free()
	if combat_status_label != null:
		combat_status_label.text = combat_feedback
	var has_preview: bool = not attack_preview.is_empty()
	if combat_panel != null:
		combat_panel.visible = has_preview or not combat_feedback.is_empty()
	if not has_preview:
		combat_title_label.text = "战斗预览（选中弟子后悬停可攻击格）"
		combat_info_label.text = "可攻击格由服务端 queryAttackable 下发，与 preview().attackable 同一判定。"
		return
	var blocked: String = str(attack_preview.get("blockedReason", ""))
	combat_title_label.text = "战斗预览 · 目标 %s" % str(attack_preview.get("targetTileId", ""))
	if not blocked.is_empty():
		combat_info_label.text = "✗ 不可攻击：%s" % blocked
		return
	combat_info_label.text = "\n".join(PackedStringArray([
		"攻 %s 战力 %d · 守 %s 战力 %d" % [
			_unit_class_label(str(attack_preview.get("attackerClass", "?"))),
			int(attack_preview.get("attackerPower", 0)),
			_unit_class_label(str(attack_preview.get("defenderClass", "?"))),
			int(attack_preview.get("defenderPower", 0)),
		],
		"胜率 %.0f%% · 相克 ×%.2f · 反击 %d" % [
			float(attack_preview.get("winChance", 0.0)) * 100.0,
			float(attack_preview.get("counterMultiplier", 1.0)),
			int(attack_preview.get("retaliationPower", 0)),
		],
		"距离 %d · %s · 预计战功 %d" % [
			int(attack_preview.get("distance", 0)),
			"远程" if bool(attack_preview.get("ranged", false)) else "近战",
			int(attack_preview.get("xpPreview", 0)),
		],
	]))
	for note: Variant in attack_preview.get("notes", []):
		combat_list.add_child(_queue_hint(str(note)))
	var attack_button: Button = Button.new()
	attack_button.text = "发起攻击（%s）" % str(attack_preview.get("targetTileId", ""))
	attack_button.tooltip_text = "attack：与预览共用同一套 matchup 构建，预览与实战不会漂移"
	var target_tile: String = str(attack_preview.get("targetTileId", ""))
	attack_button.pressed.connect(func() -> void: Session.request_attack(selected_disciple_id, target_tile))
	combat_list.add_child(attack_button)


# ---------------------------------------------------------------------------
# R5 弟子详情面板（详情 + 撤退/传送/驻守 + 转职/晋升）
# ---------------------------------------------------------------------------

func _build_unit_panel() -> void:
	unit_panel = CanvasLayer.new()
	unit_panel.name = "UnitPanel"
	unit_panel.layer = 3
	unit_panel.visible = false
	add_child(unit_panel)

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_right = UNIT_PANEL_WIDTH
	panel.offset_top = -UNIT_PANEL_HEIGHT
	panel.offset_bottom = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.96)
	style.border_color = Color("b6ad8b")
	style.border_width_top = 2
	style.border_width_right = 2
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	unit_panel.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	unit_title_label = Label.new()
	unit_title_label.text = "弟子详情（点选己方弟子）"
	unit_title_label.add_theme_font_size_override("font_size", 17)
	unit_title_label.add_theme_color_override("font_color", Color("294e48"))
	unit_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(unit_title_label)
	var close: Button = Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: _clear_move_state())
	header.add_child(close)

	unit_info_label = Label.new()
	unit_info_label.add_theme_font_size_override("font_size", 13)
	unit_info_label.add_theme_color_override("font_color", Color("3c4b45"))
	unit_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(unit_info_label)

	column.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 150)
	column.add_child(scroll)
	unit_list = VBoxContainer.new()
	unit_list.add_theme_constant_override("separation", 3)
	unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(unit_list)

	unit_status_label = Label.new()
	unit_status_label.add_theme_font_size_override("font_size", 12)
	unit_status_label.add_theme_color_override("font_color", Color("7a5a2c"))
	unit_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(unit_status_label)


## 弟子详情面板纯读缓存（`queryDiscipleDetail` / `queryTeleportOptions` 回包），不发请求。
func _render_unit_panel() -> void:
	if unit_title_label == null or unit_list == null:
		return
	for child: Node in unit_list.get_children():
		unit_list.remove_child(child)
		child.queue_free()
	if unit_status_label != null:
		unit_status_label.text = combat_feedback
	var active: bool = not selected_disciple_id.is_empty()
	if unit_panel != null:
		unit_panel.visible = active
	if not active:
		unit_title_label.text = "弟子详情（点选己方弟子）"
		unit_info_label.text = "点选己方弟子查看兵种/战功/晋升，并可转职、晋升、传送、驻守、撤退。"
		return
	if not bool(disciple_detail.get("found", false)):
		unit_title_label.text = "弟子详情（查询中…）"
		unit_info_label.text = "discipleId=%s" % selected_disciple_id
		return
	unit_title_label.text = "弟子详情 · %s" % str(disciple_detail.get("name", selected_disciple_id))
	unit_info_label.text = "\n".join(PackedStringArray([
		"%s · %s · 射程 %d" % [
			str(disciple_detail.get("unitClassName", disciple_detail.get("unitClass", "?"))),
			str(disciple_detail.get("realmName", disciple_detail.get("realm", "?"))),
			int(disciple_detail.get("range", 1)),
		],
		"战功 %d · 战阶 %d · 晋升点 %d · 转职冷却 %d" % [
			int(disciple_detail.get("battleXp", 0)),
			int(disciple_detail.get("battleLevel", 0)),
			int(disciple_detail.get("promotionPoints", 0)),
			int(disciple_detail.get("reclassCooldown", 0)),
		],
		"出手 %d · 移动 %d/%d · 驻守 %s" % [
			int(disciple_detail.get("strikesLeft", 0)),
			int(disciple_detail.get("movePoints", 0)),
			int(disciple_detail.get("maxMovePoints", 0)),
			"无" if str(disciple_detail.get("garrisonNodeId", "")).is_empty() else str(disciple_detail.get("garrisonNodeId", "")),
		],
		"已习晋升 %s" % _list_of(disciple_detail, "promotionNames"),
	]))
	_populate_unit_actions()


func _populate_unit_actions() -> void:
	# 多选（batchMove）：Shift+点选累积，≥2 时点可达格走 batchMove。
	unit_list.add_child(_city_section_label("多选（Shift+点选己方弟子 → 点高亮格批量移动，上限 8 人）"))
	unit_list.add_child(_queue_hint("当前已选 %d 人：%s" % [selected_ids.size(), "、".join(PackedStringArray(_names_of(selected_ids)))]))
	# 撤退 / 驻守 / 传送
	unit_list.add_child(_city_section_label("机动"))
	var retreat: Button = Button.new()
	retreat.text = "撤退（选相邻格）"
	retreat.tooltip_text = "retreat：成功率由兵种/晋升决定，失败则被咬住并耗尽移动力"
	retreat.pressed.connect(func() -> void: _begin_retreat())
	unit_list.add_child(retreat)
	var node_id: String = _node_at_disciple(selected_disciple_id)
	var garrison: Button = Button.new()
	garrison.text = "驻守本格节点"
	garrison.tooltip_text = "assignGarrison：弟子须先移动到己方节点所在地块"
	garrison.disabled = node_id.is_empty()
	garrison.pressed.connect(func() -> void: Session.request_assign_garrison(selected_disciple_id, node_id))
	unit_list.add_child(garrison)
	var withdraw: Button = Button.new()
	withdraw.text = "撤离驻守"
	withdraw.disabled = str(disciple_detail.get("garrisonNodeId", "")).is_empty()
	withdraw.pressed.connect(func() -> void: Session.request_withdraw_garrison(selected_disciple_id))
	unit_list.add_child(withdraw)
	var teleport: Button = Button.new()
	teleport.text = "传送（列出己方灵峰）"
	teleport.tooltip_text = "teleport：仅己方灵峰之间，消耗灵石并占用本回合传送次数"
	teleport.pressed.connect(func() -> void: Session.request_query_teleport_options(selected_disciple_id))
	unit_list.add_child(teleport)
	# 传送候选（queryTeleportOptions 回包）
	if bool(teleport_options.get("found", false)):
		unit_list.add_child(_queue_hint("传送容量 %d/%d（已用 %d）" % [
			int(teleport_options.get("remaining", 0)),
			int(teleport_options.get("capacity", 0)),
			int(teleport_options.get("capacity", 0)) - int(teleport_options.get("remaining", 0)),
		]))
		for option: Dictionary in teleport_options.get("options", []):
			var option_button: Button = Button.new()
			option_button.text = "传往 %s（%d 灵石）" % [
				str(option.get("name", option.get("peakId", "?"))),
				int(option.get("cost", 0)),
			]
			option_button.tooltip_text = "blocker：%s" % str(option.get("blocker", "无"))
			option_button.disabled = not bool(option.get("allowed", false))
			var peak_id: String = str(option.get("peakId", ""))
			option_button.pressed.connect(func() -> void: Session.request_teleport(selected_disciple_id, peak_id))
			unit_list.add_child(option_button)
	# 转职：availableUnitClasses[] 三态由服务端判定，非法/不满足者置灰并显示 blocker。
	unit_list.add_child(_city_section_label("转职（十兵种）"))
	for entry: Dictionary in disciple_detail.get("availableUnitClasses", []):
		var class_button: Button = Button.new()
		var unit_class: String = str(entry.get("id", ""))
		class_button.name = "Reclass_" + unit_class
		class_button.text = "%s %s" % ["◻" if bool(entry.get("allowed", false)) else "✗", str(entry.get("name", entry.get("id", "?")))]
		class_button.tooltip_text = "blocker：%s" % str(entry.get("blocker", "无"))
		class_button.disabled = not bool(entry.get("allowed", false))
		class_button.pressed.connect(func() -> void: Session.request_reclass(selected_disciple_id, unit_class))
		unit_list.add_child(class_button)
	# 晋升：availablePromotions[] 由服务端按战阶过滤。
	unit_list.add_child(_city_section_label("晋升（消耗晋升点）"))
	var promotions: Array = disciple_detail.get("availablePromotions", [])
	if promotions.is_empty():
		unit_list.add_child(_queue_hint("（暂无可选晋升：战阶或晋升点不足）"))
	for entry: Dictionary in promotions:
		var promotion_button: Button = Button.new()
		var promotion_id: String = str(entry.get("id", ""))
		promotion_button.name = "Promote_" + promotion_id
		promotion_button.text = "%s（需战阶 %d）" % [
			str(entry.get("name", entry.get("id", "?"))),
			int(entry.get("minLevel", 0)),
		]
		promotion_button.tooltip_text = str(entry.get("description", ""))
		promotion_button.disabled = int(disciple_detail.get("promotionPoints", 0)) <= 0
		promotion_button.pressed.connect(func() -> void: Session.request_promote(selected_disciple_id, promotion_id))
		unit_list.add_child(promotion_button)


## 撤退模式：候选格 = 服务端可达集中**相邻**者（相邻性属纯几何，用 Hex.distance 判，
## 不涉及任何玩法规则；能否撤退、成功率、代价一律由服务端 `retreat` 判定）。
func _begin_retreat() -> void:
	if selected_disciple_id.is_empty():
		return
	var origin: String = _disciple_tile_id(selected_disciple_id)
	if origin.is_empty() or not map.tiles.has(origin):
		combat_feedback = "✗ 弟子尚未落位，无法撤退"
		_render_combat_panel()
		_render_unit_panel()
		return
	var from: Dictionary = (map.tiles[origin] as Node3D).get_meta("display_data")
	unit_retreat_ids.clear()
	for tile_id: String in reachable_ids:
		if not map.tiles.has(tile_id):
			continue
		var data: Dictionary = (map.tiles[tile_id] as Node3D).get_meta("display_data")
		if Hex.distance(Vector2i(int(from.get("q", 0)), int(from.get("r", 0))), Vector2i(int(data.get("q", 0)), int(data.get("r", 0)))) != 1:
			continue
		unit_retreat_ids.append(tile_id)
	unit_mode = "retreat"
	if map != null:
		map.show_move_range(unit_retreat_ids, {}, origin)
	combat_feedback = "撤退模式：%d 个相邻候选格，点击高亮格撤退" % unit_retreat_ids.size()
	_render_combat_panel()
	_render_unit_panel()


func _exit_unit_mode() -> void:
	if unit_mode.is_empty():
		return
	unit_mode = ""
	unit_retreat_ids.clear()
	# 撤退候选与移动高亮共用同一层，退出后按缓存还原移动高亮。
	if map != null:
		if move_mode and not reachable_ids.is_empty():
			map.show_move_range(reachable_ids, reachable_costs, reachable_origin)
		else:
			map.clear_move_range()
	_render_unit_panel()


## 己方节点：返回该弟子所在地块上的节点 id（非节点格返回空串）。
func _node_at_disciple(disciple_id: String) -> String:
	var tile_id: String = _disciple_tile_id(disciple_id)
	if tile_id.is_empty():
		return ""
	for node_id: String in Session.current_view.get("nodes", {}):
		var node: Dictionary = (Session.current_view.get("nodes", {}) as Dictionary)[node_id]
		if str(node.get("tileId", "")) == tile_id:
			return node_id
	return ""


func _names_of(ids: Array[String]) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for disciple_id: String in ids:
		var disciple: Dictionary = _find_disciple(disciple_id)
		names.append(str(disciple.get("name", disciple_id)))
	return names


# --- R5 服务端回包 ---

func _on_attackable_received(result: Dictionary) -> void:
	if str(result.get("discipleId", "")) != selected_disciple_id:
		return
	attackable_ids.clear()
	for value: Variant in result.get("tileIds", []):
		attackable_ids.append(str(value))
	attack_range = int(result.get("range", 1))
	attack_mode = not attackable_ids.is_empty()
	if map != null:
		if attack_mode:
			map.show_attack_range(attackable_ids, _disciple_tile_id(selected_disciple_id))
		else:
			map.clear_attack_range()
	_set_selection(_describe_disciple(selected_disciple_id, {}))
	# 串行链③：可攻击集到齐后再拉弟子详情（第三步，同一次点选内）。
	Session.request_query_disciple_detail(selected_disciple_id)


func _on_attack_preview_received(result: Dictionary) -> void:
	# 回包只认「当前悬停格」，避免慢回包把预览画到新目标上。
	if str(result.get("targetTileId", "")) != preview_tile_id:
		return
	attack_preview = result.duplicate(true)
	_render_combat_panel()


func _on_teleport_options_received(result: Dictionary) -> void:
	if str(result.get("discipleId", "")) != selected_disciple_id:
		return
	teleport_options = result.duplicate(true)
	if not bool(result.get("enabled", false)):
		combat_feedback = "✗ 传送网络未开启（需道法 chuan_song）"
	_render_combat_panel()
	_render_unit_panel()


func _on_disciple_detail_received(result: Dictionary) -> void:
	if str(result.get("discipleId", result.get("id", ""))) != selected_disciple_id:
		return
	disciple_detail = result.duplicate(true)
	_render_unit_panel()


func _on_r5_result_received(command: String, result: Dictionary) -> void:
	# 只读 `query*` 的 result 不带 `success`（由各自 `*_received` 信号处理）。
	if not result.has("success"):
		return
	var success: bool = bool(result.get("success", false))
	var message: String = str(result.get("message", ""))
	var text: String = ("✓ " if success else "✗ ") + (message if not message.is_empty() else "操作失败")
	combat_feedback = text
	if command == Commands.ATTACK:
		combat_feedback = _combat_result_text(result)
	elif command == Commands.RETREAT:
		_exit_unit_mode()
	_render_combat_panel()
	_render_unit_panel()
	if not success:
		return
	match command:
		Commands.ATTACK:
			# 战斗后位置/血量/归属可能全变：重拉选中弟子（若还活着）的三段数据。
			if not _find_disciple(selected_disciple_id).is_empty():
				Session.request_query_move_range(selected_disciple_id)
			else:
				_clear_move_state()
		Commands.RETREAT, Commands.TELEPORT, Commands.BATCH_MOVE:
			if not _find_disciple(selected_disciple_id).is_empty():
				Session.request_query_move_range(selected_disciple_id)
		Commands.RECLASS, Commands.PROMOTE:
			# 转职/晋升会改机动上限与晋升加成，详情与高亮都要重拉。
			Session.request_query_disciple_detail(selected_disciple_id)
		Commands.ASSIGN_GARRISON, Commands.WITHDRAW_GARRISON:
			Session.request_query_disciple_detail(selected_disciple_id)


## 把 `CombatResult` 摊平成一行可读反馈（含 outcome / 伤亡 / 俘获 / notes）。
func _combat_result_text(result: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s %s（%d 回合 · 胜率 %.0f%%）" % [
		"✓" if bool(result.get("attackerWon", false)) else "✗",
		str(result.get("message", "")),
		int(result.get("rounds", 0)),
		float(result.get("winChance", 0.0)) * 100.0,
	])
	lines.append("战力 %d vs %d · 战功 +%d" % [
		int(result.get("attackerPower", 0)),
		int(result.get("defenderPower", 0)),
		int(result.get("xpAwarded", 0)),
	])
	var casualties: Array = result.get("casualties", [])
	if not casualties.is_empty():
		lines.append("伤亡：%s" % "、".join(PackedStringArray(casualties)))
	var captured: Array = result.get("capturedIds", [])
	if not captured.is_empty():
		lines.append("俘获：%s" % "、".join(PackedStringArray(captured)))
	for note: Variant in result.get("notes", []):
		lines.append("· " + str(note))
	return "\n".join(lines)


## 兵种 id → 中文名：名称一律取自服务端 `availableUnitClasses[]`，
## 客户端**不内置**任何兵种表（避免与 config 漂移）。
func _unit_class_label(unit_class: String) -> String:
	for entry: Dictionary in disciple_detail.get("availableUnitClasses", []):
		if str(entry.get("id", "")) == unit_class:
			return str(entry.get("name", unit_class))
	return unit_class


# --- 供自动验收断言（R5）---

func combat_panel_visible() -> bool:
	return combat_panel != null and combat_panel.visible

func combat_title_text() -> String:
	return combat_title_label.text if combat_title_label != null else ""

func combat_info_text() -> String:
	return combat_info_label.text if combat_info_label != null else ""

func combat_feedback_text() -> String:
	return combat_status_label.text if combat_status_label != null else ""

func combat_button_count() -> int:
	return combat_list.get_child_count() if combat_list != null else 0

func attack_highlight_count() -> int:
	return map.attack_ids.size() if map != null else 0

func unit_panel_visible() -> bool:
	return unit_panel != null and unit_panel.visible

func unit_info_text() -> String:
	return unit_info_label.text if unit_info_label != null else ""

func unit_button_count() -> int:
	return unit_list.get_child_count() if unit_list != null else 0

## 按兵种 id 找到转职按钮（按钮名 `Reclass_<unitClass>`）；未渲染返回空字典。
func reclass_button_state(unit_class: String) -> Dictionary:
	if unit_list == null:
		return {}
	var button: Button = unit_list.get_node_or_null(NodePath("Reclass_" + unit_class)) as Button
	if button == null:
		return {}
	return {"disabled": button.disabled, "text": button.text, "tooltip": button.tooltip_text}


## 按晋升 id 找到晋升按钮（按钮名 `Promote_<promotionId>`）；未渲染返回空字典。
func promote_button_state(promotion_id: String) -> Dictionary:
	if unit_list == null:
		return {}
	var button: Button = unit_list.get_node_or_null(NodePath("Promote_" + promotion_id)) as Button
	if button == null:
		return {}
	return {"disabled": button.disabled, "text": button.text, "tooltip": button.tooltip_text}


# --- 供自动验收断言 ---

func dao_panel_visible() -> bool:
	return dao_open

func dao_button_count() -> int:
	return dao_list.get_child_count() if dao_list != null else 0

func dao_option_count() -> int:
	return dao_options.size()

func dao_state_of(dao_id: String) -> String:
	for entry: Dictionary in dao_options:
		if str(entry.get("id", "")) == dao_id:
			return str(entry.get("state", ""))
	return ""

func dao_blocker_of(dao_id: String) -> String:
	for entry: Dictionary in dao_options:
		if str(entry.get("id", "")) == dao_id:
			return str(entry.get("blocker", ""))
	return ""

## 按道法 id 找到道统树里的按钮（按钮名 `Dao_<daoId>`）。
func dao_button(dao_id: String) -> Button:
	if dao_list == null:
		return null
	return dao_list.get_node_or_null(NodePath("Dao_" + dao_id)) as Button

func queue_panel_visible() -> bool:
	return queue_open

func queue_build_count() -> int:
	return _queue_row_count(queue_build_list)

func queue_research_count() -> int:
	return _queue_row_count(queue_research_list)

## 只数「条目行」（HBoxContainer）；空列表占位是 Label，不计入。
static func _queue_row_count(list: VBoxContainer) -> int:
	if list == null:
		return 0
	var count: int = 0
	for child: Node in list.get_children():
		if child is HBoxContainer:
			count += 1
	return count

func queue_status_text() -> String:
	return queue_status_label.text if queue_status_label != null else ""

func disciple_detail_text(disciple_id: String) -> String:
	return _describe_disciple(disciple_id, {})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 仅在移动/攻击/撤退态做悬停提示，避免常态下每帧射线拾取。
		if (move_mode or attack_mode or not unit_mode.is_empty()) and map != null:
			var motion: InputEventMouseMotion = event
			var hovered: String = map.pick_tile(Session.camera_rig.camera, motion.position)
			if hovered != hover_tile_id:
				hover_tile_id = hovered
				hover_cost = map.highlight_cost(hovered) if not hovered.is_empty() else -1
				if not selected_disciple_id.is_empty():
					_set_selection(_describe_disciple(selected_disciple_id, {}))
				_update_attack_preview(hovered)
		return
	if not (event is InputEventMouseButton):
		return
	var button: InputEventMouseButton = event
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if map == null or fog == null:
		return
	var picked: String = map.pick_tile(Session.camera_rig.camera, button.position)
	if not picked.is_empty():
		on_tile_clicked(picked)
		get_viewport().set_input_as_handled()


## 悬停攻击预览：只对「服务端判定可攻击」的格发请求。
## `Session._request` 是单请求语义，busy 期间直接跳过（回包按 `preview_tile_id` 校验，不会错位）。
func _update_attack_preview(hovered: String) -> void:
	if not attack_mode or hovered.is_empty() or not attackable_ids.has(hovered):
		if not preview_tile_id.is_empty():
			preview_tile_id = ""
			attack_preview.clear()
			_render_combat_panel()
		return
	if hovered == preview_tile_id:
		return
	if Session.busy:
		return
	query_attack_preview(hovered)


## 显式请求某格的攻击预览（悬停与自动验收共用）。
## 先锁定 `preview_tile_id` 再发请求，故慢回包不会画到新目标上。
func query_attack_preview(tile_id: String) -> String:
	if selected_disciple_id.is_empty():
		return ""
	preview_tile_id = tile_id
	return Session.request_query_attack_preview(selected_disciple_id, tile_id)


# ---------------------------------------------------------------------------
# 场景自建节点（避免 .tscn 里塞非必要子资源）
# ---------------------------------------------------------------------------

func _build_lighting() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	add_child(sun)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e7e2d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff6e2")
	environment.ambient_light_energy = 0.95
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


func _build_sidebar() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -SIDEBAR_WIDTH
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.94)
	style.border_color = Color("b6ad8b")
	style.border_width_left = 2
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title: Label = Label.new()
	title.text = "山河画卷 · R5"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("294e48"))
	column.add_child(title)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("5d6b64"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)

	column.add_child(HSeparator.new())

	sidebar = RichTextLabel.new()
	sidebar.fit_content = false
	sidebar.scroll_active = true
	sidebar.selection_enabled = false
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_font_size_override("normal_font_size", 15)
	sidebar.text = "点击地块查看详情"
	column.add_child(sidebar)

	column.add_child(HSeparator.new())

	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)
	var refresh: Button = Button.new()
	refresh.text = "刷新 view"
	refresh.tooltip_text = "向服务端请求 getState，相机角度与缩放保持不变"
	refresh.pressed.connect(func() -> void: Session.request_refresh())
	buttons.add_child(refresh)
	var back: Button = Button.new()
	back.text = "返回菜单"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	buttons.add_child(back)

	var hint: Label = Label.new()
	hint.text = "正交 45° · 滚轮缩放 · 中/右键平移 · 左键选中弟子/灵峰/地块 · 青高亮=可移动、赭红=可攻击 · 悬停可攻击格看胜率预览 · Shift+点选多选后点高亮格批量移动 · 左下弟子详情可转职/晋升/传送/驻守/撤退 · 顶栏「道统」「队列」 · 结束回合"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("6d7470"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	Session.status_changed.connect(_refresh_status)


func _refresh_status() -> void:
	if status_label != null:
		status_label.text = Session.status


# ---------------------------------------------------------------------------
# R6：探索 / 政令 / 自动化（三面板互斥；只读 view 与回包，客户端零规则）
# ---------------------------------------------------------------------------
# 三面板都只做「展示 + 发命令」：成功率、槽位、时代门控、阈值一律来自服务端
# `queryJiYuanInfo` / `queryMiJingInfo` / `queryPolicyOptions` / `queryAutomationState` 回包。
# 任何面板开关与操作都**不触碰相机**（不调 frame_once / 不改 transform / 不改 size）。

const R6_PANEL_WIDTH: float = 440.0
const R6_PANEL_HEIGHT: float = 392.0

var explore_panel: CanvasLayer = null
var explore_title_label: Label = null
var explore_info_label: Label = null
var explore_list: VBoxContainer = null
var explore_status_label: Label = null
var explore_open: bool = false
var explore_node_id: String = ""
var explore_info: Dictionary = {}
var explore_selected_ids: Array[String] = []

var policy_panel: CanvasLayer = null
var policy_title_label: Label = null
var policy_info_label: Label = null
var policy_list: VBoxContainer = null
var policy_status_label: Label = null
var policy_open: bool = false
var policy_options: Dictionary = {}

var automation_panel: CanvasLayer = null
var automation_title_label: Label = null
var automation_info_label: Label = null
var automation_list: VBoxContainer = null
var automation_status_label: Label = null
var automation_open: bool = false
var automation_state: Dictionary = {}

## 客户端本地设置（`setSetting` 只确认，值留在这里）。
var local_settings: Dictionary = {}


## 三面板共用骨架（左侧竖排，互斥显示）。
func _make_r6_panel(node_name: String, title_text: String) -> Array:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = node_name
	layer.layer = 3
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 8.0
	panel.offset_right = 8.0 + R6_PANEL_WIDTH
	panel.offset_top = TOPBAR_HEIGHT + 8.0
	panel.offset_bottom = TOPBAR_HEIGHT + 8.0 + R6_PANEL_HEIGHT
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.94)
	style.border_color = Color("b6ad8b")
	style.border_width_top = 2
	style.border_width_right = 2
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("294e48"))
	column.add_child(title)
	var info: Label = Label.new()
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color("3c4b45"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info)
	column.add_child(HSeparator.new())
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	column.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var status: Label = Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("7a5a2c"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	layer.visible = false
	return [layer, title, info, list, status]


## 清空按钮列表。`VBoxContainer` 没有 `clear()`，按本项目既有写法逐个摘除再释放；
## `remove_child` 是同步的，所以紧接着 `get_child_count()` 立刻归零（验收用例依赖这点）。
func _clear_r6_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _build_explore_panel() -> void:
	var parts: Array = _make_r6_panel("ExplorePanel", "探索")
	explore_panel = parts[0] as CanvasLayer
	explore_title_label = parts[1] as Label
	explore_info_label = parts[2] as Label
	explore_list = parts[3] as VBoxContainer
	explore_status_label = parts[4] as Label


func _build_policy_panel() -> void:
	var parts: Array = _make_r6_panel("PolicyPanel", "政令")
	policy_panel = parts[0] as CanvasLayer
	policy_title_label = parts[1] as Label
	policy_info_label = parts[2] as Label
	policy_list = parts[3] as VBoxContainer
	policy_status_label = parts[4] as Label


func _build_automation_panel() -> void:
	var parts: Array = _make_r6_panel("AutomationPanel", "自动化")
	automation_panel = parts[0] as CanvasLayer
	automation_title_label = parts[1] as Label
	automation_info_label = parts[2] as Label
	automation_list = parts[3] as VBoxContainer
	automation_status_label = parts[4] as Label


## 关闭三面板（`keep` 指定的那个保留），供互斥显示用。
func _close_r6_panels(keep: CanvasLayer = null) -> void:
	if explore_panel != keep:
		explore_open = false
	if policy_panel != keep:
		policy_open = false
	if automation_panel != keep:
		automation_open = false
	_sync_r6_visibility()


func _sync_r6_visibility() -> void:
	if explore_panel != null:
		explore_panel.visible = explore_open
	if policy_panel != null:
		policy_panel.visible = policy_open
	if automation_panel != null:
		automation_panel.visible = automation_open


# --- 探索 ---

## 地块上的节点 id（`view.tiles[tile].nodeId`；无节点回空串）。
func _node_id_at(tile_id: String) -> String:
	var tile: Dictionary = Session.current_view.get("tiles", {}).get(tile_id, {})
	var node_id: Variant = tile.get("nodeId")
	return "" if node_id == null else str(node_id)


## 节点类型（`view.nodes[nodeId].type`；未下发回空串）。
func node_type_of(node_id: String) -> String:
	var node: Dictionary = Session.current_view.get("nodes", {}).get(node_id, {})
	return str(node.get("type", ""))


func open_explore_panel(node_id: String) -> void:
	explore_node_id = node_id
	explore_open = true
	explore_info = {}
	explore_selected_ids.clear()
	_close_r6_panels(explore_panel)
	explore_status_label.text = "已选中节点 %s" % node_id
	_refresh_explore_info()
	_render_explore_panel()


func close_explore_panel() -> void:
	explore_open = false
	explore_node_id = ""
	explore_info = {}
	explore_selected_ids.clear()
	_sync_r6_visibility()
	_render_explore_panel()


## 按节点类型重拉只读信息（机缘 / 秘境各一条命令）。
func _refresh_explore_info() -> void:
	if explore_node_id.is_empty():
		return
	if node_type_of(explore_node_id) == Enums.NodeType.MI_JING:
		Session.request_query_mi_jing_info(explore_node_id)
	else:
		Session.request_query_ji_yuan_info(explore_node_id)


func _on_ji_yuan_info_received(result: Dictionary) -> void:
	if str(result.get("nodeId", "")) != explore_node_id:
		return
	explore_info = result
	_render_explore_panel()


func _on_mi_jing_info_received(result: Dictionary) -> void:
	if str(result.get("nodeId", "")) != explore_node_id:
		return
	explore_info = result
	_render_explore_panel()


## 探索面板纯读缓存 + 弟子列表（弟子来自 view，客户端不算任何成功率）。
func _render_explore_panel() -> void:
	_sync_r6_visibility()
	if explore_info_label == null:
		return
	if not explore_open:
		explore_info_label.text = ""
		_clear_r6_list(explore_list)
		return
	var info: Dictionary = explore_info.get("info", {})
	var kind: String = str(explore_info.get("kind", ""))
	var lines: PackedStringArray = PackedStringArray()
	if info.is_empty():
		lines.append("（等待服务端节点信息…）")
	else:
		lines.append("%s · 等级 %d" % [str(info.get("name", "")), int(info.get("level", 0))])
		lines.append("冷却 %d 回合" % int(info.get("cooldown", 0)))
		lines.append("奖励预览 %s" % str(info.get("rewardPreview", "")))
		if kind == "jiYuan":
			lines.append("需修为 %d 级 · 单人" % int(info.get("requiredRealmLevel", 0)))
		else:
			lines.append("耗灵石 %d · 最多 %d 人" % [int(info.get("cost", 0)), int(info.get("maxParticipants", 0))])
	explore_info_label.text = "\n".join(lines)
	_clear_r6_list(explore_list)
	var disciples: Array = _own_disciples()
	if kind == "miJing":
		for disciple: Dictionary in disciples:
			var disciple_id: String = str(disciple.get("id", ""))
			var picked: bool = explore_selected_ids.has(disciple_id)
			var toggle: Button = Button.new()
			toggle.name = "Pick_" + disciple_id
			toggle.text = ("☑ " if picked else "☐ ") + str(disciple.get("name", disciple_id))
			toggle.pressed.connect(func() -> void: _toggle_explore_pick(disciple_id))
			explore_list.add_child(toggle)
		var start: Button = Button.new()
		start.name = "ExploreMiJing"
		start.text = "开始探索（已选 %d 人）" % explore_selected_ids.size()
		start.disabled = explore_selected_ids.is_empty()
		start.pressed.connect(func() -> void:
			Session.request_explore_mi_jing(explore_selected_ids.duplicate(), explore_node_id))
		explore_list.add_child(start)
	else:
		for disciple: Dictionary in disciples:
			var disciple_id: String = str(disciple.get("id", ""))
			var send: Button = Button.new()
			send.name = "Send_" + disciple_id
			send.text = "派 %s 探机缘" % str(disciple.get("name", disciple_id))
			send.pressed.connect(func() -> void: Session.request_send_to_ji_yuan(disciple_id, explore_node_id))
			explore_list.add_child(send)
	var close: Button = Button.new()
	close.name = "CloseExplore"
	close.text = "关闭"
	close.pressed.connect(func() -> void: close_explore_panel())
	explore_list.add_child(close)


func _toggle_explore_pick(disciple_id: String) -> void:
	if explore_selected_ids.has(disciple_id):
		explore_selected_ids.erase(disciple_id)
	else:
		explore_selected_ids.append(disciple_id)
	_render_explore_panel()


## 己方弟子（`view.sects[player].disciples[]`，按 id 升序保证渲染稳定）。
func _own_disciples() -> Array:
	var out: Array = []
	for sect: Dictionary in Session.current_view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		for disciple: Dictionary in sect.get("disciples", []):
			out.append(disciple)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	return out


# --- 政令 ---

func open_policy_panel() -> void:
	policy_open = true
	_close_r6_panels(policy_panel)
	policy_status_label.text = ""
	Session.request_query_policy_options(player_sect_id())
	_render_policy_panel()


func close_policy_panel() -> void:
	policy_open = false
	_sync_r6_visibility()
	_render_policy_panel()


func _on_policy_options_received(result: Dictionary) -> void:
	policy_options = result
	_render_policy_panel()


func _render_policy_panel() -> void:
	_sync_r6_visibility()
	if policy_info_label == null:
		return
	if not policy_open:
		policy_info_label.text = ""
		_clear_r6_list(policy_list)
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("政体 %s · 时代序号 %d" % [str(policy_options.get("governmentName", "?")), int(policy_options.get("eraIndex", 0))])
	var cooldown: int = int(policy_options.get("switchCooldownLeft", 0))
	lines.append("切换冷却 %s" % ("%d 回合" % cooldown if cooldown > 0 else "就绪"))
	var effects: Dictionary = policy_options.get("effects", {})
	var effect_parts: PackedStringArray = PackedStringArray()
	for key: String in effects.keys():
		var value: float = float(effects[key])
		if is_zero_approx(value):
			continue
		effect_parts.append("%s%+.2f" % [key, value])
	lines.append("效果合计 %s" % ("、".join(effect_parts) if not effect_parts.is_empty() else "无"))
	policy_info_label.text = "\n".join(lines)
	_clear_r6_list(policy_list)
	for entry: Variant in policy_options.get("governments", []):
		var gov: Dictionary = entry
		var button: Button = Button.new()
		button.name = "Gov_" + str(gov.get("id", ""))
		button.text = ("● " if bool(gov.get("current", false)) else "○ ") + str(gov.get("name", "")) + " · " + str(gov.get("effectsText", ""))
		button.disabled = bool(gov.get("current", false)) or not bool(gov.get("allowed", false))
		button.tooltip_text = str(gov.get("blocker", ""))
		var gov_id: String = str(gov.get("id", ""))
		button.pressed.connect(func() -> void: Session.request_switch_government(player_sect_id(), gov_id))
		policy_list.add_child(button)
	policy_list.add_child(HSeparator.new())
	for entry: Variant in policy_options.get("cards", []):
		var card: Dictionary = entry
		var button: Button = Button.new()
		button.name = "Card_" + str(card.get("id", ""))
		var prefix: String = "✕ " if bool(card.get("enacted", false)) else "＋ "
		button.text = prefix + str(card.get("name", "")) + "（%s）· %s" % [str(card.get("categoryLabel", "")), str(card.get("effectsText", ""))]
		button.disabled = not bool(card.get("enacted", false)) and not bool(card.get("allowed", false))
		button.tooltip_text = str(card.get("blocker", ""))
		var card_id: String = str(card.get("id", ""))
		var enacted: bool = bool(card.get("enacted", false))
		button.pressed.connect(func() -> void:
			if enacted:
				Session.request_revoke_policy(player_sect_id(), card_id)
			else:
				Session.request_enact_policy(player_sect_id(), card_id))
		policy_list.add_child(button)
	var close: Button = Button.new()
	close.name = "ClosePolicy"
	close.text = "关闭"
	close.pressed.connect(func() -> void: close_policy_panel())
	policy_list.add_child(close)


# --- 自动化 ---

func open_automation_panel() -> void:
	automation_open = true
	_close_r6_panels(automation_panel)
	automation_status_label.text = ""
	Session.request_query_automation_state(player_sect_id())
	_render_automation_panel()


func close_automation_panel() -> void:
	automation_open = false
	_sync_r6_visibility()
	_render_automation_panel()


func _on_automation_state_received(result: Dictionary) -> void:
	automation_state = result
	_render_automation_panel()


func _render_automation_panel() -> void:
	_sync_r6_visibility()
	if automation_info_label == null:
		return
	if not automation_open:
		automation_info_label.text = ""
		_clear_r6_list(automation_list)
		return
	automation_info_label.text = str(automation_state.get("summary", "（等待服务端状态…）"))
	_clear_r6_list(automation_list)
	var toggles: Array = [
		["improve", "自动改良", bool(automation_state.get("autoImprove", false))],
		["repair", "自动修缮", bool(automation_state.get("autoRepair", false))],
		["road", "自动修路", bool(automation_state.get("autoRoad", false))],
		["explore", "自动探索", bool(automation_state.get("autoExplore", false))],
	]
	for entry: Variant in toggles:
		var row: Array = entry
		var key: String = str(row[0])
		var on: bool = bool(row[2])
		var button: Button = Button.new()
		button.name = "Toggle_" + key
		button.text = ("☑ " if on else "☐ ") + str(row[1])
		button.pressed.connect(func() -> void: Session.request_set_automation_toggle(player_sect_id(), key, not on))
		automation_list.add_child(button)
	for entry: Variant in automation_state.get("peaks", []):
		var peak: Dictionary = entry
		var on: bool = bool(peak.get("autoProject", false))
		var button: Button = Button.new()
		button.name = "Peak_" + str(peak.get("peakId", ""))
		button.text = ("☑ " if on else "☐ ") + str(peak.get("name", "")) + " 自动项目"
		var peak_id: String = str(peak.get("peakId", ""))
		button.pressed.connect(func() -> void: Session.request_set_peak_auto_project(peak_id, not on))
		automation_list.add_child(button)
	automation_list.add_child(HSeparator.new())
	var all_on: Button = Button.new()
	all_on.name = "AllAutoProjectOn"
	all_on.text = "全部峰自动项目：开"
	all_on.pressed.connect(func() -> void: Session.request_set_all_auto_project(player_sect_id(), true))
	automation_list.add_child(all_on)
	var all_off: Button = Button.new()
	all_off.name = "AllAutoProjectOff"
	all_off.text = "全部峰自动项目：关"
	all_off.pressed.connect(func() -> void: Session.request_set_all_auto_project(player_sect_id(), false))
	automation_list.add_child(all_off)
	var explore_now: Button = Button.new()
	explore_now.name = "ExploreNow"
	explore_now.text = "立即探索"
	explore_now.pressed.connect(func() -> void: Session.request_explore_now(player_sect_id()))
	automation_list.add_child(explore_now)
	var rally: Button = Button.new()
	rally.name = "Rally"
	rally.text = "一键集结"
	rally.pressed.connect(func() -> void: Session.request_rally(player_sect_id()))
	automation_list.add_child(rally)
	var defend: Button = Button.new()
	defend.name = "ReturnToDefense"
	defend.text = "一键回防"
	defend.pressed.connect(func() -> void: Session.request_return_to_defense(player_sect_id()))
	automation_list.add_child(defend)
	var fast: Button = Button.new()
	fast.name = "FastSettlement"
	fast.text = "快速结算：%s" % ("开" if bool(local_settings.get("fastSettlement", false)) else "关")
	fast.pressed.connect(func() -> void: _toggle_local_setting("fastSettlement"))
	automation_list.add_child(fast)
	var close: Button = Button.new()
	close.name = "CloseAutomation"
	close.text = "关闭"
	close.pressed.connect(func() -> void: close_automation_panel())
	automation_list.add_child(close)


## 本地设置：先本地生效，再让服务端确认（服务端 `applied:false`，不回 view）。
func _toggle_local_setting(key: String) -> void:
	var value: bool = not bool(local_settings.get(key, false))
	local_settings[key] = value
	Session.request_set_setting(key, value)
	_render_automation_panel()


func settings_value(key: String) -> Variant:
	return local_settings.get(key, null)


# --- 回包汇总 ---

## R6 写命令回包：把 message 落到对应面板，并重拉该面板的只读数据。
func _on_r6_result_received(command: String, result: Dictionary) -> void:
	var message: String = str(result.get("message", ""))
	if not bool(result.get("success", true)):
		message = "✗ " + message
	match command:
		Commands.SEND_TO_JI_YUAN, Commands.EXPLORE_MI_JING:
			if explore_status_label != null:
				explore_status_label.text = message
			_refresh_explore_info()
		Commands.SWITCH_GOVERNMENT, Commands.ENACT_POLICY, Commands.REVOKE_POLICY:
			if policy_status_label != null:
				policy_status_label.text = message
			Session.request_query_policy_options(player_sect_id())
		Commands.SET_AUTOMATION_TOGGLE, Commands.SET_PEAK_AUTO_PROJECT, Commands.SET_ALL_AUTO_PROJECT, Commands.EXPLORE_NOW, Commands.RALLY, Commands.RETURN_TO_DEFENSE:
			if automation_status_label != null:
				automation_status_label.text = message
			Session.request_query_automation_state(player_sect_id())
		Commands.SET_SETTING:
			if automation_status_label != null:
				automation_status_label.text = "本地设置已生效：" + str(result.get("key", ""))
		_:
			pass


# --- 供自动验收断言（R6）---

func explore_panel_visible() -> bool:
	return explore_open

func explore_info_text() -> String:
	return explore_info_label.text if explore_info_label != null else ""

func explore_feedback_text() -> String:
	return explore_status_label.text if explore_status_label != null else ""

func explore_button_count() -> int:
	return explore_list.get_child_count() if explore_list != null else 0

func policy_panel_visible() -> bool:
	return policy_open

func policy_info_text() -> String:
	return policy_info_label.text if policy_info_label != null else ""

func policy_feedback_text() -> String:
	return policy_status_label.text if policy_status_label != null else ""

func policy_button_count() -> int:
	return policy_list.get_child_count() if policy_list != null else 0

func automation_panel_visible() -> bool:
	return automation_open

func automation_info_text() -> String:
	return automation_info_label.text if automation_info_label != null else ""

func automation_feedback_text() -> String:
	return automation_status_label.text if automation_status_label != null else ""

func automation_button_count() -> int:
	return automation_list.get_child_count() if automation_list != null else 0

## 按按钮名找到按钮状态（`Toggle_<key>` / `Peak_<peakId>` / `Card_<cardId>` / `Gov_<govId>`）。
func r6_button_state(button_name: String) -> Dictionary:
	for list: VBoxContainer in [explore_list, policy_list, automation_list]:
		if list == null:
			continue
		var button: Button = list.get_node_or_null(NodePath(button_name)) as Button
		if button != null:
			return {"disabled": button.disabled, "text": button.text, "tooltip": button.tooltip_text}
	return {}
