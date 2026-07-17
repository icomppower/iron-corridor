extends SceneTree
## Fast smoke test — not part of CI, just for local sanity checks during dev.

func _initialize() -> void:
	var catalog := Catalog.load_from("res://")
	print("Loaded %d units, %d bosses, %d levels" % [catalog.units.size(), catalog.bosses.size(), catalog.levels.size()])
	var level: Dictionary = catalog.levels[0]
	for strat in ["rush", "eco", "turtle", "mixed"]:
		var r := MatchSim.run(level, catalog, strat, 42)
		print("%s -> %s ticks=%d score=%.1f boss_killed=%s built=%s" % [strat, r["result"], r["ticks"], r["score"], r["boss_killed"], r["built_units"]])
	var duel := MatchSim.run_duel(catalog, "gunboat", "destroyer", 1000.0)
	print("duel gunboat vs destroyer: ", duel)
	quit()
