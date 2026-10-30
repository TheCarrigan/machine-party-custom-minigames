extends "res://autoloads/globals.gd"
# custom_minigames wrapper (calls the original first; see compat.gd for what it relies on)
# The game drops negative minigame IDs when it loads the saved custom playlist.
# Let the original load, then rebuild the list from the same file keeping custom
# minigames that are registered right now (unknown IDs are still dropped).

func load_playlist():
	super()
	var cm = _custom_minigames()
	if cm == null or not FileAccess.file_exists(playlist_save_path):
		return
	var f := FileAccess.open(playlist_save_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_line())
	if typeof(parsed) != TYPE_ARRAY:
		return
	var has_custom := false
	var rebuilt: Array[MinigameListResource] = []
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := int(entry.get("gid", 0))
		var rounds := int(entry.get("r", 1))
		if cm.is_custom(id):
			has_custom = true
			rebuilt.append(MinigameListResource.create(id, rounds))
		elif id >= 0 and MinigameIdentifier.values().has(id):
			rebuilt.append(MinigameListResource.create(id, rounds))
	if has_custom and not rebuilt.is_empty():
		session_playlist = rebuilt


func _custom_minigames():
	var loader = get_node_or_null("/root/ModLoader")
	return null if loader == null else loader.registry("custom_minigames").get("api", null)
