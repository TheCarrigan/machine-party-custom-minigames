extends Minigame
# LIVE WIRE - a custom minigame for Machine Party (fan mod, own code).
# Hot potato: one worker holds a live cable. Touch another worker to pass it on.
# When the hidden fuse runs out, whoever holds it is electrocuted. Last one standing wins.
# The host runs all rules; other players only receive "who holds it", warnings and zaps.
# Players are the game's own Disco Dodge workers (walk, shove, fall off edges).

const PLAYER_SCENE := preload("res://minigames/disco_dodge/components/player/disco_dodge_player.tscn")

@export_category("Gameplay")
@export var pass_distance: float = 1.75         # metres between worker centres; bodies touch at 1.4 (radius 0.7)
@export var pass_cooldown: float = 0.8          # seconds before it can be passed again
@export var no_pass_back_time: float = 1.5      # "no tag-backs": the last holder can't get it straight back
@export var first_fuse_range := Vector2(10.0, 15.0)
@export var fuse_range := Vector2(7.0, 12.0)
@export var warning_time: float = 2.5           # wire crackles harder in the last seconds
@export var pause_between_zaps: float = 2.5

@export_category("Practice bots")
@export var bot_names: Array[String] = ["SPARKY", "FUSE", "OHM"]
@export var bot_hats: Array[String] = ["tophat", "traffic_cone", "cap_blade", "beer_hat", ""]
@export var bot_flee_distance: float = 4.5      # bots only start running when the holder is this close
@export var bot_hesitate_chance: float = 0.3     # chance per decision to falter while being chased
@export var bot_shove_chance: float = 0.03       # per physics frame, when the holder is close

@export_category("Arenas")
@export var sweeper_speed: float = 0.9          # radians per second
@export var sweeper_reach: float = 5.5          # metres from the centre to the arm's tip

@export_category("Scene parts")
@export var countdown: State                    # shared countdown stage (3, 2, 1, GO)
@export var worker_parent: Node3D               # spawned workers live here (network-replicated)
@export var spawn_points: Node3D                # one Marker3D per possible worker
@export var wire: Node3D

# host-side bookkeeping (same shape as the built-in minigames)
var players: Dictionary = {}          # network_id -> player node
var active_players: Dictionary = {}   # still alive
var dead_players: Array[int] = []     # in order of elimination
var player_scores: Dictionary = {}
var player_count := 0
var game_end := false
var _scored := false

var holder_id: int = 0                # every player: who holds the wire (0 = nobody)

## Emitted on every player's machine whenever the wire changes hands (0 = nobody holds it).
signal holder_changed(network_id: int)

var _fuse_left: float = 0.0
var _cooldown_left: float = 0.0
var _fuse_running: bool = false
var _warned: bool = false
var _burst_pending: bool = false
var _last_holder: int = 0
var _last_pass_time: float = -100.0
var _play_time: float = 0.0       # game time, so the rules follow pauses and time scale

# Arenas. The host picks one per round (settings.cfg [arena]) and tells every machine.
const ARENAS := {
	"classic": {"half": Vector2(9.0, 6.0), "pillars": [Vector2(-4, 0), Vector2(4, 0)], "sweeper": false, "zoom": 1.0},
	"pocket": {"half": Vector2(6.0, 4.5), "pillars": [], "sweeper": false, "zoom": 0.78},
	"sweeper": {"half": Vector2(9.0, 6.0), "pillars": [], "sweeper": true, "zoom": 1.0},
}
const ARENA_ORDER := ["classic", "pocket", "sweeper"]
var arena := "classic"
var arena_half := Vector2(9.0, 6.0)
var pillars: Array = [Vector2(-4, 0), Vector2(4, 0)]
var _sweeper: AnimatableBody3D = null
var _dressing: Node3D = null
const Dressing := preload("res://custom_minigames_content/live_wire/live_wire_dressing.gd")
var _sweep_angle := 0.0

## Emitted on every machine when the arena is set up for the round.
signal arena_changed(arena_name: String)

# Bots get negative IDs: real network player IDs are always positive, so they can never clash.
var bot_ids: Array[int] = []
var _bot_brain: Dictionary = {}    # id -> {"t": seconds until next decision, "dir": Vector3}


