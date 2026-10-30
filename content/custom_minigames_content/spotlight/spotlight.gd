extends Minigame
# SPOTLIGHT - a custom minigame for Machine Party (fan mod, own code).
# A spotlight wanders across the floor. A worker standing in it ALONE earns a point per second;
# if two or more share it, nobody scores. Shove rivals out of the light (or off the floor).
# Workers who fall are out but keep their points. Most points when time runs out wins.
# The host keeps score; every machine moves the light along the same path from a shared seed.

const PLAYER_SCENE := preload("res://minigames/disco_dodge/components/player/disco_dodge_player.tscn")

@export_category("Gameplay")
@export var match_time: float = 45.0
@export var light_radius_start: float = 2.4      # metres; the light shrinks over the match...
@export var light_radius_end: float = 1.6        # ...to this
@export var light_speed: float = 2.2             # metres per second along its path
@export var points_interval: float = 0.25        # how often the host sends the scoreboard

@export_category("Practice bots")
@export var bot_names: Array[String] = ["SPARKY", "FUSE", "OHM"]
@export var bot_hats: Array[String] = ["tophat", "traffic_cone", "cap_blade", "beer_hat", ""]
@export var bot_shove_chance: float = 0.05       # per physics frame, when a rival shares the light
@export var bot_aggression: Array[float] = [0.85, 0.5, 0.25]   # per bot: how readily it barges into a taken light

@export_category("Scene parts")
@export var countdown: State
@export var worker_parent: Node3D
@export var spawn_points: Node3D
@export var light_root: Node3D
@export var hum: AudioStreamPlayer

const ARENA_HALF := Vector2(9.0, 6.0)
const PATH_MARGIN := Vector2(2.6, 2.2)            # the light's centre stays this far from the edges

# host-side bookkeeping
var players: Dictionary = {}          # network_id -> worker
var active_players: Dictionary = {}   # still on the floor
var points: Dictionary = {}           # network_id -> seconds alone in the light (host)
var player_scores: Dictionary = {}
var player_count := 0
var game_end := false
var _scored := false
var _send_t := 0.0

# every machine
var shown_points: Dictionary = {}     # network_id -> whole points, as last sent by the host
var light_owner := 0                  # who is scoring right now (0 = nobody)
var contested := false
var _seed := 0
var _path: PackedVector2Array = []
var _path_len: PackedFloat32Array = []   # distance along the path at each point
var _running := false
var _play_t := 0.0

## Every machine: the light changed hands (owner 0 = nobody scoring; contested = shared).
signal light_changed(owner_id: int, is_contested: bool)
## Every machine: the host sent new points.
signal points_changed(points_by_id: Dictionary)

var bot_ids: Array[int] = []
var _bot_brain: Dictionary = {}

var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _rim: MeshInstance3D
var _rim_mat: StandardMaterial3D
var _spot: SpotLight3D
var _hud: Label


func _ready() -> void:
	super._ready()
	_build_light()
	if multiplayer.is_server():
		for pair in [["countdown_started", _on_countdown_started], ["tick", _on_countdown_tick], ["expired", _on_countdown_expired]]:
			countdown.connect(pair[0], pair[1])
	if GameManager.local_game:
		get_tree().create_timer(1.0).timeout.connect(func(): minigame_ready.emit(1))


func initialize(_round_number: int, _total_rounds: int, _scores: Dictionary = {}):
	super.initialize(_round_number, _total_rounds, _scores)
	set_seed_rpc.rpc(randi())
	spawn_players()
	state_machine.transition_to_rpc.rpc(&"Round", {"round": _round_number, "total": _total_rounds})


func cleanup():
	if is_multiplayer_authority():
		queue_free()


func fade_in_ambience():
	pass


func all_players_loaded():
	super.all_players_loaded()
	if not multiplayer.is_server():
		return
	is_all_player_loaded = true
	minigame_ready.emit(multiplayer.get_unique_id())


func spawn_players():
	var spawns = spawn_points.get_children()
	spawns.shuffle()
	var i := 0
	for key in PlayerManager.player_presences.keys():
		var presence = PlayerManager.player_presences[key]
		var w = PLAYER_SCENE.instantiate()
		worker_parent.add_child(w, true)
		w.set_player_presence.rpc(presence.network_id)
		w.teleport_rpc.rpc(spawns[i % spawns.size()].global_position)
		_track(presence.network_id, w)
		i += 1
	for k in mini(_practice_bot_count(), 4 - players.size()):
		_spawn_bot(k, spawns[i % spawns.size()].global_position)
		i += 1
	player_count = players.size()


func _track(id: int, w) -> void:
	players[id] = w
	active_players[id] = w
	points[id] = 0.0
	player_scores[id] = 0
	w.died.connect(_on_player_died)


