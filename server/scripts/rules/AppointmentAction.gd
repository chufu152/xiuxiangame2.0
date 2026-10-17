class_name AppointmentAction
extends RefCounted
## 任命 / 渡劫命令（R7）：`tribulate` / `appointFengZhu` / `appointZhangLao` / `appointZongZhu`。
##
## 规则本体在 `AppointmentRules`（任命）与 `DiscipleRules.tribulate`（渡劫，R4 已实现，此处只注册）。
##
## **结果形状**（裁决二，已回 1.0 `entity/AppointmentResult.java` 与
## `bridge/CommandDispatcher.toResult()` 逐字段核对）：`{success, message}` 两键，**不增不减**。


## `appointFengZhu`：`{success, message}`。
static func appoint_feng_zhu(state: GameState, config: Dictionary, disciple_id: String, peak_id: String) -> Dictionary:
	return AppointmentRules.appoint_feng_zhu(state, config, disciple_id, peak_id)


## `appointZhangLao`：`{success, message}`。
static func appoint_zhang_lao(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	return AppointmentRules.appoint_zhang_lao(state, config, disciple_id)


## `appointZongZhu`：`{success, message}`。
static func appoint_zong_zhu(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	return AppointmentRules.appoint_zong_zhu(state, config, disciple_id)


## `tribulate`：渡劫飞升。R4 已实现规则函数，本里程碑只把它接到命令层。
##
## 成功时补记 `ascended = true`（1.0 家族流 `ascensionCount` 与分数公式的「飞升数」都读它）。
## 结果 = `DiscipleRules.tribulate` 的 `{success, reason, chance, realm, heartDevil, fallen}`
## 加 `message`（客户端要能直接显示一句人话，与其它写命令一致）。
static func tribulate(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = CityAction.find_disciple(state, disciple_id)
	if disciple == null:
		return {"success": false, "reason": "弟子不存在: " + disciple_id, "chance": 0.0,
			"realm": "", "heartDevil": 0, "fallen": false, "message": "弟子不存在: " + disciple_id}
	var result: Dictionary = DiscipleRules.tribulate(state, config, disciple)
	var success: bool = bool(result["success"])
	if success:
		disciple.ascended = true
		result["message"] = "%s 渡劫成功, 飞升化神" % disciple.name
	else:
		var reason: String = str(result.get("reason", ""))
		if bool(result.get("fallen", false)):
			result["message"] = "%s 渡劫失败, 身死道消" % disciple.name
			BloodlineRules.on_clan_death(state, config, CityAction.find_sect(state, disciple.sectId), disciple)
			# **R10 修复**：`DiscipleRules.tribulate` 只置 `fallen=true`，注释写明「由调用方移除弟子」，
			# 而调用方一直没移——「身死道消」的弟子仍留在名册里，继续被算进 `highRealmMembers`、
			# 战力与家族人口。此处补上唯一出口 `DiscipleRules.remove_disciple`。
			DiscipleRules.remove_disciple(state, disciple)
		else:
			result["message"] = "%s 渡劫失败: %s" % [disciple.name, reason] if not reason.is_empty() \
				else "%s 渡劫失败" % disciple.name
	return result
