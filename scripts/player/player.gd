extends CharacterBody3D

var speed
const WALK_SPEED = 4.0
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 4.8
const SENSITIVITY = 0.004
const TOUCH_SENSITIVITY = 0.006
const CROUCH_SPEED = 2.5
const CROUCH_DEPTH = 0.8
const STAND_HEIGHT = 1.8

# bob variables
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

# fov variables
const BASE_FOV = 80.0
const FOV_CHANGE = 1.1

# noise variables for enemy AI hearing
const SPRINT_NOISE_INTERVAL = 0.45
const SPRINT_NOISE_RADIUS = 14.0
const DROP_NOISE_RADIUS = 12.0
const INTERACT_NOISE_RADIUS = 10.0
var sprint_noise_timer = 0.0

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
var camera_base_pos: Vector3 = Vector3.ZERO

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

var mobile_pick_pressed := false
var mobile_drop_pressed := false
var mobile_interact_pressed := false


func _ready():
	add_to_group("player")
	camera_base_pos = camera.transform.origin
	standing_colide_shape.disabled = false
	crouch_colide_shape.disabled = true

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


func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(60))
	elif event is InputEventScreenDrag and is_touch_device:
		# Allow camera look on right half of screen
		var viewport_width = get_viewport().get_visible_rect().size.x
		if event.position.x > viewport_width * 0.45:
			head.rotate_y(-event.relative.x * TOUCH_SENSITIVITY)
			camera.rotate_x(-event.relative.y * TOUCH_SENSITIVITY)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(60))


func _can_interact_collider(col: Object) -> bool:
	if col == null or not is_instance_valid(col):
		return false
	if not (col is CollisionObject3D):
		return false
	# Layer 3 ("doors") is bit 4; exclude floors/walls even if layer 10 is set
	if (col.collision_layer & 4) == 0:
		return false
	return col.has_method("interact")


func _emit_noise(radius: float) -> void:
	get_tree().call_group("enemy", "hear_noise", global_position, radius)


func _show_hint(msg: String, duration: float = 2.0) -> void:
	label_2.text = msg
	hint_timer = duration


func _process(delta):
	var want_pick = Input.is_action_just_pressed("F") or mobile_pick_pressed
	var want_drop = Input.is_action_just_pressed("G") or mobile_drop_pressed
	var want_interact = Input.is_action_just_pressed("E") or mobile_interact_pressed
	mobile_pick_pressed = false
	mobile_drop_pressed = false
	mobile_interact_pressed = false

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

	# Clean up if held object was freed elsewhere
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
			elif col != detected:
				detected.picked = false
				detected.dropped = true
				detected = col
				col.picked = true

	# Keep held item in hand & handle drop
	if picked:
		handpos.emit(hand.global_transform)
		bx_bt.visible = true
		if want_drop:
			detected.picked = false
			detected.dropped = true
			picked = false
			detected = null
			_emit_noise(DROP_NOISE_RADIUS)
	else:
		bx_bt.visible = false

	# Priority UI + interactions:
	# 1. Pickable item in reach
	# 2. Boat escape (for_ship)
	# 3. Doors / drawers / locks (interact)
	var reach_col = reach.get_collider() if reach.is_colliding() else null
	var ship_hit = for_ship.is_colliding()
	var interact_col = interact.get_collider() if interact.is_colliding() else null

	if reach_col is pickable:
		ws_bt.visible = true
		rc_bt.visible = false
		label.text = "[F] to PICK UP"
	elif ship_hit:
		ws_bt.visible = false
		rc_bt.visible = true
		if picked and is_instance_valid(detected) and detected.name == "need_gear":
			label.text = "[E] to ESCAPE BY BOAT"
			if want_interact:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				get_tree().change_scene_to_file("res://scenes/game_over.tscn")
				return
		else:
			label.text = "[E] BOAT (NEED BOAT GEAR)"
			if want_interact:
				_show_hint("NEED BOAT GEAR to ESCAPE")
	elif _can_interact_collider(interact_col):
		ws_bt.visible = false
		rc_bt.visible = true
		label.text = "[E] to INTERACT"
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
					_show_hint("NEED a KEY to OPEN")
			elif needs_beat:
				var req_beat = str(interact_col.get("beatname"))
				if picked and is_instance_valid(detected) and detected.name == req_beat:
					interact_col.interact()
					interact_col.collision_layer = 1
					_emit_noise(INTERACT_NOISE_RADIUS)
				else:
					_show_hint("NEED a HAMMER to OPEN")
			elif needs_pin:
				if picked and is_instance_valid(detected) and detected.name == "lockpin":
					pending_unlock_target = interact_col
					hold_player_circle_loading()
					timer.start()
				else:
					_show_hint("NEED a LOCKPIN to OPEN")
			else:
				interact_col.interact()
				_emit_noise(INTERACT_NOISE_RADIUS * 0.6)
	else:
		label.text = ""
		rc_bt.visible = false
		ws_bt.visible = false


func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouched:
		velocity.y = JUMP_VELOCITY

	# Handle Sprint.
	var is_sprinting = Input.is_action_pressed("sprint") and not crouched
	if is_sprinting:
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Handle Crouch.
	var want_crouch = Input.is_action_pressed("crouch") or (is_touch_device and gt_bt.button_pressed)
	if want_crouch:
		standing_colide_shape.disabled = true
		crouch_colide_shape.disabled = false
		head.position.y = lerp(head.position.y, CROUCH_DEPTH, delta * 12.0)
		speed = CROUCH_SPEED
		crouched = true
	elif crouched and crouch_raycast.is_colliding():
		# Only stay crouched under low obstacles if already crouching
		standing_colide_shape.disabled = true
		crouch_colide_shape.disabled = false
		head.position.y = lerp(head.position.y, CROUCH_DEPTH, delta * 12.0)
		speed = CROUCH_SPEED
		crouched = true
	else:
		head.position.y = lerp(head.position.y, STAND_HEIGHT, delta * 12.0)
		standing_colide_shape.disabled = false
		crouch_colide_shape.disabled = true
		crouched = false

	# Movement & deceleration
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
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

	# Sprint footstep noise alerts nearby enemy
	var horiz_speed = Vector2(velocity.x, velocity.z).length()
	if is_sprinting and is_on_floor() and horiz_speed > WALK_SPEED + 1.0:
		sprint_noise_timer -= delta
		if sprint_noise_timer <= 0.0:
			sprint_noise_timer = SPRINT_NOISE_INTERVAL
			_emit_noise(SPRINT_NOISE_RADIUS)
	else:
		sprint_noise_timer = 0.0

	# Head bob (preserve camera base offset!)
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = camera_base_pos + _headbob(t_bob)

	# FOV
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
			# Allow door_lock doors to open/close normally once lockpicked
			pending_unlock_target.set("pinreq", false)
		elif pending_unlock_target is CollisionObject3D:
			pending_unlock_target.collision_layer = 1
		_emit_noise(INTERACT_NOISE_RADIUS)
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
