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
const BASE_PATROL_SPEED = 2.35
const STALK_SPEED = 2.65
const INVESTIGATE_SPEED = 3.45
const SEARCH_SPEED = 2.75
const AMBUSH_SPEED = 4.55
const BASE_CHASE_SPEED = 4.45
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
const PATROL_WAIT_TIME = 1.0
const AMBUSH_WAIT_TIME = 2.4
const DOOR_BREACH_PAUSE = 0.28
const DOOR_CHECK_INTERVAL = 0.20
const ANOMALY_SCAN_INTERVAL = 0.65
const STUCK_CHECK_INTERVAL = 0.65
const STUCK_MIN_DISTANCE = 0.16
const GRAVITY = 9.8

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

# Cognitive memory & spatial heat-map
var patrol_points: Array[Vector3] = []
var zone_heat: Array[float] = []
var zone_last_visited: Array[float] = []
var current_patrol_idx: int = -1
var current_target_pos: Vector3 = Vector3.ZERO

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
	_build_patrol_points()
	ai_ready = true
	_set_state(AIState.PATROL)
	_pick_next_patrol_point()


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
				door_memory[id] = {
					"node": node,
					"opened": bool(opened_val),
					"pos": (node as Node3D).global_position,
					"ai_ignore_until": 0.0,
				}
		for child in node.get_children():
			stack.append(child)


func _build_patrol_points() -> void:
	patrol_points.clear()
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
				if p.distance_to(world_v) < 4.2:
					too_close = true
					break
			if not too_close:
				candidates.append(world_v)

	# Reachability filter so the clown never targets disconnected roof/outside islands
	for cand in candidates:
		var snapped: Vector3 = _closest_nav_point(cand)
		if nav_map.is_valid():
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start_nav, snapped, true)
			if path.is_empty():
				continue
			var path_end: Vector3 = path[path.size() - 1]
			if path_end.distance_to(snapped) > 2.0:
				continue
		patrol_points.append(snapped)
		zone_heat.append(0.1)
		zone_last_visited.append(0.0)

	if patrol_points.is_empty():
		for angle_deg in [0, 60, 120, 180, 240, 300]:
			var rad: float = deg_to_rad(float(angle_deg))
			var fallback_pt: Vector3 = _closest_nav_point(
				global_position + Vector3(cos(rad) * 5.5, 0.0, sin(rad) * 5.5)
			)
			patrol_points.append(fallback_pt)
			zone_heat.append(0.1)
			zone_last_visited.append(0.0)


func notify_world_changed() -> void:
	# Re-evaluate reachable rooms after locked doors/gates are opened
	blocked_doors.clear()
	_build_patrol_points()


func notify_player_progress(amount: float = 0.14) -> void:
	aggression = clampf(aggression + amount, 0.0, 1.0)
	if is_instance_valid(player):
		_add_heat_near(player.global_position, 1.8)


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
		if d < 10.0:
			var falloff: float = 1.0 - (d / 10.0)
			zone_heat[i] = clampf(zone_heat[i] + amount * falloff, 0.0, 6.0)


func _set_state(new_state: AIState) -> void:
	if ai_state == new_state:
		return
	ai_state = new_state
	state_timer = 0.0
	if int(ai_state) != last_emitted_state:
		last_emitted_state = int(ai_state)
		var names: Array[String] = ["PATROL", "STALK", "INVESTIGATE", "SEARCH", "AMBUSH", "CHASE", "DOOR_BREACH", "ATTACK"]
		ai_state_changed.emit(names[int(ai_state)], suspicion)


func _pick_next_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var best_idx: int = -1
	var best_score: float = -100000.0

	for i in range(patrol_points.size()):
		if i == current_patrol_idx and patrol_points.size() > 1:
			continue
		var pt: Vector3 = patrol_points[i]
		var dist: float = pt.distance_to(global_position)
		if dist < 2.5 or _is_position_blocked(pt):
			continue
		var staleness: float = minf(now - zone_last_visited[i], 60.0)
		var floor_bonus: float = 4.0 if absf(pt.y - global_position.y) < 2.5 else 0.0
		var score: float = staleness * 1.15 + zone_heat[i] * 3.2 + floor_bonus - dist * 0.25 + randf_range(0.0, 6.0)
		if score > best_score:
			best_score = score
			best_idx = i

	if best_idx == -1:
		best_idx = randi() % patrol_points.size()

	current_patrol_idx = best_idx
	zone_last_visited[best_idx] = now
	current_target_pos = patrol_points[best_idx]
	nav_agent.set_target_position(current_target_pos)
	stuck_count = 0