func _on_countdown_expired():
	super._on_countdown_expired()
	for w in players.values():
		w.set_active_rpc.rpc(true)
	state_machine.transition_to_rpc.rpc(&"Play")
	start_light_rpc.rpc()


# --- the light's path (same on every machine, from the host's seed) ----------------

func _make_path(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lim := ARENA_HALF - PATH_MARGIN
	_path = PackedVector2Array([Vector2.ZERO])
	_path_len = PackedFloat32Array([0.0])
	var total := 0.0
	var need := light_speed * (match_time + 10.0)
	while total < need:
		var last: Vector2 = _path[_path.size() - 1]
		var next := Vector2(rng.randf_range(-lim.x, lim.x), rng.randf_range(-lim.y, lim.y))
		if next.distance_to(last) < 3.0:
			continue                      # always travel a fair distance
		total += last.distance_to(next)
		_path.append(next)
		_path_len.append(total)


## Where the light's centre is after `t` seconds of play.
func light_position(t: float) -> Vector2:
	if _path.size() < 2:
		return Vector2.ZERO
	var s := maxf(0.0, t) * light_speed
	for i in range(1, _path.size()):
		if _path_len[i] >= s:
			var seg := _path_len[i] - _path_len[i - 1]
			var f := 0.0 if seg <= 0.0 else (s - _path_len[i - 1]) / seg
			return _path[i - 1].lerp(_path[i], f)
	return _path[_path.size() - 1]


func light_radius(t: float) -> float:
	return lerpf(light_radius_start, light_radius_end, clampf(t / match_time, 0.0, 1.0))


## Workers (still on the floor) inside the light right now, as this machine sees them.
func workers_in_light() -> Array:
	var c := light_position(_play_t)
	var r := light_radius(_play_t)
	var inside: Array = []
	for id in active_players.keys():
		var w = active_players[id]
		if not is_instance_valid(w):
			continue
		var at: Vector3 = w.global_position
		if at.y < -0.3 or at.y > 1.2:
			continue
		if Vector2(at.x, at.z).distance_to(c) <= r:
			inside.append(id)
	return inside


# --- every frame -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _running:
		_play_t += delta
	_update_visuals()
	if not multiplayer.is_server():
		return
	if not bot_ids.is_empty():
		_drive_bots(delta)
	if not _running or game_end:
		return
	if _play_t >= match_time:
		_end_match()
		return
	var inside := workers_in_light()
	var new_owner: int = inside[0] if inside.size() == 1 else 0
	var new_contested := inside.size() > 1
	if new_owner != 0:
		points[new_owner] = float(points[new_owner]) + delta
	if new_owner != light_owner or new_contested != contested:
		light_state_rpc.rpc(new_owner, new_contested)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = points_interval
		points_rpc.rpc(_whole_points())


func _whole_points() -> Dictionary:
	var d := {}
	for id in points:
		d[id] = int(floor(float(points[id])))
	return d


func _update_visuals() -> void:
	if _disc == null:
		return
	var on := _running and not game_end
	_disc.visible = on
	_rim.visible = on
	_spot.visible = on
	if not on:
		return
	var c := light_position(_play_t)
	var r := light_radius(_play_t)
	_disc.position = Vector3(c.x, 0.03, c.y)
	_disc.scale = Vector3(r, 1.0, r)
	_spot.position = Vector3(c.x, 8.0, c.y)
	_spot.spot_angle = rad_to_deg(atan(r / 8.0)) + 2.0
	var col := Color(0.95, 0.95, 0.9)
	if contested:
		col = Color(1.0, 0.2, 0.15) if int(_play_t * 8.0) % 2 == 0 else Color(0.6, 0.1, 0.08)
	elif light_owner != 0:
		col = Color(1.0, 0.8, 0.25)
	_disc_mat.albedo_color = Color(col, 0.42)
	_disc_mat.emission = col
	_rim_mat.albedo_color = col
	_rim.position = Vector3(c.x, 0.05, c.y)
	_rim.scale = Vector3(r, 1.0, r)
	_spot.light_color = col
	if _hud:
		_hud.text = str(ceili(maxf(0.0, match_time - _play_t)))


func _build_light() -> void:
	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.02
	_disc.mesh = cyl
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.emission_enabled = true
	_disc.material_override = _disc_mat
	_disc.visible = false
	light_root.add_child(_disc)
	_rim = MeshInstance3D.new()            # a bright ring marks exactly where the light ends
	var ring := TorusMesh.new()
	ring.inner_radius = 0.95
	ring.outer_radius = 1.0
	ring.rings = 48
	_rim.mesh = ring
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim.material_override = _rim_mat
	_rim.visible = false
	light_root.add_child(_rim)
	_spot = SpotLight3D.new()
	_spot.rotation_degrees = Vector3(-90, 0, 0)       # pointing straight down
	_spot.spot_range = 12.0
	_spot.light_energy = 12.0
	_spot.shadow_enabled = true
	_spot.visible = false
	light_root.add_child(_spot)
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud.position.y = 18.0
	_hud.add_theme_font_size_override("font_size", 40)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 10)
	layer.add_child(_hud)
	add_child(layer)


