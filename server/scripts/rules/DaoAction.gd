class_name DaoAction
extends RefCounted
## 道统与收徒命令（R4）：`researchDao` / `holdRecruitment` / `queryProjectQueue` /
## `cancelProject` / `accelerateProject`。
##
## 全部静态、无状态；数值只取自 `data/gameConfig.json`，规则委托 `DaoRules` / `ProjectRules`。
## 1.0 蓝本：`BuildAction.{researchDao,holdRecruitment,cancelProject,accelerateProject,completeRecruitment}`。
##
## 返回口径（PROTOCOL §4）：
##   - 写命令 → `BuildResult{success, message, projectId, turnsRequired, spiritPowerCost}`；
##   - `queryProjectQueue` → `{peakId, found, peakName, projects[], researchQueue[]}`（`view=null`）。
## **两池不混**（裁决二）：`projects[]` 是灵峰建造队列，`researchQueue[]` 是宗门研究队列。


# ---------------------------------------------------------------------------
# researchDao
# ---------------------------------------------------------------------------

## 推演道法：扣道点（1.0 口径：入队时一次扣清）→ 入宗门研究队列。
static func research_dao(state: GameState, config: Dictionary, sect_id: String, dao_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return CityAction.fail_result("宗门不存在: " + sect_id)
	var check: Dictionary = DaoRules.can_research(state, config, sect, dao_id)
	if not bool(check["allowed"]):
		return CityAction.fail_result(str(check["blocker"]))
	var dao: Dao = DaoRules.find_dao(config, dao_id)
	var point_cost: int = DaoRules.dao_point_cost(config, dao)
	var work_cost: int = DaoRules.work_cost(config, dao)
	var turns: int = DaoRules.research_turns(config, sect, dao)
	sect.resources["daoPoints"] = int(sect.resources.get("daoPoints", 0)) - point_cost
	state.projectSeq += 1
	var project: ResearchProject = ResearchProject.new()
	project.id = "research_%d" % state.projectSeq
	project.daoId = dao_id
	project.name = "推演道法(%s)" % dao.name
	project.turnsRequired = turns
	project.turnsRemaining = turns
	project.daoPointCost = point_cost
	project.spiritPowerCost = work_cost
	sect.researchQueue.append(project)
	state.eventLog.append("[道统] %s 开始推演%s, 需 %d 回合" % [sect.name, dao.name, turns])
	return CityAction.ok_result("已加入宗门研究队列: 推演道法 %s, 消耗道点 %d, 需 %d 回合, 消耗工力 %d" % [dao.name, point_cost, turns, work_cost], project.id, turns, work_cost)


# ---------------------------------------------------------------------------
# holdRecruitment
# ---------------------------------------------------------------------------

## 举办收徒大典：扣工力 → 入灵峰项目队列（`building.recruitmentTurns`）。
## 两次大典间隔不足 `disciple.recruitmentBaseInterval` 回合则拒绝（1.0 同口径）。
static func hold_recruitment(state: GameState, config: Dictionary, peak_id: String) -> Dictionary:
	var peak: SpiritPeak = CityAction.find_peak(state, peak_id)
	if peak == null:
		return CityAction.fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = CityAction.find_sect(state, peak.sectId)
	if sect == null:
		return CityAction.fail_result("灵峰所属宗门不存在")
	var interval: int = int(config["disciple"]["recruitmentBaseInterval"])
	var since: int = state.turn - sect.lastRecruitmentTurn
	if sect.lastRecruitmentTurn > 0 and since < interval:
		return CityAction.fail_result("距上次收徒大典不足 %d 回合(还需 %d 回合)" % [interval, interval - since])
	var building: Dictionary = config["building"]
	var cost: int = int(building["recruitmentCost"])
	var turns: int = int(building["recruitmentTurns"])
	var work_power: int = int(sect.resources.get("workPower", 0))
	if work_power < cost:
		return CityAction.fail_result("工力不足(%d/%d)" % [work_power, cost])
	sect.resources["workPower"] = work_power - cost
	state.projectSeq += 1
	var project: Project = Project.new()
	project.id = "project_%d" % state.projectSeq
	project.type = Project.TYPE_RECRUITMENT
	project.name = "收徒大典"
	project.turnsRequired = maxi(1, turns)
	project.turnsRemaining = maxi(1, turns)
	project.spiritPowerCost = cost
	project.targetId = peak.id
	peak.projectQueue.append(project)
	sect.lastRecruitmentTurn = state.turn
	state.eventLog.append("[收徒] %s 于%s 举办收徒大典, 需 %d 回合" % [sect.name, peak.name, turns])
	return CityAction.ok_result("已加入项目队列: 举办收徒大典, 需 %d 回合, 消耗 %d 工力" % [turns, cost], project.id, turns, cost)


## 收徒落成：新增 `recruitmentBaseCount + recruitmentPerLevel × (峰级 − 1)` 名外门弟子。
## 1.0 为 `baseCount + level × perLevel`；2.0 按 R4 提示词取 `(峰级 − 1)`，差额登记于里程碑汇报。
static func complete_recruitment(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak, _project: Project) -> void:
	var building: Dictionary = config["building"]
	var count: int = int(building["recruitmentBaseCount"]) + int(building["recruitmentPerLevel"]) * maxi(0, peak.level - 1)
	var setup: Dictionary = config["map"]["setup"]
	var roots: Array = setup["rootTypes"]
	for index: int in range(count):
		state.discipleSeq += 1
		var disciple: Disciple = Disciple.new()
		disciple.id = "disciple_%s_%d" % [sect.id, state.discipleSeq]
		disciple.name = "%s外门%d" % [sect.name, sect.disciples.size() + 1]
		disciple.sectId = sect.id
		disciple.tileId = peak.tileId
		disciple.realm = str(setup["outerRealm"])
		disciple.realmLevel = Disciple.level_of(disciple.realm)
		disciple.position = str(setup["outerPosition"])
		disciple.rootGrade = int(setup["rootGrade"])
		disciple.spiritRoots.append(str(roots[state.rng.next_int(0, roots.size() - 1)]))
		disciple.unitClass = str(setup["unitClass"])
		var points: int = MoveRules.calculate_max_move_points(disciple, config, state, sect)
		disciple.maxMovePoints = points
		disciple.movePoints = points
		disciple.attacksRemaining = int(config["warfare"]["attacksPerTurn"])
		disciple.assignedPeakId = peak.id
		disciple.lastReproduceTurn = state.turn
		sect.disciples.append(disciple)
		# 收徒后同步人口与劳力，避免「有人无口」
		peak.population += 1
		peak.housing = CityRules.housing_of(state, config, peak)
		CityRules.sync_free_workers(peak)
	sect.recruitedTotal += count
	state.eventLog.append("[收徒] %s 的%s 收徒 %d 名" % [sect.name, peak.name, count])


# ---------------------------------------------------------------------------
# queryProjectQueue
# ---------------------------------------------------------------------------

## 只读：`{peakId, found, peakName, projects[], researchQueue[]}`（两池分列，不合并）。
static func query_project_queue(state: GameState, config: Dictionary, peak_id: String) -> Dictionary:
	var peak: SpiritPeak = CityAction.find_peak(state, peak_id)
	if peak == null:
		return {"peakId": peak_id, "found": false, "peakName": "", "projects": [], "researchQueue": []}
	var sect: Sect = CityAction.find_sect(state, peak.sectId)
	var projects: Array[Dictionary] = []
	for project: Project in peak.projectQueue:
		projects.append(project.to_dict())
	var research: Array[Dictionary] = []
	if sect != null:
		for project: ResearchProject in sect.researchQueue:
			research.append(project.to_dict())
	return {"peakId": peak.id, "found": true, "peakName": peak.name, "projects": projects, "researchQueue": research}


# ---------------------------------------------------------------------------
# cancelProject
# ---------------------------------------------------------------------------

## 取消项目：按 `building.refundRate` 返还**实际已支付**的代价，并全额返还建造材料。
## 建造项目（R3 口径）在入队时已一次性扣灵力 → 退灵力；研究项目（R4 口径）逐回合扣工力 → 退工力。
static func cancel_project(state: GameState, config: Dictionary, peak_id: String, project_id: String) -> Dictionary:
	var peak: SpiritPeak = CityAction.find_peak(state, peak_id)
	if peak == null:
		return CityAction.fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = CityAction.find_sect(state, peak.sectId)
	if sect == null:
		return CityAction.fail_result("灵峰所属宗门不存在")
	var refund_rate: float = float(config["building"]["refundRate"])
	for index: int in range(peak.projectQueue.size()):
		var project: Project = peak.projectQueue[index]
		if project.id != project_id:
			continue
		peak.projectQueue.remove_at(index)
		var refund: int = int(round(float(project.spiritPowerCost) * refund_rate))
		sect.resources["spiritPower"] = int(sect.resources.get("spiritPower", 0)) + refund
		var material_text: String = _refund_materials(sect, project)
		state.eventLog.append("[项目] %s 取消 %s, 返还灵力 %d" % [sect.name, project.name, refund])
		return CityAction.ok_result("已取消项目 %s, 返还灵力 %d%s" % [project.name, refund, material_text], "", 0, refund)
	for index: int in range(sect.researchQueue.size()):
		var research: ResearchProject = sect.researchQueue[index]
		if research.id != project_id:
			continue
		sect.researchQueue.remove_at(index)
		var paid: int = ProjectRules.paid_work_cost(research)
		var refund: int = int(round(float(paid) * refund_rate))
		sect.resources["workPower"] = int(sect.resources.get("workPower", 0)) + refund
		state.eventLog.append("[道统] %s 取消 %s, 返还工力 %d" % [sect.name, research.name, refund])
		return CityAction.ok_result("已取消研究 %s, 返还工力 %d" % [research.name, refund], "", 0, refund)
	return CityAction.fail_result("项目不存在: " + project_id)


static func _refund_materials(sect: Sect, project: Project) -> String:
	if project.materialCost.is_empty():
		return ""
	var materials: Dictionary = sect.resources.get("materials", {})
	var parts: Array[String] = []
	for material: Variant in project.materialCost.keys():
		var amount: int = int(project.materialCost[material])
		materials[material] = int(materials.get(material, 0)) + amount
		parts.append("%sx%d" % [str(material), amount])
	sect.resources["materials"] = materials
	return ", 返还 " + ", ".join(parts)


# ---------------------------------------------------------------------------
# accelerateProject
# ---------------------------------------------------------------------------

## 花灵石加速：`economy.accelerateStonePerTurn` × 实际加速回合数（`min(turns, turnsRemaining)`）。
## 加速到 0 则**即时完成**（建造项目走 `CityAction` 落成，研究项目走 `ProjectRules.complete_research`）。
static func accelerate_project(state: GameState, config: Dictionary, peak_id: String, project_id: String, turns: int, research: bool) -> Dictionary:
	if turns <= 0:
		return CityAction.fail_result("加速回合数需大于0")
	var peak: SpiritPeak = CityAction.find_peak(state, peak_id)
	if peak == null:
		return CityAction.fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = CityAction.find_sect(state, peak.sectId)
	if sect == null:
		return CityAction.fail_result("灵峰所属宗门不存在")
	if research:
		return _accelerate_research(state, config, sect, project_id, turns)
	return _accelerate_build(state, config, sect, peak, project_id, turns)


static func _accelerate_research(state: GameState, config: Dictionary, sect: Sect, project_id: String, turns: int) -> Dictionary:
	for index: int in range(sect.researchQueue.size()):
		var project: ResearchProject = sect.researchQueue[index]
		if project.id != project_id:
			continue
		var cut: int = mini(turns, project.turnsRemaining)
		var stone_cost: int = int(config["economy"]["accelerateStonePerTurn"]) * cut
		var stones: int = int(sect.resources.get("spiritStones", 0))
		if stones < stone_cost:
			return CityAction.fail_result("灵石不足: 加速 %d 回合需 %d, 当前 %d" % [cut, stone_cost, stones])
		sect.resources["spiritStones"] = stones - stone_cost
		project.turnsRemaining -= cut
		if project.turnsRemaining > 0:
			state.eventLog.append("[道统] %s 加速 %s %d 回合" % [sect.name, project.name, cut])
			return CityAction.ok_result("已花费灵石 %d 将 %s 加速 %d 回合, 剩 %d 回合" % [stone_cost, project.name, cut, project.turnsRemaining], project.id, cut, stone_cost)
		sect.researchQueue.remove_at(index)
		ProjectRules.complete_research(state, config, sect, project)
		state.eventLog.append("[道统] %s 加速完成 %s" % [sect.name, project.name])
		return CityAction.ok_result("已花费灵石 %d 即时完成 %s" % [stone_cost, project.name], project.id, cut, stone_cost)
	return CityAction.fail_result("研究项目不存在: " + project_id)


static func _accelerate_build(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak, project_id: String, turns: int) -> Dictionary:
	for index: int in range(peak.projectQueue.size()):
		var project: Project = peak.projectQueue[index]
		if project.id != project_id:
			continue
		var cut: int = mini(turns, project.turnsRemaining)
		var stone_cost: int = int(config["economy"]["accelerateStonePerTurn"]) * cut
		var stones: int = int(sect.resources.get("spiritStones", 0))
		if stones < stone_cost:
			return CityAction.fail_result("灵石不足: 加速 %d 回合需 %d, 当前 %d" % [cut, stone_cost, stones])
		sect.resources["spiritStones"] = stones - stone_cost
		project.turnsRemaining -= cut
		if project.turnsRemaining > 0:
			state.eventLog.append("[项目] %s 加速 %s %d 回合" % [sect.name, project.name, cut])
			return CityAction.ok_result("已花费灵石 %d 将 %s 加速 %d 回合, 剩 %d 回合" % [stone_cost, project.name, cut, project.turnsRemaining], project.id, cut, stone_cost)
		peak.projectQueue.remove_at(index)
		CityAction.complete_project_now(state, config, sect, peak, project)
		state.eventLog.append("[项目] %s 加速完成 %s" % [sect.name, project.name])
		return CityAction.ok_result("已花费灵石 %d 即时完成 %s" % [stone_cost, project.name], project.id, cut, stone_cost)
	return CityAction.fail_result("项目不存在: " + project_id)
