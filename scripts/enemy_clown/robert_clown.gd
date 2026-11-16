extends CharacterBody3D

const ATTACK_RANGE: float = 1.5
const ATTACK_VERTICAL_RANGE: float = 1.65
const DOOR_CHECK_INTERVAL: float = 0.14
const STUCK_CHECK_INTERVAL: float = 0.65
const STUCK_MIN_DISTANCE: float = 0.18
const GRAVITY: float = 9.8
const BEAR_TRAP_SCRIPT = preload("res://scripts/bear_trap.gd")

@export var player_path: NodePath

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer

signal kill(death: bool)
signal ai_state_changed(state_name: String, suspicion_value: float)

var player: Node3D = null
var state_machine = null
var ai_brain: Node = null
var ai_ready: bool = false
var is_attacking: bool = false
var kill_emitted: bool = false
var death: bool = true

# Multi-floor patrol & spatial heat-map
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

# Player velocity tracking
var prev_player_pos: Vector3 = Vector3.ZERO
var smoothed_player_vel: Vector3 = Vector3.ZERO
var has_prev_player_pos: bool = false

# Doors & obstacle avoidance
var door_memory: Dictionary = {}
var blocked_doors: Array[Dictionary] = []
var door_check_timer: float = 0.0
var stuck_check_timer: float = 0.0
var last_stuck_check_pos: Vector3 = Vector3.ZERO
var stuck_count: int = 0
var sidestep_dir: Vector3 = Vector3.ZERO
var sidestep_timer: float = 0.0

# Audio & traps
var clown_step_timer: float = 0.0
var alert_sfx_cooldown: float = 0.0
var hum_timer: float = 4.0
var trap_cooldown_timer: float = 14.0
var active_traps: Array[Area3D] = []
var max_active_traps: int = 2
var trap_drop_interval: float = 36.0


func _ready() -> void:
	add_to_group("enemy")
	randomize()
	player = get_node_or_null(player_path)
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if anim_tree:
		anim_tree.active = true
		state_machine = anim_tree.get("parameters/playback")
	if nav_agent:
		nav_agent.path_desired_distance = 0.70
		nav_agent.target_desired_distance = 0.90
	last_stuck_check_pos = global_position
	_load_difficulty_brain()
	call_deferred("_init_ai")


func _load_difficulty_brain() -> void:
	if ai_brain and is_instance_valid(ai_brain):
		ai_brain.queue_free()
		ai_brain = null

	var script_path: String = "res://scripts/enemy_clown/ai_normal.gd"
	if has_node("/root/GameSettings"):
		script_path = str(get_node("/root/GameSettings").get_difficulty_script_path())

	var brain_script: Script = load(script_path) as Script
	if brain_script == null:
		brain_script = load("res://scripts/enemy_clown/ai_normal.gd") as Script

	ai_brain = Node.new()
	ai_brain.name = "AIBrain"
	ai_brain.set_script(brain_script)
	add_child(ai_brain)

	if ai_brain.has_method("get_trap_config"):
		var cfg: Dictionary = ai_brain.get_trap_config()
		max_active_traps = int(cfg.get("max_traps", 2))
		trap_drop_interval = float(cfg.get("interval", 36.0))
		trap_cooldown_timer = minf(trap_drop_interval * 0.55, 16.0)


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
	if ai_brain and ai_brain.has_method("setup"):
		ai_brain.setup(self)


func _get_floor_band(y_val: float) -> int:
	if y_val < 4.8:
		return 0  # Sewer / Basement
	if y_val < 8.2:
		return 1  # Ground Floor
	if y_val < 11.8:
		return 2  # 1st Floor
	return 3      # Attic / Upper Floor


