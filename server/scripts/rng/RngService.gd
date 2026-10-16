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
