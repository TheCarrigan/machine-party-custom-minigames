extends "res://scripts/scenes/game/game.gd"
# custom_minigames wrapper (calls the original first; see compat.gd for what it relies on)
# Wraps the game's minigame loader so custom (negative-ID) minigames load through
# the framework's proxy slot. Built-in minigames go straight to the original code.

# While a custom minigame is loading, the game's "current minigame" briefly holds the borrowed
# slot's ID. The host tells the other players which minigame to load by reading that value, so
# those two messages are wrapped to send the custom ID instead (found by the networked session test:
# clients loaded the real Shape Cutter).
var _cm_loading_custom := 0


func _on_host_minigame_loaded():
	var restore = _cm_send_custom_id()
	super()
	_cm_restore_id(restore)


func _on_minigame_loaded(_network_id: int):
	var restore = _cm_send_custom_id()
	super(_network_id)
	_cm_restore_id(restore)


func _cm_send_custom_id():
	var cm = _custom_minigames()
	if cm == null or _cm_loading_custom == 0:
		return null
	var current := int(GameManager.current_minigame_identifier)
	if current != cm.PROXY_ID:
		return null
	GameManager.set("current_minigame_identifier", _cm_loading_custom)
	return current


func _cm_restore_id(restore) -> void:
	if restore != null:
		GameManager.set("current_minigame_identifier", restore)


func load_minigame(minigame_identifier: Globals.MinigameIdentifier, _is_round: bool, _total_rounds: int = -1):
	var cm = _custom_minigames()
	if cm == null or not cm.is_custom(int(minigame_identifier)):
		_cm_loading_custom = 0
		await super(minigame_identifier, _is_round, _total_rounds)
		return
	var custom_id := int(minigame_identifier)
	_cm_loading_custom = custom_id
	var proxy: int = cm.prepare_proxy(custom_id)
	await super(proxy, _is_round, _total_rounds)
	Globals.set("current_minigame_identifier", custom_id)
	GameManager.set("current_minigame_identifier", custom_id)


func _custom_minigames():
	var loader = get_node_or_null("/root/ModLoader")
	if loader == null:
		return null
	return loader.registry("custom_minigames").get("api", null)


# Custom-playlist sessions: the original filters the host's playlist through the built-in
# allowed list, which drops custom minigames. Put them back in at random positions
# (the original always shuffles too).
func generate_session_playlist():
	super()
	var cm = _custom_minigames()
	if cm == null or not GameManager.custom_game or GameManager.arcade_game:
		return
	for mlr in Globals.session_playlist:
		var id := int(mlr.game_identifier)
		if cm.is_custom(id) and not session_minigame_list.has(id):
			session_minigame_list.insert(randi_range(0, session_minigame_list.size()), id)
			session_minigame_rounds[id] = max(int(mlr.total_rounds), 1)
	total_games_count = session_minigame_list.size()
