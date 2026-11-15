extends CharacterBody3D

enum AIState {
	PATROL,
	STALK,
	INVESTIGATE,
	SEARCH,
	AMBUSH,
	CHASE,
	DOOR_BREACH,
	ATTACK,
}

# Movement speeds (scale dynamically with aggression)
const BASE_PATROL_SPEED = 2.45
const STALK_SPEED = 2.7
const INVESTIGATE_SPEED = 3.5
const SEARCH_SPEED = 2.8
const AMBUSH_SPEED = 4.6
const BASE_CHASE_SPEED = 4.5
const MAX_CHASE_BONUS = 0.65

# Combat & perception tuning
const ATTACK_RANGE = 1.5
const ATTACK_VERTICAL_RANGE = 1.65
const CORE_VISION_RANGE = 20.0
const CORE_VISION_HALF_ANGLE_DEG = 34.0
const PERIPHERAL_VISION_RANGE = 14.0
const PERIPHERAL_HALF_ANGLE_DEG = 76.0
const CROUCH_VISION_MULT = 0.62
const PROXIMITY_SENSE_RANGE = 2.8
const CROUCH_PROXIMITY_RANGE = 1.65

# Tactical timing
const BASE_CHASE_MEMORY_TIME = 4.2
const INVESTIGATE_WAIT_TIME = 2.2
const PATROL_WAIT_TIME = 0.85
const AMBUSH_WAIT_TIME = 2.4
const DOOR_BREACH_PAUSE = 0.25
const DOOR_CHECK_INTERVAL = 0.14
const ANOMALY_SCAN_INTERVAL = 0.65
const STUCK_CHECK_INTERVAL = 0.65
const STUCK_MIN_DISTANCE = 0.16
const GRAVITY = 9.8
const BEAR_TRAP_SCRIPT = preload("res://scripts/bear_trap.gd")
const MAX_ACTIVE_TRAPS = 3
const TRAP_DROP_INTERVAL = 24.0

@export var player_path: NodePath

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer

signal kill(death: bool)
signal ai_state_changed(state_name: String, suspicion_value: float)

var player: Node3D = null
var state_machine = null
var ai_state: AIState = AIState.PATROL
var last_emitted_state: int = -1
var ai_ready: bool = false
var is_attacking: bool = false
var kill_emitted: bool = false
var death: bool = true

# Cognitive memory, multi-floor patrol & spatial heat-map
var patrol_points: Array[Vector3] = []
var patrol_floors: Array[int] = []
var zone_heat: Array[float] = []
var zone_last_visited: Array[float] = []
var floor_last_visited: Dictionary = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}
var current_floor_band: int = 1
var patrols_on_current_floor: int = 0
var current_patrol_idx: int = -1
var current_target_pos: Vector3 = Vector3.ZERO
var nav_bridges_built: bool = false

# Player tracking & prediction
var last_known_player_pos: Vector3 = Vector3.ZERO
var last_known_player_vel: Vector3 = Vector3.ZERO
var prev_player_pos: Vector3 = Vector3.ZERO
var smoothed_player_vel: Vector3 = Vector3.ZERO
var has_prev_player_pos: bool = false

# Suspicion, aggression & timers
var suspicion: float = 0.0
var aggression: float = 0.15
var lose_sight_timer: float = 0.0
var wait_timer: float = 0.0
var state_timer: float = 0.0
var stalk_freeze_timer: float = 0.0
var door_breach_timer: float = 0.0
var post_breach_state: AIState = AIState.PATROL
var last_noise_priority: float = 0.0

# Multi-point search sweep
var search_waypoints: Array[Vector3] = []
var search_step_idx: int = 0

# Environmental forensics (door tampering + locked door avoidance)
var door_memory: Dictionary = {}
var blocked_doors: Array[Dictionary] = []
var anomaly_scan_timer: float = 0.0
var door_check_timer: float = 0.0

# Anti-stuck recovery
var stuck_check_timer: float = 0.0
var last_stuck_check_pos: Vector3 = Vector3.ZERO
var stuck_count: int = 0
var sidestep_dir: Vector3 = Vector3.ZERO
var sidestep_timer: float = 0.0

# Audio timers & traps
var clown_step_timer: float = 0.0
var alert_sfx_cooldown: float = 0.0
var hum_timer: float = 4.0
var time_since_last_seen: float = 999.0
var trap_cooldown_timer: float = 12.0
var active_traps: Array[Area3D] = []


func _ready() -> void:
	add_to_group("enemy")
	randomize()
	player = get_node_or_null(player_path)
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if anim_tree:
		anim_tree.active = true
		state_machine = anim_tree.get("parameters/playback")
	last_stuck_check_pos = global_position
	call_deferred("_init_ai")


func _init_ai() -> void:
	var nav_map: RID = nav_agent.get_navigation_map()
	var sync_frames: int = 0
	while sync_frames < 30:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		sync_frames += 1
		if nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			break

	_snapshot_world_doors()
	if not nav_bridges_built:
		_bridge_navmesh_islands()
		nav_bridges_built = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not is_inside_tree():
			return

	_build_patrol_points()
	ai_ready = true
	_set_state(AIState.PATROL)
	_pick_next_patrol_point()


