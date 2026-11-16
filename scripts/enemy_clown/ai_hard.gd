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

# HARD MODE: Preserves the Predator Director AI (Stalk, Ambush, Forensics, Predictive Intercept)!
const BASE_PATROL_SPEED: float = 2.45
const STALK_SPEED: float = 2.7
const INVESTIGATE_SPEED: float = 3.5
const SEARCH_SPEED: float = 2.8
const AMBUSH_SPEED: float = 4.6
const BASE_CHASE_SPEED: float = 4.5
const MAX_CHASE_BONUS: float = 0.65

const CORE_VISION_RANGE: float = 20.0
const CORE_VISION_HALF_ANGLE_DEG: float = 34.0
const PERIPHERAL_VISION_RANGE: float = 14.0
const PERIPHERAL_HALF_ANGLE_DEG: float = 76.0
const CROUCH_VISION_MULT: float = 0.62
const PROXIMITY_SENSE_RANGE: float = 2.8
const CROUCH_PROXIMITY_RANGE: float = 1.65

const BASE_CHASE_MEMORY_TIME: float = 4.2
const INVESTIGATE_WAIT_TIME: float = 2.2
const PATROL_WAIT_TIME: float = 0.85
const AMBUSH_WAIT_TIME: float = 2.4
const DOOR_BREACH_PAUSE: float = 0.25
const ANOMALY_SCAN_INTERVAL: float = 0.65

var clown: CharacterBody3D = null
var ai_state: int = AIState.PATROL
var last_emitted_state: int = -1
var suspicion: float = 0.0
var aggression: float = 0.15
var lose_sight_timer: float = 0.0
var wait_timer: float = 0.0
var state_timer: float = 0.0
var stalk_freeze_timer: float = 0.0
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


func setup(clown_body: CharacterBody3D) -> void:
	clown = clown_body
	_set_state(AIState.PATROL)
	clown.pick_next_patrol_point()


func get_trap_config() -> Dictionary:
	return {"max_traps": 3, "interval": 24.0}


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
	aggression = clampf(aggression + amount, 0.0, 1.0)


func on_day_reset(day: int) -> void:
	suspicion = 0.0
	time_since_last_seen = 999.0
	aggression = clampf(0.15 + float(day - 1) * 0.14, 0.15, 0.9)
	wait_timer = 0.5
	_set_state(AIState.PATROL)
	clown.pick_next_patrol_point()


