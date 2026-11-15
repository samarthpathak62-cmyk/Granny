extends Node3D

@onready var pausemenu = $pausemenu
var pause = false


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	pause = false
	if pausemenu:
		pausemenu.hide()


func pmenu():
	pause = !pause
	if pause:
		pausemenu.show()
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		pausemenu.hide()
		get_tree().paused = false
		if DisplayServer.is_touchscreen_available():
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_robert_clown_kill(death):
	if death == true:
		get_tree().paused = false
		Engine.time_scale = 1.0
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file("res://scenes/death_scene/death_scene.tscn")