func _show_points() -> void:
	for c in worker_parent.get_children():
		var pr = c.get("player_presence")
		if pr == null or c.get("player_name_label") == null:
			continue
		var id := int(pr.network_id)
		if not shown_points.has(id):
			continue
		var mine: bool = id == multiplayer.get_unique_id() and not GameManager.local_game
		var label: String = str(shown_points[id]) if mine else "%s  %d" % [pr.network_name, shown_points[id]]
		c.player_name_label.text = label


# --- host: end and scoring ---------------------------------------------------------

func _on_player_died(network_id: int) -> void:
	if not active_players.has(network_id):
		return
	active_players.erase(network_id)          # out, but keeps the points earned so far
	if active_players.is_empty():
		_end_match()
	elif active_players.size() == 1:
		# the last worker on the floor: end now if nobody else can still catch up anyway
		var last: int = active_players.keys()[0]
		var best_other := 0.0
		for id in points:
			if id != last:
				best_other = maxf(best_other, float(points[id]))
		if float(points[last]) > best_other:
			_end_match()


func _end_match() -> void:
	if game_end:
		return
	game_end = true
	points_rpc.rpc(_whole_points())
	stop_light_rpc.rpc()
	await get_tree().create_timer(2.5).timeout
	calculate_score()
	finish_game()


## Places by points (whole points, ties share a place); the top scorer(s) get the winner's score,
## as in the game's own minigames.
func calculate_score():
	if _scored:
		return
	_scored = true
	var whole := _whole_points()
	var best := -1
	for id in whole:
		best = maxi(best, whole[id])
	for id in whole:
		if whole[id] == best:
			player_scores[id] = player_count
		else:
			var below := 0
			for other in whole:
				if whole[other] < whole[id]:
					below += 1
			player_scores[id] = below
	var real_scores := {}
	for id in player_scores:
		if not bot_ids.has(id):
			real_scores[id] = player_scores[id]
	player_scores_finalized.emit(real_scores)


func finish_game():
	await get_tree().create_timer(2.0).timeout
	state_machine.transition_to_rpc.rpc(&"Finish")


func player_disconnected(_network_id: int):
	super.player_disconnected(_network_id)
	if not multiplayer.is_server():
		return
	remove_player_rpc.rpc(_network_id)


# --- practice bots (host only; only when no other machines are connected) ------------

func _practice_bot_count() -> int:
	if not multiplayer.get_peers().is_empty():
		return 0
	var loader = get_node_or_null("/root/ModLoader")
	if loader == null:
		return 0
	var reg: Dictionary = loader.registry("spotlight")
	var n := clampi(int(reg.get("practice_bots", 0)), 0, 3)
	# alone on one machine with bots off: nobody to play against, so bring the bots anyway
	if n == 0 and PlayerManager.player_presences.size() <= 1 and reg.get("bots_when_alone", true):
		n = 3
	return n


func _spawn_bot(k: int, at: Vector3) -> void:
	var id := -(k + 1)                          # real players' IDs are always positive
	var bot = PLAYER_SCENE.instantiate()
	worker_parent.add_child(bot, true)
	var presence := PlayerPresence.new()       # private; never added to the game's player list
	presence.network_id = id
	presence.network_name = bot_names[k % bot_names.size()]
	presence.local = true
	bot.player_presence = presence
	bot.player_name_label.text = presence.network_name
	bot.customization_assigner.assign_hat(bot_hats.pick_random())
	bot.customization_assigner.assign_glasses("")
	bot.customization_assigner.assign_suit_color("")
	bot.set_multiplayer_authority(id, true)
	bot.set_process(false)
	bot.shove_area.body_entered.connect(bot._on_shove_proximity_entered)
	bot.shove_area.body_exited.connect(bot._on_shove_proximity_exited)
	bot.teleport_rpc(at)
	_track(id, bot)
	bot_ids.append(id)


