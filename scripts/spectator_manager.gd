extends Node3D
# ============================================================
# Watch Mode / Spectator Manager
# The game plays itself: player auto-walks & interacts, Robert
# keeps patrolling/chasing via its AI. You just watch and switch
# camera modes. Press F10 to toggle, 1/2/3/4 to switch camera.
# ============================================================

enum CamMode { PLAYER, ROBERT, ORBIT, CINEMATIC }

var player: CharacterBody3D = null
var robert: Node3D = null
var nav_region: NavigationRegion3D = null
var nav_map: RID = RID()

var active: bool = false
var cam_mode: CamMode = CamMode.PLAYER

# Spectator camera
var spectator_cam: Camera3D = null
var player_cam: Camera3D = null

# Auto-pilot state
var waypoint: Vector3 = Vector3.ZERO
var waypoint_timer: float = 0.0
var auto_interact_timer: float = 0.0
var cinematic_timer: float = 0.0
var cinematic_points: Array[Vector3] = []
var cinematic_idx: int = 0

# Orbit state
var orbit_yaw: float = 0.0
var orbit_pitch: float = 0.25
var orbit_dist: float = 4.5
var orbit_target: Vector3 = Vector3.ZERO

# UI
var ui_layer: CanvasLayer = null
var ui_label: Label = null
var ui_panel: PanelContainer = null

const WATCH_KEY: int = 4194346  # F10


func _ready() -> void:
	_find_nodes()
	_build_ui()
	_build_spectator_cam()


func _find_nodes() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	robert = get_tree().get_first_node_in_group("enemy") as Node3D
	nav_region = find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if nav_region == null:
		nav_region = find_child("NavigationRegion3D", true, true) as NavigationRegion3D
	if nav_region:
		nav_map = nav_region.get_navigation_map()
	if player:
		player_cam = player.get_node_or_null("head/Camera3D") as Camera3D


func _build_spectator_cam() -> void:
	spectator_cam = Camera3D.new()
	spectator_cam.fov = 72.0
	spectator_cam.near = 0.05
	spectator_cam.far = 200.0
	add_child(spectator_cam)


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 50
	add_child(ui_layer)

	ui_panel = PanelContainer.new()
	ui_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ui_panel.offset_left = -340.0
	ui_panel.offset_top = 16.0
	ui_panel.offset_right = -16.0
	ui_panel.offset_bottom = 120.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.04, 0.88)
	style.border_color = Color(0.72, 0.12, 0.12, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	ui_panel.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(ui_panel)

	ui_label = Label.new()
	ui_label.text = "WATCH MODE"
	ui_label.add_theme_font_size_override("font_size", 28)
	ui_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	ui_panel.add_child(ui_label)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.85, 0.8, 0.75))
	hint.text = "F10: Exit Watch  |  1: Player  2: Robert\n3: Orbit  4: Cinematic  (mouse: look)"
	ui_panel.add_child(hint)
	ui_label = hint  # keep ref for updates


func activate(on: bool) -> void:
	if on:
		_activate()
	else:
		_deactivate()


func _activate() -> void:
	if active:
		return
	active = true
	_find_nodes()

	# Enable spectator mode on player (disables input, allows auto-dir)
	if player and player.has_method("spectator_enable"):
		player.spectator_enable(true)

	# Take over camera
	if spectator_cam:
		spectator_cam.make_current()
	if player_cam:
		player_cam.make_current(false)

	# Prepare cinematic tour points
	_build_cinematic_points()
	_pick_waypoint()

	_update_ui()


func _deactivate() -> void:
	if not active:
		return
	active = false

	# Restore player control
	if player and player.has_method("spectator_enable"):
		player.spectator_enable(false)
	player.spectator_dir = Vector3.ZERO

	# Restore original camera
	if player_cam:
		player_cam.make_current()
	if spectator_cam:
		spectator_cam.make_current(false)


func _build_cinematic_points() -> void:
	cinematic_points.clear()
	if nav_region == null:
		return
	# Sample points spread across the house for a tour
	var min_bx: float = 0.0
	var max_bx: float = 0.0
	var min_bz: float = 0.0
	var max_bz: float = 0.0
	var aabb: AABB = nav_region.get_global_bounds()
	min_bx = aabb.position.x; max_bx = aabb.position.x + aabb.size.x
	min_bz = aabb.position.z; max_bz = aabb.position.z + aabb.size.z
	var count := 12
	for i in range(count):
		var x := randf_range(min_bx, max_bx)
		var z := randf_range(min_bz, max_bz)
		var y := aabb.position.y + aabb.size.y * 0.5
		var pt: Vector3 = _snap_to_nav(Vector3(x, y, z))
		if pt != Vector3.INF:
			cinematic_points.append(pt)
	if cinematic_points.is_empty():
		if player:
			cinematic_points.append(player.global_position)


