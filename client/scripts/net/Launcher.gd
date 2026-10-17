class_name Launcher
extends RefCounted
## 拉起本地 headless 服务端子进程（§2.1）。
##
## 客户端在 9527 连不上时调用：按顺序定位 Godot 控制台版可执行文件，用
## `OS.create_process` 以 `--headless --path <abs>\server` 启动服务端，并记录 PID；
## 客户端退出时由上层调用 `stop(pid)` 回收。
##
## **两种运行态**（R9 W3 起）：
##   - **开发态**（编辑器/`--path client` 直接跑）：拉 Godot 控制台版 + `--path <repo>/server`；
##   - **导出态**（`OS.has_feature("template")`）：拉**同目录**的 `XiuxianServer.exe`（服务端工程
##     另有一份 Windows 导出预设），运行时根目录即可执行文件所在目录。
##
## 可执行文件查找顺序（开发态，与 docs/prompts/README.md 一致）：
##   1. 环境变量 GODOT_CONSOLE_EXE
##   2. tools/godot_path.txt（本地文件，不入库）
##   3. 固定路径 C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe

const GODOT_PATH_FILE_RELATIVE: String = "tools/godot_path.txt"
const DATA_RELATIVE: String = "data/gameConfig.json"
const SERVER_PROJECT_RELATIVE: String = "server"

## 导出态下服务端可执行文件名（与 `server/export_presets.cfg` 的 export_path 保持一致）。
const SERVER_EXE_NAME: String = "XiuxianServer.exe"

## 环境已确认的固定回退路径（Godot 4.4.1 控制台版）。
const FALLBACK_CONSOLE_EXE: String = "C:/Users/Administrator/godot/Godot_v4.4.1-stable_win64_console.exe"


## 仅供测试注入：-1 = 按引擎实际特性判断；0 = 强制开发态；1 = 强制导出态。
## 导出态分支在编辑器里跑不到，用它可以对路径解析做真实断言（见 tests/R9ClientTest.gd）。
static var _exported_override: int = -1


## 是否运行在导出产物里（PCK 打包后）。
static func is_exported() -> bool:
	if _exported_override >= 0:
		return _exported_override == 1
	return OS.has_feature("template")


## 运行时根目录：**导出态 = 可执行文件所在目录**，开发态 = `client/` 的上一级（仓库根）。
##
## 这是 `assets/` 与 `data/` 的定位基准，也是 `AssetLibrary.asset_root` 的来源。
## 注意不能一律用 `ProjectSettings.globalize_path("res://").get_base_dir()`：导出后
## `res://` 指向**可执行文件所在目录**，再取一次 `get_base_dir()` 就跑到上一级去了。
static func repo_root() -> String:
	if is_exported():
		return OS.get_executable_path().get_base_dir()
	var project_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	return project_dir.get_base_dir()


## 服务端工程目录（仅开发态有意义）；导出态返回服务端可执行文件路径，便于日志与报错。
static func server_project_dir() -> String:
	if is_exported():
		return server_executable()
	return repo_root().path_join(SERVER_PROJECT_RELATIVE)


## 导出态的服务端可执行文件路径（同目录）。
static func server_executable() -> String:
	return repo_root().path_join(SERVER_EXE_NAME)


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
	var resolved_data: String = data_path
	if resolved_data.is_empty():
		resolved_data = default_data_path()
	if not FileAccess.file_exists(resolved_data):
		return _fail("配置文件不存在：%s" % resolved_data)

	if is_exported():
		return _launch_exported(port, resolved_data)

	var executable: String = resolve_console_executable()
	if executable.is_empty():
		return _fail("找不到 Godot 控制台版可执行文件。请设置环境变量 GODOT_CONSOLE_EXE，或把可执行文件路径写入 %s"
			% godot_path_file())

	var project_dir: String = server_project_dir()
	if not DirAccess.dir_exists_absolute(project_dir):
		return _fail("服务端工程目录不存在：%s" % project_dir)

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


## 导出态：拉同目录的服务端可执行文件。它自带 PCK，不需要 `--path`。
static func _launch_exported(port: int, resolved_data: String) -> Dictionary:
	var executable: String = server_executable()
	if not FileAccess.file_exists(executable):
		return _fail("找不到服务端可执行文件：%s（导出产物需把 XiuxianServer.exe 放在同一目录）"
			% executable)

	var arguments: PackedStringArray = PackedStringArray([
		"--headless",
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
