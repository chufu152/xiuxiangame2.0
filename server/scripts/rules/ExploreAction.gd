class_name ExploreAction
extends RefCounted
## 探索命令（R6）：机缘 / 秘境的查询与派遣。
##
## 规则本体在 `ExploreRules`（本文件只是命令层门面，保持与 R2–R5 的 `*Action` 分层一致）。
## 只读命令（`queryJiYuanInfo` / `queryMiJingInfo`）由 dispatcher 以 `view=null` 回包；
## 写命令（`sendToJiYuan` / `exploreMiJing`）回实时 view + 本命令期间新增日志。

## `queryJiYuanInfo`：`{nodeId, kind:"jiYuan", found, info:NodeInfo}`。
static func query_ji_yuan_info(state: GameState, config: Dictionary, node_id: String) -> Dictionary:
	return ExploreRules.query_ji_yuan_info(state, config, node_id)


## `sendToJiYuan`：返回 `ExploreResult`（`{success, message, rewards[], casualties[], injured[], cooldown}`）。
static func send_to_ji_yuan(state: GameState, config: Dictionary, disciple_id: String, node_id: String) -> Dictionary:
	return ExploreRules.send_to_ji_yuan(state, config, disciple_id, node_id)


## `queryMiJingInfo`：`{nodeId, kind:"miJing", found, info:NodeInfo}`。
static func query_mi_jing_info(state: GameState, config: Dictionary, node_id: String) -> Dictionary:
	return ExploreRules.query_mi_jing_info(state, config, node_id)


## `exploreMiJing`：返回 `ExploreResult`。
static func explore_mi_jing(state: GameState, config: Dictionary, disciple_ids: Array, node_id: String) -> Dictionary:
	return ExploreRules.explore_mi_jing(state, config, disciple_ids, node_id)
