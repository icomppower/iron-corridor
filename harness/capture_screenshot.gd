extends SceneTree
## Dev-only visual QA capture. Not part of CI. Run with:
##   godot --path . --script res://harness/capture_screenshot.gd
## (must NOT pass --headless, or the viewport texture will be blank).

func _initialize() -> void:
	var save_path := "user://skill_progress.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	var main_scene: PackedScene = load("res://presentation/Main.tscn")
	var instance: Node = main_scene.instantiate()
	root.add_child(instance)
	for i in range(10):
		await process_frame

	instance.skill_state["meta_points"] = 500.0
	instance.ui.refresh_skills(instance.catalog, instance.skill_state)
	instance.ui._skills_panel.visible = true
	for i in range(5):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/iron_corridor_skills.png")
	print("saved skills panel screenshot")

	instance.ui.skill_unlock_requested.emit("high_altitude_bombing")
	for i in range(5):
		await process_frame
	var img2 := root.get_viewport().get_texture().get_image()
	img2.save_png("/tmp/iron_corridor_skills_after_unlock.png")
	print("saved post-unlock screenshot, unlocked=", instance.skill_state["unlocked"])

	quit()
