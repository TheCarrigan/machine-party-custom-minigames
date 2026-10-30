extends RefCounted
# Compatibility contract: everything in the game that the framework's wrappers rely on.
# Checked before any wrapper is installed. If a game update removes or changes any of it,
# the framework stays switched off instead of risking a broken game.
# Format: script path -> { "methods": {name: argument count}, "props": [...], "consts": [...],
#                         "signals": [...], "load_first": scene path (optional, see check()) }

const TESTED_GAME_VERSIONS := ["v2.1.2"]

const CONTRACT := {
	"res://autoloads/globals.gd": {
		"methods": {"load_playlist": 0, "save_playlist": 0},
		"props": ["playlist_save_path", "session_playlist", "default_playlist", "game_version", "current_minigame_identifier"],
		"consts": ["MinigameIdentifier", "MinigamePaths", "CustomMinigamesWhitelist"],
	},
	"res://scripts/scenes/game/game.gd": {
		"methods": {"load_minigame": 3, "generate_session_playlist": 0, "_on_host_minigame_loaded": 0,
			"_on_minigame_loaded": 1, "_host_minigame_loaded_rpc": 1},
		"props": ["session_minigame_list", "session_minigame_rounds", "total_games_count", "session_minigame_played_list"],
	},
	"res://scenes/local_game/script/local_game.gd": {
		"methods": {"load_minigame": 3, "generate_session_playlist": 0},
		"props": ["session_minigame_list", "session_minigame_rounds", "total_games_count", "session_minigame_played_list"],
	},
	"res://minigames/intermission_new/components/intermission_game_picker.gd": {
		"methods": {"pick_next_game": 2, "setup_icons_from_data_rpc": 4, "move_viewfinder": 2, "setup_minigame_pick_host": 0},
		"props": ["intermission_manager", "active_icons", "next_minigame_label", "next_minigame_label_higher", "debug_active_identifier"],
	},
	"res://minigames/intermission_new/components/intermission_manager.gd": {
		"props": ["minigame_icon_resource_array", "game", "picker"],
	},
	"res://minigames/intermission_new/components/intermission_icon_resource.gd": {
		"props": ["identifier", "icon_texture", "brief_instructions_content_pages", "brief_instructions_header_pages", "controls_data"],
	},
	"res://scenes/lobby/components/playlist_handler.gd": {
		"methods": {"_ready": 0, "add_minigame_button": 3, "load_current_playlist": 0, "_on_default_button_pressed": 0,
			"_on_reset_button_pressed": 0, "_on_minigame_add_pressed": 2},
		"props": ["all_minigames_list_items", "selected_minigames_list_items"],
	},
	"res://modules/minigame_list_handler/components/minigame_list_item/minigame_list_item.gd": {
		"methods": {"_drop_data": 2, "set_rounds": 1, "set_inactive": 1},
		"props": ["name_label", "minigame_icon", "minigame_identifier"],
	},
	"res://minigames/shared/states/round_state.gd": {
		"methods": {"enter": 1},
	},
	"res://scripts/resources/minigame_list_resource.gd": {
		"methods": {"create": 2},
		"props": ["game_identifier", "total_rounds"],
	},
}


## Returns a list of human-readable problems; empty means the installed game matches.
static func check(contract: Dictionary = CONTRACT) -> Array:
	var problems: Array = []
	for path in contract:
		if not ResourceLoader.exists(path):
			problems.append("missing script " + path.get_file())
			continue
		var want: Dictionary = contract[path]
		# Some game scripts sit in a loop with their own scene (script -> other classes -> scene ->
		# script). Loading such a script on its own caches that scene half-loaded, so load the
		# scene first, the way the game does.
		if want.has("load_first"):
			if not ResourceLoader.exists(want["load_first"]):
				problems.append("missing scene " + str(want["load_first"]).get_file())
				continue
			load(want["load_first"])
		var s = load(path)
		if not (s is Script):
			problems.append("can't load " + path.get_file())
			continue
		var methods := {}
		for m in s.get_script_method_list():
			methods[m.name] = m.args.size()
		for name in want.get("methods", {}):
			if not methods.has(name):
				problems.append("%s: method %s() is gone" % [path.get_file(), name])
			elif methods[name] != int(want["methods"][name]):
				problems.append("%s: %s() now takes %d arguments (expected %d)" % [path.get_file(), name, methods[name], want["methods"][name]])
		var props := {}
		for p in s.get_script_property_list():
			props[p.name] = true
		for name in want.get("props", []):
			if not props.has(name):
				problems.append("%s: variable %s is gone" % [path.get_file(), name])
		var consts: Dictionary = s.get_script_constant_map()
		for name in want.get("consts", []):
			if not consts.has(name):
				problems.append("%s: constant %s is gone" % [path.get_file(), name])
		var signals := {}
		for sg in s.get_script_signal_list():
			signals[sg.name] = true
		for name in want.get("signals", []):
			if not signals.has(name):
				problems.append("%s: signal %s is gone" % [path.get_file(), name])
	return problems


## The framework borrows the unused Shape Cutter slot to load custom scenes.
static func check_proxy_slot(proxy_id: int, proxy_path: String) -> Array:
	var g = load("res://autoloads/globals.gd")
	if g == null:
		return ["can't load globals.gd"]
	var consts: Dictionary = g.get_script_constant_map()
	var ids = consts.get("MinigameIdentifier", {})
	var paths = consts.get("MinigamePaths", {})
	if typeof(ids) != TYPE_DICTIONARY or ids.get("ShapeCutter", -1) != proxy_id:
		return ["the borrowed minigame slot (Shape Cutter) has moved"]
	if typeof(paths) != TYPE_DICTIONARY or str(paths.get(proxy_id, "")) != proxy_path:
		return ["the borrowed minigame slot's scene path changed"]
	var whitelist = consts.get("CustomMinigamesWhitelist", [])
	if proxy_id in whitelist:
		return ["the borrowed minigame slot is now a real minigame"]
	return []
