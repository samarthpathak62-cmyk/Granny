extends CharacterBody3D

var speed
const WALK_SPEED = 4.0
const SPRINT_SPEED = 7.6
const JUMP_VELOCITY = 4.8
const SENSITIVITY = 0.004
const TOUCH_SENSITIVITY = 0.006
const CROUCH_SPEED = 2.4
const CROUCH_DEPTH = 0.8
const STAND_HEIGHT = 1.8

# stamina variables
const MAX_STAMINA = 100.0
const STAMINA_DRAIN = 26.0
const STAMINA_REGEN = 18.0
var stamina: float = MAX_STAMINA
var stamina_exhausted: bool = false

# bob variables
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

# fov variables
const BASE_FOV = 80.0
const FOV_CHANGE = 1.1

# noise variables for enemy AI hearing
const WALK_NOISE_INTERVAL = 0.65
const WALK_NOISE_RADIUS = 5.5
const SPRINT_NOISE_INTERVAL = 0.42
const SPRINT_NOISE_RADIUS = 15.0
const DROP_NOISE_RADIUS = 13.0
const INTERACT_NOISE_RADIUS = 10.0
const UNLOCK_NOISE_RADIUS = 16.0
var sprint_noise_timer = 0.0
var walk_noise_timer = 0.0

# buttons
@onready var rc_bt = $head/Camera3D/red_circle_bt
@onready var gt_bt = $head/Camera3D/green_tri_bt
@onready var ws_bt = $head/Camera3D/white_square_bt
@onready var bx_bt = $head/Camera3D/bx_bt
@onready var touch_controls: Control = $head/Camera3D/Control

# collision shapes
@onready var standing_colide_shape: CollisionShape3D = $"standing colide_shape"
@onready var crouch_colide_shape: CollisionShape3D = $crouch_colide_shape
var crouched = false

# raycasts
@onready var crouch_raycast: RayCast3D = $crouch_raycast

var gravity = 9.8
@onready var head: Node3D = $head
@onready var camera: Camera3D = $head/Camera3D
@onready var flashlight: SpotLight3D = $head/Camera3D/SpotLight3D
var camera_base_pos: Vector3 = Vector3.ZERO
var dark_mode_enabled: bool = false
var flashlight_on: bool = false

# pickme
@onready var hand: Node3D = $head/hand
@onready var reach: RayCast3D = $head/Camera3D/reach
signal handpos(handpos: Transform3D)
var picked = false
var detected = null

# doors & boat
@onready var interact: RayCast3D = $head/Camera3D/interact
@onready var label: Label = $head/Camera3D/Label
@onready var for_ship: RayCast3D = $head/Camera3D/for_ship
@onready var label_2: Label = $head/Camera3D/Label2
@onready var timer: Timer = $head/Camera3D/Timer

var is_touch_device := false
var is_unlocking := false
var pending_unlock_target: Object = null
var hint_timer := 0.0

# Granny survival state
var is_hidden: bool = false
var trapped_timer: float = 0.0
var camera_shake: float = 0.0
var wakeup_timer: float = 0.0
var jumpscare_target_pos: Vector3 = Vector3.ZERO
var jumpscare_lock_active: bool = false
var wardrobe_nodes: Array[Node3D] = []

var mobile_pick_pressed := false
var mobile_drop_pressed := false
var mobile_interact_pressed := false


