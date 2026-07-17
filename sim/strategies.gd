class_name Strategies
extends RefCounted
## Scripted policies driving a side's spend decisions. Pure functions of
## sim state — no hidden RNG, no Node deps. Called once per decision interval.

const MAX_MONO_BUYS_PER_DECISION := 6
const MAX_WEIGHTED_BUYS_PER_DECISION := 3

static func decide(strategy_id: String, side: Dictionary, catalog: Catalog, level: Dictionary, economy: Dictionary, tick: int) -> void:
	if strategy_id.begins_with("mono:"):
		decide_mono(strategy_id.substr(5), side, catalog, economy, tick)
		return
	match strategy_id:
		"rush":
			_spend_weighted(side, catalog, economy, tick, ["gunboat", "gunboat", "midget_sub", "hovercraft"])
		"eco":
			_eco(side, catalog, level, economy, tick)
		"turtle":
			_spend_weighted(side, catalog, economy, tick, ["destroyer", "destroyer", "corvette_asw", "flak_cruiser"])
		"mixed":
			_spend_weighted(side, catalog, economy, tick, ["corvette_asw", "destroyer", "flak_cruiser", "submarine_shallow", "hovercraft", "minelayer", "INCOME", "battleship_flagship", "carrier"])
		"level_ai":
			# Per-level enemy composition is rules-as-data: levels may ship an
			# "enemy_priority" list to shape what the AI masses (e.g. sub-heavy
			# wall-breaker comps on later levels). Roster still gates buys.
			var default_priority := ["gunboat", "destroyer", "submarine_shallow", "hovercraft", "corvette_asw", "flak_cruiser", "midget_sub", "submarine_deep", "INCOME", "battleship_flagship"]
			_spend_weighted(side, catalog, economy, tick, level.get("enemy_priority", default_priority))
		_:
			push_error("Strategies: unknown strategy_id %s" % strategy_id)

static func mono_strategy_id(unit_id: String) -> String:
	return "mono:%s" % unit_id

static func decide_mono(unit_id: String, side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int) -> void:
	_spend_repeat(side, catalog, economy, tick, [unit_id])

## eco needs early defenders before it dumps gold into upgrades, or it
## dies to the opening rush before its economy ever pays off. The seed
## scales with the enemy's income so eco holds a proportionate wall on
## later, richer levels instead of folding in the opening minutes.
static func _eco(side: Dictionary, catalog: Catalog, level: Dictionary, economy: Dictionary, tick: int) -> void:
	var defender_hp := 0.0
	for uid in side["stacks"].keys():
		defender_hp += float(side["stacks"][uid]["alive_hp"])
	var seed_unit := "corvette_asw" if side["roster"].has("corvette_asw") else "gunboat"
	var udef: Dictionary = catalog.units.get(seed_unit, {})
	var threat_scale: float = max(1.0, float(level.get("enemy_income_base", 12.0)) / 12.0)
	var seed_target: float = float(udef.get("hp", 40.0)) * 3.0 * threat_scale
	if defender_hp < seed_target and side["roster"].has(seed_unit):
		MatchSim.enqueue_build(side, catalog, seed_unit, economy, tick)
		return
	# Payoff phase: once INCOME/INSTALLMENT max out the fair-share credit
	# flows into heavy units bought at full discount — eco's identity is
	# a slow start that converts into a late-game hammer, not a wall that
	# survives on gunboats and never closes.
	_spend_weighted(side, catalog, economy, tick, ["INCOME", "INSTALLMENT", "destroyer", "corvette_asw", "battleship_flagship"])

## Fair-share purchase scheduler: every priority item accrues "credit" each
## decision call, and we always spend on the most-overdue item. If the
## most-overdue item is not affordable yet, the side holds its gold and
## saves up for it instead of skipping to something cheaper — otherwise
## expensive/rare slots (submarines, flagships) are perpetually crowded
## out by whatever's cheap and never get bought at all.
static func _spend_weighted(side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int, priority: Array) -> void:
	var credit: Dictionary = side.get("_credit", {})
	for item in priority:
		credit[item] = float(credit.get(item, 0.0)) + 1.0
	var attempts := 0
	while attempts < MAX_WEIGHTED_BUYS_PER_DECISION:
		attempts += 1
		var best := ""
		var best_credit := -1.0
		for item in priority:
			if float(credit.get(item, 0.0)) > best_credit and _purchasable(side, catalog, item):
				best = item
				best_credit = credit[item]
		if best == "" or not _affordable(side, catalog, economy, best):
			break
		_execute_buy(side, catalog, economy, tick, best)
		credit[best] = 0.0
	side["_credit"] = credit

## Whether the item is a valid purchase target at all (in roster / upgrade
## not maxed) — independent of current gold, so the scheduler can decide
## to save up for it.
static func _purchasable(side: Dictionary, catalog: Catalog, item: String) -> bool:
	if item == "INCOME":
		return int(side["income_level"]) < int(catalog.economy["income_upgrade"]["max_level"])
	elif item == "INSTALLMENT":
		return int(side["installment_level"]) < int(catalog.economy["installment_upgrade"]["max_level"])
	return side["roster"].has(item) and catalog.units.has(item)

static func _affordable(side: Dictionary, catalog: Catalog, economy: Dictionary, item: String) -> bool:
	if item == "INCOME":
		var cfg: Dictionary = economy["income_upgrade"]
		if int(side["income_level"]) >= int(cfg["max_level"]):
			return false
		var cost: float = float(cfg["cost_base"]) * pow(float(cfg["cost_growth"]), int(side["income_level"]))
		return side["gold"] >= cost
	elif item == "INSTALLMENT":
		var cfg: Dictionary = economy["installment_upgrade"]
		if int(side["installment_level"]) >= int(cfg["max_level"]):
			return false
		var cost: float = float(cfg["cost_base"]) * pow(float(cfg["cost_growth"]), int(side["installment_level"]))
		return side["gold"] >= cost
	if not side["roster"].has(item) or not catalog.units.has(item):
		return false
	return side["gold"] >= MatchSim.spawn_cost(side, catalog, item, economy)

static func _execute_buy(side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int, item: String) -> void:
	if item == "INCOME":
		MatchSim.buy_income_upgrade(side, economy)
	elif item == "INSTALLMENT":
		MatchSim.buy_installment_upgrade(side, economy)
	else:
		MatchSim.enqueue_build(side, catalog, item, economy, tick)

## Buys the first affordable item repeatedly — used for mono-composition
## balance testing where we deliberately want an all-in spam pattern.
static func _spend_repeat(side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int, priority: Array) -> void:
	var roster: Array = side["roster"]
	var buys := 0
	while buys < MAX_MONO_BUYS_PER_DECISION:
		var bought := false
		for item in priority:
			if item == "INCOME":
				if MatchSim.buy_income_upgrade(side, economy):
					bought = true
					break
			elif item == "INSTALLMENT":
				if MatchSim.buy_installment_upgrade(side, economy):
					bought = true
					break
			else:
				if not roster.has(item) or not catalog.units.has(item):
					continue
				if MatchSim.enqueue_build(side, catalog, item, economy, tick):
					bought = true
					break
		if not bought:
			break
		buys += 1