func _drive_bots(delta: float) -> void:
	var inside := workers_in_light() if _running else []
	for id in bot_ids:
		var bot = active_players.get(id, null)
		if bot == null or not is_instance_valid(bot) or not bot.active:
			continue
		var brain: Dictionary = _bot_brain.get(id, {"t": 0.0, "goal": Vector2.ZERO})
		brain["t"] -= delta
		if brain["t"] <= 0.0:
			brain["t"] = randf_range(0.2, 0.4)     # reaction time
			brain["goal"] = _bot_goal(id, bot, inside)
		_bot_brain[id] = brain
		var here := Vector2(bot.global_position.x, bot.global_position.z)
		var to: Vector2 = brain["goal"] - here
		var dir := Vector3.ZERO if to.length() < 0.3 else Vector3(to.x, 0, to.y).normalized()
		bot.movement_input = _edge_guard(bot.global_position, dir)
		# a rival shares the light: shove (but not near an edge, a shove lunges forward)
		var near_edge := absf(here.x) > ARENA_HALF.x - 2.0 or absf(here.y) > ARENA_HALF.y - 2.0
		if inside.size() > 1 and inside.has(id) and not near_edge and randf() < bot_shove_chance:
			for other in inside:
				if other != id and active_players.has(other) and active_players[other].global_position.distance_to(bot.global_position) < 1.7:
					bot.shove()
					break


func _bot_goal(id: int, bot: Node3D, inside: Array) -> Vector2:
	var here := Vector2(bot.global_position.x, bot.global_position.z)
	if not _running:
		return here
	var brain: Dictionary = _bot_brain.get(id, {})
	var ahead := light_position(_play_t + 0.6)       # aim where the light is going
	var rivals := inside.filter(func(o): return o != id).size()
	if rivals == 0:
		return ahead + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))   # free (or mine): take it
	# taken: commit for a while to either barging in or waiting at the rim for a gap
	brain["mode_t"] = float(brain.get("mode_t", 0.0)) - 0.3
	if brain["mode_t"] <= 0.0:
		var aggression: float = bot_aggression[(-id - 1) % bot_aggression.size()]
		var crowd_factor := 1.0 if rivals == 1 else 0.4     # rarely joins a brawl of three
		brain["mode"] = "contest" if randf() < aggression * crowd_factor else "wait"
		brain["mode_t"] = randf_range(1.5, 3.0)
	_bot_brain[id] = brain
	if brain["mode"] == "contest":
		var target = null                                  # walk into the nearest rival in the light
		var best := INF
		for o in inside:
			if o != id and active_players.has(o):
				var d: float = active_players[o].global_position.distance_to(bot.global_position)
				if d < best:
					best = d
					target = active_players[o]
		if target != null:
			return Vector2(target.global_position.x, target.global_position.z)
		return ahead
	var away := (here - ahead).normalized() if here.distance_to(ahead) > 0.1 else Vector2.RIGHT
	return ahead + away * (light_radius(_play_t) + 1.0)


func _edge_guard(at: Vector3, dir: Vector3) -> Vector3:
	var limit_x := ARENA_HALF.x - 1.0
	var limit_z := ARENA_HALF.y - 1.0
	if (at.x > limit_x and dir.x > 0.0) or (at.x < -limit_x and dir.x < 0.0):
		dir.x = 0.0
	if (at.z > limit_z and dir.z > 0.0) or (at.z < -limit_z and dir.z < 0.0):
		dir.z = 0.0
	return dir


# --- every player ------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func set_seed_rpc(seed_value: int) -> void:
	_seed = seed_value
	_make_path(seed_value)


@rpc("authority", "call_local", "reliable")
func start_light_rpc() -> void:
	_play_t = 0.0
	_running = true
	SoundManager.play_omni("collar_activate", -8.0, 0.7)


@rpc("authority", "call_local", "reliable")
func stop_light_rpc() -> void:
	_running = false
	light_owner = 0
	contested = false
	if hum:
		hum.stop()


@rpc("authority", "call_local", "reliable")
func light_state_rpc(owner_id: int, is_contested: bool) -> void:
	var was_owner := light_owner
	light_owner = owner_id
	contested = is_contested
	if hum:
		if is_contested and not hum.playing:
			hum.play()
		elif not is_contested and hum.playing:
			hum.stop()
	if owner_id != 0 and owner_id != was_owner:
		SoundManager.play_omni("collar_activate", -14.0, 1.5)
	light_changed.emit(owner_id, is_contested)


@rpc("authority", "call_local", "reliable")
func points_rpc(points_by_id: Dictionary) -> void:
	shown_points = points_by_id
	_show_points()
	points_changed.emit(points_by_id)


@rpc("authority", "call_local", "reliable")
func remove_player_rpc(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		var w = players[id]
		if is_instance_valid(w):
			w.queue_free()
		players.erase(id)
		active_players.erase(id)


func _find_player(id: int) -> Node3D:
	if id == 0 or worker_parent == null:
		return null
	for c in worker_parent.get_children():
		var presence = c.get("player_presence")
		if presence != null and int(presence.network_id) == id:
			return c
	return null