func _ready():
	add_to_group("player")
	camera_base_pos = camera.transform.origin
	standing_colide_shape.disabled = false
	crouch_colide_shape.disabled = true
	if has_node("/root/GameSettings"):
		dark_mode_enabled = bool(get_node("/root/GameSettings").dark_mode)
	flashlight_on = dark_mode_enabled
	if flashlight:
		flashlight.visible = flashlight_on
		if dark_mode_enabled:
			flashlight.light_energy = 3.2
			flashlight.spot_range = 19.0
			flashlight.spot_angle = 44.0

	is_touch_device = DisplayServer.is_touchscreen_available()
	if is_touch_device:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		touch_controls.visible = true
		gt_bt.visible = true
		gt_bt.toggle_mode = true
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		touch_controls.visible = false
		gt_bt.visible = false

	rc_bt.visible = false
	ws_bt.visible = false
	bx_bt.visible = false
	label.text = ""
	label_2.text = ""

	ws_bt.pressed.connect(func(): mobile_pick_pressed = true)
	bx_bt.pressed.connect(func(): mobile_drop_pressed = true)
	rc_bt.pressed.connect(func(): mobile_interact_pressed = true)
	call_deferred("_cache_wardrobes")


func _cache_wardrobes() -> void:
	wardrobe_nodes.clear()
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and n.name.to_lower().begins_with("wardrobe"):
			wardrobe_nodes.append(n as Node3D)
		for c in n.get_children():
			stack.append(c)


func _unhandled_input(event):
	if jumpscare_lock_active:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(60))
	elif event is InputEventScreenDrag and is_touch_device:
		var viewport_width = get_viewport().get_visible_rect().size.x
		if event.position.x > viewport_width * 0.45:
			head.rotate_y(-event.relative.x * TOUCH_SENSITIVITY)
			camera.rotate_x(-event.relative.y * TOUCH_SENSITIVITY)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(60))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_flashlight()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T or event.keycode == KEY_L:
			_toggle_flashlight()


func _toggle_flashlight() -> void:
	if not dark_mode_enabled:
		if flashlight:
			flashlight.visible = false
		flashlight_on = false
		return
	flashlight_on = !flashlight_on
	if flashlight:
		flashlight.visible = flashlight_on
	_play_sfx("ui_click", -5.0, 1.2 if flashlight_on else 0.85)


func _can_interact_collider(col: Object) -> bool:
	if col == null or not is_instance_valid(col):
		return false
	if not (col is CollisionObject3D):
		return false
	if (col.collision_layer & 4) == 0:
		return false
	return col.has_method("interact")