func _ready() -> void:
	super._ready()
	_dress()
	if multiplayer.is_server():
		for pair in [["countdown_started", _on_countdown_started], ["tick", _on_countdown_tick], ["expired", _on_countdown_expired]]:
			countdown.connect(pair[0], pair[1])
	if GameManager.local_game:
		# couch play: there are no remote players to wait for
		get_tree().create_timer(1.0).timeout.connect(func(): minigame_ready.emit(1))


func initialize(_round_number: int, _total_rounds: int, _scores: Dictionary = {}):
	super.initialize(_round_number, _total_rounds, _scores)
	set_arena_rpc.rpc(_pick_arena())
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
		var p = PLAYER_SCENE.instantiate()
		worker_parent.add_child(p, true)
		p.set_player_presence.rpc(presence.network_id)
		p.teleport_rpc.rpc(spawns[i % spawns.size()].global_position)
		players[presence.network_id] = p
		active_players[presence.network_id] = p
		player_scores[presence.network_id] = 0
		p.died.connect(_on_player_died)
		i += 1
	var bots: int = mini(_practice_bot_count(), 4 - players.size())
	for k in bots:
		_spawn_bot(k, spawns[i % spawns.size()].global_position)
		i += 1
	player_count = players.size()


# --- arenas -------------------------------------------------------------------

## Host: which arena this round. settings.cfg [arena] arena = rotate (default: a different one each
## time) or classic / pocket / sweeper.
func _pick_arena() -> String:
	var loader = get_node_or_null("/root/ModLoader")
	var reg: Dictionary = loader.registry("live_wire") if loader != null else {}
	var want := str(reg.get("arena", "rotate"))
	if ARENAS.has(want):
		return want
	var n: int = int(reg.get("arena_next", randi() % ARENA_ORDER.size()))
	reg["arena_next"] = n + 1
	return ARENA_ORDER[n % ARENA_ORDER.size()]


@rpc("authority", "call_local", "reliable")
func set_arena_rpc(arena_name: String) -> void:
	_apply_arena(arena_name if ARENAS.has(arena_name) else "classic")


func _apply_arena(arena_name: String) -> void:
	var a: Dictionary = ARENAS[arena_name]
	arena = arena_name
	arena_half = a["half"]
	pillars = a["pillars"]
	var size := Vector3(arena_half.x * 2.0, 1.0, arena_half.y * 2.0)
	var floor_mesh: MeshInstance3D = get_node("Arena/Floor/Mesh")
	floor_mesh.mesh = floor_mesh.mesh.duplicate()       # never change the shared resource
	floor_mesh.mesh.size = size
	var floor_shape: CollisionShape3D = get_node("Arena/Floor/Shape")
	floor_shape.shape = floor_shape.shape.duplicate()
	floor_shape.shape.size = size
	var edge: MeshInstance3D = get_node("Arena/HazardEdge")
	edge.mesh = edge.mesh.duplicate()
	edge.mesh.size = Vector3(size.x + 0.3, 0.15, size.z + 0.3)
	var pillar_nodes := [get_node("Arena/PillarLeft"), get_node("Arena/PillarRight")]
	for i in pillar_nodes.size():
		var on := i < pillars.size()
		pillar_nodes[i].visible = on
		pillar_nodes[i].get_node("Shape").disabled = not on
		if on:
			pillar_nodes[i].position = Vector3(pillars[i].x, 1.5, pillars[i].y)
	# spawn spots: one per corner area, well inside the floor
	var sx := arena_half.x - 3.0
	var sz := minf(3.0, arena_half.y - 1.5)
	var spots := [Vector3(-sx, 0, -sz), Vector3(sx, 0, -sz), Vector3(sx, 0, sz), Vector3(-sx, 0, sz)]
	var markers := spawn_points.get_children()
	for i in markers.size():
		markers[i].position = spots[i % spots.size()]
	var cam: Camera3D = get_node_or_null("Camera3D")
	if cam:
		cam.position = Vector3(0, 9.2, 11.6) * float(a["zoom"])
	if a["sweeper"] and _sweeper == null:
		_sweeper = _build_sweeper()
		get_node("Arena").add_child(_sweeper)
	elif not a["sweeper"] and _sweeper != null:
		_sweeper.queue_free()
		_sweeper = null
	_dress()
	arena_changed.emit(arena)


func _dress() -> void:
	if _dressing == null:
		_dressing = Dressing.new()
		_dressing.name = "Dressing"
		add_child(_dressing)
	var pillar_meshes := []
	for i in pillars.size():
		pillar_meshes.append(get_node(["Arena/PillarLeft", "Arena/PillarRight"][i]).get_node("Mesh"))
	_dressing.build(get_node("Arena/Floor/Mesh"), pillar_meshes, arena_half)


