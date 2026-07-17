extends SceneTree
## Dev-only diagnostic: loss-phase breakdown per (level, strategy). Not part of CI.

func _initialize() -> void:
	var catalog := Catalog.load_from("res://")
	for level in catalog.levels:
		var level_id: String = level["id"]
		for strat in ["rush", "eco", "turtle", "mixed"]:
			var counts := {}
			var n := 100
			for i in range(n):
				var r := MatchSim.run(level, catalog, strat, i * 7919 + 13)
				var key: String = r["result"] if r["result"] == "WIN" else "LOSS:%s" % r["loss_phase"]
				counts[key] = int(counts.get(key, 0)) + 1
			print("%s / %-6s -> %s" % [level_id, strat, counts])
	quit()
