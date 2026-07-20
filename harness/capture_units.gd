extends SceneTree
## Dev-only visual QA: lay the 12 unit types out in a spaced grid so each
## silhouette + label can be eyeballed individually. Run WITHOUT --headless:
##   godot --path . --script res://harness/capture_units.gd

func _initialize() -> void:
	var main: Node = load("res://presentation/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(10):
		await process_frame

	var catalog: Catalog = main.catalog
	for uid in catalog.units.keys():
		for _n in range(2):
			MatchSim._materialize(main.live.player, catalog, uid)
	main.live.started = true
	main.ships.sync(main.live, catalog)

	# Override the sync'd lane positions: 2 rows of 6, spread along X so no two
	# silhouettes overlap. Keep each unit's layer height so subs/planes sit right.
	var uids: Array = catalog.units.keys()
	for i in range(uids.size()):
		var uid: String = uids[i]
		var entry: Dictionary = main.ships._nodes["player:%s" % uid]
		var col: int = i % 6
		var rowz: float = -3.5 if i < 6 else 3.5
		var y := 0.4
		match String(catalog.units[uid].get("layer", "surface")):
			"air": y = 2.6
			"periscope": y = 0.05
			"deep": y = -0.55
		entry["root"].position = Vector3(-8.0 + col * 3.2, y, rowz)

	var rig: CameraRig = main.camera_rig
	rig.position = Vector3(0.5, 0, 0)
	rig._distance = 22.0
	rig._apply_distance()
	for i in range(8):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/iron_corridor_units_grid.png")

	# Closer pass over the left cluster to check label legibility at play zoom.
	rig.position = Vector3(-1.0, 0, 0)
	rig._distance = 13.0
	rig._apply_distance()
	for i in range(8):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/iron_corridor_units_close.png")
	print("saved unit captures")
	quit()