func _get_floor_band(y_val: float) -> int:
	if y_val < 4.8:
		return 0  # Sewer / Basement
	if y_val < 8.2:
		return 1  # Ground Floor
	if y_val < 11.8:
		return 2  # 1st Floor
	return 3      # Attic / Upper Floor


func _bridge_navmesh_islands() -> void:
	var nav_region := get_parent() as NavigationRegion3D
	if nav_region == null or nav_region.navigation_mesh == null:
		return
	var nav_mesh: NavigationMesh = nav_region.navigation_mesh
	var verts: PackedVector3Array = nav_mesh.get_vertices()
	var poly_count: int = nav_mesh.get_polygon_count()
	if verts.is_empty() or poly_count == 0:
		return

	# Quantize vertices to detect connected polygon islands
	var adj: Dictionary = {}
	var coord_map: Dictionary = {}
	for i in range(poly_count):
		var poly: PackedInt32Array = nav_mesh.get_polygon(i)
		for k in range(poly.size()):
			var v1: Vector3 = nav_region.to_global(verts[poly[k]])
			var v2: Vector3 = nav_region.to_global(verts[poly[(k + 1) % poly.size()]])
			if v1.y > 16.5 or v2.y > 16.5:
				continue
			var key1: Vector3i = Vector3i(roundi(v1.x * 10.0), roundi(v1.y * 10.0), roundi(v1.z * 10.0))
			var key2: Vector3i = Vector3i(roundi(v2.x * 10.0), roundi(v2.y * 10.0), roundi(v2.z * 10.0))
			coord_map[key1] = v1
			coord_map[key2] = v2
			if not adj.has(key1):
				adj[key1] = []
			if not adj.has(key2):
				adj[key2] = []
			(adj[key1] as Array).append(key2)
			(adj[key2] as Array).append(key1)

	var visited: Dictionary = {}
	var islands: Array = []
	for start_k in adj.keys():
		if visited.has(start_k):
			continue
		var queue: Array = [start_k]
		visited[start_k] = true
		var comp: Array[Vector3] = []
		while not queue.is_empty():
			var cur = queue.pop_front()
			comp.append(coord_map[cur])
			for nb in adj[cur]:
				if not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
		islands.append(comp)

	if islands.size() <= 1:
		return

	islands.sort_custom(func(a, b) -> bool: return a.size() > b.size())

	# Iteratively bridge disconnected floor/room islands to the connected main graph
	var connected_pts: Array[Vector3] = []
	for p in islands[0]:
		connected_pts.append(p as Vector3)

	var pending_islands: Array = []
	for idx in range(1, islands.size()):
		pending_islands.append(islands[idx])

	var made_progress: bool = true
	var link_count: int = 0
	while made_progress and not pending_islands.is_empty() and link_count < 24:
		made_progress = false
		for idx in range(pending_islands.size() - 1, -1, -1):
			var isl: Array = pending_islands[idx]
			var best_dist: float = 9999.0
			var best_a: Vector3 = Vector3.ZERO
			var best_b: Vector3 = Vector3.ZERO
			for pa in isl:
				var pva: Vector3 = pa as Vector3
				for pb in connected_pts:
					var d: float = pva.distance_to(pb)
					if d < best_dist:
						best_dist = d
						best_a = pva
						best_b = pb
			if best_dist <= 3.2:
				var link := NavigationLink3D.new()
				link.bidirectional = true
				link.navigation_layers = 1
				link.enter_cost = 1.0
				link.travel_cost = 1.0
				nav_region.add_child(link)
				link.position = Vector3.ZERO
				link.start_position = nav_region.to_local(best_a)
				link.end_position = nav_region.to_local(best_b)
				link_count += 1
				for p in isl:
					connected_pts.append(p)
				pending_islands.remove_at(idx)
				made_progress = true


func _snapshot_world_doors() -> void:
	door_memory.clear()
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and node.has_method("interact"):
			var opened_val = node.get("opened")
			if opened_val is bool:
				var id: int = node.get_instance_id()
				var pos: Vector3 = (node as Node3D).global_position
				# Find associated door leaf PhysicsBody3D (parent of door_lock, or self)
				var door_body: PhysicsBody3D = null
				var door_ref = node.get("door")
				if door_ref is PhysicsBody3D:
					door_body = door_ref as PhysicsBody3D
				elif node is PhysicsBody3D and node.name != "door_lock":
					door_body = node as PhysicsBody3D
				elif node.get_parent() is PhysicsBody3D:
					door_body = node.get_parent() as PhysicsBody3D
				door_memory[id] = {
					"node": node,
					"door_body": door_body,
					"opened": bool(opened_val),
					"pos": pos,
					"ai_ignore_until": 0.0,
				}
		for child in node.get_children():
			stack.append(child)


