extends "res://modules/minigame_list_handler/components/minigame_list_item/minigame_list_item.gd"
# custom_minigames wrapper (calls the original first; see compat.gd for what it relies on)
# Drag-to-reorder re-reads names and icons from the built-in tables; fix custom entries after it.

func _drop_data(_position: Vector2, _data: Variant) -> void:
	super(_position, _data)
	var loader = get_node_or_null("/root/ModLoader")
	if loader == null:
		return
	var cm = loader.registry("custom_minigames").get("api", null)
	if cm != null and cm.is_custom(int(minigame_identifier)):
		cm.style_list_item(self, int(minigame_identifier))
