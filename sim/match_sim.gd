class_name MatchSim
extends RefCounted
## Deterministic fixed-tick sim core for one level attempt. Zero Node deps —
## pure data in, JSON-serializable result out. Presentation layer only reads
## MatchSim output; it never writes back into the sim.

const PHASE_PUSH := "PUSH"
const PHASE_MISSILE := "MISSILE_DEFENSE"
const PHASE_BOSS := "BOSS"
const PHASE_FINISH := "FINISH"

const DT := 1.0

static func run(level: Dictionary, catalog: Catalog, player_strategy_id: String, seed_value: int) -> Dictionary:
	var rng := IronRNG.new(seed_value)
	var economy: Dictionary = catalog.economy

	var player := _new_side(level["player_roster"], float(level["player_base_hp"]), float(economy["starting_gold"]))
	var enemy := _new_side(level["enemy_roster"], float(level["enemy_base_hp"]), 0.0)
	enemy["base_hp_max"] = float(level["enemy_base_hp"])

	var weather_id: String = rng.pick_weighted(level["weather_table"])
	var weather_table: Dictionary = catalog.weather

	var phase := PHASE_PUSH
	var boss: Dictionary = {}
	var missile_state := {"launched": 0, "timer": 0.0}
	var turn_budget := int(level["turn_budget"])
	var boss_trigger_hp: float = float(level["enemy_base_hp"]) * float(level["boss_trigger_hp_pct"])

	var result := "LOSS"
	var final_tick := 0
	var running_hash := 0
	var boss_killed := false
	var loss_phase := ""

	for tick in range(turn_budget):
		final_tick = tick

		# --- income ---
		player["gold"] += _effective_income(player, float(economy["income_base"]), economy) * DT
		enemy["gold"] += _effective_income(enemy, float(level["enemy_income_base"]), economy) * DT

		# --- era evolution ---
		_check_era_upgrade(player, catalog)
		_check_era_upgrade(enemy, catalog)

		# --- spawn queue resolution ---
		_process_spawn_queue(player, catalog, tick)
		_process_spawn_queue(enemy, catalog, tick)

		# --- decisions ---
		if tick % int(economy["decision_interval_ticks"]) == 0:
			Strategies.decide(player_strategy_id, player, catalog, level, economy, tick)
			Strategies.decide("level_ai", enemy, catalog, level, economy, tick)

		# --- phase resolution ---
		match phase:
			PHASE_PUSH:
				_resolve_combat_tick(player, enemy, catalog, weather_id, weather_table, economy, DT, rng)
				if enemy["base_hp"] <= boss_trigger_hp:
					phase = PHASE_MISSILE
					missile_state = {"launched": 0, "timer": 0.0}
			PHASE_MISSILE:
				var wave: Dictionary = level["missile_wave"]
				missile_state["timer"] += DT
				if missile_state["timer"] >= float(wave["interval"]) and missile_state["launched"] < int(wave["count"]):
					missile_state["timer"] = 0.0
					missile_state["launched"] += 1
					var ciws_hp := _layer_alive_hp_by_flag(player, catalog, "ciws")
					var intercept_chance: float = clamp(ciws_hp / float(economy["ciws_intercept_scale"]), 0.0, 0.9)
					if rng.randf() > intercept_chance:
						player["base_hp"] -= float(wave["damage"])
				if missile_state["launched"] >= int(wave["count"]):
					phase = PHASE_BOSS
					boss = _spawn_boss(catalog, level["boss_id"])
			PHASE_BOSS:
				# The lane keeps fighting while the boss is engaged — that is
				# what makes "enemy base is invincible while its boss is
				# alive" a rule rather than a no-op. A frozen lane turned the
				# boss fight into a pure standing-army check that a slow wall
				# comp banked its way through every time.
				var enemy_base_before: float = enemy["base_hp"]
				_resolve_combat_tick(player, enemy, catalog, weather_id, weather_table, economy, DT, rng)
				enemy["base_hp"] = enemy_base_before
				_resolve_boss_tick(player, boss, catalog, weather_id, weather_table, DT, rng)
				if boss["hp"] <= 0.0:
					boss_killed = true
					phase = PHASE_FINISH
			PHASE_FINISH:
				_resolve_combat_tick(player, enemy, catalog, weather_id, weather_table, economy, DT, rng)

		if player["base_hp"] <= 0.0:
			result = "LOSS"
			loss_phase = phase
			break
		if enemy["base_hp"] <= 0.0 and boss_killed:
			result = "WIN"
			break

		var tick_str := "%d|%.2f|%.2f|%.2f|%s" % [tick, player["gold"], player["base_hp"], enemy["base_hp"], phase]
		running_hash = (str(running_hash) + tick_str).hash()

	if result == "LOSS" and loss_phase == "":
		loss_phase = "TIMEOUT"

	var score := 0.0
	if result == "WIN":
		score += 1000.0
		score += float(turn_budget - final_tick)
	score += max(0.0, player["base_hp"]) * 0.5

	return {
		"result": result,
		"ticks": final_tick,
		"weather": weather_id,
		"score": score,
		"final_hash": running_hash,
		"player_base_hp_remaining": max(0.0, player["base_hp"]),
		"enemy_base_hp_remaining": max(0.0, enemy["base_hp"]),
		"boss_killed": boss_killed,
		"loss_phase": loss_phase,
		"strategy": player_strategy_id,
		"level_id": level["id"],
		"built_units": player["built"].keys(),
		"player_era_level": int(player["era_level"])
	}