func _play_sfx(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx(sound_name, volume_db, pitch_scale)


func _emit_noise(radius: float, priority: float = 1.0) -> void:
	get_tree().call_group("enemy", "hear_noise", global_position, radius, priority)


func _notify_enemy_progress(amount: float = 0.14) -> void:
	get_tree().call_group("enemy", "notify_player_progress", amount)
	get_tree().call_group("enemy", "notify_world_changed")


func _show_hint(msg: String, duration: float = 2.0) -> void:
	label_2.text = msg
	hint_timer = duration


func trap_player(duration: float = 3.5) -> void:
	trapped_timer = maxf(trapped_timer, duration)
	camera_shake = 0.75
	_show_hint("BEAR TRAP! Press [E] repeatedly to break free!", 3.5)
	var root: Node = get_tree().current_scene
	if root and root.has_method("trigger_blood_flash"):
		root.trigger_blood_flash(0.85)


func force_look_at_enemy(enemy_face_pos: Vector3) -> void:
	jumpscare_target_pos = enemy_face_pos
	jumpscare_lock_active = true
	camera_shake = 0.9


func play_wakeup_animation() -> void:
	wakeup_timer = 1.6
	head.position.y = 0.75
	camera.rotation.z = deg_to_rad(14.0)


func reset_for_new_day() -> void:
	if picked and is_instance_valid(detected):
		detected.picked = false
		detected.dropped = true
	picked = false
	detected = null
	jumpscare_lock_active = false
	trapped_timer = 0.0
	is_unlocking = false
	pending_unlock_target = null
	stamina = MAX_STAMINA
	stamina_exhausted = false
	camera_shake = 0.0
	velocity = Vector3.ZERO
	crouched = false
	is_hidden = false
	standing_colide_shape.disabled = false
	crouch_colide_shape.disabled = true
	head.position.y = STAND_HEIGHT
	camera.rotation = Vector3.ZERO
	set_physics_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	label.text = ""
	label_2.text = ""
	play_wakeup_animation()


func _pretty_item_name(raw_name: String) -> String:
	var pretty: Dictionary = {
		"hammer": "Hammer",
		"old_key": "Wardrobe Key",
		"grid_key": "Grid Gate Key",
		"gf_base_door_key": "Basement Key",
		"lockpin": "Lockpin",
		"monster_key": "Master Key",
		"need_gear": "Boat Gear",
	}
	return str(pretty.get(raw_name, raw_name))


func get_held_item_label() -> String:
	if not picked or not is_instance_valid(detected):
		return "Hands: Empty"
	return "Holding: %s" % _pretty_item_name(detected.name)


func consume_held_item() -> void:
	if picked and is_instance_valid(detected):
		var item: Node = detected
		if item is pickable:
			item.picked = false
			item.dropped = false
		if item is CollisionObject3D:
			item.collision_layer = 0
			item.collision_mask = 0
		item.visible = false
		item.queue_free()
	picked = false
	detected = null


func _get_interact_prompt(col: Object) -> String:
	if col.has_method("get_interact_prompt"):
		return str(col.get_interact_prompt())
	if col.get("keyreq") == true:
		var req_key: String = str(col.get("keyname"))
		var key_label: String = _pretty_item_name(req_key)
		if picked and is_instance_valid(detected) and detected.name == req_key:
			return "[E] Unlock (%s)" % key_label
		return "[E] Locked — Needs %s" % key_label
	if col.get("beatreq") == true:
		var req_beat: String = str(col.get("beatname"))
		var beat_label: String = _pretty_item_name(req_beat)
		if picked and is_instance_valid(detected) and detected.name == req_beat:
			return "[E] Break Plank (%s)" % beat_label
		return "[E] Barricaded — Needs %s" % beat_label
	if col.get("pinreq") == true:
		if picked and is_instance_valid(detected) and detected.name == "lockpin":
			return "[E] Pick Lock (Lockpin)"
		return "[E] Locked — Needs Lockpin"
	if col is Node and col.name == "openz_all_locks":
		var md: Node = col.get_parent()
		if md:
			var has_mkey: bool = md.get("monster_key") == true
			var has_plank: bool = md.get("wooden_hammer") == true
			if picked and is_instance_valid(detected):
				if detected.name == "monster_key" and not has_mkey:
					return "[E] Unlock Padlock (Master Key)"
				if detected.name == "hammer" and not has_plank:
					return "[E] Break Plank (Hammer)"
			if has_mkey and has_plank:
				return "[E] Open Main Door & Escape!"
			var missing: PackedStringArray = PackedStringArray()
			if not has_plank:
				missing.append("Hammer (Plank)")
			if not has_mkey:
				missing.append("Master Key")
			return "[E] Main Door — Needs: %s" % " + ".join(missing)
	return "[E] Open / Close"


func get_stealth_status() -> String:
	if trapped_timer > 0.0:
		return "TRAPPED! Press [E]!"
	if is_hidden:
		return "HIDDEN (Wardrobe)"
	if crouched:
		return "CROUCHED (Silent)"
	if dark_mode_enabled and not flashlight_on:
		return "DARK STEALTH (Light Off)"
	return ""


func get_stamina_ratio() -> float:
	return clampf(stamina / MAX_STAMINA, 0.0, 1.0)


func _update_wardrobe_hiding() -> void:
	is_hidden = false
	if not crouched:
		return
	for w in wardrobe_nodes:
		if not is_instance_valid(w):
			continue
		if absf(w.global_position.y - global_position.y) < 1.8 and w.global_position.distance_to(global_position) < 1.55:
			is_hidden = true
			return


func _process(delta):
	if jumpscare_lock_active:
		# Snap player head/camera dramatically toward the clown face during attack
		var to_enemy: Vector3 = jumpscare_target_pos - camera.global_position
		if to_enemy.length_squared() > 0.001:
			var target_yaw: float = atan2(-to_enemy.x, -to_enemy.z)
			head.global_rotation.y = lerp_angle(head.global_rotation.y, target_yaw, delta * 14.0)
			var horiz: float = Vector2(to_enemy.x, to_enemy.z).length()
			var target_pitch: float = atan2(to_enemy.y, maxf(horiz, 0.01))
			camera.rotation.x = lerp_angle(camera.rotation.x, clampf(target_pitch, -0.7, 0.7), delta * 14.0)
		camera_shake = maxf(camera_shake - delta * 0.7, 0.25)
		camera.transform.origin = camera_base_pos + Vector3(
			randf_range(-0.04, 0.04) * camera_shake,
			randf_range(-0.04, 0.04) * camera_shake,
			0.0
		)
		return

	var want_pick = Input.is_action_just_pressed("F") or mobile_pick_pressed
	var want_drop = Input.is_action_just_pressed("G") or mobile_drop_pressed
	var want_interact = Input.is_action_just_pressed("E") or mobile_interact_pressed
	mobile_pick_pressed = false
	mobile_drop_pressed = false
	mobile_interact_pressed = false

	if trapped_timer > 0.0:
		trapped_timer -= delta
		if want_interact:
			trapped_timer -= 0.7
			_play_sfx("door_locked", -3.0, 1.15)
		if trapped_timer <= 0.0:
			trapped_timer = 0.0
			_show_hint("Freed from Bear Trap!", 1.2)

	if hint_timer > 0.0:
		hint_timer -= delta
		if hint_timer <= 0.0 and not is_unlocking:
			label_2.text = ""

	if is_unlocking:
		if picked and is_instance_valid(detected):
			handpos.emit(hand.global_transform)
		label.text = ""
		rc_bt.visible = false
		ws_bt.visible = false
		bx_bt.visible = false
		return

	if picked and not is_instance_valid(detected):
		picked = false
		detected = null

	# Pick up or swap item
	if want_pick and reach.is_colliding():
		var col = reach.get_collider()
		if col is pickable:
			if not picked:
				picked = true
				detected = col
				col.picked = true
				_play_sfx("pickup", -2.0, randf_range(0.95, 1.08))
			elif col != detected:
				detected.picked = false
				detected.dropped = true
				detected = col
				col.picked = true
				_play_sfx("pickup", -2.0, randf_range(0.95, 1.08))

	# Keep held item in hand & handle drop
	if picked:
		handpos.emit(hand.global_transform)
		bx_bt.visible = true
		if want_drop:
			detected.picked = false
			detected.dropped = true
			picked = false
			detected = null
			_play_sfx("drop", -1.5, randf_range(0.92, 1.08))
			_emit_noise(DROP_NOISE_RADIUS)
	else:
		bx_bt.visible = false

	var reach_col = reach.get_collider() if reach.is_colliding() else null
	var ship_hit = for_ship.is_colliding()
	var interact_col = interact.get_collider() if interact.is_colliding() else null

	if reach_col is pickable:
		ws_bt.visible = true
		rc_bt.visible = false
		label.text = "[F] Pick Up %s" % _pretty_item_name(reach_col.name)
	elif ship_hit:
		var ship_col = for_ship.get_collider()
		ws_bt.visible = false
		rc_bt.visible = true
		if ship_col and ship_col.has_method("get_prompt"):
			label.text = ship_col.get_prompt(self)
			if want_interact and ship_col.has_method("interact_boat"):
				ship_col.interact_boat(self)
				return
		else:
			label.text = "[E] Boat"
	elif _can_interact_collider(interact_col):
		ws_bt.visible = false
		rc_bt.visible = true
		label.text = _get_interact_prompt(interact_col)
		if want_interact:
			var needs_key = interact_col.get("keyreq") == true
			var needs_beat = interact_col.get("beatreq") == true
			var needs_pin = interact_col.get("pinreq") == true

			if needs_key:
				var req_key = str(interact_col.get("keyname"))
				if picked and is_instance_valid(detected) and detected.name == req_key:
					pending_unlock_target = interact_col
					hold_player_circle_loading()
					timer.start()
				else:
					_play_sfx("door_locked", -2.0, randf_range(0.95, 1.05))
					_show_hint("LOCKED! Needs %s" % _pretty_item_name(req_key))
			elif needs_beat:
				var req_beat = str(interact_col.get("beatname"))
				if picked and is_instance_valid(detected) and detected.name == req_beat:
					interact_col.interact()
					interact_col.collision_layer = 1
					_play_sfx("plank_break", 0.0, randf_range(0.95, 1.05))
					_emit_noise(UNLOCK_NOISE_RADIUS, 1.5)
					_notify_enemy_progress(0.18)
				else:
					_play_sfx("door_locked", -2.0, randf_range(0.95, 1.05))
					_show_hint("BARRICADED! Needs %s" % _pretty_item_name(req_beat))
			elif needs_pin:
				if picked and is_instance_valid(detected) and detected.name == "lockpin":
					pending_unlock_target = interact_col
					hold_player_circle_loading()
					timer.start()
				else:
					_play_sfx("door_locked", -2.0, randf_range(0.95, 1.05))
					_show_hint("LOCKED! Needs Lockpin")
			elif interact_col.name == "openz_all_locks":
				var md: Node = interact_col.get_parent()
				var handled_shortcut: bool = false
				if md and picked and is_instance_valid(detected):
					if detected.name == "monster_key" and md.get("monster_key") != true:
						var lock_node := md.get_node_or_null("need_monster_key")
						if lock_node:
							pending_unlock_target = lock_node
							hold_player_circle_loading()
							timer.start()
							handled_shortcut = true
					elif detected.name == "hammer" and md.get("wooden_hammer") != true:
						var plank_node := md.get_node_or_null("wood_hammer")
						if plank_node and plank_node.has_method("interact"):
							plank_node.interact()
							if plank_node is CollisionObject3D:
								plank_node.collision_layer = 1
							_play_sfx("plank_break", 0.0, randf_range(0.95, 1.05))
							_emit_noise(UNLOCK_NOISE_RADIUS, 1.5)
							_notify_enemy_progress(0.18)
							handled_shortcut = true
				if not handled_shortcut:
					interact_col.interact()
					_play_sfx("door_open", -3.5, randf_range(0.90, 1.10))
					_emit_noise(INTERACT_NOISE_RADIUS * 0.6)
			else:
				interact_col.interact()
				_play_sfx("door_open", -3.5, randf_range(0.90, 1.10))
				_emit_noise(INTERACT_NOISE_RADIUS * 0.6)
	else:
		label.text = ""
		rc_bt.visible = false
		ws_bt.visible = false


func _physics_process(delta):
	if jumpscare_lock_active:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if trapped_timer > 0.0:
		velocity.x = lerp(velocity.x, 0.0, delta * 12.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 12.0)
		camera_shake = maxf(camera_shake - delta * 1.5, 0.0)
		camera.transform.origin = camera_base_pos + Vector3(
			randf_range(-0.025, 0.025) * camera_shake,
			randf_range(-0.025, 0.025) * camera_shake,
			0.0
		)
		move_and_slide()
		return

	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouched:
		velocity.y = JUMP_VELOCITY

	# Crouch handling
	if wakeup_timer > 0.0:
		wakeup_timer = maxf(wakeup_timer - delta, 0.0)
		camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, delta * 3.2)
	else:
		camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, delta * 8.0)

	var want_crouch = Input.is_action_pressed("crouch") or (is_touch_device and gt_bt.button_pressed)
	if want_crouch:
		standing_colide_shape.disabled = true
		crouch_colide_shape.disabled = false
		head.position.y = lerp(head.position.y, CROUCH_DEPTH, delta * 12.0)
		crouched = true
	elif crouched and crouch_raycast.is_colliding():
		standing_colide_shape.disabled = true
		crouch_colide_shape.disabled = false
		head.position.y = lerp(head.position.y, CROUCH_DEPTH, delta * 12.0)
		crouched = true
	else:
		head.position.y = lerp(head.position.y, STAND_HEIGHT, delta * 12.0)
		standing_colide_shape.disabled = false
		crouch_colide_shape.disabled = true
		crouched = false

	_update_wardrobe_hiding()

	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Stamina & Sprint
	var wants_sprint: bool = Input.is_action_pressed("sprint") and not crouched and direction.length() > 0.1
	var is_sprinting: bool = wants_sprint and not stamina_exhausted and stamina > 0.5
	if is_sprinting:
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
		if stamina <= 0.5:
			stamina_exhausted = true
			_show_hint("Out of breath!", 1.2)
		speed = SPRINT_SPEED
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, MAX_STAMINA)
		if stamina_exhausted and stamina >= 24.0:
			stamina_exhausted = false
		speed = CROUCH_SPEED if crouched else WALK_SPEED

	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, 0.0, delta * 7.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)

	# Footstep noise alerts nearby enemy (crouching is completely silent)
	var horiz_speed = Vector2(velocity.x, velocity.z).length()
	if is_sprinting and is_on_floor() and horiz_speed > WALK_SPEED + 1.0:
		walk_noise_timer = 0.0
		sprint_noise_timer -= delta
		if sprint_noise_timer <= 0.0:
			sprint_noise_timer = SPRINT_NOISE_INTERVAL
			_play_sfx("footstep_player", -6.0, randf_range(0.95, 1.15))
			_emit_noise(SPRINT_NOISE_RADIUS, 1.25)
	elif not crouched and is_on_floor() and horiz_speed > 1.5:
		sprint_noise_timer = 0.0
		walk_noise_timer -= delta
		if walk_noise_timer <= 0.0:
			walk_noise_timer = WALK_NOISE_INTERVAL
			_play_sfx("footstep_player", -12.0, randf_range(0.88, 1.05))
			_emit_noise(WALK_NOISE_RADIUS, 0.7)
	else:
		sprint_noise_timer = 0.0
		walk_noise_timer = 0.0

	# Head bob + subtle camera shake
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera_shake = maxf(camera_shake - delta * 2.0, 0.0)
	var shake_vec: Vector3 = Vector3(
		randf_range(-0.02, 0.02) * camera_shake,
		randf_range(-0.02, 0.02) * camera_shake,
		0.0
	)
	camera.transform.origin = camera_base_pos + _headbob(t_bob) + shake_vec

	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)

	move_and_slide()


func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos


func _on_timer_timeout() -> void:
	is_unlocking = false
	set_physics_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	label_2.text = ""
	if is_instance_valid(pending_unlock_target):
		if pending_unlock_target.has_method("interact"):
			pending_unlock_target.interact()
		if pending_unlock_target.get("pinreq") == true:
			pending_unlock_target.set("pinreq", false)
		elif pending_unlock_target is CollisionObject3D:
			pending_unlock_target.collision_layer = 1
		_play_sfx("unlock", -1.0, randf_range(0.95, 1.05))
		_emit_noise(UNLOCK_NOISE_RADIUS, 1.4)
		_notify_enemy_progress(0.16)
	pending_unlock_target = null


func hold_player_circle_loading():
	is_unlocking = true
	label_2.text = "Unlocking~ please wait..."
	hint_timer = 0.0
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)


func hit(_dir: Vector3 = Vector3.ZERO) -> void:
	pass
