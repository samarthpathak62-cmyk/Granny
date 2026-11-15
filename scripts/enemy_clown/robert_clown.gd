extends CharacterBody3D

enum AIState {
	PATROL,
	INVESTIGATE,
	CHASE,
	ATTACK,
}

const PATROL_SPEED = 2.3
const INVESTIGATE_SPEED = 3.1
const CHASE_SPEED = 4.3
const ATTACK_RANGE = 1.45
const ATTACK_VERTICAL_RANGE = 1.6
const VISION_RANGE = 18.0
const PROXIMITY_SENSE_RANGE = 3.0
const VISION_HALF_ANGLE_DEG = 70.0
const CHASE_MEMORY_TIME = 3.5
const INVESTIGATE_WAIT_TIME = 2.5
const PATROL_WAIT_TIME = 1.2
const DOOR_CHECK_INTERVAL = 0.25
const STUCK_CHECK_INTERVAL = 0.75
const STUCK_MIN_DISTANCE = 0.18
const GRAVITY = 9.8

@export var player_path: NodePath

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var player: Node3D = null
var state_machine = null
var ai_state: AIState = AIState.PATROL
var ai_ready := false
var is_attacking := false
var kill_emitted := false

var patrol_points: Array[Vector3] = []
var current_patrol_idx := -1
var current_target_pos: Vector3 = Vector3.ZERO
var last_known_player_pos: Vector3 = Vector3.ZERO
var lose_sight_timer := 0.0
var wait_timer := 0.0

var door_check_timer := 0.0
var stuck_check_timer := 0.0
var last_stuck_check_pos: Vector3 = Vector3.ZERO
var stuck_count := 0
var sidestep_dir: Vector3 = Vector3.ZERO
var sidestep_timer := 0.0

signal kill(death: bool)


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
	call_deferred("_init_navigation")


func _init_navigation() -> void:
	# Wait for NavigationServer3D map synchronization
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_build_patrol_points()
	ai_ready = true
	_pick_next_patrol_point()


func _build_patrol_points() -> void:
	patrol_points.clear()
	var nav_region := get_parent() as NavigationRegion3D
	if nav_region and nav_region.navigation_mesh:
		var verts: PackedVector3Array = nav_region.navigation_mesh.get_vertices()
		for v in verts:
			var world_v: Vector3 = nav_region.to_global(v)
			# Keep points inside reasonable house floor heights and spaced apart
			if world_v.y < -4.0 or world_v.y > 18.0:
				continue
			var too_close := false
			for p in patrol_points:
				if p.distance_to(world_v) < 4.5:
					too_close = true
					break
			if not too_close:
				patrol_points.append(world_v)
	if patrol_points.is_empty():
		# Fallback ring around spawn
		for angle_deg in [0, 60, 120, 180, 240, 300]:
			var rad = deg_to_rad(angle_deg)
			patrol_points.append(global_position + Vector3(cos(rad) * 6.0, 0.0, sin(rad) * 6.0))


func _closest_nav_point(world_pos: Vector3) -> Vector3:
	var nav_map := nav_agent.get_navigation_map()
	if nav_map.is_valid():
		return NavigationServer3D.map_get_closest_point(nav_map, world_pos)
	return world_pos


func _pick_next_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	var attempts := 0
	var chosen: Vector3 = patrol_points[randi() % patrol_points.size()]
	while attempts < 8:
		var idx := randi() % patrol_points.size()
		if idx != current_patrol_idx or patrol_points.size() == 1:
			var candidate := _closest_nav_point(patrol_points[idx])
			if candidate.distance_to(global_position) > 2.5:
				current_patrol_idx = idx
				chosen = candidate
				break
		attempts += 1
	current_target_pos = chosen
	nav_agent.set_target_position(current_target_pos)
	stuck_count = 0