## ---------------------------------------------------------------- side state

static func _new_side(roster: Array, base_hp: float, starting_gold: float) -> Dictionary:
	return {
		"gold": starting_gold,
		"income_level": 0,
		"installment_level": 0,
		"base_hp": base_hp,
		"base_hp_max": base_hp,
		"roster": roster,
		"stacks": {},
		"spawn_queue": [],
		"built": {},
		"xp": 0.0,
		"era_level": 0
	}

static func _effective_income(side: Dictionary, base_income: float, economy: Dictionary) -> float:
	var bonus: float = float(economy["income_upgrade"]["income_bonus_pct"]) * int(side["income_level"])
	return base_income * (1.0 + bonus)

## In-match XP unlocks tech eras (WWII gunline -> missile age): a flat
## attack multiplier applied once a side crosses the tier's XP threshold.
## XP itself accrues from damage dealt (see _apply_layer_damage /
## _resolve_boss_tick), so aggression is what pulls a side into the next era.
static func _era_attack_mult(side: Dictionary, catalog: Catalog) -> float:
	var level: int = int(side.get("era_level", 0))
	if level < 0 or level >= catalog.eras.size():
		return 1.0
	return float(catalog.eras[level]["attack_mult"])

## Cross-stage skill-tree bonuses (interactive play only). MatchSim.run()
## never sets "unlocked_skills" on a side, so this is always a no-op 1.0x
## for every harness/oracle run — unlocks stay power, never keys, by
## construction, matching Oracle #4 without needing a separate code path.
static func _skill_attack_mult(side: Dictionary, catalog: Catalog, udef: Dictionary) -> float:
	var unlocked: Array = side.get("unlocked_skills", [])
	if unlocked.is_empty():
		return 1.0
	var mult := 1.0
	var weapon: String = udef.get("weapon", "")
	var unit_id: String = String(udef.get("id", ""))
	for skill_id in unlocked:
		if not catalog.skills.has(skill_id):
			continue
		var effect: Dictionary = catalog.skills[skill_id]["effect"]
		var etype: String = String(effect["type"])
		if etype == "weapon_attack" and String(effect["target"]) == weapon:
			mult += float(effect["pct"])
		elif etype == "unit_attack" and String(effect["target"]) == unit_id:
			mult += float(effect["pct"])
	return mult

static func _check_era_upgrade(side: Dictionary, catalog: Catalog) -> void:
	var xp: float = float(side.get("xp", 0.0))
	var level: int = int(side.get("era_level", 0))
	while level + 1 < catalog.eras.size() and xp >= float(catalog.eras[level + 1]["xp_threshold"]):
		level += 1
	side["era_level"] = level

