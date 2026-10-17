class_name PolicyAction
extends RefCounted
## 政令命令（R6）：切换政体 / 颁废政令 / 政令面板数据。
##
## 规则本体在 `PolicyRules`。三条写命令的结果形状 = 1.0 `PolicyAction.PolicyResult`
## `{success, message}`（裁决二核对确认，PROTOCOL §11.2 #1 已回填）。

## `switchGovernment`：`{success, message}`；超槽位的在行政令自动废止。
static func switch_government(state: GameState, config: Dictionary, sect_id: String, government_id: String) -> Dictionary:
	return PolicyRules.switch_government(state, config, sect_id, government_id)


## `enactPolicy`：`{success, message}`（参数名 `cardId`，PROTOCOL §11.1 #5）。
static func enact_policy(state: GameState, config: Dictionary, sect_id: String, card_id: String) -> Dictionary:
	return PolicyRules.enact_policy(state, config, sect_id, card_id)


## `revokePolicy`：`{success, message}`（参数名 `cardId`）。
static func revoke_policy(state: GameState, config: Dictionary, sect_id: String, card_id: String) -> Dictionary:
	return PolicyRules.revoke_policy(state, config, sect_id, card_id)


## `queryPolicyOptions`：只读，PROTOCOL §6 全字段（`view=null`）。
static func query_policy_options(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	return PolicyRules.query_policy_options(state, config, sect_id)
