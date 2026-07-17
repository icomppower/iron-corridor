class_name DataLoader
extends RefCounted
## Loads rules-as-data JSON into plain Dictionaries/Arrays. Zero Node deps.

static func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataLoader: failed to open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)

static func index_by_id(arr: Array) -> Dictionary:
	var out := {}
	for item in arr:
		out[item["id"]] = item
	return out

static func load_all_levels(dir_path: String) -> Array:
	var levels := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("DataLoader: failed to open dir %s" % dir_path)
		return levels
	dir.list_dir_begin()
	var fname := dir.get_next()
	var names := []
	while fname != "":
		if fname.ends_with(".json"):
			names.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var lvl = load_json(dir_path.path_join(n))
		if lvl != null:
			levels.append(lvl)
	return levels