func hear_noise(noise_pos: Vector3, radius: float, priority: float = 1.0) -> void:
	if not ai_ready or is_attacking:
		return
	# Sounds on other floors travel less effectively unless loud
	var vertical_diff: float = absf(noise_pos.y - global_position.y)
	var effective_radius: float = radius * (0.65 if vertical_diff > 3.0 else 1.0)
	var dist: float = global_position.distance_to(noise_pos)
	if dist > effective_radius:
		return

	_add_heat_near(noise_pos, 0.9 * priority)
	var closeness: float = 1.0 - (dist / maxf(effective_radius, 0.1))
	suspicion = clampf(suspicion + (22.0 + 38.0 * closeness) * priority, 0.0, 100.0)

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
	# Returns: 0 = not visible, 1 = peripheral glimpse, 2 = clear core/proximity sight
	if player == null or not is_instance_valid(player):
		return 0
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	if absf(to_player.y) > 6.0:
		return 0

	var crouched: bool = _is_player_crouched()
	var prox_range: float = CROUCH_PROXIMITY_RANGE if (crouched and smoothed_player_vel.length() < 0.4) else PROXIMITY_SENSE_RANGE
	if dist <= prox_range:
		return 2 if _has_line_of_sight_to_player() else 0

	var core_range: float = CORE_VISION_RANGE * (CROUCH_VISION_MULT if crouched else 1.0)
	var periph_range: float = PERIPHERAL_VISION_RANGE * (CROUCH_VISION_MULT if crouched else 1.0)
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

		# Check if AI has line of sight to this altered door
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye_origin, door_pos + Vector3(0.0, 0.8, 0.0))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit: Dictionary = space_state.intersect_ray(q)
		if not hit.is_empty():
			continue

		# Tampered door spotted! Update memory and investigate
		info["opened"] = current_opened
		suspicion = clampf(suspicion + 45.0, 0.0, 100.0)
		_add_heat_near(door_pos, 2.2)
		last_known_player_pos = _closest_nav_point(door_pos)
		current_target_pos = last_known_player_pos
		nav_agent.set_target_position(current_target_pos)
		wait_timer = INVESTIGATE_WAIT_TIME
		_set_state(AIState.INVESTIGATE)
		return


func _check_door_ahead(move_dir: Vector3) -> int:
	# Returns: 0 = clear, 1 = unlocked door being opened, 2 = locked door blocking path
	if move_dir.length_squared() < 0.01:
		return 0
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var dir_horiz: Vector3 = Vector3(move_dir.x, 0.0, move_dir.z).normalized()
	var origin: Vector3 = global_position + Vector3(0.0, 1.0, 0.0)
	var target: Vector3 = origin + dir_horiz * 1.65
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	query.collision_mask = 4
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return 0
	var col = hit.get("collider")
	if col == null or not is_instance_valid(col) or not col.has_method("interact"):
		return 0

	var locked: bool = (col.get("keyreq") == true) or (col.get("beatreq") == true) or (col.get("pinreq") == true)
	if locked:
		var door_pos: Vector3 = (col as Node3D).global_position if col is Node3D else target
		if not _is_position_blocked(door_pos):
			blocked_doors.append({
				"pos": door_pos,
				"until": Time.get_ticks_msec() * 0.001 + 22.0,
			})
		return 2

	if col.get("opened") == false:
		var cid: int = col.get_instance_id()
		if door_memory.has(cid):
			door_memory[cid]["opened"] = true
			door_memory[cid]["ai_ignore_until"] = Time.get_ticks_msec() * 0.001 + 4.0
		col.interact()
		return 1
	return 0


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

	if anim_tree:
		anim_tree.set("parameters/conditions/attack", true)
		anim_tree.set("parameters/conditions/run", false)
	if state_machine and state_machine.has_method("travel"):
		state_machine.travel("Attack")

	if is_instance_valid(player):
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
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

	# Passive director escalation & heat decay
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

	# Immediate kill check
	if _target_in_attack_range():
		_trigger_attack()
		return

	# Environmental forensics scan
	anomaly_scan_timer += delta
	if anomaly_scan_timer >= ANOMALY_SCAN_INTERVAL:
		anomaly_scan_timer = 0.0
		_scan_environmental_anomalies()

	# Multi-zone perception update
	var vision: int = _evaluate_vision()
	var dist_to_player: float = global_position.distance_to(player.global_position)

	if vision == 2:
		last_known_player_pos = _closest_nav_point(player.global_position)
		last_known_player_vel = smoothed_player_vel
		_add_heat_near(player.global_position, delta * 2.5)
		suspicion = clampf(suspicion + delta * (120.0 if dist_to_player < 9.0 else 75.0), 0.0, 100.0)
		lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.5

		# Predator Stalk vs Immediate Chase decision
		if ai_state != AIState.CHASE and dist_to_player > 9.5 and not _is_player_facing_me():
			_set_state(AIState.STALK)
			nav_agent.set_target_position(last_known_player_pos)
		elif suspicion >= 65.0 or dist_to_player <= 9.5 or _is_player_facing_me():
			_set_state(AIState.CHASE)
	elif vision == 1:
		# Peripheral glimpse builds suspicion smoothly
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
				# Decide between predictive AMBUSH cutoff or local SEARCH sweep
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
			# Lost sight while stalking -> investigate last spot
			current_target_pos = last_known_player_pos
			nav_agent.set_target_position(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)

	# Animation control
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
			# Creepy corner-freeze if player begins turning around at medium range
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
				# Watch toward expected player approach direction
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
			if nav_agent.is_navigation_finished():
				should_move = false
				if wait_timer <= 0.0:
					wait_timer = PATROL_WAIT_TIME
				else:
					wait_timer -= delta
					if wait_timer <= 0.0:
						_pick_next_patrol_point()

	# Gravity
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
					# Locked door blocking path -> pick a different route immediately
					if ai_state != AIState.CHASE:
						_set_state(AIState.PATROL)
						_pick_next_patrol_point()
		else:
			velocity.x = 0.0
			velocity.z = 0.0

		# Two-stage anti-stuck recovery
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

	move_and_slide()


func _hit_finished() -> void:
	if player and is_instance_valid(player) and global_position.distance_to(player.global_position) < ATTACK_RANGE + 1.0:
		var dir: Vector3 = global_position.direction_to(player.global_position)
		if player.has_method("hit"):
			player.hit(dir)
