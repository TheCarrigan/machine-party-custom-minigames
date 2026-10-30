extends Node3D
# Live Wire's set: a high-voltage switch room. Our own layout; the textures and the lamp model are
# loaded at runtime from the player's own copy of the game. If any of them is missing (for example
# after a game update), that piece is simply left out and the minigame still works.

const METAL_TEX := "res://textures/materials/metal_01.png"
const RACK_TEX := "res://textures/environment/server_rack_seamless.png"
const RACK_GLOW_TEX := "res://textures/environment/server_rack_seamless_gradient glow.png"
const BELT_TEX := "res://textures/conveyor belt new1.png"
const LAMP_RUST_TEX := "res://minigames/exploding_collar_race/models/collar race light fixture1/collar race light fixture1_mixed rust1.png"

var _rack_mats: Array[StandardMaterial3D] = []
var _pit_mat: StandardMaterial3D
var _t := 0.0


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Builds the room around a floor of `half` (half-size in metres).
func build(floor_mesh: MeshInstance3D, pillar_meshes: Array, half: Vector2) -> void:
	for c in get_children():
		c.queue_free()
	_rack_mats.clear()
	_dress_floor(floor_mesh, half)
	for p in pillar_meshes:
		_dress_pillar(p)
	_build_pit()
	_build_walls()
	_build_lamps()
	_build_sign()


func _dress_floor(floor_mesh: MeshInstance3D, half: Vector2) -> void:
	var tex := _tex(METAL_TEX)
	if tex == null or floor_mesh == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.8, 0.78, 0.74)
	m.metallic = 0.55
	m.roughness = 0.6
	m.uv1_scale = Vector3(half.x / 3.0, half.y / 3.0, 1.0) * Vector3(1.0, 1.0, 1.0)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.18, 0.18, 0.18)
	floor_mesh.material_override = m


func _rack_material() -> StandardMaterial3D:
	var tex := _tex(RACK_TEX)
	if tex == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.42, 0.44, 0.47)
	m.metallic = 0.3
	m.roughness = 0.7
	var glow := _tex(RACK_GLOW_TEX)
	if glow:
		m.emission_enabled = true
		m.emission_texture = glow
		m.emission = Color(1.0, 0.18, 0.12)
		m.emission_energy_multiplier = 0.2
	_rack_mats.append(m)
	return m


func _dress_pillar(pillar_mesh: MeshInstance3D) -> void:
	var m := _rack_material()
	if m == null or pillar_mesh == null:
		return
	var mm: StandardMaterial3D = m.duplicate()
	mm.uv1_scale = Vector3(1.5, 1.1, 1.0)     # roughly one rack per face
	_rack_mats.append(mm)
	pillar_mesh.material_override = mm


func _build_walls() -> void:
	var m := _rack_material()
	if m == null:
		return
	# back wall and two side walls of racks, standing in the pit around the floor
	var walls := [
		{"pos": Vector3(0, -1.5, -12.5), "size": Vector3(34, 14, 1.2)},
		{"pos": Vector3(-16.0, -1.5, -3.0), "size": Vector3(1.2, 14, 20)},
		{"pos": Vector3(16.0, -1.5, -3.0), "size": Vector3(1.2, 14, 20)},
	]
	for w in walls:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = w["size"]
		mi.mesh = box
		var mm: StandardMaterial3D = m.duplicate()
		var across: float = maxf(w["size"].x, w["size"].z)
		mm.uv1_scale = Vector3(across / 2.4, w["size"].y / 2.8, 1.0)   # one rack ~1.2 m wide, 1.4 m tall
		_rack_mats.append(mm)
		mi.material_override = mm
		mi.position = w["pos"]
		add_child(mi)


func _build_pit() -> void:
	# far below the floor: a machinery floor glowing blue, so a fall reads as a long drop
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 30)
	mi.mesh = plane
	_pit_mat = StandardMaterial3D.new()
	_pit_mat.albedo_color = Color(0.05, 0.08, 0.12)
	var belt := _tex(BELT_TEX)
	if belt:
		_pit_mat.emission_texture = belt
		_pit_mat.uv1_scale = Vector3(6, 6, 1)
	_pit_mat.emission_enabled = true
	_pit_mat.emission = Color(0.2, 0.55, 1.0)
	_pit_mat.emission_energy_multiplier = 0.3
	mi.material_override = _pit_mat
	mi.position = Vector3(0, -9.0, -2.0)
	add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.3, 0.6, 1.0)
	glow.light_energy = 1.5
	glow.omni_range = 14.0
	glow.position = Vector3(0, -6.0, 0)
	add_child(glow)


func _build_lamps() -> void:
	var shade_mat := StandardMaterial3D.new()
	shade_mat.albedo_color = Color(0.12, 0.13, 0.12)
	shade_mat.metallic = 0.6
	shade_mat.roughness = 0.4
	var rust := _tex(LAMP_RUST_TEX)
	if rust:
		shade_mat.albedo_texture = rust
		shade_mat.albedo_color = Color(0.6, 0.55, 0.5)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.9, 0.7)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.85, 0.55)
	bulb_mat.emission_energy_multiplier = 3.0
	for x in [-6.0, 0.0, 6.0]:
		var holder := Node3D.new()
		holder.position = Vector3(x, 6.0, -5.5)
		add_child(holder)
		var shade := MeshInstance3D.new()          # an industrial lamp shade: a wide, shallow cone
		var cone := CylinderMesh.new()
		cone.top_radius = 0.12
		cone.bottom_radius = 0.75
		cone.height = 0.45
		shade.mesh = cone
		shade.material_override = shade_mat
		holder.add_child(shade)
		var bulb := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		bulb.mesh = sph
		bulb.material_override = bulb_mat
		bulb.position.y = -0.2
		holder.add_child(bulb)
		var light := SpotLight3D.new()
		light.rotation_degrees = Vector3(-90, 0, 0)
		light.light_color = Color(1.0, 0.86, 0.62)
		light.light_energy = 5.0
		light.spot_range = 14.0
		light.spot_angle = 38.0
		light.shadow_enabled = x == 0.0
		holder.add_child(light)
		# the lamp's own cable up into the dark
		var cord := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = 6.0
		cord.mesh = cyl
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.05, 0.05, 0.05)
		cord.material_override = cm
		cord.position = Vector3(0, 3.0, 0)
		holder.add_child(cord)


func _build_sign() -> void:
	var sign := Label3D.new()
	sign.text = "DANGER  -  HIGH VOLTAGE"
	sign.font_size = 160
	sign.outline_size = 0
	sign.modulate = Color(1.0, 0.8, 0.1)
	sign.position = Vector3(0, 3.6, -11.75)
	sign.pixel_size = 0.01
	add_child(sign)
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(15.0, 1.8, 0.1)
	plate.mesh = box
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.08, 0.07, 0.05)
	plate.material_override = pm
	plate.position = Vector3(0, 3.6, -11.85)
	add_child(plate)


func _process(delta: float) -> void:
	# rack lights breathe, the pit hums
	_t += delta
	var k := 0.18 + 0.08 * sin(_t * 2.3)
	for m in _rack_mats:
		m.emission_energy_multiplier = k
	if _pit_mat:
		_pit_mat.emission_energy_multiplier = 0.3 + 0.08 * sin(_t * 5.1)
