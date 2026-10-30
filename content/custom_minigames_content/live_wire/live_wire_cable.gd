extends Node3D
# The live cable: hangs from above onto whoever holds it, hums, sparks, and flares on a zap.

@export var light: OmniLight3D
@export var sparks: GPUParticles3D
@export var plug: Node3D
@export var hum: AudioStreamPlayer3D
@export var ring: Node3D                 # glowing ring at the holder's feet, so it reads from far away
@export var height_offset: float = 2.0
@export var base_light_energy: float = 3.0

var _target: Node3D = null
var _warning := false
var _flare := 0.0


func _ready() -> void:
	visible = false
	if hum:
		hum.finished.connect(func(): if visible: hum.play())


func attach_to(node: Node3D) -> void:
	_target = node
	visible = node != null
	if hum:
		if visible and not hum.playing:
			hum.play()
		elif not visible:
			hum.stop()


func set_warning(on: bool) -> void:
	_warning = on
	if hum:
		hum.pitch_scale = 1.35 if on else 1.0


func zap() -> void:
	_flare = 1.0
	if sparks:
		sparks.restart()


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		if visible:
			attach_to(null)
		return
	global_position = _target.global_position + Vector3(0, height_offset, 0)
	_flare = maxf(_flare - delta * 1.5, 0.0)
	var flicker := randf_range(0.55, 1.0) * (2.2 if _warning else 1.0)
	if light:
		light.light_energy = base_light_energy * flicker + _flare * 25.0
	if sparks:
		sparks.amount_ratio = 1.0 if (_warning or _flare > 0.0) else 0.35
	var pulse := 1.0 + (sin(Time.get_ticks_msec() * 0.03) * 0.15 if _warning else 0.0)
	if plug:
		plug.scale = Vector3.ONE * pulse
	if ring:
		ring.scale = Vector3(pulse, 1.0, pulse) * (1.0 + _flare * 0.6)