## A low rotating arm with a hub. Workers can't jump it, so it pushes them along (and off edges).
func _build_sweeper() -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = "Sweeper"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.72, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.05)
	mat.emission_energy_multiplier = 0.6
	var arm_size := Vector3(sweeper_reach * 2.0, 0.7, 0.45)
	var arm_mesh := MeshInstance3D.new()
	arm_mesh.mesh = BoxMesh.new()
	arm_mesh.mesh.size = arm_size
	arm_mesh.material_override = mat
	arm_mesh.position.y = 0.35
	body.add_child(arm_mesh)
	var arm_shape := CollisionShape3D.new()
	arm_shape.shape = BoxShape3D.new()
	arm_shape.shape.size = arm_size
	arm_shape.position.y = 0.35
	body.add_child(arm_shape)
	var hub := MeshInstance3D.new()
	hub.mesh = CylinderMesh.new()
	hub.mesh.top_radius = 0.7
	hub.mesh.bottom_radius = 0.7
	hub.mesh.height = 1.2
	hub.position.y = 0.6
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.15, 0.15, 0.17)
	hub.material_override = hub_mat
	body.add_child(hub)
	var hub_shape := CollisionShape3D.new()
	hub_shape.shape = CylinderShape3D.new()
	hub_shape.shape.radius = 0.7
	hub_shape.shape.height = 1.2
	hub_shape.position.y = 0.6
	body.add_child(hub_shape)
	return body


# --- practice bots (host only; only when no other machines are connected) ------

func _practice_bot_count() -> int:
	if not multiplayer.get_peers().is_empty():
		return 0
	var loader = get_node_or_null("/root/ModLoader")
	if loader == null:
		return 0
	var reg: Dictionary = loader.registry("live_wire")
	var n := clampi(int(reg.get("practice_bots", 0)), 0, 3)
	# alone on one machine with bots off: nobody to play against, so bring the bots anyway
	if n == 0 and PlayerManager.player_presences.size() <= 1 and reg.get("bots_when_alone", true):
		n = 3
	return n


func _spawn_bot(k: int, at: Vector3) -> void:
	var id := -(k + 1)
	var bot = PLAYER_SCENE.instantiate()
	worker_parent.add_child(bot, true)
	var presence := PlayerPresence.new()       # private to this bot; never added to the game's player list
	presence.network_id = id
	presence.network_name = bot_names[k % bot_names.size()]
	presence.local = true
	bot.player_presence = presence
	bot.player_name_label.text = presence.network_name
	bot.customization_assigner.assign_hat(bot_hats.pick_random())
	bot.customization_assigner.assign_glasses("")
	bot.customization_assigner.assign_suit_color("")
	bot.set_multiplayer_authority(id, true)   # not "this machine's" worker: no player marker for it
	bot.set_process(false)                    # never reads the keyboard/controller; we steer it
	bot.shove_area.body_entered.connect(bot._on_shove_proximity_entered)
	bot.shove_area.body_exited.connect(bot._on_shove_proximity_exited)
	bot.teleport_rpc(at)
	players[id] = bot
	active_players[id] = bot
	player_scores[id] = 0
	bot.died.connect(_on_player_died)
	bot_ids.append(id)


func _drive_bots(delta: float) -> void:
	for id in bot_ids:
		var bot = active_players.get(id, null)
		if bot == null or not is_instance_valid(bot) or not bot.active:
			continue
		var brain: Dictionary = _bot_brain.get(id, {"t": 0.0, "dir": Vector3.ZERO})
		brain["t"] -= delta
		if brain["t"] <= 0.0:
			brain["t"] = randf_range(0.15, 0.35)   # reaction time
			brain["dir"] = _bot_decide(id, bot)
		_bot_brain[id] = brain
		bot.movement_input = _edge_guard(bot.global_position, brain["dir"])
		var holder = active_players.get(holder_id, null)
		if id != holder_id and holder != null and randf() < bot_shove_chance \
				and bot.global_position.distance_to(holder.global_position) < 1.8:
			bot.shove()


