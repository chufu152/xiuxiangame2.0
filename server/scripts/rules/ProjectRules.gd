class_name ProjectRules
extends RefCounted
## 项目 / 研究队列推进（R4）：`SPIRIT_PEAK` 阶段唯一入口。
##
## 两池**不混**（R4 提示词裁决二）：
##   - 灵峰建造项目 → `SpiritPeak.projectQueue`，推进逻辑仍在 `CityAction.advance_projects`（R3 已验证）；
##   - 宗门道法研究 → `Sect.researchQueue`，由本类 `advance_research` 推进。
##
## 研究按 1.0 `BuildAction.advanceProject` 口径：**工力逐回合分摊扣除**，工力不足则该研究**暂停**
## （不推进、不消耗），恢复后继续。

## 单回合应扣工力（1.0 同式：`ceil(总额 / 总回合数)`，末回合只扣余额）。
static func per_turn_work_cost(project: ResearchProject) -> int:
	return maxi(1, int(ceil(float(project.spiritPowerCost) / float(maxi(1, project.turnsRequired)))))


## 已支付工力（按已推进回合数均摊）。
static func paid_work_cost(project: ResearchProject) -> int:
	var done: int = maxi(0, project.turnsRequired - project.turnsRemaining)
	return mini(project.spiritPowerCost, per_turn_work_cost(project) * done)


## 推进全部宗门的项目与研究队列；返回本阶段新增事件。
static func advance_projects(state: GameState, config: Dictionary) -> Array[String]:
	var before: int = state.eventLog.size()
	for sect: Sect in state.sects:
		for peak: SpiritPeak in sect.spiritPeaks:
			CityAction.advance_projects(state, config, sect, peak)
		advance_research(state, config, sect)
	return state.eventLog.slice(before)


## 推进单个宗门的研究队列：逐项扣工力并 `turnsRemaining -= 1`，归零则结算解锁。
static func advance_research(state: GameState, config: Dictionary, sect: Sect) -> void:
	var index: int = 0
	while index < sect.researchQueue.size():
		var project: ResearchProject = sect.researchQueue[index]
		var cost: int = mini(per_turn_work_cost(project), maxi(0, project.spiritPowerCost - paid_work_cost(project)))
		if int(sect.resources.get("workPower", 0)) < cost:
			# 工力不足 → 该研究暂停（不扣、不推进），队列继续看下一项
			index += 1
			continue
		sect.resources["workPower"] = int(sect.resources.get("workPower", 0)) - cost
		project.turnsRemaining -= 1
		if project.turnsRemaining > 0:
			index += 1
			continue
		sect.researchQueue.remove_at(index)
		complete_research(state, config, sect, project)


## 研究完成：解锁道法并记录事件（1.0 `completeResearchProject` 同口径）。
static func complete_research(state: GameState, config: Dictionary, sect: Sect, project: ResearchProject) -> void:
	var dao: Dao = DaoRules.find_dao(config, project.daoId)
	if dao == null:
		state.eventLog.append("[道统] %s 研究完成: 未知道法 %s" % [sect.name, project.daoId])
		return
	if not sect.unlockedDaoIds.has(project.daoId):
		sect.unlockedDaoIds.append(project.daoId)
	var effect_text: String = _effect_text(dao)
	state.eventLog.append("[道统] %s 推演完成: %s%s" % [sect.name, dao.name, effect_text])


## 效果文案（事件日志用；`UNLOCK_*` 显示 key，加成类显示百分比/点数）。
static func _effect_text(dao: Dao) -> String:
	if dao.effects.is_empty():
		return ""
	var parts: Array[String] = []
	for effect: Variant in dao.effects:
		var entry: Dictionary = effect
		var type: String = str(entry.get("type", ""))
		if entry.has("key"):
			parts.append("%s(%s)" % [type, str(entry["key"])])
		elif entry.has("amount"):
			var amount: float = float(entry["amount"])
			if amount > 0.0 and amount < 1.0:
				parts.append("%s+%d%%" % [type, int(round(amount * 100.0))])
			else:
				parts.append("%s+%d" % [type, int(round(amount))])
	return " (效果: " + "、".join(parts) + ")"
