extends Node
# Registers the Power Grid minigame with the Custom Minigames framework.
# The scene and scripts live in power_grid.zip (our own files only); they use the
# player character, animations and sounds from the player's own copy of the game.

const KEY := "power_grid"
const SCENE := "res://custom_minigames_content/power_grid/power_grid.tscn"

# Game pieces Power Grid borrows at runtime (from the player's own copy of the game).
const GAME_FILES := [
	"res://minigames/disco_dodge/components/player/disco_dodge_player.tscn",
	"res://modules/state_machine/StateMachine.gd",
	"res://minigames/shared/states/empty_state.gd",
	"res://minigames/shared/states/round_state.gd",
	"res://minigames/shared/states/player_marker_state.gd",
	"res://minigames/shared/states/countdown_state.gd",
	"res://modules/minigame/components/overlay/minigame_overlay.tscn",
	"res://audio/unique/kato/kato_light hum loop.ogg",
]
const GAME_PARTS := {
	"res://modules/minigame/minigame.gd": {
		"methods": {"initialize": 3, "all_players_loaded": 0, "player_disconnected": 1, "cleanup": 0,
			"_on_countdown_started": 0, "_on_countdown_tick": 1, "_on_countdown_expired": 0,
			"set_minigame_sfx_linear_volume_rpc": 1, "set_effects_visibility_rpc": 1},
		"props": ["minigame_overlay", "is_all_player_loaded", "state_machine"],
		"signals": ["minigame_ready", "minigame_finished", "player_scores_finalized"],
	},
	"res://minigames/disco_dodge/components/player/scripts/disco_dodge_player.gd": {
		"load_first": "res://minigames/disco_dodge/components/player/disco_dodge_player.tscn",
		"methods": {"set_player_presence": 1, "teleport_rpc": 1, "set_active_rpc": 1, "kill_rpc": 0},
		"props": ["player_presence", "player_name_label"],
		"signals": ["died"],
	},
	"res://minigames/shared/states/countdown_state.gd": {
		"signals": ["countdown_started", "tick", "expired"],
	},
}


func _mod_init(loader) -> void:
	var dir: String = loader.dir_of(KEY)
	var bots := clampi(int(read_setting(dir.path_join("settings.cfg"), "practice", "bots", 0)), 0, 3)
	loader.registry(KEY)["practice_bots"] = bots
	if not loader.mount_assets(KEY, KEY + ".zip"):
		loader.note("power_grid: content pack missing - not registered")
		return
	var cm = loader.registry("custom_minigames").get("api", null)
	if cm == null:
		loader.note("power_grid: Custom Minigames framework missing")
		return
	if cm.is_disabled():
		return   # the framework's own notice explains why
	var problems: Array = cm.check_contract(GAME_PARTS)
	for path in GAME_FILES:
		if not ResourceLoader.exists(path):
			problems.append("missing game file " + path.get_file())
	if not problems.is_empty():
		for pr in problems:
			cm.report_problem("Power Grid", str(pr))
		loader.note("power_grid: not added - the game changed parts it borrows")
		return
	cm.register({
		"key": KEY,
		"scene": SCENE,
		"version": _mod_version(loader),
		"name": "Power Grid",
		"tagline": "STAND CLEAR",
		"icon": dir.path_join("icon_power_grid.png"),
		"rounds": 2,
		"brief_from": "DiscoDodge",
		"brief_headers": ["POWER GRID", "THE SURGE", "THE EDGE"],
		"brief_pages": [
			"The floor is a grid of power panels.\nPanels flash amber before they surge.",
			"Get off amber panels before they go live.\nEach surge covers more of the floor, and comes faster.",
			"Shoving works. So does gravity.\nWorkers who fall off the floor are out.\nLast worker standing wins.",
		],
	})


func _mod_version(loader) -> String:
	var info = JSON.parse_string(FileAccess.get_file_as_string(loader.dir_of("power_grid").path_join("mod.json")))
	return str(info.get("version", "?")) if info is Dictionary else "?"

## Reads one setting. Uses Godot's ConfigFile; if the file has a mistake (for example text without
## quotes), falls back to reading plain "key=value" lines, so one typo can't switch every option off.
static func read_setting(path: String, section: String, key: String, default_value):
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		return cfg.get_value(section, key, default_value)
	var current := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2).strip_edges()
		elif current == section and line.contains("=") and not line.begins_with(";") and not line.begins_with("#"):
			var k := line.get_slice("=", 0).strip_edges()
			if k == key:
				var v := line.substr(line.find("=") + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
				return int(v) if typeof(default_value) == TYPE_INT and v.is_valid_int() else v
	return default_value