func hear_noise(noise_pos: Vector3, radius: float) -> void:
	if not ai_ready or is_attacking:
		return
	if global_position.distance_to(noise_pos) > radius:
		return
	var nav_target := _closest_nav_point(noise_pos)
	if ai_state == AIState.CHASE:
		# Already chasing; update last known position if not directly visible
		if not _can_see_player():
			last_known_player_pos = nav_target
			nav_agent.set_target_position(last_known_player_pos)
		return
	ai_state = AIState.INVESTIGATE
	current_target_pos = nav_target
	nav_agent.set_target_position(current_target_pos)
	wait_timer = 0.0
	lose_sight_timer = INVESTIGATE_WAIT_TIME
	stuck_count = 0


func _get_player_eye_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var is_crouched: bool = player.get("crouched") == true
	var y_offset := 0.75 if is_crouched else 1.35
	return player.global_position + Vector3(0.0, y_offset, 0.0)


func _has_line_of_sight_to_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var space_state := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 1.5, 0.0)
	var target := _get_player_eye_pos()
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	# Check against walls/floors (1), player (2), doors (4)
	query.collision_mask = 1 | 2 | 4
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == player


func _can_see_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist > VISION_RANGE:
		return false
	if absf(to_player.y) > 6.0:
		return false
	if dist <= PROXIMITY_SENSE_RANGE:
		return _has_line_of_sight_to_player()

	var forward := -global_transform.basis.z
	forward.y = 0.0
	var to_horiz := Vector3(to_player.x, 0.0, to_player.z)
	if forward.length_squared() < 0.001 or to_horiz.length_squared() < 0.001:
		return false
	var cos_angle := forward.normalized().dot(to_horiz.normalized())
	if cos_angle < cos(deg_to_rad(VISION_HALF_ANGLE_DEG)):
		return false
	return _has_line_of_sight_to_player()


func _target_in_attack_range() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var diff := player.global_position - global_position
	var horiz_dist := Vector2(diff.x, diff.z).length()
	if horiz_dist > ATTACK_RANGE or absf(diff.y) > ATTACK_VERTICAL_RANGE:
		return false
	return _has_line_of_sight_to_player()


func _check_and_open_door_ahead(move_dir: Vector3) -> void:
	if move_dir.length_squared() < 0.01:
		return
	var space_state := get_world_3d().direct_space_state
	var dir_horiz := Vector3(move_dir.x, 0.0, move_dir.z).normalized()
	var origin := global_position + Vector3(0.0, 1.0, 0.0)
	var target := origin + dir_horiz * 1.7
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	query.collision_mask = 4  # Doors layer
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var col = hit.get("collider")
	if col == null or not is_instance_valid(col):
		return
	if not col.has_method("interact"):
		return
	# Only auto-open unlocked doors that are currently closed
	var locked: bool = (col.get("keyreq") == true) or (col.get("beatreq") == true) or (col.get("pinreq") == true)
	if not locked and col.get("opened") == false:
		col.interact()


func _trigger_attack() -> void:
	if is_attacking or kill_emitted:
		return
	is_attacking = true
	ai_state = AIState.ATTACK
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

	await get_tree().create_timer(0.95).timeout
	if not is_inside_tree():
		return
	if not kill_emitted:
		kill_emitted = true
		kill.emit(death)


var death := true


