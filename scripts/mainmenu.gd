extends Control

var mainhouse = preload("res://scenes/Main House/house.tscn")

@onready var menu = $menu
@onready var options = $options
@onready var audio = $Audio
@onready var graphics = $graphics
@onready var fullscreen_check: CheckBox = $graphics/HBoxContainer/Checks/FullScreen
@onready var vsync_check: CheckBox = $graphics/HBoxContainer/Checks/VSync
@onready var master_slider: HSlider = $Audio/HBoxContainer/slider/master
@onready var music_slider: HSlider = $Audio/HBoxContainer/slider/music
@onready var sfx_slider: HSlider = $"Audio/HBoxContainer/slider/sound fx"


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.set_chase_intensity(0.0)
		am.start_ambience(-10.0)

	menu.visible = true
	options.visible = false
	audio.visible = false
	graphics.visible = false

	if fullscreen_check:
		fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if vsync_check:
		vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED

	_sync_slider(0, master_slider)
	_sync_slider(1, music_slider)
	_sync_slider(2, sfx_slider)


func _sync_slider(bus_index: int, slider: HSlider) -> void:
	if slider == null or bus_index >= AudioServer.bus_count:
		return
	if AudioServer.is_bus_mute(bus_index):
		slider.set_value_no_signal(0.0)
	else:
		var lin := db_to_linear(AudioServer.get_bus_volume_db(bus_index))
		slider.set_value_no_signal(clampf(lin, 0.0, 1.0))


func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		if graphics.visible:
			showandhide(options, graphics)
		elif audio.visible:
			showandhide(options, audio)
		elif options.visible:
			showandhide(menu, options)


func _play_click() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0)


func _on_new_game_pressed():
	_play_click()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_packed(mainhouse)


func _on_options_pressed():
	_play_click()
	showandhide(options, menu)


func _on_exit_pressed():
	_play_click()
	get_tree().quit()


func _on_graphics_pressed():
	_play_click()
	showandhide(graphics, options)


func _on_audio_pressed():
	_play_click()
	showandhide(audio, options)


func _on_full_screen_toggled(button_pressed):
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_v_sync_toggled(button_pressed):
	if button_pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func showandhide(first, second):
	first.visible = true
	second.visible = false


func _on_master_value_changed(value):
	volume(0, value)


func volume(bus_index: int, value: float):
	if bus_index >= AudioServer.bus_count:
		return
	if value <= 0.001:
		AudioServer.set_bus_mute(bus_index, true)
	else:
		AudioServer.set_bus_mute(bus_index, false)
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))


func _on_music_value_changed(value):
	volume(1, value)


func _on_sound_fx_value_changed(value):
	volume(2, value)


func _on_backfrom_audio_pressed():
	_play_click()
	showandhide(options, audio)


func _on_backfrom_graphics_pressed():
	_play_click()
	showandhide(options, graphics)


func _on_backfrom_options_pressed():
	_play_click()
	showandhide(menu, options)


func _on_load_game_pressed():
	_play_click()
	get_tree().change_scene_to_file("res://scenes/load_game_menu.tscn")
