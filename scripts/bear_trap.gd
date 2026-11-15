extends Area3D

var armed: bool = true
var lifetime: float = 95.0
var jaw_left: MeshInstance3D = null
var jaw_right: MeshInstance3D = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Player layer
	monitoring = true
	monitorable = false
	_build_visuals_and_shape()
	body_entered.connect(_on_body_entered)


func _build_visuals_and_shape() -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.42
	cyl.height = 0.25
	shape.shape = cyl
	shape.position = Vector3(0.0, 0.12, 0.0)
	add_child(shape)

	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color(0.16, 0.15, 0.16)
	iron_mat.metallic = 0.75
	iron_mat.roughness = 0.45

	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.45, 0.08, 0.08)
	plate_mat.metallic = 0.4
	plate_mat.roughness = 0.6

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.34
	base_mesh.bottom_radius = 0.36
	base_mesh.height = 0.03
	base.mesh = base_mesh
	base.material_override = iron_mat
	base.position = Vector3(0.0, 0.015, 0.0)
	add_child(base)

	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.14
	plate_mesh.bottom_radius = 0.14
	plate_mesh.height = 0.04
	plate.mesh = plate_mesh
	plate.material_override = plate_mat
	plate.position = Vector3(0.0, 0.03, 0.0)
	add_child(plate)

	jaw_left = MeshInstance3D.new()
	var jl_mesh := BoxMesh.new()
	jl_mesh.size = Vector3(0.56, 0.08, 0.06)
	jaw_left.mesh = jl_mesh
	jaw_left.material_override = iron_mat
	jaw_left.position = Vector3(0.0, 0.045, -0.22)
	add_child(jaw_left)

	jaw_right = MeshInstance3D.new()
	var jr_mesh := BoxMesh.new()
	jr_mesh.size = Vector3(0.56, 0.08, 0.06)
	jaw_right.mesh = jr_mesh
	jaw_right.material_override = iron_mat
	jaw_right.position = Vector3(0.0, 0.045, 0.22)
	add_child(jaw_right)


func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if not armed:
		return
	if body == null or not body.is_in_group("player"):
		return
	armed = false
	if jaw_left:
		jaw_left.position.z = -0.05
		jaw_left.rotation.x = deg_to_rad(35.0)
	if jaw_right:
		jaw_right.position.z = 0.05
		jaw_right.rotation.x = deg_to_rad(-35.0)

	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.play_sfx("plank_break", 1.5, 1.15)
		am.play_sfx("door_locked", 1.0, 0.85)

	if body.has_method("trap_player"):
		body.trap_player(3.5)

	get_tree().call_group("enemy", "hear_noise", global_position, 26.0, 2.2)

	var timer := get_tree().create_timer(4.2)
	timer.timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)
