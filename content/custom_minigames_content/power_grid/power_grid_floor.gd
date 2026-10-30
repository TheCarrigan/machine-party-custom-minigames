extends Node3D
# The floor panels of Power Grid: builds a grid of tiles and shows each tile's state.
# Purely visual; the host decides which tiles are dangerous and tells everyone.

enum { IDLE, WARNING, LIVE }

@export var columns: int = 6
@export var rows: int = 4
@export var tile_size: float = 3.0
@export var gap: float = 0.12
@export var idle_color := Color(0.16, 0.18, 0.2)
@export var warning_color := Color(1.0, 0.62, 0.08)
@export var live_color := Color(0.25, 0.6, 1.0)

var _tiles: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _state: PackedInt32Array = []


func _ready() -> void:
	_build()


func tile_count() -> int:
	return columns * rows


func tile_center(index: int) -> Vector3:
	var c := index % columns
	var r := index / columns
	return Vector3((c - (columns - 1) * 0.5) * tile_size, 0.0, (r - (rows - 1) * 0.5) * tile_size)


## Which tile a world position is over, or -1 when off the grid.
func tile_at(pos: Vector3) -> int:
	var c := int(floor(pos.x / tile_size + columns * 0.5))
	var r := int(floor(pos.z / tile_size + rows * 0.5))
	if c < 0 or c >= columns or r < 0 or r >= rows:
		return -1
	return r * columns + c


func state_of(index: int) -> int:
	return _state[index] if index >= 0 and index < _state.size() else IDLE


func set_tiles(state: int, indices: PackedInt32Array) -> void:
	for i in indices:
		if i < 0 or i >= _tiles.size():
			continue
		_state[i] = state
		_paint(i)


func clear_all() -> void:
	for i in _tiles.size():
		_state[i] = IDLE
		_paint(i)


func _build() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile_size - gap, 0.02, tile_size - gap)
	_state.resize(tile_count())
	for i in tile_count():
		var t := MeshInstance3D.new()
		t.mesh = mesh
		var m := StandardMaterial3D.new()
		m.metallic = 0.5
		m.roughness = 0.5
		m.emission_enabled = true
		t.material_override = m
		t.position = tile_center(i) + Vector3(0, -0.005, 0)
		add_child(t)
		_tiles.append(t)
		_mats.append(m)
		_state[i] = IDLE
		_paint(i)


func _paint(i: int) -> void:
	var m := _mats[i]
	match _state[i]:
		WARNING:
			m.albedo_color = warning_color
			m.emission = warning_color
			m.emission_energy_multiplier = 0.8
		LIVE:
			m.albedo_color = live_color
			m.emission = live_color
			m.emission_energy_multiplier = 1.3
		_:
			m.albedo_color = idle_color
			m.emission = Color(0.2, 0.35, 0.5)
			m.emission_energy_multiplier = 0.05


func _process(_delta: float) -> void:
	# warning tiles blink faster the closer they are to going live (driven by the host's timer)
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
	for i in _tiles.size():
		if _state[i] == WARNING:
			_mats[i].emission_energy_multiplier = 0.3 + 1.2 * blink