func _is_bridge_clear_of_walls(a: Vector3, b: Vector3) -> bool:
	if absf(a.y - b.y) > 2.35:
		return false
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var p1: Vector3 = a + Vector3(0.0, 0.95, 0.0)
	var p2: Vector3 = b + Vector3(0.0, 0.95, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(p1, p2)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	# Allow bridging through an openable door panel, reject solid house walls!
	var col = hit.get("collider")
	return _resolve_door_interact_node(col) != null


func _bridge_navmesh_islands() -> void:
	var nav_region := get_parent() as NavigationRegion3D
	if nav_region == null or nav_region.navigation_mesh == null:
		return
	var nav_mesh: NavigationMesh = nav_region.navigation_mesh
	var verts: PackedVector3Array = nav_mesh.get_vertices()
	var poly_count: int = nav_mesh.get_polygon_count()
	if verts.is_empty() or poly_count == 0:
		return

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
					if d < best_dist and d <= 2.85 and _is_bridge_clear_of_walls(pva, pb):
						best_dist = d
						best_a = pva
						best_b = pb
			if best_dist <= 2.85:
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
					connected_pts.append(p as Vector3)
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
	var start_nav: Vector3 = closest_nav_point(global_position)
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

	for cand in candidates:
		var snapped: Vector3 = closest_nav_point(cand)
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
			var fallback_pt: Vector3 = closest_nav_point(
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
	if ai_brain and ai_brain.has_method("on_player_progress"):
		ai_brain.on_player_progress(amount)
	if is_instance_valid(player):
		add_heat_near(player.global_position, 2.2)


func closest_nav_point(world_pos: Vector3) -> Vector3:
	var nav_map: RID = nav_agent.get_navigation_map()
	if nav_map.is_valid():
		return NavigationServer3D.map_get_closest_point(nav_map, world_pos)
	return world_pos


func set_nav_target(target_pos: Vector3) -> void:
	current_target_pos = target_pos
	if nav_agent:
		nav_agent.set_target_position(target_pos)


func is_nav_finished() -> bool:
	if nav_agent == null:
		return true
	return nav_agent.is_navigation_finished()


func emit_ai_state(state_name: String, suspicion_val: float) -> void:
	ai_state_changed.emit(state_name, suspicion_val)


func play_alert_sfx() -> void:
	if alert_sfx_cooldown <= 0.0:
		alert_sfx_cooldown = 4.5
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx_3d("clown_alert", global_position, 2.0, randf_range(0.95, 1.06), 28.0)


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


func _mark_temp_blocked(pos: Vector3, duration: float) -> void:
	blocked_doors.append({
		"pos": pos,
		"until": Time.get_ticks_msec() * 0.001 + duration,
	})


func add_heat_near(world_pos: Vector3, amount: float) -> void:
	for i in range(patrol_points.size()):
		var d: float = patrol_points[i].distance_to(world_pos)
		if d < 12.0:
			var falloff: float = 1.0 - (d / 12.0)
			zone_heat[i] = clampf(zone_heat[i] + amount * falloff, 0.0, 6.0)


func pick_next_patrol_point() -> void:
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
	if ai_brain and ai_brain.has_method("on_hear_noise"):
		ai_brain.on_hear_noise(noise_pos, radius, priority)


func is_player_crouched() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return player.get("crouched") == true


func is_player_facing_me() -> bool:
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


func _get_player_eye_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var y_offset: float = 0.75 if is_player_crouched() else 1.35
	return player.global_position + Vector3(0.0, y_offset, 0.0)


func has_line_of_sight_to_player() -> bool:
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


func evaluate_vision_params(
	core_range_base: float,
	core_half_deg: float,
	periph_range_base: float,
	periph_half_deg: float,
	crouch_mult: float,
	dark_mult: float,
	prox_range_base: float,
	crouch_prox_range: float,
	time_since_seen: float,
	wardrobe_memory_cutoff: float
) -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var is_player_hidden: bool = player.get("is_hidden") == true
	if is_player_hidden and time_since_seen > wardrobe_memory_cutoff:
		return 0

	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	if absf(to_player.y) > 6.0:
		return 0

	var crouched: bool = is_player_crouched()
	var light_on: bool = true
	if has_node("/root/GameSettings") and bool(get_node("/root/GameSettings").dark_mode):
		light_on = player.get("flashlight_on") != false
	var light_mult: float = 1.0 if light_on else dark_mult
	var prox_range: float = crouch_prox_range if (crouched and smoothed_player_vel.length() < 0.4) else prox_range_base
	if dist <= prox_range:
		return 2 if has_line_of_sight_to_player() else 0

	var core_range: float = core_range_base * (crouch_mult if crouched else 1.0) * light_mult
	var periph_range: float = periph_range_base * (crouch_mult if crouched else 1.0) * light_mult
	if dist > core_range:
		return 0

	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	var to_horiz: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	if forward.length_squared() < 0.001 or to_horiz.length_squared() < 0.001:
		return 0

	var cos_angle: float = forward.normalized().dot(to_horiz.normalized())
	if cos_angle >= cos(deg_to_rad(core_half_deg)):
		return 2 if has_line_of_sight_to_player() else 0
	if dist <= periph_range and cos_angle >= cos(deg_to_rad(periph_half_deg)):
		return 1 if has_line_of_sight_to_player() else 0
	return 0


func can_see_player_core_params(
	core_range_base: float,
	core_half_deg: float,
	crouch_mult: float,
	dark_mult: float,
	prox_range_base: float,
	crouch_prox_range: float,
	time_since_seen: float,
	wardrobe_memory_cutoff: float
) -> bool:
	return evaluate_vision_params(
		core_range_base,
		core_half_deg,
		0.0,
		0.0,
		crouch_mult,
		dark_mult,
		prox_range_base,
		crouch_prox_range,
		time_since_seen,
		wardrobe_memory_cutoff
	) == 2


func scan_door_anomaly(max_dist: float) -> Vector3:
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
		if door_pos.distance_to(global_position) > max_dist or absf(door_pos.y - global_position.y) > 2.8:
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
		add_heat_near(door_pos, 2.2)
		return door_pos
	return Vector3.INF


func build_search_fan_points(center_pos: Vector3, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var base: Vector3 = closest_nav_point(center_pos)
	out.append(base)
	var forward_dir: Vector3 = smoothed_player_vel
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
		-side_dir * 3.6,
	]
	for i in range(mini(count, offsets.size())):
		var cand: Vector3 = closest_nav_point(base + offsets[i])
		if cand.distance_to(base) > 1.2:
			out.append(cand)
	return out


func compute_chase_intercept_target(fallback_pos: Vector3, factor: float, max_lookahead: float) -> Vector3:
	if player == null or not is_instance_valid(player):
		return fallback_pos
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= 4.2 or smoothed_player_vel.length() < 1.2:
		return closest_nav_point(player.global_position)
	var lookahead: float = clampf(dist * factor, 0.25, max_lookahead)
	var predicted: Vector3 = player.global_position + smoothed_player_vel * lookahead
	return closest_nav_point(predicted)


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
			_mark_temp_blocked(door_pos, 22.0)
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
	if move_dir.length_squared() < 0.01:
		return 0
	var dir_horiz: Vector3 = Vector3(move_dir.x, 0.0, move_dir.z).normalized()

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


func _steer_around_walls(desired_dir: Vector3) -> Vector3:
	if desired_dir.length_squared() < 0.001:
		return desired_dir
	var dir: Vector3 = desired_dir.normalized()
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3(0.0, 0.95, 0.0)

	var left_dir: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(36.0))
	var right_dir: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(-36.0))

	var hit_center: bool = _is_solid_wall_hit(space_state, origin, dir, 0.72)
	var hit_left: bool = _is_solid_wall_hit(space_state, origin, left_dir, 0.85)
	var hit_right: bool = _is_solid_wall_hit(space_state, origin, right_dir, 0.85)

	if hit_left and not hit_right:
		return (dir + right_dir * 0.85).normalized()
	if hit_right and not hit_left:
		return (dir + left_dir * 0.85).normalized()
	if hit_center:
		if not hit_left and not hit_right:
			return left_dir
	return dir


