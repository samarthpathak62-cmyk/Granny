extends Node

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

# EXTREME MODE (NIGHTMARE DEMON CLOWN): Hyper senses, relentless speed, 5 bear traps, cross-floor hunting!
const BASE_PATROL_SPEED: float = 2.95
const STALK_SPEED: float = 3.35
const INVESTIGATE_SPEED: float = 4.25
const SEARCH_SPEED: float = 3.55
const AMBUSH_SPEED: float = 5.35
const BASE_CHASE_SPEED: float = 5.35
const MAX_CHASE_BONUS: float = 0.85

const CORE_VISION_RANGE: float = 25.5
const CORE_VISION_HALF_ANGLE_DEG: float = 42.0
const PERIPHERAL_VISION_RANGE: float = 18.0
const PERIPHERAL_HALF_ANGLE_DEG: float = 88.0
const CROUCH_VISION_MULT: float = 0.74
const PROXIMITY_SENSE_RANGE: float = 3.8
const CROUCH_PROXIMITY_RANGE: float = 2.25

const BASE_CHASE_MEMORY_TIME: float = 6.2
const INVESTIGATE_WAIT_TIME: float = 1.35
const PATROL_WAIT_TIME: float = 0.45
const AMBUSH_WAIT_TIME: float = 1.8
const DOOR_BREACH_PAUSE: float = 0.08
const ANOMALY_SCAN_INTERVAL: float = 0.40

var clown: CharacterBody3D = null
var ai_state: int = AIState.PATROL
var last_emitted_state: int = -1
var suspicion: float = 0.0
var aggression: float = 0.35
var lose_sight_timer: float = 0.0
var wait_timer: float = 0.0
var state_timer: float = 0.0
var door_breach_timer: float = 0.0
var post_breach_state: int = AIState.PATROL
var anomaly_scan_timer: float = 0.0
var last_noise_priority: float = 0.0
var current_target_pos: Vector3 = Vector3.ZERO
var last_known_player_pos: Vector3 = Vector3.ZERO
var last_known_player_vel: Vector3 = Vector3.ZERO
var search_waypoints: Array[Vector3] = []
var search_step_idx: int = 0
var time_since_last_seen: float = 999.0
var bloodlust_hunt_timer: float = 0.0


func setup(clown_body: CharacterBody3D) -> void:
	clown = clown_body
	_set_state(AIState.PATROL)
	clown.pick_next_patrol_point()


func get_trap_config() -> Dictionary:
	return {"max_traps": 5, "interval": 13.0}


func get_door_pause() -> float:
	return DOOR_BREACH_PAUSE


func is_chasing() -> bool:
	return ai_state == AIState.CHASE


func is_alert_state() -> bool:
	return ai_state == AIState.SEARCH or ai_state == AIState.INVESTIGATE


func is_stalk_or_ambush() -> bool:
	return ai_state == AIState.STALK or ai_state == AIState.AMBUSH


func can_hum_now() -> bool:
	return ai_state == AIState.PATROL or ai_state == AIState.STALK or ai_state == AIState.SEARCH


func on_door_breached() -> void:
	post_breach_state = ai_state
	door_breach_timer = DOOR_BREACH_PAUSE
	_set_state(AIState.DOOR_BREACH)


func on_locked_door_blocked() -> void:
	if ai_state != AIState.CHASE:
		_set_state(AIState.PATROL)
		clown.pick_next_patrol_point()


func on_stuck_abort() -> void:
	_set_state(AIState.PATROL)
	clown.pick_next_patrol_point()


func on_player_progress(amount: float) -> void:
	aggression = clampf(aggression + amount * 1.35, 0.35, 1.0)
	# Whenever player unlocks/breaks a plank in Extreme mode, he immediately surges toward them!
	if is_instance_valid(clown.player):
		on_hear_noise(clown.player.global_position, 28.0, 1.8)


func on_day_reset(day: int) -> void:
	suspicion = 0.0
	time_since_last_seen = 999.0
	aggression = clampf(0.35 + float(day - 1) * 0.16, 0.35, 1.0)
	wait_timer = 0.25
	bloodlust_hunt_timer = 0.0
	_set_state(AIState.PATROL)
	clown.pick_next_patrol_point()


