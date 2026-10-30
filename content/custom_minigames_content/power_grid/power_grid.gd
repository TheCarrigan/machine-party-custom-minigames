extends Minigame
# POWER GRID - a custom minigame for Machine Party (fan mod, own code).
# The floor is a grid of power panels. Panels flash amber, then surge. Anyone standing on a
# surging panel is electrocuted. Each surge covers more of the floor and comes faster.
# Shoving works, and the floor has edges. Last worker standing wins.
# The host runs all rules; other players only receive panel states and eliminations.

const PLAYER_SCENE := preload("res://minigames/disco_dodge/components/player/disco_dodge_player.tscn")
const FloorGrid := preload("res://custom_minigames_content/power_grid/power_grid_floor.gd")

@export_category("Gameplay")
@export var first_warning_time: float = 2.4      # seconds of amber before the first surge
@export var min_warning_time: float = 1.0
@export var warning_speedup: float = 0.9         # each wave's warning is this much of the last one
@export var surge_time: float = 0.9              # how long panels stay live
@export var pause_between_waves: float = 1.3
@export var first_wave_tiles: int = 6            # live panels in the first wave (of 24)
@export var tiles_per_wave: int = 2              # extra live panels each wave
@export var min_safe_tiles: int = 2              # never fewer safe panels than this...
@export var late_min_safe_tiles: int = 1         # ...until this late stage
@export var late_wave: int = 9
@export var max_waves: int = 16                  # anyone still standing after this shares the win
@export var report_timeout: float = 2.5          # host waits this long for every machine to finish a wave

@export_category("Practice bots")
@export var bot_names: Array[String] = ["SPARKY", "FUSE", "OHM"]
@export var bot_hats: Array[String] = ["tophat", "traffic_cone", "cap_blade", "beer_hat", ""]
@export var bot_misjudge_chance: float = 0.12    # chance per wave a bot picks a poor panel
@export var bot_shove_chance: float = 0.02       # per physics frame, when someone is close

@export_category("Scene parts")
@export var countdown: State
@export var worker_parent: Node3D
@export var spawn_points: Node3D
@export var grid: Node3D
@export var surge_sound: AudioStreamPlayer

# host-side bookkeeping
var players: Dictionary = {}          # network_id -> worker
var active_players: Dictionary = {}
var places: Dictionary = {}           # network_id -> score for when they went out
var player_scores: Dictionary = {}
var player_count := 0
var game_end := false
var wave := 0
var _scored := false
var _surging: PackedInt32Array = []   # host: panels live right now
var _waves_running := false

## Emitted on every machine when a wave changes phase: "warning", "surge" or "clear".
signal wave_phase(phase: String, wave_number: int, tiles: PackedInt32Array)
## Emitted on every machine when a worker is electrocuted.
signal worker_shocked(network_id: int)
## Emitted on the host when a worker is out (shock, fall or disconnect), with the reason.
signal worker_out(network_id: int, reason: String)
## Emitted on an online player's machine when it tells the host its own worker was shocked.
signal shock_reported(wave_number: int)

const ARENA_HALF := Vector2(9.0, 6.0)
var bot_ids: Array[int] = []
var _bot_brain: Dictionary = {}       # id -> {"t", "goal": Vector3, "dir": Vector3}
var _danger: PackedInt32Array = []    # host: panels that are warning or live (for bots)

# Each machine judges its own worker against the panels it sees live (like the game's own falls),
# so lag can't shock someone who had already stepped off on their own screen. The host judges
# its own worker and the practice bots, and waits for everyone's end-of-wave report before scoring.
var _local_live: PackedInt32Array = []    # every machine: panels live on this screen right now
var _local_wave := 0
var _reported_wave := 0                   # this machine already reported a shock this wave
var _wave_tiles: Dictionary = {}          # host: wave -> panels that surged
var _wave_done: Dictionary = {}           # host: wave -> ids of machines that finished it


func _ready() -> void:
	super._ready()
	if multiplayer.is_server():
		for pair in [["countdown_started", _on_countdown_started], ["tick", _on_countdown_tick], ["expired", _on_countdown_expired]]:
			countdown.connect(pair[0], pair[1])
	if GameManager.local_game:
		get_tree().create_timer(1.0).timeout.connect(func(): minigame_ready.emit(1))