func _is_solid_wall_hit(space_state: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, length: float) -> bool:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * length)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var col = hit.get("collider")
	if _resolve_door_interact_node(col) != null:
		return false
	# Ignore gentle stair steps/ramps (surface normal pointing mostly upward)
	var normal_val = hit.get("normal")
	if normal_val is Vector3 and (normal_val as Vector3).y > 0.45:
		return false
	return true


func _target_in_attack_range() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var diff: Vector3 = player.global_position - global_position
	var horiz_dist: float = Vector2(diff.x, diff.z).length()
	if horiz_dist > ATTACK_RANGE or absf(diff.y) > ATTACK_VERTICAL_RANGE:
		return false
	return has_line_of_sight_to_player()


func _trigger_attack() -> void:
	if is_attacking or kill_emitted:
		return
	is_attacking = true
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
	if alert_sfx_cooldown > 0.0:
		alert_sfx_cooldown -= delta

	if _target_in_attack_range():
		_trigger_attack()
		return

	var intent: Dictionary = {"should_move": false, "move_speed": 2.0, "vision": 0}
	if ai_brain and ai_brain.has_method("tick_ai"):
		intent = ai_brain.tick_ai(delta)

	var should_move: bool = bool(intent.get("should_move", false))
	var move_speed: float = float(intent.get("move_speed", 2.0))
	var vision: int = int(intent.get("vision", 0))

	# Creepy 3D patrol hum
	hum_timer -= delta
	if hum_timer <= 0.0:
		hum_timer = randf_range(7.0, 12.5)
		if ai_brain and ai_brain.has_method("can_hum_now") and ai_brain.can_hum_now():
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx_3d("clown_hum", global_position, -7.5, randf_range(0.92, 1.06), 19.0)

	_update_trap_placement(delta)

	# Dynamic tension / heartbeat feedback
	if has_node("/root/AudioManager"):
		var dist_p: float = global_position.distance_to(player.global_position)
		var proximity_tension: float = clampf(1.0 - (dist_p / 16.0), 0.0, 1.0)
		var state_bonus: float = 0.0
		if ai_brain and ai_brain.has_method("is_chasing") and ai_brain.is_chasing():
			state_bonus = 0.55
		elif ai_brain and ai_brain.has_method("is_stalk_or_ambush") and ai_brain.is_stalk_or_ambush():
			state_bonus = 0.30
		elif ai_brain and ai_brain.has_method("is_alert_state") and ai_brain.is_alert_state():
			state_bonus = 0.18
		get_node("/root/AudioManager").set_chase_intensity(clampf(proximity_tension * 0.75 + state_bonus, 0.0, 1.0))

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
			horiz_dir = _steer_around_walls(horiz_dir)
			velocity.x = horiz_dir.x * move_speed
			velocity.z = horiz_dir.z * move_speed
			rotation.y = lerp_angle(rotation.y, atan2(-horiz_dir.x, -horiz_dir.z), delta * 11.0)

			door_check_timer -= delta
			if door_check_timer <= 0.0:
				door_check_timer = DOOR_CHECK_INTERVAL
				var door_res: int = _check_door_ahead(horiz_dir)
				if door_res == 1:
					if ai_brain and ai_brain.has_method("on_door_breached"):
						ai_brain.on_door_breached()
					velocity.x = 0.0
					velocity.z = 0.0
				elif door_res == 2:
					if ai_brain and ai_brain.has_method("on_locked_door_blocked"):
						ai_brain.on_locked_door_blocked()
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
					if _check_door_ahead(-global_transform.basis.z) == 1:
						stuck_count = 0
					else:
						var side: Vector3 = Vector3(-horiz_dir.z, 0.0, horiz_dir.x)
						if randf() < 0.5:
							side = -side
						sidestep_dir = side.normalized()
						sidestep_timer = 0.5
						nav_agent.set_target_position(nav_agent.target_position)
				else:
					stuck_count = 0
					_mark_temp_blocked(current_target_pos, 14.0)
					var is_chasing_now: bool = ai_brain != null and ai_brain.has_method("is_chasing") and ai_brain.is_chasing()
					if not is_chasing_now or vision != 2:
						if ai_brain and ai_brain.has_method("on_stuck_abort"):
							ai_brain.on_stuck_abort()
					else:
						var side2: Vector3 = Vector3(-horiz_dir.z, 0.0, horiz_dir.x)
						sidestep_dir = (side2 if randf() < 0.5 else -side2).normalized()
						sidestep_timer = 0.6
			else:
				stuck_count = 0
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 9.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 9.0)

	var clown_horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if anim_tree:
		anim_tree.set("parameters/conditions/attack", false)
		anim_tree.set("parameters/conditions/run", clown_horiz_speed > 0.35)

	if is_on_floor() and clown_horiz_speed > 0.8 and not is_attacking:
		clown_step_timer -= delta
		if clown_step_timer <= 0.0:
			clown_step_timer = clampf(1.22 / maxf(clown_horiz_speed, 1.0), 0.24, 0.58)
			if has_node("/root/AudioManager"):
				var is_chasing_sfx: bool = ai_brain != null and ai_brain.has_method("is_chasing") and ai_brain.is_chasing()
				var vol: float = -3.0 if is_chasing_sfx else -7.5
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
	if max_active_traps <= 0 or not is_on_floor() or active_traps.size() >= max_active_traps:
		return
	if ai_brain and ai_brain.has_method("is_chasing") and ai_brain.is_chasing():
		return
	trap_cooldown_timer -= delta
	if trap_cooldown_timer <= 0.0:
		trap_cooldown_timer = trap_drop_interval
		if is_instance_valid(player) and global_position.distance_to(player.global_position) < 3.5:
			return
		var trap_pos: Vector3 = closest_nav_point(global_position)
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
	velocity = Vector3.ZERO
	stuck_count = 0
	sidestep_timer = 0.0
	if anim_tree:
		anim_tree.set("parameters/conditions/attack", false)
		anim_tree.set("parameters/conditions/run", true)
	if state_machine and state_machine.has_method("travel"):
		state_machine.travel("Run")
	if ai_brain and ai_brain.has_method("on_day_reset"):
		ai_brain.on_day_reset(day)
