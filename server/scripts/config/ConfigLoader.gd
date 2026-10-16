class_name ConfigLoader
extends RefCounted
## 读取 data/gameConfig.json（§2.2 / §2.4）。
##
## 只负责「定位 + 读文件 + 解析 JSON + 返回结构化结果」，不做取值合法性判断（那是 ConfigValidator）。
## 失败一律返回 ok=false 并给出可诊断原因，由调用方以非零退出码结束——**不允许静默降级**。

const DATA_RELATIVE_PATH: String = "data/gameConfig.json"


## 默认配置路径：工程目录的上一级（仓库根）下的 data/gameConfig.json。
## 可用启动参数 `--data=<绝对路径>` 覆盖。
static func default_path() -> String:
	var project_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repo_root: String = project_dir.get_base_dir()
	return repo_root.path_join(DATA_RELATIVE_PATH)


## 返回 { "ok": bool, "config": Dictionary, "error": String }
static func load_from_file(path: String) -> Dictionary:
	if path.is_empty():
		return _failure("未指定配置文件路径")
	if not FileAccess.file_exists(path):
		return _failure("配置文件不存在：%s" % path)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("配置文件无法打开（错误码 %d）：%s" % [FileAccess.get_open_error(), path])

	var text: String = file.get_as_text()
	file.close()

	if text.strip_edges().is_empty():
		return _failure("配置文件为空：%s" % path)

	var parser: JSON = JSON.new()
	var error: Error = parser.parse(text)
	if error != OK:
		return _failure("JSON 解析失败（第 %d 行）：%s" % [parser.get_error_line(), parser.get_error_message()])

	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY:
		return _failure("配置根节点必须是 JSON 对象，实际为 %s" % type_string(typeof(data)))

	return {"ok": true, "config": data, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "config": {}, "error": message}