func initialize(_round_number: int, _total_rounds: int, _scores: Dictionary = {}):
	super.initialize(_round_number, _total_rounds, _scores)
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
	player_scores[id] = 0
	w.died.connect(_on_player_died)


func _on_countdown_expired():
	super._on_countdown_expired()
	for w in players.values():
		w.set_active_rpc.rpc(true)
	state_machine.transition_to_rpc.rpc(&"Play")
	get_tree().create_timer(1.5, false).timeout.connect(_run_waves)


# --- host: waves ----------------------------------------------------------------

func _run_waves() -> void:
	if _waves_running:
		return
	_waves_running = true
	var warning := first_warning_time
	while not game_end:
		wave += 1
		if wave > max_waves:
			_end_match()
			return
		var tiles := pick_wave_tiles(wave)
		_danger = tiles
		set_tiles_rpc.rpc(FloorGrid.WARNING, tiles, wave)
		await get_tree().create_timer(warning, false).timeout
		if game_end:
			return
		_surging = tiles
		_wave_tiles[wave] = tiles
		set_tiles_rpc.rpc(FloorGrid.LIVE, tiles, wave)
		await get_tree().create_timer(surge_time, false).timeout
		_surging = PackedInt32Array()
		_danger = PackedInt32Array()
		set_tiles_rpc.rpc(FloorGrid.IDLE, tiles, wave)
		await _wait_for_reports(wave)
		if game_end:
			return
		_settle_wave()
		if game_end:
			return
		warning = maxf(min_warning_time, warning * warning_speedup)
		await get_tree().create_timer(pause_between_waves, false).timeout


## Chooses the panels that surge in a wave: a shape (rows, columns, checkerboard, rim, scatter)
## topped up or trimmed at random to the wave's size, always leaving some panels safe.
func pick_wave_tiles(n: int) -> PackedInt32Array:
	var cols: int = grid.columns
	var rows: int = grid.rows
	var total: int = cols * rows
	var safe_min := late_min_safe_tiles if n >= late_wave else min_safe_tiles
	var want := clampi(first_wave_tiles + (n - 1) * tiles_per_wave, 1, total - safe_min)
	var chosen: Array[int] = []
	match randi() % 5:
		0:   # a few full rows
			var r_list := range(rows)
			r_list.shuffle()
			for r in r_list.slice(0, maxi(1, rows / 2)):
				for c in cols:
					chosen.append(r * cols + c)
		1:   # a few full columns
			var c_list := range(cols)
			c_list.shuffle()
			for c in c_list.slice(0, maxi(1, cols / 2)):
				for r in rows:
					chosen.append(r * cols + c)
		2:   # checkerboard
			var parity := randi() % 2
			for i in total:
				if ((i % cols) + (i / cols)) % 2 == parity:
					chosen.append(i)
		3:   # the rim
			for i in total:
				var c := i % cols
				var r := i / cols
				if c == 0 or r == 0 or c == cols - 1 or r == rows - 1:
					chosen.append(i)
		_:
			pass   # pure scatter
	chosen.shuffle()
	if chosen.size() > want:
		chosen = chosen.slice(0, want)
	var rest: Array[int] = []
	for i in total:
		if not chosen.has(i):
			rest.append(i)
	rest.shuffle()
	while chosen.size() < want and not rest.is_empty():
		chosen.append(rest.pop_back())
	chosen.sort()
	return PackedInt32Array(chosen)


func _physics_process(delta: float) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return   # connection lost: the game's own disconnect handling takes over
	if not multiplayer.is_server():
		_check_own_worker()
		return
	if not bot_ids.is_empty():
		_drive_bots(delta)
	if _surging.is_empty() or game_end:
		return
	# the host judges the workers it moves itself: its own, the bots, and everyone in a couch game
	var remote := multiplayer.get_peers()
	for id in active_players.keys():
		if remote.has(id):
			continue   # that machine judges its own worker (_check_own_worker)
		var w = active_players[id]
		if is_instance_valid(w) and _on_tile(w, _surging) >= 0:
			_electrocute(id)