func _snap_to_nav(pos: Vector3) -> Vector3:
	if nav_map.is_valid():
		var p: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, pos)
		if p != Vector3.INF:
			return p
	return Vector3.INF


func _pick_waypoint() -> void:
	if nav_region == null:
		if player:
			waypoint = player.global_position + Vector3(0.0, 0.0, -4.0)
		return
	var aabb: AABB = nav_region.get_global_bounds()
	var tries := 0
	while tries < 12:
		var x := randf_range(aabb.position.x, aabb.position.x + aabb.size.x)
		var z := randf_range(aabb.position.z, aabb.position.z + aabb.size.z)
		var y := aabb.position.y + aabb.size.y * 0.5
		var pt := _snap_to_nav(Vector3(x, y, z))
		if pt != Vector3.INF:
			if player and pt.distance_to(player.global_position) > 2.5:
				waypoint = pt
				return
		tries += 1
	if player:
		waypoint = player.global_position + Vector3(0.0, 0.0, -4.0)


func _process(delta: float) -> void:
	if not active:
		return

	_update_autopilot(delta)
	match cam_mode:
		CamMode.PLAYER:
			_update_cam_player()
		CamMode.ROBERT:
			_update_cam_robert()
		CamMode.ORBIT:
			_update_cam_orbit(delta)
		CamMode.CINEMATIC:
			_update_cam_cinematic(delta)


func _update_autopilot(delta: float) -> void:
	if player == null:
		return
	waypoint_timer -= delta
	if waypoint_timer <= 0.0 or waypoint == Vector3.ZERO:
		_pick_waypoint()
		waypoint_timer = randf_range(6.0, 12.0)

	var to_wp := Vector3(waypoint.x - player.global_position.x, 0.0, waypoint.z - player.global_position.z)
	var dist := to_wp.length()

	# Flee from Robert if he's chasing & close (keeps watch session alive)
	if robert != null:
		var to_rob := Vector3(robert.global_position.x - player.global_position.x, 0.0, robert.global_position.z - player.global_position.z)
		var rob_dist := to_rob.length()
		if rob_dist < 8.0:
			to_rob = to_rob.normalized()
			# steer away from Robert, blended with waypoint
			to_wp = to_wp.normalized() if dist > 0.001 else Vector3(0.0, 0.0, 1.0)
			var flee := -to_rob
			to_wp = (to_wp + flee * 2.0).normalized()
			dist = 999.0

	if dist < 1.5:
		# Reached waypoint, idle briefly then pick new
		player.spectator_dir = Vector3.ZERO
		return

	# Steer player toward waypoint
	to_wp = to_wp.normalized()
	player.spectator_dir = to_wp

	# Auto-face the movement direction (rotate head to face dir)
	if player.spectator_auto_face:
		var target_yaw := atan2(-to_wp.x, -to_wp.z)
		var head: Node3D = player.get_node_or_null("head") as Node3D
		if head:
			head.global_rotation.y = lerp_angle(head.global_rotation.y, target_yaw, delta * 6.0)

	# Auto-interact with nearby interactables (doors, items)
	auto_interact_timer -= delta
	if auto_interact_timer <= 0.0:
		auto_interact_timer = 0.25
		_try_auto_interact()


func _try_auto_interact() -> void:
	if player == null:
		return
	var interact: RayCast3D = player.get_node_or_null("head/Camera3D/interact") as RayCast3D
	if interact and interact.is_colliding():
		var col := interact.get_collider()
		if col and col.is_in_group("interactable") or col.has_method("interact"):
			player.spectator_interact_request = true
			return
	# Also interact with doors directly in front
	var space := get_world_3d().direct_space_state
	var origin := player.global_position + Vector3(0.0, 1.2, 0.0)
	var fwd := Vector3(0.0, 0.0, -1.0)
	if player.spectator_dir.length_squared() > 0.001:
		fwd = player.spectator_dir.normalized()
	var dir_target := origin + fwd * 2.2
	var q := PhysicsRayQueryParameters3D.create(origin, dir_target)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var col2 = hit.get("collider")
		if col2 and (col2.is_in_group("interactable") or col2.has_method("interact")):
			# rotate head to face it then interact
			var head: Node3D = player.get_node_or_null("head") as Node3D
			if head:
				var to_it := Vector3(hit.get("position").x - player.global_position.x, 0.0, hit.get("position").z - player.global_position.z)
				if to_it.length_squared() > 0.001:
					head.global_rotation.y = atan2(-to_it.x, -to_it.z)
			player.spectator_interact_request = true


