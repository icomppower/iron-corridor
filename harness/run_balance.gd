extends SceneTree
## Headless balance harness. Run with:
##   godot --headless --script res://harness/run_balance.gd
## Emits res://harness/out/balance_results.json for the Oracle checker.

const STRATEGIES := ["rush", "eco", "turtle", "mixed"]
const RUNS_PER_STRATEGY := 500
const MONO_RUNS := 50
const BASE_SEED := 0x1C0A5A17
const DUEL_BUDGET := 1000.0

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var catalog := Catalog.load_from("res://")

	var level_strategy_stats := {}
	var mono_stats := {}
	var determinism_checks := []
	var det_sample_every := 137 # spot-check every Nth run for determinism

	for level in catalog.levels:
		var level_id: String = level["id"]
		level_strategy_stats[level_id] = {}
		mono_stats[level_id] = {}

		for strat in STRATEGIES:
			var agg := _new_agg()
			for i in range(RUNS_PER_STRATEGY):
				var seed_value := _seed_for(level_id, strat, i)
				var r := MatchSim.run(level, catalog, strat, seed_value)
				_accumulate(agg, r)
				if i % det_sample_every == 0:
					var r2 := MatchSim.run(level, catalog, strat, seed_value)
					determinism_checks.append({
						"level_id": level_id,
						"strategy": strat,
						"seed": seed_value,
						"hash_a": r["final_hash"],
						"hash_b": r2["final_hash"],
						"match": r["final_hash"] == r2["final_hash"]
					})
			level_strategy_stats[level_id][strat] = _finalize_agg(agg, RUNS_PER_STRATEGY)

		for unit_id in level["player_roster"]:
			var agg2 := _new_agg()
			var strategy_id: String = Strategies.mono_strategy_id(unit_id)
			for i in range(MONO_RUNS):
				var seed_value := _seed_for(level_id, strategy_id, i)
				var r := MatchSim.run(level, catalog, strategy_id, seed_value)
				_accumulate(agg2, r)
			mono_stats[level_id][unit_id] = _finalize_agg(agg2, MONO_RUNS)

		print("balance: level %s done (%d ms elapsed)" % [level_id, Time.get_ticks_msec() - t0])

	var matchup_matrix := []
	var unit_ids: Array = catalog.units.keys()
	for a in unit_ids:
		for b in unit_ids:
			if a == b:
				continue
			matchup_matrix.append(MatchSim.run_duel(catalog, a, b, DUEL_BUDGET))

	var output := {
		"base_seed": BASE_SEED,
		"runs_per_strategy": RUNS_PER_STRATEGY,
		"mono_runs": MONO_RUNS,
		"level_strategy_stats": level_strategy_stats,
		"mono_stats": mono_stats,
		"matchup_matrix": matchup_matrix,
		"determinism_checks": determinism_checks,
		"elapsed_ms": Time.get_ticks_msec() - t0
	}

	var out_dir := "res://harness/out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var f := FileAccess.open(out_dir.path_join("balance_results.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "  "))
	f.close()

	print("balance: wrote %s (%d ms total)" % [out_dir.path_join("balance_results.json"), Time.get_ticks_msec() - t0])
	quit()

func _seed_for(level_id: String, strategy: String, i: int) -> int:
	return ("%d|%s|%s|%d" % [BASE_SEED, level_id, strategy, i]).hash()

func _new_agg() -> Dictionary:
	return {
		"wins": 0,
		"sum_score": 0.0,
		"sum_ticks": 0.0,
		"boss_kills": 0,
		"with_sub": 0,
		"with_sub_wins": 0,
		"without_sub_wins": 0,
		"weather_runs": {},
		"weather_wins": {}
	}

func _accumulate(agg: Dictionary, r: Dictionary) -> void:
	if r["result"] == "WIN":
		agg["wins"] += 1
	agg["sum_score"] += float(r["score"])
	agg["sum_ticks"] += float(r["ticks"])
	if r["boss_killed"]:
		agg["boss_kills"] += 1
	var built: Array = r["built_units"]
	var has_sub: bool = built.has("submarine_shallow") or built.has("submarine_deep")
	if has_sub:
		agg["with_sub"] += 1
		if r["result"] == "WIN":
			agg["with_sub_wins"] += 1
	elif r["result"] == "WIN":
		agg["without_sub_wins"] += 1
	var weather: String = r["weather"]
	agg["weather_runs"][weather] = int(agg["weather_runs"].get(weather, 0)) + 1
	if r["result"] == "WIN":
		agg["weather_wins"][weather] = int(agg["weather_wins"].get(weather, 0)) + 1

func _finalize_agg(agg: Dictionary, n: int) -> Dictionary:
	var without_sub: int = n - int(agg["with_sub"])
	var weather_win_rate := {}
	for w in agg["weather_runs"].keys():
		var runs: int = agg["weather_runs"][w]
		var wins: int = int(agg["weather_wins"].get(w, 0))
		weather_win_rate[w] = float(wins) / runs
	return {
		"runs": n,
		"win_rate": float(agg["wins"]) / n,
		"avg_score": agg["sum_score"] / n,
		"avg_ticks": agg["sum_ticks"] / n,
		"boss_kill_rate": float(agg["boss_kills"]) / n,
		"submarine_play_rate": float(agg["with_sub"]) / n,
		"win_rate_with_submarine": (float(agg["with_sub_wins"]) / agg["with_sub"]) if agg["with_sub"] > 0 else -1.0,
		"win_rate_without_submarine": (float(agg["without_sub_wins"]) / without_sub) if without_sub > 0 else -1.0,
		"weather_win_rate": weather_win_rate
	}
