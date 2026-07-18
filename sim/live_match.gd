class_name LiveMatch
extends RefCounted
## Interactive, externally-tickable wrapper around the same static sim
## functions MatchSim.run() uses for headless batch verification. This
## class is presentation-facing: a Node drives step() once per game tick
## and reads state back out; MatchSim.run() itself is untouched so the
## harness/oracle pipeline never regresses.

signal phase_changed(new_phase: String)
signal result_ready(match_result: String)

var level: Dictionary
var catalog: Catalog
var economy: Dictionary
var rng: IronRNG
var player: Dictionary
var enemy: Dictionary
var weather_id: String
var phase: String = MatchSim.PHASE_PUSH
var boss: Dictionary = {}
var missile_state: Dictionary = {"launched": 0, "timer": 0.0}
var tick: int = 0
var turn_budget: int
var boss_trigger_hp: float
var result: String = ""
var boss_killed: bool = false
var enemy_strategy_id: String = "level_ai"
var _flagship_aim_bonus: float = 0.0
var _enemy_income: float = 0.0

func _init(p_level: Dictionary, p_catalog: Catalog, seed_value: int, unlocked_skills: Array = []) -> void:
	level = p_level
	catalog = p_catalog
	economy = catalog.economy
	rng = IronRNG.new(seed_value)
	player = MatchSim._new_side(level["player_roster"], float(level["player_base_hp"]), float(economy["starting_gold"]))
	player["unlocked_skills"] = unlocked_skills.duplicate()
	enemy = MatchSim._new_side(level["enemy_roster"], float(level["enemy_base_hp"]), 0.0)
	enemy["base_hp_max"] = float(level["enemy_base_hp"])
	# Mirror MatchSim.run(): seeded enemy readiness jitter.
	enemy["gold"] = float(level.get("enemy_starting_gold", 0.0)) * rng.randf_range(0.5, 1.5)
	_enemy_income = float(level["enemy_income_base"]) * rng.randf_range(0.85, 1.15)
	weather_id = rng.pick_weighted(level["weather_table"])
	turn_budget = int(level["turn_budget"])
	boss_trigger_hp = float(level["enemy_base_hp"]) * float(level["boss_trigger_hp_pct"])

func is_over() -> bool:
	return result != ""

func step() -> void:
	if is_over():
		return
	if tick >= turn_budget:
		result = "LOSS"
		result_ready.emit(result)
		return

	player["gold"] += MatchSim._effective_income(player, float(economy["income_base"]), economy)
	enemy["gold"] += MatchSim._effective_income(enemy, _enemy_income, economy)

	MatchSim._check_era_upgrade(player, catalog)
	MatchSim._check_era_upgrade(enemy, catalog)

	MatchSim._process_spawn_queue(player, catalog, tick)
	MatchSim._process_spawn_queue(enemy, catalog, tick)

	if tick % int(economy["decision_interval_ticks"]) == 0:
		Strategies.decide(enemy_strategy_id, enemy, catalog, level, economy, tick)

	match phase:
		MatchSim.PHASE_PUSH:
			MatchSim._resolve_combat_tick(player, enemy, catalog, weather_id, catalog.weather, economy, MatchSim.DT, rng)
			if enemy["base_hp"] <= boss_trigger_hp:
				phase = MatchSim.PHASE_MISSILE
				missile_state = {"launched": 0, "timer": 0.0}
				phase_changed.emit(phase)
		MatchSim.PHASE_MISSILE:
			var wave: Dictionary = level["missile_wave"]
			missile_state["timer"] += MatchSim.DT
			if missile_state["timer"] >= float(wave["interval"]) and missile_state["launched"] < int(wave["count"]):
				missile_state["timer"] = 0.0
				missile_state["launched"] += 1
				var ciws_hp: float = MatchSim._layer_alive_hp_by_flag(player, catalog, "ciws")
				var intercept_chance: float = clamp(ciws_hp / float(economy["ciws_intercept_scale"]), 0.0, 0.9)
				if rng.randf() > intercept_chance:
					player["base_hp"] -= float(wave["damage"])
			if missile_state["launched"] >= int(wave["count"]):
				phase = MatchSim.PHASE_BOSS
				boss = MatchSim._spawn_boss(catalog, level["boss_id"])
				phase_changed.emit(phase)
		MatchSim.PHASE_BOSS:
			# Mirror MatchSim: the lane keeps fighting during the boss, with
			# the enemy base invincible until the boss dies.
			var enemy_base_before: float = enemy["base_hp"]
			MatchSim._resolve_combat_tick(player, enemy, catalog, weather_id, catalog.weather, economy, MatchSim.DT, rng)
			enemy["base_hp"] = enemy_base_before
			MatchSim._resolve_boss_tick(player, boss, catalog, weather_id, catalog.weather, MatchSim.DT, rng, _flagship_aim_bonus)
			_flagship_aim_bonus = 0.0
			if boss["hp"] <= 0.0:
				boss_killed = true
				phase = MatchSim.PHASE_FINISH
				phase_changed.emit(phase)
		MatchSim.PHASE_FINISH:
			MatchSim._resolve_combat_tick(player, enemy, catalog, weather_id, catalog.weather, economy, MatchSim.DT, rng)

	if player["base_hp"] <= 0.0:
		result = "LOSS"
		result_ready.emit(result)
	elif enemy["base_hp"] <= 0.0 and boss_killed:
		result = "WIN"
		result_ready.emit(result)

	tick += 1

## ---------------------------------------------------------- player commands

func build(unit_id: String) -> bool:
	return MatchSim.enqueue_build(player, catalog, unit_id, economy, tick)

func buy_income() -> bool:
	return MatchSim.buy_income_upgrade(player, economy)

func buy_installment() -> bool:
	return MatchSim.buy_installment_upgrade(player, economy)

func recycle(unit_id: String) -> float:
	return MatchSim.recycle_stack(player, catalog, unit_id, economy)

## Tap-to-aim: each tap adds one well-aimed bonus shot against the boss,
## consumed on the next step(). Only meaningful during PHASE_BOSS with a
## living flagship — bonus is flat, not tied to precise aim coordinates,
## since this is a lane battler, not a physics-aimed shooter.
func aim_flagship_shot() -> void:
	if phase != MatchSim.PHASE_BOSS:
		return
	if not player["stacks"].has("battleship_flagship"):
		return
	if float(player["stacks"]["battleship_flagship"]["alive_hp"]) <= 0.0:
		return
	var udef: Dictionary = catalog.units["battleship_flagship"]
	_flagship_aim_bonus += float(udef["attack"]) * 0.4

## ---------------------------------------------------------- read-only state

func gold() -> float:
	return float(player["gold"])

func base_hp() -> float:
	return max(0.0, float(player["base_hp"]))

func base_hp_max() -> float:
	return float(player["base_hp_max"])

func enemy_base_hp() -> float:
	return max(0.0, float(enemy["base_hp"]))

func enemy_base_hp_max() -> float:
	return float(enemy["base_hp_max"])

func era_name() -> String:
	var level: int = int(player.get("era_level", 0))
	if level < 0 or level >= catalog.eras.size():
		return "?"
	return String(catalog.eras[level]["name"])

func boss_hp_pct() -> float:
	if boss.is_empty():
		return 0.0
	return float(boss["hp"]) / float(boss["hp_max"])

func player_stacks() -> Dictionary:
	return player["stacks"]

func enemy_stacks() -> Dictionary:
	return enemy["stacks"]
