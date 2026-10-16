class_name Commands
extends RefCounted
## 命令名常量（lowerCamelCase，与 1.0 同名）。
##
## 唯一权威：docs/REQUIREMENTS_2.0.md §6.7「2.0 命令清单（69 条 + ping）」。
## 规则层 / 网络层 / 客户端一律引用本文件常量，**禁止散落命令名字符串字面量**。
##
## R0 只登记 ping；后续里程碑在此追加（每追加一条，同步更新 hello.implementedCommands）。

const PING: String = "ping"
const NEW_GAME: String = "newGame"
const GET_STATE: String = "getState"

# --- R2：回合状态机 + 六边形移动 ---
const FINISH_TURN: String = "finishTurn"
const BEGIN_PLAYER_TURN: String = "beginPlayerTurn"
const NEXT_TURN: String = "nextTurn"
const MOVE_DISCIPLE: String = "moveDisciple"
const QUERY_MOVE_RANGE: String = "queryMoveRange"
