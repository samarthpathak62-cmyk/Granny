extends Control


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		_on_back_pressed()


func _on_save_01_pressed():
	get_tree().change_scene_to_file("res://scenes/Main House/house-2.tscn")


func _on_save_02_pressed():
	get_tree().change_scene_to_file("res://scenes/Main House/house.tscn")


func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
