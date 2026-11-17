extends StaticBody3D
var opened = false

@onready var door = $".."

var keyreq = true
var keyname = "gf_base_door_key"
var beatreq = false
var pinreq = false


func _process(delta):
	if opened:
		door.rotation.y = lerp_angle(door.rotation.y, deg_to_rad(-90.0), delta * 2)


func interact():
	if not opened:
		opened = true
		keyreq = false
		collision_layer = 1
