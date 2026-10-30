extends Node
# Custom Minigames framework for Machine Party.
# Lets other mods register new minigames. Custom minigames get negative IDs (-1, -2, ...),
# which the vanilla game ignores when it loads saved playlists. When one is due to play,
# its scene is lent to an unused built-in slot so the game's own loader can run it.

const API_VERSION := 1
const VERSION_TAG := "+custom-minigames.1"
const MAX_CUSTOM := 20

# Unused built-in slot (Shape Cutter): has a scene path but is not in the shipped playlist.
const PROXY_ID := 6
const PROXY_SCENE_PATH := "res://minigames/shape_cutter/shape_cutter.tscn"

const GAME_SCRIPT := "res://scripts/scenes/game/game.gd"
const LOCAL_GAME_SCRIPT := "res://scenes/local_game/script/local_game.gd"

var _loader
var _defs: Dictionary = {}        # id -> definition
var _ids_by_key: Dictionary = {}  # key -> id
var _next_id := -1
var _scenes: Dictionary = {}      # id -> PackedScene (kept alive)
var _version_tagged := false
var _pending_playlist: Array = []
var _game_ready := false
var _icons: Dictionary = {}       # id -> Texture2D
var _compat = null                # compat.gd (compatibility contract)
var _disabled := false
var _problems: Array = []         # why it's disabled, or problems other mods reported
var _untested_version := ""
var _add_to_standard := true      # settings.cfg [playlist] add_custom_to_standard_playlist
var _only_custom := false         # settings.cfg [playlist] only_custom_minigames
var _lent_id := 0                 # custom minigame currently using the proxy slot

signal game_ready

const PICKER_SCRIPT := "res://minigames/intermission_new/components/intermission_game_picker.gd"

# vanilla script -> our wrapper (each wrapper calls the original first).
# EARLY wrappers must be in place before the game's singletons are created (Globals is one).
const EARLY_OVERRIDES := {
	"res://autoloads/globals.gd": "overrides/globals_override.gd",
}
# The rest are applied once the singletons exist. Doing game.gd any earlier makes the
# engine mis-compile the debug tools' `var game_instance: Game` line ("Compiler bug:
# unresolved assign"). None of these scripts is loaded before a scene needs it.
const OVERRIDES := {
	"res://scripts/scenes/game/game.gd": "overrides/game_override.gd",
	"res://scenes/local_game/script/local_game.gd": "overrides/local_game_override.gd",
	"res://minigames/intermission_new/components/intermission_game_picker.gd": "overrides/game_picker_override.gd",
	"res://scenes/lobby/components/playlist_handler.gd": "overrides/playlist_handler_override.gd",
	"res://modules/minigame_list_handler/components/minigame_list_item/minigame_list_item.gd": "overrides/list_item_override.gd",
	"res://minigames/shared/states/round_state.gd": "overrides/round_state_override.gd",
}
const INTERMISSION_MANAGER_SCRIPT := "res://minigames/intermission_new/components/intermission_manager.gd"
const FALLBACK_ICON := "res://minigames/intermission_new/minigame_icons/placeholder_icons/minigame icon_placeholder11.png"


func _mod_init(loader) -> void:
	_loader = loader
	loader.registry("custom_minigames")["api"] = self
	var dir: String = loader.dir_of("custom_minigames")
	_load_settings(dir.path_join("settings.cfg"))
	_compat = loader.compile(dir.path_join("compat.gd"))
	var problems: Array = []
	if _compat == null:
		problems.append("compat.gd failed to load")
	else:
		problems.append_array(_compat.check())
		problems.append_array(_compat.check_proxy_slot(PROXY_ID, PROXY_SCENE_PATH))
	if FileAccess.file_exists(dir.path_join("SIMULATE_GAME_UPDATE")):
		problems.append("simulated game update (test switch file present)")
	if not problems.is_empty():
		_disable(problems)
		return
	_apply_overrides(EARLY_OVERRIDES)
	note("framework v%s ready (api %d)" % ["0.3.2", API_VERSION])


func _mod_ready(_loader_ref) -> void:
	_loader.on_main_menu(_on_main_menu)
	if _disabled:
		_apply_when_game_ready()   # still signal "ready" so waiting mods don't hang
		return
	_apply_overrides(OVERRIDES)
	_loader.on_scene_script(INTERMISSION_MANAGER_SCRIPT, _on_intermission_manager_added)
	_apply_when_game_ready()


func _apply_overrides(table: Dictionary) -> void:
	for vanilla in table:
		if _loader.override_script_rel("custom_minigames", vanilla, table[vanilla]) == null:
			note("WARNING: could not wrap " + vanilla)


# --- public API -------------------------------------------------------------

