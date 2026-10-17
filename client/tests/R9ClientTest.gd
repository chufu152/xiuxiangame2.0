extends Node
## R9 客户端验收（W3 导出态路径解析）：开发态 / 导出态两套根目录口径。
##
## 无头运行：`godot --headless --path client res://tests/R9ClientTest.tscn`。
##
## 为什么单独立一个测试：`Launcher` 的导出态分支（`OS.has_feature("template")`）在编辑器里
## **跑不到**，而它恰恰是最容易写错的一段——导出后 `res://` 已经指向可执行文件所在目录，
## 再套一次 `get_base_dir()` 就会跑到上一级，导致 `assets/`、`data/` 全部定位失败。
## 故这里用 `Launcher._exported_override` 强制切态，对**路径解析**做真实断言。
##
## 不覆盖的（需真导出产物，由 `tools/check.ps1` 的 `[22/25]` 导出冒烟负责）：
## 导出产物能否启动、导出态服务端能否被拉起并监听端口。

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	await get_tree().process_frame

	var engine_exe_dir: String = OS.get_executable_path().get_base_dir()
	var res_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var editor_repo_root: String = res_dir.get_base_dir()

	# ① 编辑器里必须判为开发态
	Launcher._exported_override = -1
	check(not Launcher.is_exported(), "编辑器内 is_exported() = false")
	check(Launcher.repo_root() == editor_repo_root,
		"开发态 repo_root() = client/ 的上一级（实际 %s）" % Launcher.repo_root())
	check(Launcher.server_project_dir() == editor_repo_root.path_join("server"),
		"开发态 server_project_dir() 指向仓库 server/（实际 %s）" % Launcher.server_project_dir())
	check(Launcher.default_data_path() == editor_repo_root.path_join("data/gameConfig.json"),
		"开发态 default_data_path() 指向仓库 data/gameConfig.json")
	check(FileAccess.file_exists(Launcher.default_data_path()),
		"开发态 default_data_path() 真实存在（%s）" % Launcher.default_data_path())

	# ② 强制导出态：根目录 = 可执行文件所在目录
	Launcher._exported_override = 1
	var exported_root: String = Launcher.repo_root()
	check(Launcher.is_exported(), "强制导出态 is_exported() = true")
	check(exported_root == engine_exe_dir,
		"导出态 repo_root() = 可执行文件所在目录（期望 %s，实际 %s）" % [engine_exe_dir, exported_root])
	# 这条是**回归钉子**：老写法 `globalize_path("res://").get_base_dir()` 在导出态会跑到上一级。
	check(exported_root != res_dir.get_base_dir(),
		"导出态 repo_root() 不是 res:// 的上一级（老写法会错到 %s）" % res_dir.get_base_dir())
	check(Launcher.server_executable() == exported_root.path_join(Launcher.SERVER_EXE_NAME),
		"导出态 server_executable() = <产物目录>/%s" % Launcher.SERVER_EXE_NAME)
	check(Launcher.server_executable().get_file() == "XiuxianServer.exe",
		"导出态服务端可执行文件名与导出预设一致（XiuxianServer.exe）")
	check(Launcher.server_project_dir() == Launcher.server_executable(),
		"导出态 server_project_dir() 退化为服务端可执行文件路径（无工程目录概念）")
	check(Launcher.default_data_path() == exported_root.path_join("data/gameConfig.json"),
		"导出态 default_data_path() = <产物目录>/data/gameConfig.json")
	check(Launcher.default_data_path().begins_with(exported_root),
		"导出态 assets/ 与 data/ 同根（asset_root 走同一个 repo_root()）")

	# ③ 导出态缺服务端可执行文件时必须给出可诊断错误，而不是静默失败
	var real_data: String = editor_repo_root.path_join("data/gameConfig.json")
	var outcome: Dictionary = Launcher.launch(19999, real_data)
	check(not bool(outcome["ok"]), "导出态缺服务端 exe 时 launch() 返回 ok=false")
	check(str(outcome["error"]).contains("XiuxianServer.exe"),
		"错误信息点名缺失的可执行文件（实际：%s）" % str(outcome["error"]))
	check(int(outcome["pid"]) <= 0, "失败时 pid ≤ 0（不会被误当成已拉起）")

	# ④ 复位，避免污染后续测试
	Launcher._exported_override = -1
	check(not Launcher.is_exported(), "复位后回到开发态")

	print("R9_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("R9_CLIENT_PASS: %s" % description)
	else:
		failures += 1
		printerr("R9_CLIENT_FAIL: %s" % description)
