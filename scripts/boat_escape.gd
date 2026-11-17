extends StaticBody3D

# Granny 2 style Boat Escape controller attached to `need_gear` inside `scenes/ship/ship.tscn`.
# Step 1: Install `need_gear` (Boat Gear) into the boat engine console.
# Step 2: Pull the 3D Boat Lever to start the engine and escape!

var gear_installed: bool = false
var escaping: bool = false

var lever_pivot: Node3D = null
var status_mat: StandardMaterial3D = null
var gear_mesh: MeshInstance3D = null


func _ready() -> void:
	collision_layer = 32
	_ensure_generous_hitbox()
	_build_boat_lever_console()


func _ensure_generous_hitbox() -> void:
	var col := get_node_or_null("CollisionShape3D4") as CollisionShape3D
	if col:
		var box := BoxShape3D.new()
		box.size = Vector3(2.8, 2.2, 2.2)
		col.shape = box
		col.position = Vector3(-0.2, 0.35, -0.45)


func _build_boat_lever_console() -> void:
	var console := Node3D.new()
	console.name = "BoatConsole"
	# Placed visibly near the boat stern/cockpit so the player sees it from the dock
	console.position = Vector3(-0.22, 0.28, -0.78)
	add_child(console)

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.20, 0.22, 0.25)
	metal_mat.metallic = 0.75
	metal_mat.roughness = 0.4

	var base_box := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(0.30, 0.22, 0.26)
	base_box.mesh = b_mesh
	base_box.material_override = metal_mat
	console.add_child(base_box)

	# Status lamp (red until Boat Gear is installed, then green)
	status_mat = StandardMaterial3D.new()
	status_mat.albedo_color = Color(0.9, 0.15, 0.12)
	status_mat.emission_enabled = true
	status_mat.emission = Color(0.95, 0.15, 0.1)
	status_mat.emission_energy_multiplier = 1.6

	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.045
	lamp_mesh.height = 0.09
	lamp.mesh = lamp_mesh
	lamp.material_override = status_mat
	lamp.position = Vector3(-0.08, 0.12, 0.06)
	console.add_child(lamp)

	# Visible installed Boat Gear indicator on the side of the console
	var gear_mat := StandardMaterial3D.new()
	gear_mat.albedo_color = Color(0.78, 0.62, 0.24)
	gear_mat.metallic = 0.85
	gear_mat.roughness = 0.3

	gear_mesh = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.11
	gm.bottom_radius = 0.11
	gm.height = 0.05
	gear_mesh.mesh = gm
	gear_mesh.material_override = gear_mat
	gear_mesh.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	gear_mesh.position = Vector3(0.18, 0.02, 0.0)
	gear_mesh.visible = false
	console.add_child(gear_mesh)

	# Pivoting Boat Throttle Lever
	lever_pivot = Node3D.new()
	lever_pivot.position = Vector3(0.03, 0.10, 0.0)
	lever_pivot.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
	console.add_child(lever_pivot)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.022
	shaft_mesh.bottom_radius = 0.026
	shaft_mesh.height = 0.34
	shaft.mesh = shaft_mesh
	shaft.material_override = metal_mat
	shaft.position = Vector3(0.0, 0.17, 0.0)
	lever_pivot.add_child(shaft)

	var knob_mat := StandardMaterial3D.new()
	knob_mat.albedo_color = Color(0.82, 0.12, 0.10)
	knob_mat.roughness = 0.35

	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.055
	knob_mesh.height = 0.11
	knob.mesh = knob_mesh
	knob.material_override = knob_mat
	knob.position = Vector3(0.0, 0.35, 0.0)
	lever_pivot.add_child(knob)


func _process(delta: float) -> void:
	if gear_installed and gear_mesh and gear_mesh.visible:
		gear_mesh.rotate_x(delta * (8.0 if escaping else 1.8))


func get_prompt(player: Node) -> String:
	if escaping:
		return "Starting Boat..."
	if not gear_installed:
		if player and _player_holds_gear(player):
			return "[E] Install Boat Gear"
		return "[E] Boat Engine (Needs Boat Gear)"
	return "[E] Pull Boat Lever to Escape!"


func interact_boat(player: Node) -> void:
	if escaping:
		return

	if not gear_installed:
		if player and _player_holds_gear(player):
			gear_installed = true
			if player.has_method("consume_held_item"):
				player.consume_held_item()
			if gear_mesh:
				gear_mesh.visible = true
			if status_mat:
				status_mat.albedo_color = Color(0.18, 0.92, 0.32)
				status_mat.emission = Color(0.20, 0.95, 0.35)
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("unlock", -1.0, 1.0)
			if player.has_method("_emit_noise"):
				player._emit_noise(15.0, 1.4)
			if player.has_method("_notify_enemy_progress"):
				player._notify_enemy_progress(0.20)
			if player.has_method("_show_hint"):
				player._show_hint("Boat Gear installed! Pull the Boat Lever to escape!", 3.0)
		else:
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("door_locked", -2.0, 0.95)
			if player and player.has_method("_show_hint"):
				player._show_hint("BOAT NEEDS BOAT GEAR! (Check the dining table)", 2.8)
		return

	# Step 2: Pull the Boat Lever and escape!
	escaping = true
	if lever_pivot:
		var tw := create_tween()
		tw.tween_property(lever_pivot, "rotation_degrees:x", 35.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.play_sfx("unlock", 0.0, 0.9)
		am.play_sfx("boat_escape", -2.0, 1.0)
		am.play_sfx("victory", -2.0, 1.0)
	if player and player.has_method("_show_hint"):
		player._show_hint("BOAT STARTED! Escaping...", 2.0)

	await get_tree().create_timer(0.45).timeout
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")


func _player_holds_gear(player: Node) -> bool:
	var picked_flag: Variant = player.get("picked")
	var det: Variant = player.get("detected")
	if picked_flag != true or det == null or not is_instance_valid(det):
		return false
	return str(det.name) == "need_gear"