## Register a custom minigame. Required keys: "key" (unique string), "scene" (res:// path
## to a PackedScene whose root extends Minigame). Optional: "version" (goes into the lobby tag),
## "name", "tagline", "rounds", "icon", "brief_from", "brief_headers", "brief_pages".
## Returns the assigned negative ID, or 0 on failure.
func register(def: Dictionary) -> int:
	if _disabled:
		note("register: framework is switched off (game changed) - '%s' not added" % def.get("key", "?"))
		return 0
	var key := str(def.get("key", ""))
	if key.is_empty() or not def.has("scene"):
		note("register: needs 'key' and 'scene'")
		return 0
	if _ids_by_key.has(key):
		return _ids_by_key[key]
	if _defs.size() >= MAX_CUSTOM:
		note("register: limit of %d custom minigames reached" % MAX_CUSTOM)
		return 0
	var id := _next_id
	_next_id -= 1
	var d := def.duplicate(true)
	d["id"] = id
	d["rounds"] = int(d.get("rounds", 2))
	_defs[id] = d
	_ids_by_key[key] = id
	if _add_to_standard or _only_custom:
		_add_to_default_playlist(id, d["rounds"])
	note("registered '%s' as id %d" % [key, id])
	return id


func is_custom(id: int) -> bool:
	return _defs.has(id)


func get_def(id: int) -> Dictionary:
	return _defs.get(id, {})


func all_ids() -> Array:
	return _defs.keys()


func display_name(id: int) -> String:
	return str(_defs.get(id, {}).get("name", "Custom minigame"))


func tagline(id: int) -> String:
	return str(_defs.get(id, {}).get("tagline", ""))


func icon_texture(id: int) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var path := str(_defs.get(id, {}).get("icon", ""))
	var tex = null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			tex = load(path)
	elif path != "" and FileAccess.file_exists(path):
		# a PNG shipped in a mod's own folder (not imported by the engine)
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if not (tex is Texture2D):
		tex = load(FALLBACK_ICON)
	_icons[id] = tex
	return tex


## Intermission: the picker grid, grabbed icon and briefing screen all look minigames up in
## the manager's icon-resource list. Add one entry per custom minigame before they read it.
## Briefing pages and controls come from the definition, or are copied from a built-in
## minigame named in "brief_from" (its MinigameIdentifier value).
func _on_intermission_manager_added(manager: Node) -> void:
	var list = manager.get("minigame_icon_resource_array")
	if list == null:
		note("WARNING: intermission manager has no icon list")
		return
	for id in _defs:
		var exists := false
		for r in list:
			if int(r.identifier) == int(id):
				exists = true
				break
		if exists:
			continue
		var res := Intermission_IconResource.new()
		res.identifier = id
		res.icon_texture = icon_texture(id)
		var d: Dictionary = _defs[id]
		if d.has("brief_from"):
			var from_id = d["brief_from"]
			if from_id is String:
				from_id = Globals.MinigameIdentifier.get(from_id, -999)
			for r in list:
				if int(r.identifier) == int(from_id):
					res.brief_instructions_content_pages = r.brief_instructions_content_pages.duplicate()
					res.brief_instructions_header_pages = r.brief_instructions_header_pages.duplicate()
					res.controls_data = r.controls_data.duplicate()
					break
		var pages: Array[String] = []
		for t in d.get("brief_pages", []):
			pages.append(str(t))
		var headers: Array[String] = []
		for t in d.get("brief_headers", []):
			headers.append(str(t))
		if not pages.is_empty():
			res.brief_instructions_content_pages = pages
			res.brief_instructions_header_pages = headers
		list.append(res)
	note("intermission: added %d custom icon entries" % _defs.size())


## Puts a custom minigame's name and icon on a lobby list entry.
func style_list_item(item, id: int) -> void:
	if item == null:
		return
	item.name_label.text = display_name(id)
	item.minigame_icon.texture = icon_texture(id)


## Called by the game overrides just before the game loads a minigame. Lends the custom
## scene to the proxy slot's path and returns the proxy ID for the game's loader to use.
func prepare_proxy(id: int) -> int:
	var scene := _get_scene(id)
	if scene == null:
		note("prepare_proxy: no scene for id %d" % id)
		return PROXY_ID
	scene.take_over_path(PROXY_SCENE_PATH)
	_lent_id = id
	note("lending proxy slot to id %d" % id)
	return PROXY_ID


## The custom minigame being played right now, or 0. Works at any point of loading: while the
## game still holds the borrowed slot's ID, this returns the custom minigame using that slot.
func current_custom_id() -> int:
	var g = _globals()
	if g == null:
		return 0
	var id := int(g.current_minigame_identifier)
	if is_custom(id):
		return id
	if id == PROXY_ID and _lent_id != 0:
		return _lent_id
	return 0


func note(msg: String) -> void:
	if _loader:
		_loader.note("custom_minigames: " + msg)
	else:
		print("custom_minigames: " + msg)


# --- internals --------------------------------------------------------------

