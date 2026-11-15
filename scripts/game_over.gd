extends Control


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_main_menu_pressed():
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