## Every frame: cancel any movement that would carry a bot to within a step of the edge.
## (Workers run ~8 m/s, so between two decisions a bot can cover a few metres.)
func _edge_guard(at: Vector3, dir: Vector3) -> Vector3:
	var limit_x := arena_half.x - 1.2
	var limit_z := arena_half.y - 1.2
	if (at.x > limit_x and dir.x > 0.0) or (at.x < -limit_x and dir.x < 0.0):
		dir.x = -dir.x * 0.5
	if (at.z > limit_z and dir.z > 0.0) or (at.z < -limit_z and dir.z < 0.0):
		dir.z = -dir.z * 0.5
	return dir


func _bot_decide(id: int, bot: Node3D) -> Vector3:
	var pos := Vector2(bot.global_position.x, bot.global_position.z)
	var want := Vector2.ZERO
	var holder = active_players.get(holder_id, null)
	if id == holder_id:
		# chase the nearest worker, aiming a little ahead of where it's going
		var best = null
		var best_d := INF
		for other_id in active_players:
			if other_id == id:
				continue
			var o = active_players[other_id]
			var d := pos.distance_to(Vector2(o.global_position.x, o.global_position.z))
			if d < best_d:
				best_d = d
				best = o
		if best != null:
			var lead: Vector3 = best.velocity * clampf(best_d / 4.0, 0.0, 0.6)
			want = Vector2(best.global_position.x + lead.x, best.global_position.z + lead.z) - pos
	elif holder != null:
		var away := pos - Vector2(holder.global_position.x, holder.global_position.z)
		var d := away.length()
		if d < bot_flee_distance:
			if randf() < bot_hesitate_chance:
				return Vector3.ZERO            # panics and freezes for a moment
			want = away.normalized() * (1.0 + (bot_flee_distance - d) / bot_flee_distance)
		else:
			want = -pos * 0.08                 # drift back towards the middle of the floor
	want += Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))   # a little wandering
	# keep off the edges
	var margin := minf(2.5, arena_half.y * 0.4)
	if pos.x > arena_half.x - margin: want.x -= 3.0
	if pos.x < -arena_half.x + margin: want.x += 3.0
	if pos.y > arena_half.y - margin: want.y -= 3.0
	if pos.y < -arena_half.y + margin: want.y += 3.0
	for pillar in pillars:
		var v: Vector2 = pos - pillar
		if v.length() < 1.6:
			want += v.normalized() * 1.5
	if _sweeper != null:
		# step away from the arm, and a little ahead of it
		var arm := Vector2(cos(_sweep_angle), -sin(_sweep_angle))
		var along := clampf(pos.dot(arm), -sweeper_reach, sweeper_reach)
		var off := pos - arm * along
		if off.length() < 2.0:
			var ahead := Vector2(-arm.y, arm.x) * signf(sweeper_speed)   # the way the arm is sweeping
			want += off.normalized() * 2.0 + (ahead if off.dot(ahead) > 0.0 else Vector2.ZERO)
	if want.length() < 0.2:
		return Vector3.ZERO
	want = want.normalized()
	return Vector3(want.x, 0.0, want.y)


func _on_countdown_expired():
	super._on_countdown_expired()   # shows "GO!"
	for worker in players.values():
		worker.set_active_rpc.rpc(true)
	state_machine.transition_to_rpc.rpc(&"Play")
	# give everyone a moment to scatter before the wire drops
	get_tree().create_timer(1.5, false).timeout.connect(func(): _start_burst(first_fuse_range))


# --- host: the wire ---------------------------------------------------------

func _start_burst(fuse: Vector2) -> void:
	_burst_pending = false
	if game_end or active_players.size() <= 1:
		return
	var ids: Array = active_players.keys()
	set_holder_rpc.rpc(ids.pick_random())
	_last_holder = 0
	_fuse_left = randf_range(fuse.x, fuse.y)
	_cooldown_left = pass_cooldown
	_warned = false
	_fuse_running = true
	set_warning_rpc.rpc(false)


