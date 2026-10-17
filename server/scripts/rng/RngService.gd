class_name RngService
extends RefCounted

var seed_value: int = 0
var sequence: int = 0
var _generator: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed_number: int = 0) -> void:
	reset(seed_number)

func reset(seed_number: int) -> void:
	seed_value = seed_number
	sequence = 0
	_generator.seed = seed_number

func random_seed() -> int:
	_generator.randomize()
	sequence += 1
	return int(_generator.seed)

func next_float() -> float:
	sequence += 1
	return _generator.randf()

func next_int(minimum: int, maximum: int) -> int:
	sequence += 1
	return _generator.randi_range(minimum, maximum)

func chance(probability: float) -> bool:
	return next_float() < probability


## R7 新增：存档快照。`state` 是 `RandomNumberGenerator` 的内部状态（int），
## 比「重放 sequence 次」精确且 O(1)，读档续玩与不中断跑完逐字一致。
func snapshot() -> Dictionary:
	return {"seed": seed_value, "sequence": sequence, "state": int(_generator.state)}


## R7 新增：从快照复原。`state` 缺失时（旧档/手改档）退化为「按 sequence 重放」，
## 保证仍能续玩而不是直接崩。
func restore(data: Dictionary) -> void:
	seed_value = int(data.get("seed", 0))
	sequence = int(data.get("sequence", 0))
	if data.has("state"):
		_generator.seed = seed_value
		_generator.state = int(data["state"])
		return
	_generator.seed = seed_value
	for _index: int in range(sequence):
		_generator.randf()
