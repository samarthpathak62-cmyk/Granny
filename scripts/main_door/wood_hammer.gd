extends StaticBody3D

var keyreq = false
var opened = false
var beatreq = true
var beatname = "hammer"
var pinreq = false
signal beaten(is_done: bool)
var yes = true
@onready var col: CollisionShape3D = $CollisionShape3D


func _process(_delta):
	if opened:
		hide()


func interact():
	if not opened:
		opened = true
		if col:
			col.disabled = true
		collision_layer = 1
		beaten.emit(yes)
