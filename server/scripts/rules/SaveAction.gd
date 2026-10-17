class_name SaveAction
extends RefCounted
## 存档命令（R7）：`listSaves` / `saveGame` / `loadGame`。
##
## 规则本体在 `SaveManager`（文件 I/O 与序列化）。
##
## **`saveGame` 用固定形状 `{slot, saved}`（+失败时 `message`），不使用写命令通用的 `success` 布尔**
## ——这是 PROTOCOL §2 明列、1.0 D5 已拍板的存档类特例（硬约束 4）。

## `listSaves`：`{saves:[{slotId, turn, playerSectName, factionType, savedAt, filePath, fileSize}…]}`。
static func list_saves() -> Dictionary:
	var saves: Array = []
	for info: SaveInfo in SaveManager.list_saves():
		saves.append(info.to_dict())
	return {"saves": saves}


## `saveGame`：`{slot, saved}`（失败带 `message`）。
static func save_game(state: GameState, config: Dictionary, slot: int) -> Dictionary:
	return SaveManager.save_game(state, config, slot)


## `loadGame`：`{slot, turn}`（成功）+ `{state}` 供调用方替换对局；
## 槽位不存在时 `state = null` 且带 `message`，由调用方回 `BAD_PARAMS`（PROTOCOL §2）。
static func load_game(config: Dictionary, slot: int) -> Dictionary:
	return SaveManager.load_game(config, slot)