## The panel a worker stands on if it is one of `tiles`, else -1. Falling or shoved-into-the-air
## workers don't touch the floor.
func _on_tile(w: Node3D, tiles: PackedInt32Array) -> int:
	var at: Vector3 = w.global_position
	if at.y < -0.3 or at.y > 1.2:
		return -1
	var t: int = grid.tile_at(at)
	return t if tiles.has(t) else -1


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Online players' machines: is my worker on a panel that is live on my screen?
func _check_own_worker() -> void:
	if _local_live.is_empty() or _reported_wave == _local_wave or not _online():
		return
	var w = _find_player(multiplayer.get_unique_id())
	if w == null or not w.active:
		return
	var tile := _on_tile(w, _local_live)
	if tile >= 0:
		_reported_wave = _local_wave
		w.active = false                    # stop moving right away; the host confirms the shock
		report_shock_rpc.rpc_id(1, _local_wave, tile)
		shock_reported.emit(_local_wave)


@rpc("any_peer", "call_remote", "reliable")
func report_shock_rpc(wave_number: int, tile: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not active_players.has(id) or not _wave_tiles.get(wave_number, PackedInt32Array()).has(tile):
		return
	_electrocute(id)
	if wave_number != wave or _wave_done.has(-wave_number):
		_award_places()                   # that wave was already scored: a place of its own
		if active_players.size() <= 1 and _surging.is_empty():
			_end_match()


@rpc("any_peer", "call_remote", "reliable")
func wave_done_rpc(wave_number: int) -> void:
	if multiplayer.is_server():
		var done: Array = _wave_done.get(wave_number, [])
		done.append(multiplayer.get_remote_sender_id())
		_wave_done[wave_number] = done


## Host: wait until every connected machine with a worker still in play has finished the wave
## (so their shock reports are in), or until report_timeout.
func _wait_for_reports(wave_number: int) -> void:
	var t := 0.0
	while t < report_timeout and not game_end:
		var waiting := false
		var done: Array = _wave_done.get(wave_number, [])
		for id in multiplayer.get_peers():
			if active_players.has(id) and not done.has(id):
				waiting = true
		if not waiting:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	_wave_done[-wave_number] = true      # marks the wave as scored


var _out_this_wave: Array[int] = []

func _electrocute(id: int) -> void:
	if not active_players.has(id):
		return
	zap_rpc.rpc(id)
	var w = players.get(id, null)
	_knock_out(id, "shock")
	if w != null and is_instance_valid(w):
		w.kill_rpc.rpc()


func _knock_out(id: int, reason: String) -> void:
	if not active_players.has(id):
		return
	active_players.erase(id)
	worker_out.emit(id, reason)
	_out_this_wave.append(id)


## After each wave: everyone who went out in it shares the same place.
func _settle_wave() -> void:
	_award_places()
	if active_players.size() <= 1:
		_end_match()


func _award_places() -> void:
	if _out_this_wave.is_empty():
		return
	var already_out := places.size()
	for id in _out_this_wave:
		places[id] = already_out
	_out_this_wave.clear()


func _end_match() -> void:
	if game_end:
		return
	game_end = true
	_surging = PackedInt32Array()
	_danger = PackedInt32Array()
	set_tiles_rpc.rpc(FloorGrid.IDLE, PackedInt32Array(range(grid.tile_count())), wave)
	await get_tree().create_timer(2.5).timeout
	calculate_score()
	finish_game()


func _on_player_died(network_id: int) -> void:
	# fell off the edge (or the worker was killed by a surge: then it's already counted)
	if not active_players.has(network_id):
		return
	_knock_out(network_id, "fall")
	if not _waves_running or _surging.is_empty():
		_award_places()          # between surges: a place of its own
	if active_players.size() <= 1 and _surging.is_empty():
		_end_match()


func calculate_score():
	if _scored:
		return
	_scored = true
	_award_places()
	for id in places:
		player_scores[id] = places[id]
	for id in active_players:
		player_scores[id] = player_count
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
	await get_tree().create_timer(1.0).timeout
	if active_players.size() <= 1 and not game_end and _surging.is_empty():
		_end_match()


# --- practice bots (host only; only when no other machines are connected) ------

func _practice_bot_count() -> int:
	if not multiplayer.get_peers().is_empty():
		return 0
	var loader = get_node_or_null("/root/ModLoader")
	if loader == null:
		return 0
	var reg: Dictionary = loader.registry("power_grid")
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
	for id in bot_ids:
		var bot = active_players.get(id, null)
		if bot == null or not is_instance_valid(bot) or not bot.active:
			continue
		var brain: Dictionary = _bot_brain.get(id, {"t": 0.0, "goal": bot.global_position, "wave": -1})
		brain["t"] -= delta
		if brain["t"] <= 0.0:
			brain["t"] = randf_range(0.2, 0.4)    # reaction time
			brain["goal"] = _bot_goal(id, bot, brain)
		_bot_brain[id] = brain
		var to: Vector3 = brain["goal"] - bot.global_position
		to.y = 0.0
		var dir := Vector3.ZERO if to.length() < 0.4 else to.normalized()
		bot.movement_input = _edge_guard(bot.global_position, dir)
		var at: Vector3 = bot.global_position
		var near_edge := absf(at.x) > ARENA_HALF.x - 2.0 or absf(at.z) > ARENA_HALF.y - 2.0
		if not near_edge and randf() < bot_shove_chance:   # a shove lunges forward: not near the edge
			for other_id in active_players:
				if other_id != id and active_players[other_id].global_position.distance_to(bot.global_position) < 1.6:
					bot.shove()
					break


func _bot_goal(id: int, bot: Node3D, brain: Dictionary) -> Vector3:
	var here: Vector3 = bot.global_position
	if _danger.is_empty():
		# calm: drift around the middle of the floor
		if here.distance_to(brain["goal"]) < 0.6 or randf() < 0.1:
			return Vector3(randf_range(-4.5, 4.5), 0.0, randf_range(-3.0, 3.0))
		return brain["goal"]
	# danger: head for a safe panel. Decide once per wave (sometimes badly), then commit.
	if int(brain["wave"]) == wave:
		return brain["goal"]      # already decided this wave: commit to it
	brain["wave"] = wave
	var best := here
	var best_score := INF
	for i in grid.tile_count():
		if _danger.has(i):
			continue
		var c: Vector3 = grid.tile_center(i)
		var crowd := 0
		for other_id in active_players:
			if other_id != id and grid.tile_at(active_players[other_id].global_position) == i:
				crowd += 1
		var score := here.distance_to(c) + crowd * 1.5 + randf_range(0.0, 1.0)
		if score < best_score:
			best_score = score
			best = c
	if randf() < bot_misjudge_chance:
		best = grid.tile_center(randi() % grid.tile_count())   # panics and runs the wrong way
	return best + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))


