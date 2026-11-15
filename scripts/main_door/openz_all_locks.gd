extends StaticBody3D

var keyreq = false
var beatreq = false
var pinreq = false

signal all_done(is_done: bool)
var yes = true


func interact():
	all_done.emit(yes)