static func spawn_cost(side: Dictionary, catalog: Catalog, unit_id: String, economy: Dictionary) -> float:
	var udef: Dictionary = catalog.units[unit_id]
	var reduction: float = float(economy["installment_upgrade"]["cost_reduction_pct"]) * int(side["installment_level"])
	reduction = min(reduction, 0.85)
	return float(udef["cost"]) * (1.0 - reduction)

static func enqueue_build(side: Dictionary, catalog: Catalog, unit_id: String, economy: Dictionary, tick: int) -> bool:
	var cost := spawn_cost(side, catalog, unit_id, economy)
	if side["gold"] < cost:
		return false
	var udef: Dictionary = catalog.units[unit_id]
	side["gold"] -= cost
	side["spawn_queue"].append({"id": unit_id, "ready_tick": tick + int(udef["spawn_time"])})
	return true

static func buy_income_upgrade(side: Dictionary, economy: Dictionary) -> bool:
	var cfg: Dictionary = economy["income_upgrade"]
	if int(side["income_level"]) >= int(cfg["max_level"]):
		return false
	var cost: float = float(cfg["cost_base"]) * pow(float(cfg["cost_growth"]), int(side["income_level"]))
	if side["gold"] < cost:
		return false
	side["gold"] -= cost
	side["income_level"] += 1
	return true

static func buy_installment_upgrade(side: Dictionary, economy: Dictionary) -> bool:
	var cfg: Dictionary = economy["installment_upgrade"]
	if int(side["installment_level"]) >= int(cfg["max_level"]):
		return false
	var cost: float = float(cfg["cost_base"]) * pow(float(cfg["cost_growth"]), int(side["installment_level"]))
	if side["gold"] < cost:
		return false
	side["gold"] -= cost
	side["installment_level"] += 1
	return true

static func recycle_stack(side: Dictionary, catalog: Catalog, unit_id: String, economy: Dictionary) -> float:
	if not side["stacks"].has(unit_id):
		return 0.0
	var st: Dictionary = side["stacks"][unit_id]
	var udef: Dictionary = catalog.units[unit_id]
	var refund: float = (st["alive_hp"] / float(udef["hp"])) * float(udef["cost"]) * float(economy["recycle_refund_pct"])
	side["gold"] += refund
	st["alive_hp"] = 0.0
	return refund

static func _process_spawn_queue(side: Dictionary, catalog: Catalog, tick: int) -> void:
	var remaining := []
	for entry in side["spawn_queue"]:
		if entry["ready_tick"] <= tick:
			_materialize(side, catalog, entry["id"])
		else:
			remaining.append(entry)
	side["spawn_queue"] = remaining

static func _materialize(side: Dictionary, catalog: Catalog, unit_id: String) -> void:
	var udef: Dictionary = catalog.units[unit_id]
	if not side["stacks"].has(unit_id):
		side["stacks"][unit_id] = {
			"id": unit_id,
			"layer": udef["layer"],
			"alive_hp": 0.0
		}
	side["stacks"][unit_id]["alive_hp"] += float(udef["hp"])
	side["built"][unit_id] = true

static func _layer_alive_hp_by_flag(side: Dictionary, catalog: Catalog, flag: String) -> float:
	var total := 0.0
	for uid in side["stacks"].keys():
		var udef: Dictionary = catalog.units[uid]
		if udef.has(flag) and bool(udef[flag]):
			total += float(side["stacks"][uid]["alive_hp"])
	return total

## -------------------------------------------------------------------- combat

static func _weather_attack_mult(udef: Dictionary, weather_id: String, weather_table: Dictionary) -> float:
	if not weather_table.has(weather_id):
		return 1.0
	var w: Dictionary = weather_table[weather_id]
	var mult := 1.0
	var weapon: String = udef.get("weapon", "")
	if weapon == "torpedo" and w.has("torpedo_attack_pct"):
		mult += float(w["torpedo_attack_pct"])
	if weapon == "gun" and w.has("gun_attack_pct"):
		mult += float(w["gun_attack_pct"])
	return max(0.0, mult)

