class_name SkillProgress
extends RefCounted
## Persisted cross-stage meta-progress (skill unlocks + meta points).
## Interactive presentation layer only — MatchSim.run()/the harness never
## touches this, which is what keeps Oracle #4 (unlocks are power, not
## keys) true by construction rather than by convention.

const SAVE_PATH := "user://skill_progress.json"
const WIN_POINTS := 50.0
const LOSS_POINTS := 15.0

static func load_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"unlocked": [], "meta_points": 0.0}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null:
		return {"unlocked": [], "meta_points": 0.0}
	return data

static func save_state(state: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f.close()

static func award_for_result(state: Dictionary, result: String) -> Dictionary:
	state["meta_points"] = float(state.get("meta_points", 0.0)) + (WIN_POINTS if result == "WIN" else LOSS_POINTS)
	return state

static func can_unlock(state: Dictionary, catalog: Catalog, skill_id: String) -> bool:
	if not catalog.skills.has(skill_id):
		return false
	var unlocked: Array = state.get("unlocked", [])
	if unlocked.has(skill_id):
		return false
	return float(state.get("meta_points", 0.0)) >= float(catalog.skills[skill_id]["cost"])

static func unlock(state: Dictionary, catalog: Catalog, skill_id: String) -> bool:
	if not can_unlock(state, catalog, skill_id):
		return false
	state["meta_points"] = float(state["meta_points"]) - float(catalog.skills[skill_id]["cost"])
	var unlocked: Array = state.get("unlocked", [])
	unlocked.append(skill_id)
	state["unlocked"] = unlocked
	return true
