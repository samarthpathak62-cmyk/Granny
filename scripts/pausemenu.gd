extends Control

@onready var house = $".."


func _process(_delta):
	if Input.is_action_just_pressed("pause"):
		if house and house.has_method("pmenu"):
			house.pmenu()


func _on_resume_pressed():
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0)
	if house and house.has_method("pmenu"):
		house.pmenu()


func _on_main_menu_pressed():
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.play_sfx("ui_click", -3.0)
		am.set_chase_intensity(0.0)
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
