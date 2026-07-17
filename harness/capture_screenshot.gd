extends SceneTree
## Dev-only visual QA capture. Not part of CI. Run with:
##   godot --path . --script res://harness/capture_screenshot.gd
## (must NOT pass --headless, or the viewport texture will be blank).

func _initialize() -> void:
	var main_scene: PackedScene = load("res://presentation/Main.tscn")
	var instance: Node = main_scene.instantiate()
	root.add_child(instance)
	for i in range(10):
		await process_frame

	# simulate a few build taps to prove the UI -> sim write path works
	instance.ui.build_requested.emit("gunboat")
	instance.ui.build_requested.emit("destroyer")
	instance.ui.income_requested.emit()
	for i in range(10):
		await process_frame
	print("gold after buys: ", instance.live.gold())
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/iron_corridor_push.png")
	print("saved push-phase screenshot")

	# fast-forward straight into the boss phase to check that visual too
	instance.live.phase = MatchSim.PHASE_BOSS
	instance.live.boss = MatchSim._spawn_boss(instance.catalog, "potomac")
	instance.live.boss["hp"] = instance.live.boss["hp_max"] * 0.6
	instance.ui.build_requested.emit("battleship_flagship")
	for i in range(20):
		await process_frame
	instance.live.step()
	instance._on_flagship_fire()
	for i in range(5):
		await process_frame
	var img2 := root.get_viewport().get_texture().get_image()
	img2.save_png("/tmp/iron_corridor_boss.png")
	print("saved boss-phase screenshot, boss_hp_pct=", instance.live.boss_hp_pct())

	quit()
