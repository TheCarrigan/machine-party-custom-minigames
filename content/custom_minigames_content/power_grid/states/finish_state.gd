extends State
# Hand control back to the game when the minigame is over.

func init() -> void:
	pass

func can_leave() -> bool:
	return true

func can_enter() -> bool:
	return true

func enter(_msg: Dictionary = {}) -> void:
	state_time = 0.0
	# runs on every player's machine: fade this minigame out locally, then hand back to the game
	owner.set_effects_visibility_rpc(false)
	owner.set_minigame_sfx_linear_volume_rpc(0.0)
	var overlay = owner.minigame_overlay
	overlay.set_screens_visibility(false)   # black screen while the game moves on
	overlay.set_background(true, Color.BLACK)
	if multiplayer.is_server():
		owner.minigame_finished.emit(multiplayer.get_unique_id())

func exit(_msg: Dictionary = {}) -> void:
	pass

func update(_delta: float) -> void:
	pass

func update_physics(_delta: float) -> void:
	pass
