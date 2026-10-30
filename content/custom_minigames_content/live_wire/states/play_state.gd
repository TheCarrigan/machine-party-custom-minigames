extends State

func init() -> void:
	pass

func can_leave() -> bool:
	return true

func can_enter() -> bool:
	return true

func enter(_msg: Dictionary = {}) -> void:
	state_time = 0.0

func exit(_msg: Dictionary = {}) -> void:
	pass

func update(_delta: float) -> void:
	pass

func update_physics(_delta: float) -> void:
	pass
