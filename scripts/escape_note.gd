extends StaticBody3D

# Physical aged-paper Escape Note placed on a table inside the house.
# Interacting with [E] opens the English escape guide overlay.


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	_build_note_visuals()


func _build_note_visuals() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(0.55, 0.24, 0.65)
		col.shape = box
		col.position = Vector3(0.0, 0.08, 0.0)
		add_child(col)

	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.92, 0.86, 0.72)
	paper_mat.roughness = 0.9
	paper_mat.emission_enabled = true
	paper_mat.emission = Color(0.24, 0.20, 0.12)
	paper_mat.emission_energy_multiplier = 0.65

	var sheet := MeshInstance3D.new()
	var sheet_mesh := BoxMesh.new()
	sheet_mesh.size = Vector3(0.36, 0.014, 0.46)
	sheet.mesh = sheet_mesh
	sheet.material_override = paper_mat
	sheet.position = Vector3(0.0, 0.008, 0.0)
	add_child(sheet)

	var ink_mat := StandardMaterial3D.new()
	ink_mat.albedo_color = Color(0.16, 0.11, 0.08)
	ink_mat.roughness = 0.95

	var header_strip := MeshInstance3D.new()
	var h_mesh := BoxMesh.new()
	h_mesh.size = Vector3(0.26, 0.004, 0.045)
	header_strip.mesh = h_mesh
	header_strip.material_override = ink_mat
	header_strip.position = Vector3(0.0, 0.016, -0.14)
	add_child(header_strip)

	for i in range(4):
		var line := MeshInstance3D.new()
		var l_mesh := BoxMesh.new()
		l_mesh.size = Vector3(0.27 if i != 3 else 0.18, 0.003, 0.022)
		line.mesh = l_mesh
		line.material_override = ink_mat
		line.position = Vector3(-0.02 if i == 3 else 0.0, 0.016, -0.05 + float(i) * 0.062)
		add_child(line)


func get_interact_prompt() -> String:
	return "[E] Read Escape Note"


func interact() -> void:
	var root := get_tree().current_scene
	if root and root.has_method("open_escape_note"):
		root.open_escape_note()
