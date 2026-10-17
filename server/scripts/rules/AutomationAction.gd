class_name AutomationAction
extends RefCounted
## 自动化 / 设置命令（R6）：开关、自动项目、立即探索、集结/回防、设置确认。
##
## 规则本体在 `AutomationRules`；`setSetting` 是**纯确认命令**：不改 `GameState`、不回 view
## （PROTOCOL §7 明列，`applied:false` 表示「值留在客户端」）。

## `setAutomationToggle`：`{success, message}`；`key` 非法由 dispatcher 回 `BAD_PARAMS`。
static func set_automation_toggle(state: GameState, config: Dictionary, sect_id: String, key: String, on: bool) -> Dictionary:
	return AutomationRules.set_toggle(state, config, sect_id, key, on)


## `setPeakAutoProject`：`{success, message}`（按 `peakId` 定位，不要求 `sectId`）。
static func set_peak_auto_project(state: GameState, config: Dictionary, peak_id: String, on: bool) -> Dictionary:
	return AutomationRules.set_peak_auto_project(state, config, peak_id, on)


## `setAllAutoProject`：`{success, message}`。
static func set_all_auto_project(state: GameState, config: Dictionary, sect_id: String, on: bool) -> Dictionary:
	return AutomationRules.set_all_auto_project(state, config, sect_id, on)


## `exploreNow`：`{success, message}`（文案型，逐人战报在 message）。
static func explore_now(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	return AutomationRules.explore_now(state, config, sect_id)


## `rally`：`{success, message}`（文案型，裁决七）；超 `rallyMaxDisciples` 回 `success:false`。
static func rally(state: GameState, config: Dictionary, sect_id: String, tile_id: String) -> Dictionary:
	return AutomationRules.rally(state, config, sect_id, tile_id)


## `returnToDefense`：`{success, message}`（文案型，裁决七）。
static func return_to_defense(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	return AutomationRules.return_to_defense(state, config, sect_id)


## `queryAutomationState`：只读，PROTOCOL §7 全字段（`view=null`）。
static func query_automation_state(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	return AutomationRules.describe(state, config, sect_id)


## `setSetting`：`{success:true, key, value, applied:false, note}`。
## **服务端只确认**：`GameState` 不变、`eventLog` 不写、view 不回（PROTOCOL §7）。
static func set_setting(key: String, value: Variant) -> Dictionary:
	return {
		"success": true,
		"key": key,
		"value": value,
		"applied": false,
		"note": "客户端本地偏好，服务端仅确认，值留在前端",
	}