static func _weather_detect(udef: Dictionary, weather_id: String, weather_table: Dictionary) -> Array:
	var detect: Array = udef["detect"].duplicate()
	if not weather_table.has(weather_id):
		return detect
	var w: Dictionary = weather_table[weather_id]
	if w.has("removes_detect_layer"):
		detect.erase(w["removes_detect_layer"])
	return detect

static func _is_grounded(udef: Dictionary, weather_id: String, weather_table: Dictionary) -> bool:
	if weather_id != "storm":
		return false
	if not weather_table.has("storm"):
		return false
	var w: Dictionary = weather_table["storm"]
	return bool(w.get("grounds_air", false)) and udef.get("grounded_by_storm", false)

static func _resolve_combat_tick(player: Dictionary, enemy: Dictionary, catalog: Catalog, weather_id: String, weather_table: Dictionary, economy: Dictionary, dt: float, rng: IronRNG) -> void:
	var player_layers := _alive_layers(player, catalog, weather_id, weather_table)
	var enemy_layers := _alive_layers(enemy, catalog, weather_id, weather_table)

	var dmg_to_enemy_layer := {}
	var dmg_to_player_layer := {}
	var unopposed_player := 0.0
	var unopposed_enemy := 0.0

	for uid in player["stacks"].keys():
		var st: Dictionary = player["stacks"][uid]
		if st["alive_hp"] <= 0.0:
			continue
		var udef: Dictionary = catalog.units[uid]
		if _is_grounded(udef, weather_id, weather_table):
			continue
		var variance := 1.0 + rng.randf_range(-0.05, 0.05)
		var atk: float = float(udef["attack"]) * (st["alive_hp"] / float(udef["hp"])) * _weather_attack_mult(udef, weather_id, weather_table) * _era_attack_mult(player, catalog) * _skill_attack_mult(player, catalog, udef) * variance
		var detect := _weather_detect(udef, weather_id, weather_table)
		var opposed: Array = []
		for layer in udef["targets"]:
			if layer in detect and enemy_layers.has(layer):
				opposed.append(layer)
		if opposed.is_empty():
			unopposed_player += atk
		else:
			var share := atk / opposed.size()
			for layer in opposed:
				dmg_to_enemy_layer[layer] = dmg_to_enemy_layer.get(layer, 0.0) + share

	for uid in enemy["stacks"].keys():
		var st: Dictionary = enemy["stacks"][uid]
		if st["alive_hp"] <= 0.0:
			continue
		var udef: Dictionary = catalog.units[uid]
		if _is_grounded(udef, weather_id, weather_table):
			continue
		var variance := 1.0 + rng.randf_range(-0.05, 0.05)
		var atk: float = float(udef["attack"]) * (st["alive_hp"] / float(udef["hp"])) * _weather_attack_mult(udef, weather_id, weather_table) * _era_attack_mult(enemy, catalog) * _skill_attack_mult(enemy, catalog, udef) * variance
		var detect := _weather_detect(udef, weather_id, weather_table)
		var opposed: Array = []
		for layer in udef["targets"]:
			if layer in detect and player_layers.has(layer):
				opposed.append(layer)
		if opposed.is_empty():
			unopposed_enemy += atk
		else:
			var share := atk / opposed.size()
			for layer in opposed:
				dmg_to_player_layer[layer] = dmg_to_player_layer.get(layer, 0.0) + share

	var overflow_to_enemy_base := _apply_layer_damage(enemy, player, catalog, dmg_to_enemy_layer, economy)
	var overflow_to_player_base := _apply_layer_damage(player, enemy, catalog, dmg_to_player_layer, economy)

	enemy["base_hp"] -= overflow_to_enemy_base
	player["base_hp"] -= overflow_to_player_base
	enemy["base_hp"] -= unopposed_player * float(economy["base_chip_scale"]) * dt
	player["base_hp"] -= unopposed_enemy * float(economy["base_chip_scale"]) * dt

	var xp_per_dmg: float = float(economy["xp_per_damage"])
	player["xp"] = float(player.get("xp", 0.0)) + (overflow_to_enemy_base + unopposed_player * float(economy["base_chip_scale"]) * dt) * xp_per_dmg
	enemy["xp"] = float(enemy.get("xp", 0.0)) + (overflow_to_player_base + unopposed_enemy * float(economy["base_chip_scale"]) * dt) * xp_per_dmg