func _get_scene(id: int) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var path := str(_defs.get(id, {}).get("scene", ""))
	if path.is_empty():
		return null
	# Load a private copy so taking over the proxy path never moves a shared resource.
	var scene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if scene is PackedScene:
		_scenes[id] = scene
		return scene
	return null


func _globals():
	if not is_inside_tree():
		return null
	var g = get_node_or_null("/root/Globals")
	if g == null or str(g.game_version) == "":
		return null
	return g


func _add_to_default_playlist(id: int, rounds: int) -> void:
	var g = _globals()
	if g == null or not _game_ready:
		_pending_playlist.append([id, rounds])
		return
	for mlr in g.default_playlist:
		if int(mlr.game_identifier) == id:
			return
	g.default_playlist.append(MinigameListResource.create(id, rounds))


## Waits until the game's Globals singleton exists, then tags the lobby version and
## applies queued playlist entries. Other mods can `await cm.wait_ready()`.
func _apply_when_game_ready() -> void:
	for i in 600:
		var g = _globals()
		if g != null:
			if _disabled:
				_game_ready = true
				game_ready.emit()
				return
			var base_version := str(g.game_version)
			if _compat != null and not base_version in _compat.TESTED_GAME_VERSIONS:
				_untested_version = base_version
				note("WARNING: game version %s has not been tested with this mod" % base_version)
			if not base_version.contains(VERSION_TAG):
				g.game_version = base_version + lobby_tag()
			_version_tagged = true
			note("lobby version set to " + str(g.game_version))
			_game_ready = true
			for e in _pending_playlist:
				_add_to_default_playlist(e[0], e[1])
			_pending_playlist.clear()
			if _only_custom and not _defs.is_empty():
				var keep: Array = []
				for mlr in g.default_playlist:
					if is_custom(int(mlr.game_identifier)):
						keep.append(mlr)
				g.default_playlist.clear()
				g.default_playlist.append_array(keep)
				note("settings: only_custom_minigames - standard playlist is custom minigames only")
			game_ready.emit()
			return
		await get_tree().process_frame
	note("WARNING: game never became ready; custom minigames and lobby tag not applied")


## Lobby version suffix: the framework tag plus a short fingerprint of which custom minigames
## (and versions) are installed, so players can only meet when they can load the same minigames.
func lobby_tag() -> String:
	if _defs.is_empty():
		return VERSION_TAG
	var parts: Array[String] = []
	for id in _defs:
		parts.append("%s@%s" % [_defs[id]["key"], str(_defs[id].get("version", "?"))])
	parts.sort()
	return VERSION_TAG + "." + ",".join(parts).md5_text().substr(0, 6)


func wait_ready() -> void:
	if not _game_ready:
		await game_ready


func is_ready() -> bool:
	return _game_ready


func _load_settings(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		note("settings.cfg not found - using defaults")
		return
	_add_to_standard = bool(cfg.get_value("playlist", "add_custom_to_standard_playlist", true))
	_only_custom = bool(cfg.get_value("playlist", "only_custom_minigames", false))
	note("settings: add_custom_to_standard_playlist=%s only_custom_minigames=%s" % [_add_to_standard, _only_custom])


# --- game-update safety -------------------------------------------------------

func _disable(problems: Array) -> void:
	_disabled = true
	_problems.append_array(problems)
	note("SWITCHED OFF - the installed game doesn't match what this mod was built for:")
	for pr in problems:
		note("  - " + str(pr))


func is_disabled() -> bool:
	return _disabled


func problems() -> Array:
	return _problems.duplicate()


## Lets other mods check their own dependencies with the same contract format as compat.gd.
func check_contract(contract: Dictionary) -> Array:
	if _compat == null:
		return ["compatibility checker unavailable"]
	return _compat.check(contract)


## Lets other mods (e.g. a minigame) put a problem on the main-menu notice.
func report_problem(source: String, text: String) -> void:
	_problems.append("%s: %s" % [source, text])
	note("problem reported by %s: %s" % [source, text])


func notice_text() -> String:
	var lines: Array[String] = []
	if _disabled:
		lines.append("Custom Minigames mod is switched off: this game version changed things it relies on.")
		lines.append("Your game is unaffected. Check for a mod update.")
	elif _untested_version != "":
		lines.append("Custom Minigames: game version %s is untested with this mod." % _untested_version)
	var shown := 0
	for pr in _problems:
		if shown >= 4:
			lines.append("  ...and %d more (see modloader.log)" % (_problems.size() - shown))
			break
		lines.append("  - " + str(pr))
		shown += 1
	return "\n".join(lines)


func _on_main_menu(menu: Node) -> void:
	var text := notice_text()
	if text == "":
		return
	var layer := CanvasLayer.new()
	layer.layer = 45
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 10
	label.offset_top = -12 - 15 * text.count("\n") - 15
	layer.add_child(label)
	menu.add_child.call_deferred(layer)
