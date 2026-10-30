extends "res://minigames/shared/states/round_state.gd"
# custom_minigames wrapper (calls the original first; see compat.gd for what it relies on)
# Round intro screen: show the custom minigame's own tagline.

func enter(_msg: Dictionary = {}) -> void:
	super(_msg)  # runs up to its first timer, then carries on by itself
	var loader = get_node_or_null("/root/ModLoader")
	if loader == null:
		return
	var cm = loader.registry("custom_minigames").get("api", null)
	if cm == null:
		return
	var id: int = cm.current_custom_id()
	if id == 0 or cm.tagline(id) == "":
		return
	var label = owner.minigame_overlay.countdown_detail_label
	label.text = cm.tagline(id)
	if label.get_child_count() > 0 and "original_text" in label.get_child(0):
		label.get_child(0).original_text = cm.tagline(id)
