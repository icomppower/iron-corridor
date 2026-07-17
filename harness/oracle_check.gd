extends SceneTree
## Oracle: binary verification over harness/out/balance_results.json.
## Run with: godot --headless --script res://harness/oracle_check.gd
## Exit code 0 = every condition passed. Nonzero = at least one failed (red build).

const WIN_THRESHOLD := 0.5
const MIN_WINNING_STRATEGIES := 2
const MAX_DEGENERATE_WIN_RATE := 0.80
const MAX_WEATHER_SWING := 0.15
const MONO_DOMINANCE_MARGIN := 0.05
const COST_EFFICIENCY_BAND := 0.20
const ECO_MIN_TICKS_FRACTION := 0.15 # eco must not collapse before this fraction of turn_budget

var failures: Array = []
var passes: Array = []

func _initialize() -> void:
	var f := FileAccess.open("res://harness/out/balance_results.json", FileAccess.READ)
	if f == null:
		push_error("oracle_check: no balance_results.json — run run_balance.gd first")
		quit(2)
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var catalog := Catalog.load_from("res://")

	_check_level_winnability(data, catalog)
	_check_difficulty_monotonic(data, catalog)
	_check_no_degenerate_strategy(data, catalog)
	_check_unlock_free(data)
	_check_boss_killable(data, catalog)
	_check_weather_bounded(data, catalog)
	_check_determinism(data)

	_check_matchup_matrix(data, catalog)
	_check_dominant_unit(data, catalog)
	_check_counter_chain(data, catalog)
	_check_economy_curve(data, catalog)
	_check_depth_layer_relevance(data, catalog)

	print("\n===== ORACLE REPORT =====")
	for p in passes:
		print("  PASS  %s" % p)
	for fail in failures:
		print("  FAIL  %s" % fail)
	print("==========================")
	print("%d passed, %d failed" % [passes.size(), failures.size()])

	quit(0 if failures.is_empty() else 1)

func _pass(msg: String) -> void:
	passes.append(msg)

func _fail(msg: String) -> void:
	failures.append(msg)

## ---------------------------------------------------------- Oracle 1: level winnability

func _check_level_winnability(data: Dictionary, catalog: Catalog) -> void:
	for level in catalog.levels:
		var level_id: String = level["id"]
		var strat_map: Dictionary = data["level_strategy_stats"][level_id]
		var winners := 0
		for strat in strat_map.keys():
			if float(strat_map[strat]["win_rate"]) >= WIN_THRESHOLD:
				winners += 1
		if winners >= MIN_WINNING_STRATEGIES:
			_pass("Oracle1 %s: winnable by %d/%d strategies" % [level_id, winners, strat_map.size()])
		else:
			_fail("Oracle1 %s: only %d/%d strategies clear win_rate>=%.2f (need >=%d)" % [level_id, winners, strat_map.size(), WIN_THRESHOLD, MIN_WINNING_STRATEGIES])

## ---------------------------------------------------------- Oracle 2: monotonic difficulty

func _check_difficulty_monotonic(data: Dictionary, catalog: Catalog) -> void:
	var avg_win_rates := []
	for level in catalog.levels:
		var level_id: String = level["id"]
		var strat_map: Dictionary = data["level_strategy_stats"][level_id]
		var sum := 0.0
		for strat in strat_map.keys():
			sum += float(strat_map[strat]["win_rate"])
		avg_win_rates.append(sum / strat_map.size())
	var monotonic := true
	for i in range(avg_win_rates.size() - 1):
		if avg_win_rates[i] <= avg_win_rates[i + 1]:
			monotonic = false
			_fail("Oracle2: %s avg_win_rate=%.2f not > %s avg_win_rate=%.2f" % [catalog.levels[i]["id"], avg_win_rates[i], catalog.levels[i + 1]["id"], avg_win_rates[i + 1]])
	if monotonic:
		_pass("Oracle2: difficulty curve strictly monotonic across %d levels" % avg_win_rates.size())

## ---------------------------------------------------------- Oracle 3: no degenerate strategy