static func _alive_layers(side: Dictionary, catalog: Catalog, weather_id: String, weather_table: Dictionary) -> Dictionary:
	var layers := {}
	for uid in side["stacks"].keys():
		var st: Dictionary = side["stacks"][uid]
		if st["alive_hp"] <= 0.0:
			continue
		var udef: Dictionary = catalog.units[uid]
		if _is_grounded(udef, weather_id, weather_table):
			continue
		layers[udef["layer"]] = true
	return layers

## Applies pending layer damage to `defender`'s stacks, crediting `attacker`
## with salvage gold for kills. Returns overflow damage that should carry
## through to the defender's base (layer fully wiped this tick).
static func _apply_layer_damage(defender: Dictionary, attacker: Dictionary, catalog: Catalog, dmg_by_layer: Dictionary, economy: Dictionary) -> float:
	var total_overflow := 0.0
	for layer in dmg_by_layer.keys():
		var incoming: float = dmg_by_layer[layer]
		var stacks_in_layer := []
		var layer_hp := 0.0
		for uid in defender["stacks"].keys():
			var st: Dictionary = defender["stacks"][uid]
			if st["alive_hp"] > 0.0 and catalog.units[uid]["layer"] == layer:
				stacks_in_layer.append(uid)
				layer_hp += st["alive_hp"]
		if layer_hp <= 0.0:
			total_overflow += incoming
			continue
		var dealt: float = min(incoming, layer_hp)
		var overflow: float = max(0.0, incoming - layer_hp)
		total_overflow += overflow
		for uid in stacks_in_layer:
			var st: Dictionary = defender["stacks"][uid]
			var share_pct: float = st["alive_hp"] / layer_hp
			var lost: float = dealt * share_pct
			st["alive_hp"] = max(0.0, st["alive_hp"] - lost)
			var udef: Dictionary = catalog.units[uid]
			var salvage: float = (lost / float(udef["hp"])) * float(udef["cost"]) * float(economy["wreck_salvage_pct"])
			attacker["gold"] += salvage
			attacker["xp"] = float(attacker.get("xp", 0.0)) + lost * float(economy["xp_per_damage"])
	return total_overflow

## --------------------------------------------------------------------- boss

static func _spawn_boss(catalog: Catalog, boss_id: String) -> Dictionary:
	var def: Dictionary = catalog.bosses[boss_id]
	return {
		"id": boss_id,
		"hp": float(def["hp"]),
		"hp_max": float(def["hp"]),
		"base_attack": float(def["base_attack"]),
		"target_layers": def["target_layers"],
		"phases": def["phases"]
	}

static func _current_boss_phase(boss: Dictionary) -> Dictionary:
	var hp_pct: float = boss["hp"] / boss["hp_max"]
	var best: Dictionary = boss["phases"][0]
	for phase in boss["phases"]:
		if hp_pct >= float(phase["hp_pct_above"]):
			return phase
		best = phase
	return best

