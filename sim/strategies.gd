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
			_spend_weighted(side, catalog, economy, tick, ["gunboat", "hovercraft", "submarine_shallow"])
		"eco":
			_eco(side, catalog, economy, tick)
		"turtle":
			_spend_weighted(side, catalog, economy, tick, ["destroyer", "destroyer", "corvette_asw", "flak_cruiser"])
		"mixed":
			_spend_weighted(side, catalog, economy, tick, ["gunboat", "corvette_asw", "destroyer", "flak_cruiser", "submarine_shallow", "hovercraft", "INCOME", "battleship_flagship"])
		"level_ai":
			_spend_weighted(side, catalog, economy, tick, ["gunboat", "destroyer", "submarine_shallow", "hovercraft", "corvette_asw", "flak_cruiser", "INCOME"])
		_:
			push_error("Strategies: unknown strategy_id %s" % strategy_id)

static func mono_strategy_id(unit_id: String) -> String:
	return "mono:%s" % unit_id

static func decide_mono(unit_id: String, side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int) -> void:
	_spend_repeat(side, catalog, economy, tick, [unit_id])

## eco needs a couple of early defenders before it dumps gold into upgrades,
## or it dies to the opening rush before its economy ever pays off.
static func _eco(side: Dictionary, catalog: Catalog, economy: Dictionary, tick: int) -> void:
	var defender_hp := 0.0
	for uid in side["stacks"].keys():
		defender_hp += float(side["stacks"][uid]["alive_hp"])
	var udef: Dictionary = catalog.units.get("gunboat", {})
	var seed_target: float = float(udef.get("hp", 40.0)) * 2.0
	if defender_hp < seed_target and side["roster"].has("gunboat"):
		MatchSim.enqueue_build(side, catalog, "gunboat", economy, tick)
		return
	_spend_weighted(side, catalog, economy, tick, ["INCOME", "INSTALLMENT", "gunboat", "corvette_asw"])

## Fair-share purchase scheduler: every priority item accrues "credit" each
## decision call, and we always spend on the most-overdue affordable item.
## This is what lets expensive/rare slots (submarines, flagships) actually
## get bought instead of being perpetually crowded out by whatever's cheap.
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
			if float(credit.get(item, 0.0)) > best_credit and _affordable(side, catalog, economy, item):
				best = item
				best_credit = credit[item]
		if best == "":
			break
		_execute_buy(side, catalog, economy, tick, best)
		credit[best] = 0.0
	side["_credit"] = credit

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