func _build_patrol_points() -> void:
	patrol_points.clear()
	patrol_floors.clear()
	zone_heat.clear()
	zone_last_visited.clear()

	var nav_map: RID = nav_agent.get_navigation_map()
	var start_nav: Vector3 = _closest_nav_point(global_position)
	var nav_region := get_parent() as NavigationRegion3D
	var candidates: Array[Vector3] = []

	if nav_region and nav_region.navigation_mesh:
		var verts: PackedVector3Array = nav_region.navigation_mesh.get_vertices()
		for v in verts:
			var world_v: Vector3 = nav_region.to_global(v)
			if world_v.y < -4.0 or world_v.y > 16.5:
				continue
			var too_close: bool = false
			for p in candidates:
				if p.distance_to(world_v) < 3.6:
					too_close = true
					break
			if not too_close:
				candidates.append(world_v)

	# Reachability filter across bridged navmesh
	for cand in candidates:
		var snapped: Vector3 = _closest_nav_point(cand)
		if nav_map.is_valid():
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start_nav, snapped, true)
			if path.is_empty():
				continue
			var path_end: Vector3 = path[path.size() - 1]
			if path_end.distance_to(snapped) > 2.2:
				continue
		patrol_points.append(snapped)
		patrol_floors.append(_get_floor_band(snapped.y))
		zone_heat.append(0.1)
		zone_last_visited.append(0.0)

	if patrol_points.is_empty():
		for angle_deg in [0, 60, 120, 180, 240, 300]:
			var rad: float = deg_to_rad(float(angle_deg))
			var fallback_pt: Vector3 = _closest_nav_point(
				global_position + Vector3(cos(rad) * 5.5, 0.0, sin(rad) * 5.5)
			)
			patrol_points.append(fallback_pt)
			patrol_floors.append(_get_floor_band(fallback_pt.y))
			zone_heat.append(0.1)
			zone_last_visited.append(0.0)


func notify_world_changed() -> void:
	blocked_doors.clear()
	_build_patrol_points()


func notify_player_progress(amount: float = 0.14) -> void:
	aggression = clampf(aggression + amount, 0.0, 1.0)
	if is_instance_valid(player):
		_add_heat_near(player.global_position, 2.2)


func _closest_nav_point(world_pos: Vector3) -> Vector3:
	var nav_map: RID = nav_agent.get_navigation_map()
	if nav_map.is_valid():
		return NavigationServer3D.map_get_closest_point(nav_map, world_pos)
	return world_pos


func _is_position_blocked(pos: Vector3) -> bool:
	var now: float = Time.get_ticks_msec() * 0.001
	for i in range(blocked_doors.size() - 1, -1, -1):
		var entry: Dictionary = blocked_doors[i]
		if now > float(entry["until"]):
			blocked_doors.remove_at(i)
			continue
		var door_pos: Vector3 = entry["pos"]
		if door_pos.distance_to(pos) < 2.2:
			return true
	return false


func _add_heat_near(world_pos: Vector3, amount: float) -> void:
	for i in range(patrol_points.size()):
		var d: float = patrol_points[i].distance_to(world_pos)
		if d < 12.0:
			var falloff: float = 1.0 - (d / 12.0)
			zone_heat[i] = clampf(zone_heat[i] + amount * falloff, 0.0, 6.0)


func _set_state(new_state: AIState) -> void:
	if ai_state == new_state:
		return
	var prev_state: AIState = ai_state
	ai_state = new_state
	state_timer = 0.0
	if ai_state == AIState.CHASE and prev_state != AIState.CHASE and alert_sfx_cooldown <= 0.0:
		alert_sfx_cooldown = 4.5
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx_3d("clown_alert", global_position, 2.0, randf_range(0.95, 1.06), 28.0)
	if int(ai_state) != last_emitted_state:
		last_emitted_state = int(ai_state)
		var names: Array[String] = ["PATROL", "STALK", "INVESTIGATE", "SEARCH", "AMBUSH", "CHASE", "DOOR_BREACH", "ATTACK"]
		ai_state_changed.emit(names[int(ai_state)], suspicion)


func _pick_next_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var my_floor: int = _get_floor_band(global_position.y)
	if my_floor == current_floor_band:
		patrols_on_current_floor += 1
	else:
		current_floor_band = my_floor
		patrols_on_current_floor = 1

	var force_floor_change: bool = patrols_on_current_floor >= 2
	var best_idx: int = -1
	var best_score: float = -100000.0

	for i in range(patrol_points.size()):
		if i == current_patrol_idx and patrol_points.size() > 1:
			continue
		var pt: Vector3 = patrol_points[i]
		var dist: float = pt.distance_to(global_position)
		if dist < 2.5 or _is_position_blocked(pt):
			continue
		var band: int = patrol_floors[i]
		var staleness: float = minf(now - zone_last_visited[i], 80.0)
		var floor_staleness: float = minf(now - float(floor_last_visited.get(band, 0.0)), 60.0)
		var cross_floor_bonus: float = 0.0
		if band != my_floor:
			cross_floor_bonus = (26.0 if force_floor_change else 8.0) + floor_staleness * 0.65
		var score: float = staleness * 1.1 + zone_heat[i] * 3.4 + cross_floor_bonus - dist * 0.08 + randf_range(0.0, 8.0)
		if score > best_score:
			best_score = score
			best_idx = i

	if best_idx == -1:
		best_idx = randi() % patrol_points.size()

	current_patrol_idx = best_idx
	var chosen_band: int = patrol_floors[best_idx]
	if chosen_band != current_floor_band:
		patrols_on_current_floor = 0
		current_floor_band = chosen_band
	floor_last_visited[chosen_band] = now
	zone_last_visited[best_idx] = now
	current_target_pos = patrol_points[best_idx]
	nav_agent.set_target_position(current_target_pos)
	stuck_count = 0


