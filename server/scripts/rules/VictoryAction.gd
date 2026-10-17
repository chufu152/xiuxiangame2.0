class_name VictoryAction
extends RefCounted
## 胜负命令（R7）：`queryVictoryProgress` / `checkVictory` / `checkDefeat` / `chooseVictory` /
## `queryGameOver` / `queryVictoryChoice` / `resolveChoice`。
##
## 规则本体在 `VictoryRules`（本类只做参数整形与形状组装）。
##
## **`awaitInput` 只保留 `victoryChoice`**（裁决七 / PRD §5.2 #7）：
## 同时达成多条路线时由 `settle_victory` 写入 `state.pendingVictoryChoices`，
## 由 `await_input_payload` 组装成主动消息；`resolveChoice` 只认 `req_victory_*` 前缀。

## 待决请求 id 前缀（裁决七）。
const REQ_PREFIX: String = "req_victory_"
const KIND: String = "victoryChoice"


# ---------------------------------------------------------------------------
# 只读
# ---------------------------------------------------------------------------

## `queryVictoryProgress`：`{sectId, routes:[{route, achieved, ratio, summary, stage, score, goals}…]}`。
## 会顺带刷新 `sect.powerLevel` 派生缓存（1.0 既有行为，PROTOCOL §2 已注明）。
static func query_victory_progress(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return {"sectId": sect_id, "routes": []}
	return VictoryRules.victory_progress(state, config, sect)


## `checkVictory`：`{sectId, route}`；未达成时 `route` 为 `null`。
static func check_victory(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return {"sectId": sect_id, "route": null}
	VictoryRules.refresh_power_level(state, config, sect)
	var route: String = VictoryRules.check_victory(state, config, sect)
	return {"sectId": sect_id, "route": null if route.is_empty() else route}


## `checkDefeat`：`{sectId, defeated}`。**只判定不清算**（清理由 `VICTORY_CHECK` 阶段做）。
static func check_defeat(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return {"sectId": sect_id, "defeated": false}
	return {"sectId": sect_id, "defeated": VictoryRules.check_defeat(state, config, sect)}


## `queryGameOver`：`{turn, gameOver, winType, winnerSectId, pendingVictoryChoices[]}`。
static func query_game_over(state: GameState) -> Dictionary:
	return {
		"turn": state.turn,
		"gameOver": state.gameOver,
		"winType": state.winType,
		"winnerSectId": state.winnerSectId,
		"pendingVictoryChoices": state.pendingVictoryChoices.duplicate(),
	}


## `queryVictoryChoice`：`{pending, gameOver, winnerSectId, winType, options[]}`。
static func query_victory_choice(state: GameState) -> Dictionary:
	return {
		"pending": not state.pendingVictoryChoices.is_empty(),
		"gameOver": state.gameOver,
		"winnerSectId": state.winnerSectId,
		"winType": state.winType,
		"options": _options(state),
	}


# ---------------------------------------------------------------------------
# 写
# ---------------------------------------------------------------------------

## `chooseVictory`：`{success, routeId, winType, message}`。
## 只认 `pendingVictoryChoices` 里的路线（1.0 `chooseVictory` 同口径）。
static func choose_victory(state: GameState, route_id: String) -> Dictionary:
	if state.pendingVictoryChoices.is_empty():
		return {"success": false, "routeId": route_id, "winType": "",
			"message": "当前没有待择的胜利路线"}
	if not state.pendingVictoryChoices.has(route_id):
		return {"success": false, "routeId": route_id, "winType": "",
			"message": "「%s」不在待择路线中" % route_id}
	var win_type: String = VictoryRules.choose_victory(state, route_id)
	if win_type.is_empty():
		return {"success": false, "routeId": route_id, "winType": "", "message": "择定结局失败"}
	return {"success": true, "routeId": route_id, "winType": win_type,
		"message": "已择定结局: " + win_type}


## `resolveChoice` 的**参数校验**（越界 / `reqId` 认不出时由调用方回 `BAD_PARAMS`，
## **且待决状态原样保留**——本函数只读，不改任何字段）。
static func resolve_choice_blocker(state: GameState, req_id: String, option_index: int) -> String:
	if not req_id.begins_with(REQ_PREFIX):
		return "reqId 不是 victoryChoice 请求: " + req_id
	if state.pendingVictoryChoices.is_empty():
		return "当前没有待决的胜利路线"
	if option_index < 0 or option_index >= state.pendingVictoryChoices.size():
		return "optionIndex 越界: %d (共 %d 项)" % [option_index, state.pendingVictoryChoices.size()]
	return ""


## `resolveChoice`：`{success, routeId, winType, message}`。
## 参数已在调用前由 `resolve_choice_blocker` 校验，故此处只在业务层失败。
static func resolve_choice(state: GameState, req_id: String, option_index: int) -> Dictionary:
	var blocker: String = resolve_choice_blocker(state, req_id, option_index)
	if not blocker.is_empty():
		return {"success": false, "routeId": "", "winType": "", "message": blocker}
	var route_id: String = state.pendingVictoryChoices[option_index]
	return choose_victory(state, route_id)


# ---------------------------------------------------------------------------
# 主动消息
# ---------------------------------------------------------------------------

## 组装 `awaitInput` 主动消息体；没有待决时返回 `null`（调用方据此决定要不要推）。
## 形状严格照 PROTOCOL §0.7：`{type,reqId,kind,prompt,options[{index,label,routeId,description}]}`。
static func await_input_payload(state: GameState) -> Variant:
	if state.pendingVictoryChoices.is_empty():
		return null
	return {
		"type": "awaitInput",
		"reqId": request_id(state),
		"kind": KIND,
		"prompt": "同时达成 %d 条胜利路线, 请择一而终" % state.pendingVictoryChoices.size(),
		"options": _options(state),
	}


## 待决请求 id：`req_victory_<回合>`。同回合内稳定，`loadGame` 回到待决点时按存档回合重建，
## 故读档后重新推送的 `reqId` 与存档前一致（客户端不必记 id 也能对得上）。
static func request_id(state: GameState) -> String:
	return "%s%d" % [REQ_PREFIX, state.turn]


static func _options(state: GameState) -> Array:
	var options: Array = []
	for index: int in range(state.pendingVictoryChoices.size()):
		var route_id: String = state.pendingVictoryChoices[index]
		options.append({
			"index": index,
			"label": str(VictoryRules.ROUTE_NAMES.get(route_id, route_id)),
			"routeId": route_id,
			"description": str(VictoryRules.ROUTE_DESCRIPTIONS.get(route_id, "")),
		})
	return options