func on_hear_noise(noise_pos: Vector3, radius: float, priority: float) -> void:
	# Extreme clown has acute hearing across floors!
	var vertical_diff: float = absf(noise_pos.y - clown.global_position.y)
	var effective_radius: float = radius * 1.45 * (0.85 if vertical_diff > 3.0 else 1.0)
	var dist: float = clown.global_position.distance_to(noise_pos)
	if dist > effective_radius:
		return

	clown.add_heat_near(noise_pos, 1.8 * priority)
	var closeness: float = 1.0 - (dist / maxf(effective_radius, 0.1))
	suspicion = clampf(suspicion + (35.0 + 48.0 * closeness) * priority, 0.0, 100.0)
	var nav_target: Vector3 = clown.closest_nav_point(noise_pos)

	if ai_state == AIState.CHASE:
		if not clown.can_see_player_core_params(CORE_VISION_RANGE, CORE_VISION_HALF_ANGLE_DEG, CROUCH_VISION_MULT, 0.85, PROXIMITY_SENSE_RANGE, CROUCH_PROXIMITY_RANGE, time_since_last_seen, 6.5):
			last_known_player_pos = nav_target
			clown.set_nav_target(last_known_player_pos)
		return

	if ai_state == AIState.INVESTIGATE and priority < last_noise_priority and dist > current_target_pos.distance_to(clown.global_position):
		return

	last_noise_priority = priority
	last_known_player_pos = nav_target
	current_target_pos = nav_target
	clown.set_nav_target(current_target_pos)
	wait_timer = INVESTIGATE_WAIT_TIME
	if suspicion >= 92.0 and dist < 11.5:
		lose_sight_timer = BASE_CHASE_MEMORY_TIME
		_set_state(AIState.CHASE)
	else:
		_set_state(AIState.INVESTIGATE)


func _set_state(new_state: int) -> void:
	if ai_state == new_state:
		return
	var prev_state: int = ai_state
	ai_state = new_state
	state_timer = 0.0
	if ai_state == AIState.CHASE and prev_state != AIState.CHASE:
		clown.play_alert_sfx()
	if ai_state != last_emitted_state:
		last_emitted_state = ai_state
		var names: Array[String] = ["PATROL", "STALK", "INVESTIGATE", "SEARCH", "AMBUSH", "CHASE", "DOOR_BREACH", "ATTACK"]
		clown.emit_ai_state(names[ai_state], suspicion)