func _update_cam_player() -> void:
	if spectator_cam == null or player == null:
		return
	var fwd := Vector3(0.0, 0.0, -1.0)
	var head: Node3D = player.get_node_or_null("head") as Node3D
	if head:
		fwd = -head.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var cam_pos := player.global_position + Vector3(0.0, 1.7, 0.0) - fwd * 3.2 + Vector3(0.0, 0.6, 0.0)
	spectator_cam.global_position = cam_pos
	spectator_cam.look_at(player.global_position + Vector3(0.0, 1.5, 0.0) + fwd * 4.0)


func _update_cam_robert() -> void:
	if spectator_cam == null or robert == null:
		return
	var fwd := -robert.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3(0.0, 0.0, -1.0)
	fwd = fwd.normalized()
	var cam_pos := robert.global_position + Vector3(0.0, 1.9, 0.0) - fwd * 3.6 + Vector3(0.0, 0.5, 0.0)
	spectator_cam.global_position = cam_pos
	spectator_cam.look_at(robert.global_position + Vector3(0.0, 1.5, 0.0))


func _update_cam_orbit(delta: float) -> void:
	if spectator_cam == null:
		return
	if player:
		orbit_target = player.global_position + Vector3(0.0, 1.3, 0.0)
	# Mouse look for orbit
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Input.get_mouse_position().length() > 0.0:
		# Use mouse movement via InputEvent mouse — handled in _unhandled_input
		pass
	var radius := orbit_dist
	var cam_pos := orbit_target + Vector3(
		sin(orbit_yaw) * cos(orbit_pitch) * radius,
		sin(orbit_pitch) * radius + 1.0,
		cos(orbit_yaw) * cos(orbit_pitch) * radius
	)
	spectator_cam.global_position = cam_pos
	spectator_cam.look_at(orbit_target)


func _update_cam_cinematic(delta: float) -> void:
	if spectator_cam == null:
		return
	cinematic_timer -= delta
	if cinematic_timer <= 0.0 or cinematic_idx >= cinematic_points.size():
		if cinematic_points.is_empty():
			_build_cinematic_points()
		if cinematic_points.is_empty():
			return
		cinematic_idx = 0
		cinematic_timer = 5.0
	var wp := cinematic_points[cinematic_idx]
	var prev: Vector3 = Vector3.ZERO
	if cinematic_idx > 0:
		prev = cinematic_points[cinematic_idx - 1]
	var look_dir := (wp - prev) if prev != Vector3.ZERO else Vector3(0.0, 0.0, -1.0)
	look_dir.y = 0.0
	if look_dir.length_squared() < 0.001:
		look_dir = Vector3(0.0, 0.0, -1.0)
	look_dir = look_dir.normalized()
	# Position camera offset to the side of movement for a tracking shot
	var side := Vector3(-look_dir.z, 0.0, look_dir.x)
	var cam_pos := wp - look_dir * 3.0 + side * 2.2 + Vector3(0.0, 1.8, 0.0)
	spectator_cam.global_position = lerp(spectator_cam.global_position, cam_pos, delta * 1.2)
	spectator_cam.look_at(wp + look_dir * 3.0)
	cinematic_timer = 5.0


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			WATCH_KEY:
				activate(false)
			KEY_ONE:
				_set_cam_mode(CamMode.PLAYER)
			KEY_TWO:
				_set_cam_mode(CamMode.ROBERT)
			KEY_THREE:
				_set_cam_mode(CamMode.ORBIT)
			KEY_FOUR:
				_set_cam_mode(CamMode.CINEMATIC)
	if event is InputEventMouseMotion and cam_mode == CamMode.ORBIT:
		orbit_yaw -= event.relative.x * 0.005
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.005, -0.2, 1.1)


func _set_cam_mode(mode: CamMode) -> void:
	cam_mode = mode
	_update_ui()


func _update_ui() -> void:
	if ui_label == null:
		return
	var names: Array[String] = ["PLAYER CAM", "ROBERT CAM", "ORBIT CAM", "CINEMATIC TOUR"]
	ui_label.text = "WATCH MODE  •  %s" % names[cam_mode]


func is_active() -> bool:
	return active