func _edge_guard(at: Vector3, dir: Vector3) -> Vector3:
	var limit_x := ARENA_HALF.x - 1.0
	var limit_z := ARENA_HALF.y - 1.0
	if (at.x > limit_x and dir.x > 0.0) or (at.x < -limit_x and dir.x < 0.0):
		dir.x = 0.0
	if (at.z > limit_z and dir.z > 0.0) or (at.z < -limit_z and dir.z < 0.0):
		dir.z = 0.0
	return dir


# --- every player -------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func set_tiles_rpc(state: int, tiles: PackedInt32Array, wave_number: int) -> void:
	if grid:
		if state == FloorGrid.IDLE:
			grid.clear_all()
		else:
			grid.set_tiles(state, tiles)
	match state:
		FloorGrid.WARNING:
			SoundManager.play_omni("collar_activate", -10.0, 0.8)
			wave_phase.emit("warning", wave_number, tiles)
		FloorGrid.LIVE:
			_local_live = tiles
			_local_wave = wave_number
			if surge_sound:
				surge_sound.play()
			wave_phase.emit("surge", wave_number, tiles)
		_:
			_local_live = PackedInt32Array()
			if not multiplayer.is_server() and wave_number > 0 and _online():
				wave_done_rpc.rpc_id(1, wave_number)
			if surge_sound:
				surge_sound.stop()
			wave_phase.emit("clear", wave_number, tiles)


@rpc("authority", "call_local", "reliable")
func zap_rpc(id: int) -> void:
	SoundManager.play_omni("bad_explosion", -6.0, 1.3)
	worker_shocked.emit(id)
	var w = _find_player(id)
	if w and w.get("player_name_label"):
		w.player_name_label.visible = false


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
