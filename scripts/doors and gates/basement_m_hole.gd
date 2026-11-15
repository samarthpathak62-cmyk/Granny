extends StaticBody3D
@onready var col: CollisionShape3D = $CollisionShape3D
var keyreq = false
var opened = false
var beatreq = true
var beatname = "hammer"
var pinreq = false
var initial_col_pos: Vector3 = Vector3.ZERO


func _ready():
	if col:
		initial_col_pos = col.position


func _process(delta):
	if opened and col:
		var target_pos = initial_col_pos + Vector3(0.65, -0.615, 0.423)
		col.position.y = lerp(col.position.y, target_pos.y, delta * 6)
		col.position.x = lerp(col.position.x, target_pos.x, delta * 8)
		col.position.z = lerp(col.position.z, target_pos.z, delta * 4)
		col.rotation.x = lerp_angle(col.rotation.x, deg_to_rad(90), delta * 10)


func interact():
	if not opened:
		opened = true
		if col:
			col.disabled = true
		collision_layer = 1
