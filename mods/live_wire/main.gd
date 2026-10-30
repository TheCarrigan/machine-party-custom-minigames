extends Node
# Registers the Live Wire minigame with the Custom Minigames framework.
# The scene and scripts live in live_wire.zip (our own files only); they use the
# player character, animations and sounds from the player's own copy of the game.

const SCENE := "res://custom_minigames_content/live_wire/live_wire.tscn"

# Game pieces Live Wire borrows at runtime (from the player's own copy of the game).
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

var _loader
var _id := 0


func _mod_init(loader) -> void:
	_loader = loader
	var settings: String = loader.dir_of("live_wire").path_join("settings.cfg")
	var bots := clampi(int(read_setting(settings, "practice", "bots", 0)), 0, 3)
	var arena := str(read_setting(settings, "arena", "arena", "rotate")).strip_edges().to_lower()
	loader.registry("live_wire")["practice_bots"] = bots
	loader.registry("live_wire")["arena"] = arena
	if not loader.mount_assets("live_wire", "live_wire.zip"):
		loader.note("live_wire: content pack missing - not registered")
		return
	var cm = loader.registry("custom_minigames").get("api", null)
	if cm == null:
		loader.note("live_wire: Custom Minigames framework missing")
		return
	if cm.is_disabled():
		return   # the framework's own notice explains why
	var problems: Array = cm.check_contract(GAME_PARTS)
	for path in GAME_FILES:
		if not ResourceLoader.exists(path):
			problems.append("missing game file " + path.get_file())
	if not problems.is_empty():
		for pr in problems:
			cm.report_problem("Live Wire", str(pr))
		loader.note("live_wire: not added - the game changed parts it borrows")
		return
	_id = cm.register({
		"key": "live_wire",
		"scene": SCENE,
		"version": _mod_version(loader),
		"name": "Live Wire",
		"tagline": "DON'T HOLD THE LINE",
		"icon": loader.dir_of("live_wire").path_join("icon_live_wire.png"),
		"rounds": 2,
		"brief_from": "DiscoDodge",
		"brief_headers": ["LIVE WIRE", "THE FUSE", "THE EDGE"],
		"brief_pages": [
			"One worker is holding a live cable.\nTouch another worker to pass it on.",
			"The fuse is hidden. When it runs out, whoever holds the cable is electrocuted.\nThe cable crackles harder just before it blows.",
			"Shoving works. So does gravity.\nWorkers who fall off the floor are out.\nLast worker standing wins.",
		],
	})


func _mod_version(loader) -> String:
	var info = JSON.parse_string(FileAccess.get_file_as_string(loader.dir_of("live_wire").path_join("mod.json")))
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