func on_hear_noise(noise_pos: Vector3, radius: float, priority: float) -> void:
	var vertical_diff: float = absf(noise_pos.y - clown.global_position.y)
	var effective_radius: float = radius * (0.72 if vertical_diff > 3.0 else 1.0)
	var dist: float = clown.global_position.distance_to(noise_pos)
	if dist > effective_radius:
		return

	clown.add_heat_near(noise_pos, 1.1 * priority)
	var closeness: float = 1.0 - (dist / maxf(effective_radius, 0.1))
	suspicion = clampf(suspicion + (24.0 + 38.0 * closeness) * priority, 0.0, 100.0)
	var nav_target: Vector3 = clown.closest_nav_point(noise_pos)

	if ai_state == AIState.CHASE:
		if not clown.can_see_player_core_params(CORE_VISION_RANGE, CORE_VISION_HALF_ANGLE_DEG, CROUCH_VISION_MULT, 0.72, PROXIMITY_SENSE_RANGE, CROUCH_PROXIMITY_RANGE, time_since_last_seen, 3.0):
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
	aggression = clampf(aggression + delta * 0.0018, 0.0, 1.0)

	if ai_state != AIState.CHASE and ai_state != AIState.DOOR_BREACH:
		anomaly_scan_timer += delta
		if anomaly_scan_timer >= ANOMALY_SCAN_INTERVAL:
			anomaly_scan_timer = 0.0
			var door_pos: Vector3 = clown.scan_door_anomaly(10.5)
			if door_pos != Vector3.INF:
				suspicion = clampf(suspicion + 45.0, 0.0, 100.0)
				last_known_player_pos = clown.closest_nav_point(door_pos)
				current_target_pos = last_known_player_pos
				clown.set_nav_target(current_target_pos)
				wait_timer = INVESTIGATE_WAIT_TIME
				_set_state(AIState.INVESTIGATE)

	var vision: int = clown.evaluate_vision_params(
		CORE_VISION_RANGE,
		CORE_VISION_HALF_ANGLE_DEG,
		PERIPHERAL_VISION_RANGE,
		PERIPHERAL_HALF_ANGLE_DEG,
		CROUCH_VISION_MULT,
		0.72,
		PROXIMITY_SENSE_RANGE,
		CROUCH_PROXIMITY_RANGE,
		time_since_last_seen,
		3.0
	)
	var player_node: Node3D = clown.player
	var dist_to_player: float = clown.global_position.distance_to(player_node.global_position) if is_instance_valid(player_node) else 999.0

	if vision == 2 and is_instance_valid(player_node):
		time_since_last_seen = 0.0
		last_known_player_pos = clown.closest_nav_point(player_node.global_position)
		last_known_player_vel = clown.smoothed_player_vel
		clown.add_heat_near(player_node.global_position, delta * 2.5)
		suspicion = clampf(suspicion + delta * (120.0 if dist_to_player < 9.0 else 75.0), 0.0, 100.0)
		lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.5

		if ai_state != AIState.CHASE and dist_to_player > 9.5 and not clown.is_player_facing_me():
			_set_state(AIState.STALK)
			clown.set_nav_target(last_known_player_pos)
		elif suspicion >= 65.0 or dist_to_player <= 9.5 or clown.is_player_facing_me():
			_set_state(AIState.CHASE)
	elif vision == 1 and is_instance_valid(player_node):
		var gain_rate: float = (68.0 if not clown.is_player_crouched() else 38.0) * (1.0 + aggression * 0.4)
		suspicion = clampf(suspicion + delta * gain_rate, 0.0, 100.0)
		last_known_player_pos = clown.closest_nav_point(player_node.global_position)
		last_known_player_vel = clown.smoothed_player_vel
		if suspicion >= 82.0:
			lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.0
			_set_state(AIState.CHASE)
		elif suspicion >= 38.0 and ai_state == AIState.PATROL:
			current_target_pos = last_known_player_pos
			clown.set_nav_target(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)
	else:
		suspicion = maxf(suspicion - delta * 9.0, 0.0)
		if ai_state == AIState.CHASE:
			lose_sight_timer -= delta
			if lose_sight_timer <= 0.0:
				if last_known_player_vel.length() > 2.0 and aggression >= 0.30:
					var cutoff: Vector3 = clown.closest_nav_point(
						last_known_player_pos + last_known_player_vel.normalized() * 5.5
					)
					current_target_pos = cutoff
					clown.set_nav_target(cutoff)
					wait_timer = AMBUSH_WAIT_TIME
					_set_state(AIState.AMBUSH)
				else:
					search_waypoints = clown.build_search_fan_points(last_known_player_pos, 3)
					search_step_idx = 0
					clown.set_nav_target(search_waypoints[0])
					wait_timer = 1.1
					_set_state(AIState.SEARCH)
		elif ai_state == AIState.STALK:
			current_target_pos = last_known_player_pos
			clown.set_nav_target(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)

	var move_speed: float = BASE_PATROL_SPEED + aggression * 0.35
	var should_move: bool = true

	match ai_state:
		AIState.CHASE:
			move_speed = BASE_CHASE_SPEED + aggression * MAX_CHASE_BONUS
			if vision == 2:
				clown.set_nav_target(clown.compute_chase_intercept_target(last_known_player_pos, 0.14, 1.05))
			elif clown.is_nav_finished():
				search_waypoints = clown.build_search_fan_points(last_known_player_pos, 3)
				search_step_idx = 0
				clown.set_nav_target(search_waypoints[0])
				wait_timer = 1.0
				_set_state(AIState.SEARCH)
		AIState.STALK:
			if clown.is_player_facing_me() and dist_to_player > 10.5 and stalk_freeze_timer <= 0.0:
				stalk_freeze_timer = 0.55
			if stalk_freeze_timer > 0.0:
				stalk_freeze_timer -= delta
				should_move = false
			else:
				move_speed = STALK_SPEED
				clown.set_nav_target(last_known_player_pos)
				if dist_to_player <= 7.8 or clown.is_player_facing_me():
					lose_sight_timer = BASE_CHASE_MEMORY_TIME + aggression * 2.0
					_set_state(AIState.CHASE)
		AIState.INVESTIGATE:
			move_speed = INVESTIGATE_SPEED + aggression * 0.25
			if clown.is_nav_finished():
				should_move = false
				wait_timer -= delta
				clown.rotation.y += sin(Time.get_ticks_msec() * 0.0045) * delta * 1.9
				if wait_timer <= 0.0:
					search_waypoints = clown.build_search_fan_points(current_target_pos, 3)
					if search_waypoints.size() > 1:
						search_step_idx = 1
						clown.set_nav_target(search_waypoints[1])
						wait_timer = 0.9
						_set_state(AIState.SEARCH)
					else:
						_set_state(AIState.PATROL)
						clown.pick_next_patrol_point()
		AIState.SEARCH:
			move_speed = SEARCH_SPEED
			if clown.is_nav_finished():
				should_move = false
				wait_timer -= delta
				clown.rotation.y += sin(Time.get_ticks_msec() * 0.0055) * delta * 2.2
				if wait_timer <= 0.0:
					search_step_idx += 1
					if search_step_idx < search_waypoints.size():
						clown.set_nav_target(search_waypoints[search_step_idx])
						wait_timer = 0.95
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
					clown.rotation.y = lerp_angle(clown.rotation.y, watch_yaw, delta * 3.0)
				if wait_timer <= 0.0:
					search_waypoints = clown.build_search_fan_points(current_target_pos, 3)
					search_step_idx = 0
					clown.set_nav_target(search_waypoints[0])
					wait_timer = 0.85
					_set_state(AIState.SEARCH)
		AIState.DOOR_BREACH:
			should_move = false
			door_breach_timer -= delta
			if door_breach_timer <= 0.0:
				_set_state(post_breach_state)
		AIState.PATROL:
			move_speed = BASE_PATROL_SPEED + aggression * 0.35
			if clown.is_nav_finished() or state_timer > 22.0:
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