func _physics_process(delta: float) -> void:
	if not ai_ready:
		return

	if is_attacking:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if is_instance_valid(player):
			var to_p := player.global_position - global_position
			var target_yaw := atan2(-to_p.x, -to_p.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, delta * 12.0)
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		return

	# Check attack range first
	if _target_in_attack_range():
		_trigger_attack()
		return

	# Perception update
	var sees_player := _can_see_player()
	if sees_player:
		ai_state = AIState.CHASE
		last_known_player_pos = _closest_nav_point(player.global_position)
		lose_sight_timer = CHASE_MEMORY_TIME
		wait_timer = 0.0
	elif ai_state == AIState.CHASE:
		lose_sight_timer -= delta
		if lose_sight_timer <= 0.0:
			ai_state = AIState.INVESTIGATE
			current_target_pos = last_known_player_pos
			nav_agent.set_target_position(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME

	# Ensure Run animation stays active while moving
	if anim_tree:
		anim_tree.set("parameters/conditions/attack", false)
		anim_tree.set("parameters/conditions/run", true)

	var move_speed := PATROL_SPEED
	var should_move := true

	match ai_state:
		AIState.CHASE:
			move_speed = CHASE_SPEED
			if sees_player:
				nav_agent.set_target_position(last_known_player_pos)
			elif nav_agent.is_navigation_finished():
				ai_state = AIState.INVESTIGATE
				wait_timer = INVESTIGATE_WAIT_TIME
		AIState.INVESTIGATE:
			move_speed = INVESTIGATE_SPEED
			if nav_agent.is_navigation_finished():
				should_move = false
				wait_timer -= delta
				# Look around suspiciously while searching
				rotation.y += sin(Time.get_ticks_msec() * 0.004) * delta * 1.6
				if wait_timer <= 0.0:
					ai_state = AIState.PATROL
					_pick_next_patrol_point()
		AIState.PATROL:
			move_speed = PATROL_SPEED
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
		var next_nav_point := nav_agent.get_next_path_position()
		var to_next := next_nav_point - global_position
		var horiz_dir := Vector3(to_next.x, 0.0, to_next.z)

		if sidestep_timer > 0.0:
			sidestep_timer -= delta
			horiz_dir = sidestep_dir

		if horiz_dir.length_squared() > 0.001:
			horiz_dir = horiz_dir.normalized()
			velocity.x = horiz_dir.x * move_speed
			velocity.z = horiz_dir.z * move_speed
			rotation.y = lerp_angle(rotation.y, atan2(-horiz_dir.x, -horiz_dir.z), delta * 10.0)

			# Auto-open unlocked doors in front of enemy
			door_check_timer -= delta
			if door_check_timer <= 0.0:
				door_check_timer = DOOR_CHECK_INTERVAL
				_check_and_open_door_ahead(horiz_dir)
		else:
			velocity.x = 0.0
			velocity.z = 0.0

		# Anti-stuck recovery
		stuck_check_timer += delta
		if stuck_check_timer >= STUCK_CHECK_INTERVAL:
			stuck_check_timer = 0.0
			var moved := Vector2(
				global_position.x - last_stuck_check_pos.x,
				global_position.z - last_stuck_check_pos.z
			).length()
			last_stuck_check_pos = global_position
			if moved < STUCK_MIN_DISTANCE:
				stuck_count += 1
				if stuck_count == 1:
					# Brief perpendicular sidestep to clear doorframes/furniture corners
					var side := Vector3(-horiz_dir.z, 0.0, horiz_dir.x)
					if randf() < 0.5:
						side = -side
					sidestep_dir = side.normalized()
					sidestep_timer = 0.45
					nav_agent.set_target_position(nav_agent.target_position)
				else:
					# Target is blocked/unreachable -> switch cleanly to a fresh patrol point
					stuck_count = 0
					if ai_state != AIState.CHASE or not sees_player:
						ai_state = AIState.PATROL
						_pick_next_patrol_point()
					else:
						var side2 := Vector3(-horiz_dir.z, 0.0, horiz_dir.x)
						sidestep_dir = (side2 if randf() < 0.5 else -side2).normalized()
						sidestep_timer = 0.6
			else:
				stuck_count = 0
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 8.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 8.0)

	move_and_slide()


func _hit_finished() -> void:
	if player and is_instance_valid(player) and global_position.distance_to(player.global_position) < ATTACK_RANGE + 1.0:
		var dir := global_position.direction_to(player.global_position)
		if player.has_method("hit"):
			player.hit(dir)
