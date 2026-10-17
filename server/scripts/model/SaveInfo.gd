class_name SaveInfo
extends RefCounted
## 存档槽元信息（`listSaves` 的 `saves[]` 元素）。
##
## 字段与 1.0 `save/SaveInfo.java` **逐字一致**（7 项），也与 PROTOCOL_2.0 §2 `listSaves` 的
## `{slotId, turn, playerSectName, factionType, savedAt, filePath, fileSize}` 完全对齐：
## 不增不减。本类只做「读存档文件头部」的载体，不参与对局逻辑。

var slotId: int = 0
var turn: int = 0
var playerSectName: String = ""
var factionType: String = ""
## ISO 8601 本地时间串（`Time.get_datetime_string_from_system()`），1.0 用 `ISO_LOCAL_DATE_TIME`。
var savedAt: String = ""
var filePath: String = ""
var fileSize: int = 0


func to_dict() -> Dictionary:
	return {
		"slotId": slotId,
		"turn": turn,
		"playerSectName": playerSectName,
		"factionType": factionType,
		"savedAt": savedAt,
		"filePath": filePath,
		"fileSize": fileSize,
	}
