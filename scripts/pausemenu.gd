extends Control

@onready var house = $".."


func _process(_delta):
	if Input.is_action_just_pressed("pause"):
		if house and house.has_method("pmenu"):
			house.pmenu()


func _on_resume_pressed():
	if house and house.has_method("pmenu"):
		house.pmenu()


func _on_main_menu_pressed():
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
