class_name IronRNG
extends RefCounted
## Deterministic RNG wrapper. Never use global randi()/randf() in the sim —
## always route through an IronRNG instance seeded per-run.

var _rng := RandomNumberGenerator.new()

func _init(seed_value: int) -> void:
	_rng.seed = seed_value

func randf() -> float:
	return _rng.randf()

func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)

func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)

func pick_weighted(table: Dictionary) -> String:
	var total := 0.0
	for k in table.keys():
		total += float(table[k])
	if total <= 0.0:
		return table.keys()[0]
	var roll := _rng.randf() * total
	var acc := 0.0
	var keys := table.keys()
	for i in range(keys.size()):
		acc += float(table[keys[i]])
		if roll <= acc:
			return keys[i]
	return keys[keys.size() - 1]