func hear_noise(noise_pos: Vector3, radius: float, priority: float = 1.0) -> void:
	if not ai_ready or is_attacking:
		return
	var vertical_diff: float = absf(noise_pos.y - global_position.y)
	var effective_radius: float = radius * (0.72 if vertical_diff > 3.0 else 1.0)
	var dist: float = global_position.distance_to(noise_pos)
	if dist > effective_radius:
		return

	_add_heat_near(noise_pos, 1.1 * priority)
	var closeness: float = 1.0 - (dist / maxf(effective_radius, 0.1))
	suspicion = clampf(suspicion + (24.0 + 38.0 * closeness) * priority, 0.0, 100.0)

	var nav_target: Vector3 = _closest_nav_point(noise_pos)
	if ai_state == AIState.CHASE:
		if not _can_see_player_core():
			last_known_player_pos = nav_target
			nav_agent.set_target_position(last_known_player_pos)
		return

	if ai_state == AIState.INVESTIGATE and priority < last_noise_priority and dist > current_target_pos.distance_to(global_position):
		return

	last_noise_priority = priority
	last_known_player_pos = nav_target
	current_target_pos = nav_target
	nav_agent.set_target_position(current_target_pos)
	wait_timer = INVESTIGATE_WAIT_TIME
	stuck_count = 0
	_set_state(AIState.INVESTIGATE)


func _get_player_eye_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var is_crouched: bool = player.get("crouched") == true
	var y_offset: float = 0.75 if is_crouched else 1.35
	return player.global_position + Vector3(0.0, y_offset, 0.0)


func _is_player_crouched() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return player.get("crouched") == true


func _is_player_facing_me() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var player_head: Node3D = player.get_node_or_null("head") as Node3D
	var player_fwd: Vector3 = -player_head.global_transform.basis.z if player_head else -player.global_transform.basis.z
	player_fwd.y = 0.0
	var to_clown: Vector3 = global_position - player.global_position
	to_clown.y = 0.0
	if player_fwd.length_squared() < 0.001 or to_clown.length_squared() < 0.001:
		return true
	return player_fwd.normalized().dot(to_clown.normalized()) > 0.35


func _has_line_of_sight_to_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3(0.0, 1.52, 0.0)
	var target: Vector3 = _get_player_eye_pos()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	query.collision_mask = 1 | 2 | 4
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == player


func _evaluate_vision() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var is_player_hidden: bool = player.get("is_hidden") == true
	if is_player_hidden and time_since_last_seen > 3.0:
		return 0

	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	if absf(to_player.y) > 6.0:
		return 0

	var crouched: bool = _is_player_crouched()
	var light_on: bool = player.get("flashlight_on") != false
	var light_mult: float = 1.0 if light_on else 0.72
	var prox_range: float = CROUCH_PROXIMITY_RANGE if (crouched and smoothed_player_vel.length() < 0.4) else PROXIMITY_SENSE_RANGE
	if dist <= prox_range:
		return 2 if _has_line_of_sight_to_player() else 0

	var core_range: float = CORE_VISION_RANGE * (CROUCH_VISION_MULT if crouched else 1.0) * light_mult
	var periph_range: float = PERIPHERAL_VISION_RANGE * (CROUCH_VISION_MULT if crouched else 1.0) * light_mult
	if dist > core_range:
		return 0

	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	var to_horiz: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	if forward.length_squared() < 0.001 or to_horiz.length_squared() < 0.001:
		return 0

	var cos_angle: float = forward.normalized().dot(to_horiz.normalized())
	if cos_angle >= cos(deg_to_rad(CORE_VISION_HALF_ANGLE_DEG)):
		return 2 if _has_line_of_sight_to_player() else 0
	if dist <= periph_range and cos_angle >= cos(deg_to_rad(PERIPHERAL_HALF_ANGLE_DEG)):
		return 1 if _has_line_of_sight_to_player() else 0
	return 0


func _can_see_player_core() -> bool:
	return _evaluate_vision() == 2


func _target_in_attack_range() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var diff: Vector3 = player.global_position - global_position
	var horiz_dist: float = Vector2(diff.x, diff.z).length()
	if horiz_dist > ATTACK_RANGE or absf(diff.y) > ATTACK_VERTICAL_RANGE:
		return false
	return _has_line_of_sight_to_player()


func _scan_environmental_anomalies() -> void:
	if ai_state == AIState.CHASE or ai_state == AIState.ATTACK or ai_state == AIState.DOOR_BREACH:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var eye_origin: Vector3 = global_position + Vector3(0.0, 1.5, 0.0)

	for id in door_memory.keys():
		var info: Dictionary = door_memory[id]
		var door_node: Node = info["node"]
		if not is_instance_valid(door_node):
			continue
		if now < float(info["ai_ignore_until"]):
			continue
		var door_pos: Vector3 = info["pos"]
		if door_pos.distance_to(global_position) > 10.5 or absf(door_pos.y - global_position.y) > 2.8:
			continue
		var current_opened: bool = door_node.get("opened") == true
		var remembered_opened: bool = bool(info["opened"])
		if current_opened == remembered_opened:
			continue

		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye_origin, door_pos + Vector3(0.0, 0.8, 0.0))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit: Dictionary = space_state.intersect_ray(q)
		if not hit.is_empty():
			continue

		info["opened"] = current_opened
		suspicion = clampf(suspicion + 45.0, 0.0, 100.0)
		_add_heat_near(door_pos, 2.2)
		last_known_player_pos = _closest_nav_point(door_pos)
		current_target_pos = last_known_player_pos
		nav_agent.set_target_position(current_target_pos)
		wait_timer = INVESTIGATE_WAIT_TIME
		_set_state(AIState.INVESTIGATE)
		return


