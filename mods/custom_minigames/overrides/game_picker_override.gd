extends "res://minigames/intermission_new/components/intermission_game_picker.gd"
# custom_minigames wrapper (calls the original first; see compat.gd for what it relies on)
# The original pick_next_game turns the chosen ID back into a minigame by searching the
# built-in list and falls back to the first built-in one, so for custom minigames it would
# load and point at the wrong game. Built-in picks go to the original; custom picks are
# handled here with the same steps, using the custom cell swapped into the grid.

func pick_next_game(index: int, random_active_index_icon_index: int):
	var cm = _cm()
	if cm == null or not cm.is_custom(index):
		super(index, random_active_index_icon_index)
		return
	intermission_manager.game.set("session_next_minigame_index", index)
	intermission_manager.game.set("session_next_minigame_identifier", index)
	set("debug_active_identifier", index)
	var text := tr("LOC_IM_NEXT_SIMULATION") % cm.display_name(index)
	next_minigame_label.text = text
	next_minigame_label_higher.text = text
	var grid_index := 0
	for icon in active_icons:
		if int(icon.minigame_identifier) == index:
			grid_index = icon.icons_array_assigned_index
			break
	move_viewfinder(grid_index, false)


# The picker grid has 15 cells, filled from the built-in allowed list only. Before the
# original builds it (on every player, from the data the host sent), swap each custom
# minigame in this session into a cell held by a built-in minigame that isn't in the
# playlist. The choice depends only on the shared data, so every player gets the same grid.
@rpc("authority", "call_local", "reliable")
func setup_icons_from_data_rpc(minigame_picker_data: Array[Dictionary], _last_minigame_identifier: Globals.MinigameIdentifier, _next_minigame_identifier: Globals.MinigameIdentifier, random_active_index_icon_index: int):
	var cm = _cm()
	if cm != null:
		_insert_custom_cells(cm, minigame_picker_data, int(_last_minigame_identifier), int(_next_minigame_identifier))
	super(minigame_picker_data, _last_minigame_identifier, _next_minigame_identifier, random_active_index_icon_index)


func _insert_custom_cells(cm, data: Array[Dictionary], last_id: int, next_id: int) -> void:
	var game = intermission_manager.game
	var session: Array = game.session_minigame_list
	var played: Array = game.get("session_minigame_played_list") if game.get("session_minigame_played_list") != null else []
	var cells: int = min(15, data.size())
	var ids: Array = cm.all_ids()
	ids.sort()
	ids.reverse()  # -1, -2, ... in registration order
	for id in ids:
		if not (session.has(id) or played.has(id) or id == next_id or id == last_id):
			continue
		var already := false
		for i in cells:
			if int(data[i].get("_minigame_identifier", 0)) == id:
				already = true
				break
		if already:
			continue
		for i in range(cells - 1, -1, -1):
			var cell_id := int(data[i].get("_minigame_identifier", 0))
			if cm.is_custom(cell_id) or data[i].get("_is_in_playlist", false):
				continue
			if cell_id == next_id or cell_id == last_id:
				continue
			data[i] = {
				"_minigame_identifier": id,
				"_is_played_already": played.has(id),
				"_is_in_playlist": session.has(id) or id == next_id,
			}
			break


func _cm():
	var loader = get_node_or_null("/root/ModLoader")
	return null if loader == null else loader.registry("custom_minigames").get("api", null)
