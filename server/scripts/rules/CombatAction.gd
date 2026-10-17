class_name CombatAction
extends RefCounted
## 战斗行动入口（R5）：`attack` / `queryAttackPreview` / `queryAttackable` / `retreat` / `batchMove`。
##
## 战术计算全在 `CombatResolver`（唯一结算入口）与 `UnitRules`（唯一战术查询入口），
## 本文件只做「把玩家意图翻译成结算调用」+ 参数/身份校验，不自己算任何战力或胜率。
##
## **业务失败 ≠ 协议失败**：不在射程、已出手、移动力不足、目标无可打对象等一律
## `success:false + message`；只有参数缺失/类型错/枚举非法才由 `CommandDispatcher` 回 `BAD_PARAMS`。


## `attack`：出手。近战贴身与射程内远程走同一入口，由目标性质决定夺峰/夺点/野战。
static func attack(state: GameState, config: Dictionary, disciple_id: String, target_tile_id: String) -> Dictionary:
	return CombatResolver.resolve_attack(state, config, disciple_id, target_tile_id)


## `queryAttackPreview`：只读，返回 `BattlePreview` 全字段 + `targetTileId`。
static func query_attack_preview(state: GameState, config: Dictionary, disciple_id: String, target_tile_id: String) -> Dictionary:
	return CombatResolver.preview(state, config, disciple_id, target_tile_id)


## `queryAttackable`：只读，返回 `{discipleId, range, tileIds[], tileCount}`。
static func query_attackable(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	return CombatResolver.attackable(state, config, disciple_id)


## `retreat`：主动撤退（结果形状同 `CombatResult`）。
static func retreat(state: GameState, config: Dictionary, disciple_id: String, to_tile_id: String) -> Dictionary:
	return CombatResolver.retreat(state, config, disciple_id, to_tile_id)


## `batchMove`：批量移动本宗多支部队到同一目标地块。
## 上限 `speed.batchMoveMaxTargets`（8）；逐人战报汇总进 `message`。
## 单人失败不影响其他人（各自独立走 `MoveAction.move_disciple`，与 `moveDisciple` 同源）。
static func batch_move(state: GameState, config: Dictionary, sect_id: String, disciple_ids: Array, target_tile_id: String) -> Dictionary:
	var limit: int = int(config["speed"]["batchMoveMaxTargets"])
	var out: Dictionary = {
		"success": false,
		"message": "",
		"sectId": sect_id,
		"targetTileId": target_tile_id,
		"discipleCount": 0,
	}
	if disciple_ids.size() > limit:
		out["message"] = "批量移动一次最多 %d 人（本次请求 %d 人）" % [limit, disciple_ids.size()]
		return out
	if disciple_ids.is_empty():
		out["message"] = "未指定弟子"
		return out
	var reports: Array[String] = []
	var moved: int = 0
	for entry: Variant in disciple_ids:
		var disciple_id: String = str(entry)
		var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
		if disciple == null:
			reports.append("%s: 弟子不存在" % disciple_id)
			continue
		if disciple.sectId != sect_id:
			reports.append("%s: 非本宗弟子" % disciple.name)
			continue
		if disciple.tileId == target_tile_id:
			reports.append("%s: 已在该地块" % disciple.name)
			continue
		var result: Dictionary = MoveAction.move_disciple(state, config, disciple_id, target_tile_id)
		if bool(result["success"]):
			moved += 1
			reports.append("%s: 移动成功" % disciple.name)
		else:
			reports.append("%s: %s" % [disciple.name, str(result["message"])])
	out["success"] = moved > 0
	out["discipleCount"] = moved
	out["message"] = "%d/%d 人抵达 %s；%s" % [moved, disciple_ids.size(), target_tile_id, "；".join(reports)]
	return out