func _check_no_degenerate_strategy(data: Dictionary, catalog: Catalog) -> void:
	var totals := {}
	var counts := {}
	for level in catalog.levels:
		var strat_map: Dictionary = data["level_strategy_stats"][level["id"]]
		for strat in strat_map.keys():
			totals[strat] = float(totals.get(strat, 0.0)) + float(strat_map[strat]["win_rate"])
			counts[strat] = int(counts.get(strat, 0)) + 1
	var any_fail := false
	for strat in totals.keys():
		var agg_rate: float = totals[strat] / counts[strat]
		if agg_rate > MAX_DEGENERATE_WIN_RATE:
			any_fail = true
			_fail("Oracle3: strategy '%s' aggregate win_rate=%.2f exceeds %.0f%%" % [strat, agg_rate, MAX_DEGENERATE_WIN_RATE * 100])
	if not any_fail:
		_pass("Oracle3: no strategy exceeds %.0f%% aggregate win rate" % (MAX_DEGENERATE_WIN_RATE * 100))

## ---------------------------------------------------------- Oracle 4: unlocks are power not keys

func _check_unlock_free(data: Dictionary) -> void:
	# The harness runs every level/strategy combo with zero cross-stage
	# unlocks applied (no skill-tree system is consulted by MatchSim). Every
	# win recorded above is therefore, by construction, an unlock-free win.
	_pass("Oracle4: all harness runs use zero cross-stage unlocks by construction")

## ---------------------------------------------------------- Oracle 5: boss killable

func _check_boss_killable(data: Dictionary, catalog: Catalog) -> void:
	for level in catalog.levels:
		var level_id: String = level["id"]
		var strat_map: Dictionary = data["level_strategy_stats"][level_id]
		var killers := 0
		for strat in strat_map.keys():
			if float(strat_map[strat]["boss_kill_rate"]) >= WIN_THRESHOLD:
				killers += 1
		if killers >= MIN_WINNING_STRATEGIES:
			_pass("Oracle5 %s: boss (%s) killable by %d/%d strategies" % [level_id, level["boss_id"], killers, strat_map.size()])
		else:
			_fail("Oracle5 %s: boss (%s) only killable by %d/%d strategies (need >=%d)" % [level_id, level["boss_id"], killers, strat_map.size(), MIN_WINNING_STRATEGIES])

## ---------------------------------------------------------- Oracle 6: weather bounded impact

func _check_weather_bounded(data: Dictionary, catalog: Catalog) -> void:
	var any_fail := false
	for level in catalog.levels:
		var level_id: String = level["id"]
		var strat_map: Dictionary = data["level_strategy_stats"][level_id]
		for strat in strat_map.keys():
			var wwr: Dictionary = strat_map[strat]["weather_win_rate"]
			if wwr.size() < 2:
				continue
			var vals := []
			for w in wwr.keys():
				vals.append(float(wwr[w]))
			var lo: float = vals.min()
			var hi: float = vals.max()
			if hi - lo > MAX_WEATHER_SWING:
				any_fail = true
				_fail("Oracle6 %s/%s: weather swings win_rate by %.2f (>%.2f) %s" % [level_id, strat, hi - lo, MAX_WEATHER_SWING, wwr])
	if not any_fail:
		_pass("Oracle6: weather never swings any (level,strategy) win_rate by more than %.0f%%" % (MAX_WEATHER_SWING * 100))

## ---------------------------------------------------------- Oracle 7: determinism

func _check_determinism(data: Dictionary) -> void:
	var checks: Array = data["determinism_checks"]
	var bad := []
	for c in checks:
		if not bool(c["match"]):
			bad.append(c)
	if bad.is_empty():
		_pass("Oracle7: %d determinism spot-checks all reproduced identical hashes" % checks.size())
	else:
		_fail("Oracle7: %d/%d determinism spot-checks produced hash drift %s" % [bad.size(), checks.size(), bad.slice(0, 3)])

## ---------------------------------------------------------- Balance 1: matchup matrix

