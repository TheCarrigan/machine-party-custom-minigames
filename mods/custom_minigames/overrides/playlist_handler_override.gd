extends "res://scenes/lobby/components/playlist_handler.gd"
# custom_minigames wrapper (calls the original first; see compat.gd for what it relies on)
# Lobby playlist editor: list custom minigames next to the built-in ones, show their
# names and icons, and keep them when loading the current or default playlist.

func _ready() -> void:
	super()
	var cm = _custom_minigames()
	if cm == null:
		return
	for id in cm.all_ids():
		add_minigame_button(MinigameListItem.BehaviourType.All, id)
	load_current_playlist()


func add_minigame_button(_behaviour, minigame_id, rounds: int = 1):
	super(_behaviour, minigame_id, rounds)
	var cm = _custom_minigames()
	if cm == null or not cm.is_custom(int(minigame_id)):
		return
	var list: Array = all_minigames_list_items if _behaviour == MinigameListItem.BehaviourType.All else selected_minigames_list_items
	if list.is_empty():
		return
	cm.style_list_item(list.back(), int(minigame_id))


func load_current_playlist():
	for item in selected_minigames_list_items:
		if is_instance_valid(item):
			item.free()
	selected_minigames_list_items.clear()
	for button in all_minigames_list_items:
		button.set_inactive(false)
	for mlr in Globals.session_playlist:
		var id := int(mlr.game_identifier)
		if not _is_allowed(id):
			continue
		add_minigame_button(MinigameListItem.BehaviourType.Selected, id, mlr.total_rounds)
		for button in all_minigames_list_items:
			if int(button.minigame_identifier) == id:
				button.set_inactive(true)
				break


func _on_default_button_pressed():
	_on_reset_button_pressed()
	for mlr in Globals.default_playlist:
		var id := int(mlr.game_identifier)
		if not _is_allowed(id):
			continue
		for button in all_minigames_list_items:
			if int(button.minigame_identifier) == id:
				_on_minigame_add_pressed(button, false)
				break
	for mlr in Globals.default_playlist:
		for selected in selected_minigames_list_items:
			if int(selected.minigame_identifier) == int(mlr.game_identifier):
				selected.set_rounds(mlr.total_rounds)
				break


func _is_allowed(id: int) -> bool:
	if Globals.CustomMinigamesWhitelist.has(id):
		return true
	var cm = _custom_minigames()
	return cm != null and cm.is_custom(id)


func _custom_minigames():
	var loader = get_node_or_null("/root/ModLoader")
	return null if loader == null else loader.registry("custom_minigames").get("api", null)