static func _resolve_boss_tick(player: Dictionary, boss: Dictionary, catalog: Catalog, weather_id: String, weather_table: Dictionary, dt: float, rng: IronRNG, manual_aim_bonus: float = 0.0) -> void:
	var total_dmg := manual_aim_bonus
	for uid in player["stacks"].keys():
		var st: Dictionary = player["stacks"][uid]
		if st["alive_hp"] <= 0.0:
			continue
		var udef: Dictionary = catalog.units[uid]
		if _is_grounded(udef, weather_id, weather_table):
			continue
		# A boss is a massive, fully-visible target — every stack still
		# alive can bring guns/depth-charges/flak to bear on it, regardless
		# of the stealth/detection specialization that matters against
		# regular forces.
		var atk: float = float(udef["attack"]) * (st["alive_hp"] / float(udef["hp"])) * _weather_attack_mult(udef, weather_id, weather_table) * _era_attack_mult(player, catalog) * _skill_attack_mult(player, catalog, udef)
		if udef.get("flagship", false):
			atk *= float(udef.get("boss_damage_mult", 1.0))
		total_dmg += atk
	var applied_dmg: float = min(total_dmg, boss["hp"]) * dt
	player["xp"] = float(player.get("xp", 0.0)) + applied_dmg
	boss["hp"] = max(0.0, boss["hp"] - total_dmg * dt)
	if boss["hp"] <= 0.0:
		return

	var phase := _current_boss_phase(boss)
	var boss_atk: float = float(boss["base_attack"]) * float(phase["attack_mult"])
	if phase.get("ability", null) == "missile_barrage":
		boss_atk *= 1.25
	player["base_hp"] -= boss_atk * dt

	if phase.get("ability", null) == "depth_charge_spread":
		for uid in ["submarine_shallow", "submarine_deep"]:
			if player["stacks"].has(uid):
				var st: Dictionary = player["stacks"][uid]
				st["alive_hp"] = max(0.0, st["alive_hp"] - 6.0 * dt)

## --------------------------------------------------------------------- duel

## Cost-normalized 1v1 duel used by the matchup-matrix balance test.
## Deterministic (no RNG, no weather) — reuses the same combat resolver as
## live matches so results reflect the real damage/detection rules.
static func run_duel(catalog: Catalog, unit_a: String, unit_b: String, budget: float, max_ticks: int = 300) -> Dictionary:
	var side_a := _duel_side(catalog, unit_a, budget)
	var side_b := _duel_side(catalog, unit_b, budget)
	var weather_table: Dictionary = catalog.weather
	var economy: Dictionary = catalog.economy
	var duel_rng := IronRNG.new(0) # fixed seed: duels stay deterministic for CI stability
	var ticks := 0
	for tick in range(max_ticks):
		ticks = tick
		_resolve_combat_tick(side_a, side_b, catalog, "clear", weather_table, economy, DT, duel_rng)
		if _total_alive(side_a) <= 0.0 or _total_alive(side_b) <= 0.0:
			break
	var a_hp := _total_alive(side_a)
	var b_hp := _total_alive(side_b)
	var winner := "draw"
	if a_hp > b_hp:
		winner = unit_a
	elif b_hp > a_hp:
		winner = unit_b
	return {
		"a": unit_a,
		"b": unit_b,
		"winner": winner,
		"ticks": ticks,
		"a_remaining_pct": a_hp / max(1.0, _total_alive_max(catalog, unit_a, budget)),
		"b_remaining_pct": b_hp / max(1.0, _total_alive_max(catalog, unit_b, budget))
	}

static func _duel_side(catalog: Catalog, unit_id: String, budget: float) -> Dictionary:
	var udef: Dictionary = catalog.units[unit_id]
	var count: int = max(1, int(floor(budget / float(udef["cost"]))))
	return {
		"gold": 0.0,
		"base_hp": 1000000.0,
		"base_hp_max": 1000000.0,
		"stacks": {
			unit_id: {"id": unit_id, "layer": udef["layer"], "alive_hp": float(count) * float(udef["hp"])}
		}
	}

static func _total_alive(side: Dictionary) -> float:
	var total := 0.0
	for uid in side["stacks"].keys():
		total += side["stacks"][uid]["alive_hp"]
	return total

static func _total_alive_max(catalog: Catalog, unit_id: String, budget: float) -> float:
	var udef: Dictionary = catalog.units[unit_id]
	var count: int = max(1, int(floor(budget / float(udef["cost"]))))
	return float(count) * float(udef["hp"])