func _temp_ignore_door_body(body: PhysicsBody3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	add_collision_exception_with(body)
	var t := get_tree().create_timer(1.4)
	t.timeout.connect(func():
		if is_instance_valid(self) and is_instance_valid(body):
			remove_collision_exception_with(body)
	)


func _resolve_door_interact_node(col: Object) -> Node:
	if col == null or not is_instance_valid(col):
		return null
	if col is Node:
		var node: Node = col as Node
		if node.has_method("interact"):
			return node
		var lock_child: Node = node.get_node_or_null("door_lock")
		if lock_child and lock_child.has_method("interact"):
			return lock_child
		if node.get_parent() and node.get_parent().has_method("interact"):
			return node.get_parent()
	return null


func _open_door_node(door_node: Node, door_body: PhysicsBody3D, fallback_pos: Vector3) -> int:
	if door_node == null or not is_instance_valid(door_node):
		return 0
	var locked: bool = (door_node.get("keyreq") == true) or (door_node.get("beatreq") == true) or (door_node.get("pinreq") == true)
	var door_pos: Vector3 = (door_node as Node3D).global_position if door_node is Node3D else fallback_pos
	if locked:
		if not _is_position_blocked(door_pos):
			blocked_doors.append({
				"pos": door_pos,
				"until": Time.get_ticks_msec() * 0.001 + 22.0,
			})
		return 2

	if door_node.get("opened") == false:
		var cid: int = door_node.get_instance_id()
		if door_memory.has(cid):
			door_memory[cid]["opened"] = true
			door_memory[cid]["ai_ignore_until"] = Time.get_ticks_msec() * 0.001 + 4.5
		if door_body:
			_temp_ignore_door_body(door_body)
		elif door_node.get_parent() is PhysicsBody3D:
			_temp_ignore_door_body(door_node.get_parent() as PhysicsBody3D)
		elif door_node is PhysicsBody3D:
			_temp_ignore_door_body(door_node as PhysicsBody3D)
		door_node.interact()
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx_3d("door_open", door_pos, -2.0, randf_range(0.85, 1.05), 18.0)
		return 1
	return 0


func _check_door_ahead(move_dir: Vector3) -> int:
	# Returns: 0 = clear, 1 = unlocked door being opened, 2 = locked door blocking path
	if move_dir.length_squared() < 0.01:
		return 0
	var dir_horiz: Vector3 = Vector3(move_dir.x, 0.0, move_dir.z).normalized()

	# 1) Proximity check against snapshotted doors in front of clown (catches doors even when ray misses tiny knob!)
	for id in door_memory.keys():
		var info: Dictionary = door_memory[id]
		var dnode: Node = info["node"]
		if not is_instance_valid(dnode) or dnode.get("opened") != false:
			continue
		var dpos: Vector3 = info["pos"]
		if absf(dpos.y - global_position.y) > 2.2:
			continue
		var to_door: Vector3 = Vector3(dpos.x - global_position.x, 0.0, dpos.z - global_position.z)
		var dist: float = to_door.length()
		if dist < 2.15 and dist > 0.05:
			if dir_horiz.dot(to_door / dist) > 0.15:
				var dbody: PhysicsBody3D = info.get("door_body") as PhysicsBody3D
				var res: int = _open_door_node(dnode, dbody, dpos)
				if res != 0:
					return res

	# 2) Forward raycast on both layer 1 (door panel) and layer 4 (door lock/knob)
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3(0.0, 1.1, 0.0)
	var target: Vector3 = origin + dir_horiz * 1.85
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	query.collision_mask = 1 | 4
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return 0
	var col = hit.get("collider")
	var door_node: Node = _resolve_door_interact_node(col)
	if door_node == null:
		return 0
	var hit_body: PhysicsBody3D = col as PhysicsBody3D
	return _open_door_node(door_node, hit_body, target)


func _build_search_fan(center_pos: Vector3) -> void:
	search_waypoints.clear()
	search_step_idx = 0
	var base: Vector3 = _closest_nav_point(center_pos)
	search_waypoints.append(base)
	var forward_dir: Vector3 = last_known_player_vel
	forward_dir.y = 0.0
	if forward_dir.length_squared() < 0.04:
		forward_dir = -global_transform.basis.z
		forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()
	var side_dir: Vector3 = Vector3(-forward_dir.z, 0.0, forward_dir.x)

	var offsets: Array[Vector3] = [
		forward_dir * 3.5 + side_dir * 2.2,
		forward_dir * 3.5 - side_dir * 2.2,
		forward_dir * 5.2,
	]
	for off in offsets:
		var cand: Vector3 = _closest_nav_point(base + off)
		if cand.distance_to(base) > 1.2:
			search_waypoints.append(cand)


func _compute_chase_intercept_target() -> Vector3:
	if player == null or not is_instance_valid(player):
		return last_known_player_pos
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= 4.2 or smoothed_player_vel.length() < 1.2:
		return _closest_nav_point(player.global_position)
	var lookahead: float = clampf(dist * 0.14, 0.25, 1.05)
	var predicted: Vector3 = player.global_position + smoothed_player_vel * lookahead
	return _closest_nav_point(predicted)


func _trigger_attack() -> void:
	if is_attacking or kill_emitted:
		return
	is_attacking = true
	_set_state(AIState.ATTACK)
	velocity = Vector3.ZERO
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.set_chase_intensity(1.0)
		am.play_sfx("clown_jumpscare", 3.0, 1.0)

	if anim_tree:
		anim_tree.set("parameters/conditions/attack", true)
		anim_tree.set("parameters/conditions/run", false)
	if state_machine and state_machine.has_method("travel"):
		state_machine.travel("Attack")

	if is_instance_valid(player):
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
		if player.has_method("force_look_at_enemy"):
			player.force_look_at_enemy(global_position + Vector3(0.0, 1.55, 0.0))
		player.set_physics_process(false)
		player.set_process_input(false)
		player.set_process_unhandled_input(false)

	await get_tree().create_timer(0.88).timeout
	if not is_inside_tree():
		return
	if not kill_emitted:
		kill_emitted = true
		kill.emit(death)


func _update_player_velocity(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not has_prev_player_pos:
		prev_player_pos = player.global_position
		has_prev_player_pos = true
		return
	if delta > 0.0001:
		var inst_vel: Vector3 = (player.global_position - prev_player_pos) / delta
		inst_vel.y = 0.0
		smoothed_player_vel = smoothed_player_vel.lerp(inst_vel, clampf(delta * 8.0, 0.0, 1.0))
	prev_player_pos = player.global_position


func _physics_process(delta: float) -> void:
	if not ai_ready:
		return

	aggression = clampf(aggression + delta * 0.0018, 0.0, 1.0)
	for i in range(zone_heat.size()):
		zone_heat[i] = maxf(zone_heat[i] - delta * 0.015, 0.0)

	if is_attacking:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if is_instance_valid(player):
			var to_p: Vector3 = player.global_position - global_position
			var target_yaw: float = atan2(-to_p.x, -to_p.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, delta * 14.0)
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		return

	_update_player_velocity(delta)
	state_timer += delta
	time_since_last_seen += delta
	if alert_sfx_cooldown > 0.0:
		alert_sfx_cooldown -= delta

	# Creepy 3D patrol hum so player hears the clown roaming nearby floors
	hum_timer -= delta
	if hum_timer <= 0.0:
		hum_timer = randf_range(7.0, 12.5)
		if ai_state == AIState.PATROL or ai_state == AIState.STALK or ai_state == AIState.SEARCH:
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx_3d("clown_hum", global_position, -7.5, randf_range(0.92, 1.06), 19.0)

	_update_trap_placement(delta)

	# Dynamic tension / heartbeat feedback for AudioManager
	if has_node("/root/AudioManager"):
		var dist_p: float = global_position.distance_to(player.global_position)
		var proximity_tension: float = clampf(1.0 - (dist_p / 16.0), 0.0, 1.0)
		var state_bonus: float = 0.0
		if ai_state == AIState.CHASE:
			state_bonus = 0.55
		elif ai_state == AIState.AMBUSH or ai_state == AIState.STALK:
			state_bonus = 0.30
		elif ai_state == AIState.SEARCH or ai_state == AIState.INVESTIGATE:
			state_bonus = 0.18
		get_node("/root/AudioManager").set_chase_intensity(clampf(proximity_tension * 0.75 + state_bonus, 0.0, 1.0))

	if _target_in_attack_range():
		_trigger_attack()
		return

	anomaly_scan_timer += delta
	if anomaly_scan_timer >= ANOMALY_SCAN_INTERVAL:
		anomaly_scan_timer = 0.0
		_scan_environmental_anomalies()

	var vision: int = _evaluate_vision()
	var dist_to_player: float = global_position.distance_to(player.global_position)

	if vision == 2:
		time_since_last_seen = 0.0
		last_known_player_pos = _closest_nav_point(player.global_position)
		last_known_player_vel = smoothed_player_vel
		_add_heat_near(player.global_position, delta * 2.5)
		suspicion = clampf(suspicion + delta * (120.0 if dist_to_player < 9.0 else 75.0), 0.0, 100.0)
		lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.5

		if ai_state != AIState.CHASE and dist_to_player > 9.5 and not _is_player_facing_me():
			_set_state(AIState.STALK)
			nav_agent.set_target_position(last_known_player_pos)
		elif suspicion >= 65.0 or dist_to_player <= 9.5 or _is_player_facing_me():
			_set_state(AIState.CHASE)
	elif vision == 1:
		var gain_rate: float = (68.0 if not _is_player_crouched() else 38.0) * (1.0 + aggression * 0.4)
		suspicion = clampf(suspicion + delta * gain_rate, 0.0, 100.0)
		last_known_player_pos = _closest_nav_point(player.global_position)
		last_known_player_vel = smoothed_player_vel
		if suspicion >= 82.0:
			lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.0
			_set_state(AIState.CHASE)
		elif suspicion >= 38.0 and ai_state == AIState.PATROL:
			current_target_pos = last_known_player_pos
			nav_agent.set_target_position(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)
	else:
		suspicion = maxf(suspicion - delta * 9.0, 0.0)
		if ai_state == AIState.CHASE:
			lose_sight_timer -= delta
			if lose_sight_timer <= 0.0:
				if last_known_player_vel.length() > 2.0 and aggression >= 0.30:
					var cutoff: Vector3 = _closest_nav_point(
						last_known_player_pos + last_known_player_vel.normalized() * 5.5
					)
					current_target_pos = cutoff
					nav_agent.set_target_position(cutoff)
					wait_timer = AMBUSH_WAIT_TIME
					_set_state(AIState.AMBUSH)
				else:
					_build_search_fan(last_known_player_pos)
					nav_agent.set_target_position(search_waypoints[0])
					wait_timer = 1.1
					_set_state(AIState.SEARCH)
		elif ai_state == AIState.STALK:
			current_target_pos = last_known_player_pos
			nav_agent.set_target_position(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)

	if anim_tree:
		anim_tree.set("parameters/conditions/attack", false)
		anim_tree.set("parameters/conditions/run", true)

	var move_speed: float = BASE_PATROL_SPEED + aggression * 0.35
	var should_move: bool = true

	match ai_state:
		AIState.CHASE:
			move_speed = BASE_CHASE_SPEED + aggression * MAX_CHASE_BONUS
			if vision == 2:
				nav_agent.set_target_position(_compute_chase_intercept_target())
			elif nav_agent.is_navigation_finished():
				_build_search_fan(last_known_player_pos)
				nav_agent.set_target_position(search_waypoints[0])
				wait_timer = 1.0
				_set_state(AIState.SEARCH)
		AIState.STALK:
			if _is_player_facing_me() and dist_to_player > 10.5 and stalk_freeze_timer <= 0.0:
				stalk_freeze_timer = 0.55
			if stalk_freeze_timer > 0.0:
				stalk_freeze_timer -= delta
				should_move = false
			else:
				move_speed = STALK_SPEED
				nav_agent.set_target_position(last_known_player_pos)
				if dist_to_player <= 7.8 or _is_player_facing_me():
					lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.0
					_set_state(AIState.CHASE)
		AIState.INVESTIGATE:
			move_speed = INVESTIGATE_SPEED + aggression * 0.25
			if nav_agent.is_navigation_finished():
				should_move = false
				wait_timer -= delta
				rotation.y += sin(Time.get_ticks_msec() * 0.0045) * delta * 1.9
				if wait_timer <= 0.0:
					_build_search_fan(current_target_pos)
					if search_waypoints.size() > 1:
						search_step_idx = 1
						nav_agent.set_target_position(search_waypoints[1])
						wait_timer = 0.9
						_set_state(AIState.SEARCH)
					else:
						_set_state(AIState.PATROL)
						_pick_next_patrol_point()
		AIState.SEARCH:
			move_speed = SEARCH_SPEED
			if nav_agent.is_navigation_finished():
				should_move = false
				wait_timer -= delta
				rotation.y += sin(Time.get_ticks_msec() * 0.0055) * delta * 2.2
				if wait_timer <= 0.0:
					search_step_idx += 1
					if search_step_idx < search_waypoints.size():
						nav_agent.set_target_position(search_waypoints[search_step_idx])
						wait_timer = 0.95
					else:
						_set_state(AIState.PATROL)
						_pick_next_patrol_point()
		AIState.AMBUSH:
			move_speed = AMBUSH_SPEED
			if nav_agent.is_navigation_finished():
				should_move = false
				wait_timer -= delta
				if last_known_player_vel.length() > 0.2:
					var watch_yaw: float = atan2(last_known_player_vel.x, last_known_player_vel.z)
					rotation.y = lerp_angle(rotation.y, watch_yaw, delta * 3.0)
				if wait_timer <= 0.0:
					_build_search_fan(current_target_pos)
					nav_agent.set_target_position(search_waypoints[0])
					wait_timer = 0.85
					_set_state(AIState.SEARCH)
		AIState.DOOR_BREACH:
			should_move = false
			door_breach_timer -= delta
			if door_breach_timer <= 0.0:
				_set_state(post_breach_state)
		AIState.PATROL:
			move_speed = BASE_PATROL_SPEED + aggression * 0.35
			if nav_agent.is_navigation_finished() or state_timer > 22.0:
				should_move = false
				if wait_timer <= 0.0:
					wait_timer = PATROL_WAIT_TIME
				else:
					wait_timer -= delta
					if wait_timer <= 0.0:
						_pick_next_patrol_point()
						state_timer = 0.0

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if should_move:
		var next_nav_point: Vector3 = nav_agent.get_next_path_position()
		var to_next: Vector3 = next_nav_point - global_position
		var horiz_dir: Vector3 = Vector3(to_next.x, 0.0, to_next.z)

		if sidestep_timer > 0.0:
			sidestep_timer -= delta
			horiz_dir = sidestep_dir

		if horiz_dir.length_squared() > 0.001:
			horiz_dir = horiz_dir.normalized()
			velocity.x = horiz_dir.x * move_speed
			velocity.z = horiz_dir.z * move_speed
			rotation.y = lerp_angle(rotation.y, atan2(-horiz_dir.x, -horiz_dir.z), delta * 11.0)

			door_check_timer -= delta
			if door_check_timer <= 0.0:
				door_check_timer = DOOR_CHECK_INTERVAL
				var door_res: int = _check_door_ahead(horiz_dir)
				if door_res == 1:
					post_breach_state = ai_state
					door_breach_timer = DOOR_BREACH_PAUSE
					_set_state(AIState.DOOR_BREACH)
					velocity.x = 0.0
					velocity.z = 0.0
				elif door_res == 2:
					if ai_state != AIState.CHASE:
						_set_state(AIState.PATROL)
						_pick_next_patrol_point()
		else:
			velocity.x = 0.0
			velocity.z = 0.0

		stuck_check_timer += delta
		if stuck_check_timer >= STUCK_CHECK_INTERVAL:
			stuck_check_timer = 0.0
			var moved: float = Vector2(
				global_position.x - last_stuck_check_pos.x,
				global_position.z - last_stuck_check_pos.z
			).length()
			last_stuck_check_pos = global_position
			if moved < STUCK_MIN_DISTANCE:
				stuck_count += 1
				if stuck_count == 1:
					# Try opening any nearby door before sidestepping
					if _check_door_ahead(-global_transform.basis.z) == 1:
						stuck_count = 0
					else:
						var side: Vector3 = Vector3(-horiz_dir.z, 0.0, horiz_dir.x)
						if randf() < 0.5:
							side = -side
						sidestep_dir = side.normalized()
						sidestep_timer = 0.45
						nav_agent.set_target_position(nav_agent.target_position)
				else:
					stuck_count = 0
					if ai_state != AIState.CHASE or vision != 2:
						_set_state(AIState.PATROL)
						_pick_next_patrol_point()
					else:
						var side2: Vector3 = Vector3(-horiz_dir.z, 0.0, horiz_dir.x)
						sidestep_dir = (side2 if randf() < 0.5 else -side2).normalized()
						sidestep_timer = 0.6
			else:
				stuck_count = 0
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 9.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 9.0)

	# 3D Spatial Clown Footsteps
	var clown_horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and clown_horiz_speed > 0.8 and not is_attacking:
		clown_step_timer -= delta
		if clown_step_timer <= 0.0:
			clown_step_timer = clampf(1.22 / maxf(clown_horiz_speed, 1.0), 0.24, 0.58)
			if has_node("/root/AudioManager"):
				var vol: float = -3.0 if ai_state == AIState.CHASE else -7.5
				get_node("/root/AudioManager").play_sfx_3d("footstep_clown", global_position, vol, randf_range(0.86, 1.08), 22.0)
	else:
		clown_step_timer = 0.05

	move_and_slide()


func _hit_finished() -> void:
	if player and is_instance_valid(player) and global_position.distance_to(player.global_position) < ATTACK_RANGE + 1.0:
		var dir: Vector3 = global_position.direction_to(player.global_position)
		if player.has_method("hit"):
			player.hit(dir)


func _update_trap_placement(delta: float) -> void:
	for i in range(active_traps.size() - 1, -1, -1):
		if not is_instance_valid(active_traps[i]):
			active_traps.remove_at(i)
	if not is_on_floor() or active_traps.size() >= MAX_ACTIVE_TRAPS:
		return
	if ai_state != AIState.PATROL and ai_state != AIState.INVESTIGATE and ai_state != AIState.SEARCH:
		return
	trap_cooldown_timer -= delta
	if trap_cooldown_timer <= 0.0:
		trap_cooldown_timer = TRAP_DROP_INTERVAL
		if is_instance_valid(player) and global_position.distance_to(player.global_position) < 3.5:
			return
		var trap_pos: Vector3 = _closest_nav_point(global_position)
		for t in active_traps:
			if t.global_position.distance_to(trap_pos) < 4.0:
				return
		var trap := Area3D.new()
		trap.set_script(BEAR_TRAP_SCRIPT)
		var scene_root: Node = get_tree().current_scene
		if scene_root:
			scene_root.add_child(trap)
			trap.global_position = trap_pos
			active_traps.append(trap)
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx_3d("door_locked", trap_pos, -4.5, 0.8, 16.0)


func reset_for_new_day(day: int) -> void:
	is_attacking = false
	kill_emitted = false
	suspicion = 0.0
	time_since_last_seen = 999.0
	aggression = clampf(0.15 + float(day - 1) * 0.14, 0.15, 0.9)
	velocity = Vector3.ZERO
	stuck_count = 0
	sidestep_timer = 0.0
	wait_timer = 0.5
	if anim_tree:
		anim_tree.set("parameters/conditions/attack", false)
		anim_tree.set("parameters/conditions/run", true)
	if state_machine and state_machine.has_method("travel"):
		state_machine.travel("Run")
	_set_state(AIState.PATROL)
	_pick_next_patrol_point()
