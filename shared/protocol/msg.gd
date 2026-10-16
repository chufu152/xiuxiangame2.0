class_name Msg
extends RefCounted
## 协议常量：版本、身份、网络参数、消息类型、信封字段名、错误码。
##
## 唯一权威：docs/REQUIREMENTS_2.0.md §6.1–§6.4。
## WebSocket 文本帧，UTF-8 JSON，一条消息一个 JSON 对象。

# --- 版本与身份 ---
const PROTOCOL_VERSION: String = "2.0"
const SAVE_VERSION: String = "3.0"
const BACKEND: String = "xiuxian-godot-headless"

# --- 网络参数（开发期本地回环）---
const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 9527

# --- 主动消息类型（服务端 -> 客户端）---
const TYPE_HELLO: String = "hello"

# --- 信封字段名 ---
const KEY_ID: String = "id"
const KEY_TYPE: String = "type"
const KEY_PARAMS: String = "params"
const KEY_OK: String = "ok"
const KEY_EVENTS: String = "events"
const KEY_VIEW: String = "view"
const KEY_RESULT: String = "result"
const KEY_ERROR_CODE: String = "errorCode"
const KEY_MESSAGE: String = "message"

# --- hello 字段名（§6.1）---
const KEY_PROTOCOL_VERSION: String = "protocolVersion"
const KEY_BACKEND: String = "backend"
const KEY_SAVE_VERSION: String = "saveVersion"
const KEY_IMPLEMENTED_COMMANDS: String = "implementedCommands"

# --- 错误码（§6.4）---
const ERR_BAD_JSON: String = "BAD_JSON"
const ERR_NO_ID: String = "NO_ID"
const ERR_BAD_REQUEST: String = "BAD_REQUEST"
const ERR_UNKNOWN_COMMAND: String = "UNKNOWN_COMMAND"
const ERR_NOT_IMPLEMENTED: String = "NOT_IMPLEMENTED"
const ERR_BAD_PARAMS: String = "BAD_PARAMS"
const ERR_NO_GAME: String = "NO_GAME"
const ERR_INTERNAL: String = "INTERNAL"
