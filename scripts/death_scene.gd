extends Control


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.set_chase_intensity(0.0)
		am.play_sfx("death_sting", -2.0, 1.0)


func _on_main_menu_pressed():
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0)
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
