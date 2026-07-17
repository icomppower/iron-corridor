extends SceneTree
## Dev-only: drives LiveMatch tick-by-tick with the "mixed" policy standing
## in for a human player, and checks it lands on the same result as
## MatchSim.run() for the same level/seed — confirms the stepping wrapper
## didn't diverge from the batch sim it wraps. Not part of CI.

func _initialize() -> void:
	var catalog := Catalog.load_from("res://")
	var level: Dictionary = catalog.levels[0]
	var seed_value := 4242

	var batch := MatchSim.run(level, catalog, "mixed", seed_value)
	print("batch: ", batch["result"], " ticks=", batch["ticks"])

	var live := LiveMatch.new(level, catalog, seed_value)
	var t := 0
	while not live.is_over():
		if t % int(catalog.economy["decision_interval_ticks"]) == 0:
			Strategies.decide("mixed", live.player, catalog, level, catalog.economy, live.tick)
		live.step()
		t += 1
		if t > 2000:
			print("live: RUNAWAY, aborting")
			break
	print("live:  ", live.result, " ticks=", live.tick, " phase=", live.phase)
	print("match: ", batch["result"] == live.result)
	quit()
