extends StaticBody3D

var opened = false
var yes = true
signal monster_done(is_done: bool)
var keyreq = true
var keyname = "monster_key"
var beatreq = false
var pinreq = false
@onready var col: CollisionShape3D = $CollisionShape3D


func interact():
	if not opened:
		opened = true
		if col:
			col.disabled = true
		collision_layer = 1
		monster_done.emit(true)