func _physics_process(delta: float) -> void:
	if _sweeper != null and state_machine.current_state != null and state_machine.current_state.name == &"Play":
		# every machine turns its own arm from the moment play starts; each machine moves its own
		# worker, so the arm pushes you on your own screen
		_sweep_angle += sweeper_speed * delta
		_sweeper.rotation.y = _sweep_angle
	if not bot_ids.is_empty() and multiplayer.is_server():
		_drive_bots(delta)
	if not _fuse_running or not multiplayer.is_server():
		return
	_play_time += delta
	_fuse_left -= delta
	_cooldown_left -= delta
	if not _warned and _fuse_left <= warning_time:
		_warned = true
		set_warning_rpc.rpc(true)
	if _fuse_left <= 0.0:
		_fuse_running = false
		_zap(holder_id)
		return
	if _cooldown_left > 0.0:
		return
	var holder = active_players.get(holder_id, null)
	if holder == null or not is_instance_valid(holder):
		return
	var now := _play_time
	for id in active_players:
		if id == holder_id:
			continue
		if id == _last_holder and now - _last_pass_time < no_pass_back_time:
			continue   # no tag-backs
		var other = active_players[id]
		if not is_instance_valid(other):
			continue
		var d: Vector3 = other.global_position - holder.global_position
		if Vector2(d.x, d.z).length() <= pass_distance and absf(d.y) < 1.5:
			_last_holder = holder_id
			_last_pass_time = now
			set_holder_rpc.rpc(id)
			_cooldown_left = pass_cooldown
			return


func _zap(id: int) -> void:
	if id == 0:
		_queue_next_burst()
		return
	zap_rpc.rpc(id)
	await get_tree().create_timer(0.6, false).timeout
	var p = players.get(id, null)
	if p != null and is_instance_valid(p):
		p.kill_rpc.rpc()
	_eliminate(id)


func _eliminate(id: int) -> void:
	if not active_players.has(id):
		return
	active_players.erase(id)
	if not dead_players.has(id):
		dead_players.append(id)
	if id == holder_id:
		_fuse_running = false
		set_holder_rpc.rpc(0)
	_check_end_or_next()


func _check_end_or_next() -> void:
	if game_end:
		return
	if active_players.size() <= 1:
		game_end = true
		_fuse_running = false
		set_holder_rpc.rpc(0)
		await get_tree().create_timer(3.0).timeout
		calculate_score()
		finish_game()
		return
	if holder_id == 0 and not _fuse_running:
		_queue_next_burst()


func _queue_next_burst() -> void:
	if _burst_pending or game_end:
		return
	_burst_pending = true
	await get_tree().create_timer(pause_between_zaps, false).timeout
	if not game_end and holder_id == 0:
		_start_burst(fuse_range)
	else:
		_burst_pending = false


func _on_player_died(network_id: int) -> void:
	# fell off the edge (shoved, or walked off)
	_eliminate(network_id)


func calculate_score():
	if _scored:
		return
	_scored = true
	# n-th worker out scores n-1; anyone still standing gets the top score
	var place := 0
	for id in dead_players:
		player_scores[id] = place
		place += 1
	for id in active_players:
		player_scores[id] = player_count
	var real_scores := {}               # only real players' scores go back to the game
	for id in player_scores:
		if not bot_ids.has(id):
			real_scores[id] = player_scores[id]
	player_scores_finalized.emit(real_scores)


func finish_game():
	await get_tree().create_timer(2.0).timeout
	set_holder_rpc.rpc(0)              # make sure the cable is gone before the screen fades
	state_machine.transition_to_rpc.rpc(&"Finish")   # the Finish stage fades out on every machine


func player_disconnected(_network_id: int):
	super.player_disconnected(_network_id)
	if not multiplayer.is_server():
		return
	remove_player_rpc.rpc(_network_id)
	await get_tree().create_timer(1.0).timeout
	if _network_id == holder_id:
		_fuse_running = false
		set_holder_rpc.rpc(0)
	_check_end_or_next()


# --- every player -------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func set_holder_rpc(id: int) -> void:
	holder_id = id
	holder_changed.emit(id)
	if wire:
		wire.attach_to(_find_player(id))
	if id != 0:
		SoundManager.play_omni("collar_activate", -8.0, randf_range(0.9, 1.1))


@rpc("authority", "call_local", "reliable")
func set_warning_rpc(on: bool) -> void:
	if wire:
		wire.set_warning(on)


@rpc("authority", "call_local", "reliable")
func zap_rpc(id: int) -> void:
	if wire:
		wire.zap()
	SoundManager.play_omni("bad_explosion", -4.0, 1.2)
	var p = _find_player(id)
	if p and p.get("player_name_label"):
		p.player_name_label.visible = false


@rpc("authority", "call_local", "reliable")
func remove_player_rpc(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		var p = players[id]
		if is_instance_valid(p):
			p.queue_free()
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