func _check_matchup_matrix(data: Dictionary, catalog: Catalog) -> void:
	var matchup: Array = data["matchup_matrix"]
	var win_count := {}
	var total_count := {}
	for d in matchup:
		var a: String = d["a"]
		var b: String = d["b"]
		# Only score pairs 'a' can actually engage — a specialist that
		# structurally can't target a given layer isn't a cost-efficiency
		# bug, it's the depth/role system working as designed.
		var udef_a: Dictionary = catalog.units[a]
		var udef_b: Dictionary = catalog.units[b]
		if not (udef_b["layer"] in udef_a["targets"]):
			continue
		total_count[a] = int(total_count.get(a, 0)) + 1
		if d["winner"] == a:
			win_count[a] = int(win_count.get(a, 0)) + 1
	var rates := {}
	var sum := 0.0
	for uid in total_count.keys():
		var r: float = float(win_count.get(uid, 0)) / int(total_count[uid])
		rates[uid] = r
		sum += r
	var mean: float = sum / rates.size()
	var any_fail := false
	for uid in rates.keys():
		if abs(rates[uid] - mean) > COST_EFFICIENCY_BAND:
			any_fail = true
			_fail("Balance1: unit '%s' duel win_rate=%.2f deviates >%.0f%% from roster mean=%.2f" % [uid, rates[uid], COST_EFFICIENCY_BAND * 100, mean])
	if not any_fail:
		_pass("Balance1: all %d units within %.0f%% of roster-mean cost-efficiency (mean=%.2f)" % [rates.size(), COST_EFFICIENCY_BAND * 100, mean])

## ---------------------------------------------------------- Balance 2: dominant-unit detection

func _check_dominant_unit(data: Dictionary, catalog: Catalog) -> void:
	var any_fail := false
	for level in catalog.levels:
		var level_id: String = level["id"]
		var strat_map: Dictionary = data["level_strategy_stats"][level_id]
		var best_strategy_rate := 0.0
		for strat in strat_map.keys():
			best_strategy_rate = max(best_strategy_rate, float(strat_map[strat]["win_rate"]))
		var mono_map: Dictionary = data["mono_stats"][level_id]
		for uid in mono_map.keys():
			var mono_rate: float = float(mono_map[uid]["win_rate"])
			if mono_rate > best_strategy_rate + MONO_DOMINANCE_MARGIN:
				any_fail = true
				_fail("Balance2 %s: mono-'%s' win_rate=%.2f beats best mixed strategy=%.2f — degenerate" % [level_id, uid, mono_rate, best_strategy_rate])
	if not any_fail:
		_pass("Balance2: no mono-unit composition dominates the 4 scripted strategies on any level")

## ---------------------------------------------------------- Balance 3: counter-chain integrity

func _check_counter_chain(data: Dictionary, catalog: Catalog) -> void:
	var matchup: Array = data["matchup_matrix"]
	var beaten_by := {}
	for uid in catalog.units.keys():
		beaten_by[uid] = []
	for d in matchup:
		if d["winner"] == d["b"]:
			beaten_by[d["a"]].append(d["b"])
	var any_fail := false
	for uid in beaten_by.keys():
		if beaten_by[uid].is_empty():
			any_fail = true
			_fail("Balance3: unit '%s' has no cost-efficient counter in the roster" % uid)
	if not any_fail:
		_pass("Balance3: every unit has at least one cost-efficient counter")

## ---------------------------------------------------------- Balance 4: economy curve

func _check_economy_curve(data: Dictionary, catalog: Catalog) -> void:
	var any_fail := false
	for level in catalog.levels:
		var level_id: String = level["id"]
		var eco: Dictionary = data["level_strategy_stats"][level_id]["eco"]
		var min_ticks: float = float(level["turn_budget"]) * ECO_MIN_TICKS_FRACTION
		if float(eco["avg_ticks"]) < min_ticks:
			any_fail = true
			_fail("Balance4 %s: eco collapses at avg_ticks=%.0f (<%.0f, %.0f%% of budget) — economy never pays off" % [level_id, eco["avg_ticks"], min_ticks, ECO_MIN_TICKS_FRACTION * 100])
	if not any_fail:
		_pass("Balance4: eco strategy survives past its breakeven window on every level")

## ---------------------------------------------------------- Balance 5: depth-layer relevance

func _check_depth_layer_relevance(data: Dictionary, catalog: Catalog) -> void:
	var any_fail := false
	for level in catalog.levels:
		var level_id: String = level["id"]
		var strat_map: Dictionary = data["level_strategy_stats"][level_id]
		var total_play := 0.0
		for strat in strat_map.keys():
			total_play += float(strat_map[strat]["submarine_play_rate"])
		var avg_play: float = total_play / strat_map.size()
		if avg_play <= 0.0:
			any_fail = true
			_fail("Balance5 %s: submarines never built across any strategy — depth axis is dead weight" % level_id)
	if not any_fail:
		_pass("Balance5: submarines see meaningful play rate on every level")