func tick_ai(delta: float) -> Dictionary:
	state_timer += delta
	time_since_last_seen += delta
	bloodlust_hunt_timer += delta
	aggression = clampf(aggression + delta * 0.0038, 0.35, 1.0)

	if ai_state != AIState.CHASE and ai_state != AIState.DOOR_BREACH:
		anomaly_scan_timer += delta
		if anomaly_scan_timer >= ANOMALY_SCAN_INTERVAL:
			anomaly_scan_timer = 0.0
			var door_pos: Vector3 = clown.scan_door_anomaly(13.5)
			if door_pos != Vector3.INF:
				suspicion = clampf(suspicion + 60.0, 0.0, 100.0)
				last_known_player_pos = clown.closest_nav_point(door_pos)
				current_target_pos = last_known_player_pos
				clown.set_nav_target(current_target_pos)
				wait_timer = INVESTIGATE_WAIT_TIME
				_set_state(AIState.INVESTIGATE)

	var vision: int = clown.evaluate_vision_params(
		CORE_VISION_RANGE,
		CORE_VISION_HALF_ANGLE_DEG,
		PERIPHERAL_VISION_RANGE,
		PERIPH_HALF_ANGLE_DEG,
		CROUCH_VISION_MULT,
		0.84,
		PROXIMITY_SENSE_RANGE,
		CROUCH_PROXIMITY_RANGE,
		time_since_last_seen,
		7.0
	)
	var player_node: Node3D = clown.player
	var dist_to_player: float = clown.global_position.distance_to(player_node.global_position) if is_instance_valid(player_node) else 999.0

	if vision == 2 and is_instance_valid(player_node):
		time_since_last_seen = 0.0
		bloodlust_hunt_timer = 0.0
		last_known_player_pos = clown.closest_nav_point(player_node.global_position)
		last_known_player_vel = clown.smoothed_player_vel
		clown.add_heat_near(player_node.global_position, delta * 4.0)
		suspicion = clampf(suspicion + delta * 180.0, 0.0, 100.0)
		lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 3.0
		# Extreme clown snaps straight into CHASE on sight (or relentless stalk if very far & unseen)
		if dist_to_player > 16.0 and not clown.is_player_facing_me() and ai_state != AIState.CHASE:
			_set_state(AIState.STALK)
			clown.set_nav_target(last_known_player_pos)
		else:
			_set_state(AIState.CHASE)
	elif vision == 1 and is_instance_valid(player_node):
		suspicion = clampf(suspicion + delta * 95.0, 0.0, 100.0)
		last_known_player_pos = clown.closest_nav_point(player_node.global_position)
		last_known_player_vel = clown.smoothed_player_vel
		if suspicion >= 58.0:
			lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.5
			_set_state(AIState.CHASE)
		elif ai_state == AIState.PATROL:
			current_target_pos = last_known_player_pos
			clown.set_nav_target(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)
	else:
		suspicion = maxf(suspicion - delta * 5.5, 0.0)
		if ai_state == AIState.CHASE:
			lose_sight_timer -= delta
			if lose_sight_timer <= 0.0:
				if last_known_player_vel.length() > 1.4:
					var cutoff: Vector3 = clown.closest_nav_point(
						last_known_player_pos + last_known_player_vel.normalized() * 8.0
					)
					current_target_pos = cutoff
					clown.set_nav_target(cutoff)
					wait_timer = AMBUSH_WAIT_TIME
					_set_state(AIState.AMBUSH)
				else:
					search_waypoints = clown.build_search_fan_points(last_known_player_pos, 4)
					search_step_idx = 0
					clown.set_nav_target(search_waypoints[0])
					wait_timer = 0.75
					_set_state(AIState.SEARCH)
		elif ai_state == AIState.STALK:
			current_target_pos = last_known_player_pos
			clown.set_nav_target(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)

	# Extreme Hunter Instinct: if quiet for 15s, heat up player's current floor so you can't camp safely!
	if bloodlust_hunt_timer >= 15.0 and is_instance_valid(player_node) and ai_state == AIState.PATROL:
		bloodlust_hunt_timer = 0.0
		clown.add_heat_near(player_node.global_position, 3.2)

	var move_speed: float = BASE_PATROL_SPEED + aggression * 0.45
	var should_move: bool = true

	match ai_state:
		AIState.CHASE:
			move_speed = BASE_CHASE_SPEED + aggression * MAX_CHASE_BONUS
			if vision == 2:
				clown.set_nav_target(clown.compute_chase_intercept_target(last_known_player_pos, 0.19, 1.45))
			elif clown.is_nav_finished():
				search_waypoints = clown.build_search_fan_points(last_known_player_pos, 4)
				search_step_idx = 0
				clown.set_nav_target(search_waypoints[0])
				wait_timer = 0.75
				_set_state(AIState.SEARCH)
		AIState.STALK:
			move_speed = STALK_SPEED
			clown.set_nav_target(last_known_player_pos)
			if dist_to_player <= 11.5 or clown.is_player_facing_me():
				lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.5
				_set_state(AIState.CHASE)
		AIState.INVESTIGATE:
			move_speed = INVESTIGATE_SPEED + aggression * 0.35
			if clown.is_nav_finished():
				should_move = false
				wait_timer -= delta
				clown.rotation.y += sin(Time.get_ticks_msec() * 0.0065) * delta * 2.4
				if wait_timer <= 0.0:
					search_waypoints = clown.build_search_fan_points(current_target_pos, 4)
					if search_waypoints.size() > 1:
						search_step_idx = 1
						clown.set_nav_target(search_waypoints[1])
						wait_timer = 0.65
						_set_state(AIState.SEARCH)
					else:
						_set_state(AIState.PATROL)
						clown.pick_next_patrol_point()
		AIState.SEARCH:
			move_speed = SEARCH_SPEED
			if clown.is_nav_finished():
				should_move = false
				wait_timer -= delta
				clown.rotation.y += sin(Time.get_ticks_msec() * 0.007) * delta * 2.6
				if wait_timer <= 0.0:
					search_step_idx += 1
					if search_step_idx < search_waypoints.size():
						clown.set_nav_target(search_waypoints[search_step_idx])
						wait_timer = 0.65
					else:
						_set_state(AIState.PATROL)
						clown.pick_next_patrol_point()
		AIState.AMBUSH:
			move_speed = AMBUSH_SPEED
			if clown.is_nav_finished():
				should_move = false
				wait_timer -= delta
				if last_known_player_vel.length() > 0.2:
					var watch_yaw: float = atan2(last_known_player_vel.x, last_known_player_vel.z)
					clown.rotation.y = lerp_angle(clown.rotation.y, watch_yaw, delta * 4.5)
				if wait_timer <= 0.0:
					search_waypoints = clown.build_search_fan_points(current_target_pos, 4)
					search_step_idx = 0
					clown.set_nav_target(search_waypoints[0])
					wait_timer = 0.6
					_set_state(AIState.SEARCH)
		AIState.DOOR_BREACH:
			should_move = false
			door_breach_timer -= delta
			if door_breach_timer <= 0.0:
				_set_state(post_breach_state)
		AIState.PATROL:
			move_speed = BASE_PATROL_SPEED + aggression * 0.45
			if clown.is_nav_finished() or state_timer > 18.0:
				should_move = false
				if wait_timer <= 0.0:
					wait_timer = PATROL_WAIT_TIME
				else:
					wait_timer -= delta
					if wait_timer <= 0.0:
						clown.pick_next_patrol_point()
						state_timer = 0.0

	return {
		"should_move": should_move,
		"move_speed": move_speed,
		"vision": vision,
	}
