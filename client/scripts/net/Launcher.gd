class_name Launcher
extends RefCounted
## 拉起本地 headless 服务端子进程（§2.1）。
##
## 客户端在 9527 连不上时调用：按顺序定位 Godot 控制台版可执行文件，用
## `OS.create_process` 以 `--headless --path <abs>\server` 启动服务端，并记录 PID；
## 客户端退出时由上层调用 `stop(pid)` 回收。
##
## 可执行文件查找顺序（与 docs/prompts/README.md 一致）：
##   1. 环境变量 GODOT_CONSOLE_EXE
##   2. tools/godot_path.txt（本地文件，不入库）
##   3. 固定路径 C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe

const GODOT_PATH_FILE_RELATIVE: String = "tools/godot_path.txt"
const DATA_RELATIVE: String = "data/gameConfig.json"
const SERVER_PROJECT_RELATIVE: String = "server"

## 环境已确认的固定回退路径（Godot 4.4.1 控制台版）。
const FALLBACK_CONSOLE_EXE: String = "C:/Users/Administrator/godot/Godot_v4.4.1-stable_win64_console.exe"


## 仓库根目录（client/ 的上一级）。
static func repo_root() -> String:
	var project_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	return project_dir.get_base_dir()


static func server_project_dir() -> String:
	return repo_root().path_join(SERVER_PROJECT_RELATIVE)


static func default_data_path() -> String:
	return repo_root().path_join(DATA_RELATIVE)


static func godot_path_file() -> String:
	return repo_root().path_join(GODOT_PATH_FILE_RELATIVE)


## 返回 Godot 控制台版可执行文件路径；找不到返回空串。
static func resolve_console_executable() -> String:
	var from_env: String = OS.get_environment("GODOT_CONSOLE_EXE").strip_edges()
	if not from_env.is_empty() and FileAccess.file_exists(from_env):
		return from_env

	var pointer_path: String = godot_path_file()
	if FileAccess.file_exists(pointer_path):
		var pointer: FileAccess = FileAccess.open(pointer_path, FileAccess.READ)
		if pointer != null:
			var pointer_text: String = pointer.get_as_text().strip_edges()
			pointer.close()
			if not pointer_text.is_empty() and FileAccess.file_exists(pointer_text):
				return pointer_text

	if FileAccess.file_exists(FALLBACK_CONSOLE_EXE):
		return FALLBACK_CONSOLE_EXE
	return ""


## 拉起服务端。
## 返回 { "ok": bool, "pid": int, "error": String, "command": String }
static func launch(port: int, data_path: String = "") -> Dictionary:
	var executable: String = resolve_console_executable()
	if executable.is_empty():
		return _fail("找不到 Godot 控制台版可执行文件。请设置环境变量 GODOT_CONSOLE_EXE，或把可执行文件路径写入 %s"
			% godot_path_file())

	var project_dir: String = server_project_dir()
	if not DirAccess.dir_exists_absolute(project_dir):
		return _fail("服务端工程目录不存在：%s" % project_dir)

	var resolved_data: String = data_path
	if resolved_data.is_empty():
		resolved_data = default_data_path()
	if not FileAccess.file_exists(resolved_data):
		return _fail("配置文件不存在：%s" % resolved_data)

	var arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path", project_dir,
		"--",
		"--port=%d" % port,
		"--data=%s" % resolved_data,
	])

	var pid: int = OS.create_process(executable, arguments, false)
	if pid <= 0:
		return _fail("创建服务端子进程失败（OS.create_process 返回 %d）" % pid)

	return {
		"ok": true,
		"pid": pid,
		"error": "",
		"command": "%s %s" % [executable, " ".join(arguments)],
	}


## 回收自己拉起的服务端子进程。
static func stop(pid: int) -> void:
	if pid > 0:
		OS.kill(pid)


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "pid": -1, "error": message, "command": ""}
