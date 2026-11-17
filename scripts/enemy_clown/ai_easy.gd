extends Node

enum AIState {
	PATROL,
	INVESTIGATE,
	SEARCH,
	CHASE,
	DOOR_BREACH,
	ATTACK,
}

const PATROL_SPEED: float = 1.65
const INVESTIGATE_SPEED: float = 2.15
const SEARCH_SPEED: float = 1.85
const CHASE_SPEED: float = 3.25
const CORE_VISION_RANGE: float = 11.0
const CORE_HALF_ANGLE_DEG: float = 28.0
const PERIPH_VISION_RANGE: float = 7.0
const PERIPH_HALF_ANGLE_DEG: float = 58.0
const PROX_RANGE: float = 1.6
const CROUCH_PROX_RANGE: float = 0.95
const CHASE_MEMORY_TIME: float = 1.8
const PATROL_WAIT_TIME: float = 1.6
const INVESTIGATE_WAIT_TIME: float = 2.4
const DOOR_BREACH_PAUSE: float = 0.65

var clown: CharacterBody3D = null
var ai_state: int = AIState.PATROL
var last_emitted_state: int = -1
var suspicion: float = 0.0
var aggression: float = 0.05
var lose_sight_timer: float = 0.0
var wait_timer: float = 0.0
var state_timer: float = 0.0
var door_breach_timer: float = 0.0
var post_breach_state: int = AIState.PATROL
var current_target_pos: Vector3 = Vector3.ZERO
var last_known_player_pos: Vector3 = Vector3.ZERO
var search_waypoints: Array[Vector3] = []
var search_step_idx: int = 0
var time_since_last_seen: float = 999.0


func setup(clown_body: CharacterBody3D) -> void:
	clown = clown_body
	_set_state(AIState.PATROL)
	clown.pick_next_patrol_point()


func get_trap_config() -> Dictionary:
	return {"max_traps": 0, "interval": 999.0}


func get_door_pause() -> float:
	return DOOR_BREACH_PAUSE


func is_chasing() -> bool:
	return ai_state == AIState.CHASE


func is_alert_state() -> bool:
	return ai_state == AIState.INVESTIGATE or ai_state == AIState.SEARCH


func can_hum_now() -> bool:
	return ai_state == AIState.PATROL or ai_state == AIState.SEARCH


func on_door_breached() -> void:
	if ai_state != AIState.DOOR_BREACH:
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


func on_day_reset(_day: int) -> void:
	suspicion = 0.0
	time_since_last_seen = 999.0
	wait_timer = 1.0
	_set_state(AIState.PATROL)
	clown.pick_next_patrol_point()


func on_hear_noise(noise_pos: Vector3, radius: float, priority: float) -> void:
	# Easy clown ignores quiet normal footsteps and only investigates loud sounds
	if priority < 0.9:
		return
	var effective_radius: float = radius * 0.55
	var dist: float = clown.global_position.distance_to(noise_pos)
	if dist > effective_radius:
		return
	suspicion = clampf(suspicion + 30.0 * priority, 0.0, 100.0)
	var nav_target: Vector3 = clown.closest_nav_point(noise_pos)
	last_known_player_pos = nav_target
	current_target_pos = nav_target
	clown.set_nav_target(current_target_pos)
	wait_timer = INVESTIGATE_WAIT_TIME
	if ai_state != AIState.CHASE:
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
		var names: Array[String] = ["PATROL", "INVESTIGATE", "SEARCH", "CHASE", "DOOR_BREACH", "ATTACK"]
		clown.emit_ai_state(names[ai_state], suspicion)


func tick_ai(delta: float) -> Dictionary:
	state_timer += delta
	time_since_last_seen += delta

	var vision: int = clown.evaluate_vision_params(
		CORE_VISION_RANGE,
		CORE_HALF_ANGLE_DEG,
		PERIPH_VISION_RANGE,
		PERIPH_HALF_ANGLE_DEG,
		0.55,
		0.65,
		PROX_RANGE,
		CROUCH_PROX_RANGE,
		time_since_last_seen,
		2.0
	)
	var player_node: Node3D = clown.player

	if vision == 2 and is_instance_valid(player_node):
		time_since_last_seen = 0.0
		last_known_player_pos = clown.closest_nav_point(player_node.global_position)
		suspicion = clampf(suspicion + delta * 62.0, 0.0, 100.0)
		lose_sight_timer = CHASE_MEMORY_TIME
		if suspicion >= 55.0:
			_set_state(AIState.CHASE)
	elif vision == 1 and is_instance_valid(player_node):
		suspicion = clampf(suspicion + delta * 30.0, 0.0, 100.0)
		last_known_player_pos = clown.closest_nav_point(player_node.global_position)
		if suspicion >= 65.0 and ai_state == AIState.PATROL:
			current_target_pos = last_known_player_pos
			clown.set_nav_target(current_target_pos)
			wait_timer = INVESTIGATE_WAIT_TIME
			_set_state(AIState.INVESTIGATE)
	else:
		suspicion = maxf(suspicion - delta * 14.0, 0.0)
		if ai_state == AIState.CHASE:
			lose_sight_timer -= delta
			if lose_sight_timer <= 0.0:
				search_waypoints = clown.build_search_fan_points(last_known_player_pos, 1)
				search_step_idx = 0
				clown.set_nav_target(search_waypoints[0])
				wait_timer = 1.2
				_set_state(AIState.SEARCH)

	var move_speed: float = PATROL_SPEED
	var should_move: bool = true

	match ai_state:
		AIState.CHASE:
			move_speed = CHASE_SPEED
			if vision == 2 and is_instance_valid(player_node):
				clown.set_nav_target(clown.closest_nav_point(player_node.global_position))
			elif clown.is_nav_finished():
				search_waypoints = clown.build_search_fan_points(last_known_player_pos, 1)
				search_step_idx = 0
				clown.set_nav_target(search_waypoints[0])
				wait_timer = 1.2
				_set_state(AIState.SEARCH)
		AIState.INVESTIGATE:
			move_speed = INVESTIGATE_SPEED
			if clown.is_nav_finished():
				should_move = false
				wait_timer -= delta
				clown.rotation.y += sin(Time.get_ticks_msec() * 0.0035) * delta * 1.4
				if wait_timer <= 0.0:
					_set_state(AIState.PATROL)
					clown.pick_next_patrol_point()
		AIState.SEARCH:
			move_speed = SEARCH_SPEED
			if clown.is_nav_finished():
				should_move = false
				wait_timer -= delta
				clown.rotation.y += sin(Time.get_ticks_msec() * 0.004) * delta * 1.6
				if wait_timer <= 0.0:
					search_step_idx += 1
					if search_step_idx < search_waypoints.size():
						clown.set_nav_target(search_waypoints[search_step_idx])
						wait_timer = 1.0
					else:
						_set_state(AIState.PATROL)
						clown.pick_next_patrol_point()
		AIState.DOOR_BREACH:
			should_move = false
			door_breach_timer -= delta
			if door_breach_timer <= 0.0:
				_set_state(post_breach_state)
		AIState.PATROL:
			move_speed = PATROL_SPEED
			if clown.is_nav_finished() or state_timer > 24.0:
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
