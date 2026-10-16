class_name ConfigValidator
extends RefCounted
## data/gameConfig.json 取值校验（§2.4 / §8.3 / §9 DoD）。
##
## 原则：**缺字段 / 类型错 / 引用已裁剪模块，一律报错而非静默**。
## 返回错误字符串数组，空数组表示通过。
##
## R0 只校验骨架字段与「已裁剪模块不得出现」；R1 迁移全量配置后在此补充
## 必需块 / 枚举合法性 / 数值范围 / 2.0 新增地形块（map.baseTerrains、map.relief、
## map.features、map.river、map.nodeSpawnByTerrain）的完整校验。

## 2.0 首版已裁剪、不得出现在配置中的模块（§5.1 / §5.2 / data/README.md）。
const FORBIDDEN_BLOCKS: Array = [
	"diplomacy", "threat", "event", "disaster", "loyalty", "strategy",
]


## 校验配置；返回错误列表（空表示通过）。
static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []

	for block: String in FORBIDDEN_BLOCKS:
		if config.has(block):
			errors.append("配置块 `%s` 属于 2.0 已裁剪模块，必须删除或禁用（§5.1）" % block)

	if not config.has("schemaVersion"):
		errors.append("缺少 `schemaVersion`")
	else:
		var schema: Variant = config["schemaVersion"]
		if typeof(schema) != TYPE_STRING:
			errors.append("`schemaVersion` 必须是字符串")
		elif String(schema).strip_edges().is_empty():
			errors.append("`schemaVersion` 不能为空")

	if config.has("saveVersion"):
		var save_version: String = str(config["saveVersion"])
		if save_version != Msg.SAVE_VERSION:
			errors.append("`saveVersion` 为 %s，与代码常量 %s 不一致"
				% [save_version, Msg.SAVE_VERSION])

	return errors
