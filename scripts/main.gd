extends Node3D

const MAX_DAYS: int = 5

@onready var pausemenu = $pausemenu
@onready var player_node: Node3D = get_node_or_null("useless/player") as Node3D
@onready var enemy_node: Node3D = get_node_or_null("house02/NavigationRegion3D/robert_clown") as Node3D

var pause: bool = false
var current_day: int = 1
var transitioning_day: bool = false
var player_spawn_transform: Transform3D
var enemy_spawn_transform: Transform3D

# Granny HUD & Horror Overlay
var hud_layer: CanvasLayer = null
var vignette_rect: ColorRect = null
var vignette_mat: ShaderMaterial = null
var fade_rect: ColorRect = null
var day_banner_label: Label = null
var day_sub_label: Label = null
var day_hud_label: Label = null
var item_hud_label: Label = null
var stealth_hud_label: Label = null
var stamina_bar: ProgressBar = null
var blood_flash_alpha: float = 0.0


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	pause = false
	if pausemenu:
		pausemenu.hide()

	if player_node == null:
		player_node = get_tree().get_first_node_in_group("player") as Node3D
	if enemy_node == null:
		enemy_node = get_tree().get_first_node_in_group("enemy") as Node3D

	if player_node:
		player_spawn_transform = player_node.global_transform
	if enemy_node:
		enemy_spawn_transform = enemy_node.global_transform

	_enhance_horror_environment()
	_build_granny_hud()
	_show_day_intro(current_day, "Escape via the Main Door or Boat. Crouch [C] to stay silent!")


func _enhance_horror_environment() -> void:
	var world_env: WorldEnvironment = find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_env and world_env.environment:
		var env: Environment = world_env.environment
		env.fog_enabled = true
		env.fog_light_color = Color(0.05, 0.06, 0.08, 1.0)
		env.fog_light_energy = 0.65
		env.fog_density = 0.042
		env.ambient_light_energy = 0.35


func _build_granny_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)

	var horror_font: Font = load("res://assets/FONTS/HelpMe.ttf") as Font
	var ui_font: Font = load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font

	# Radial danger / heartbeat vignette
	vignette_rect = ColorRect.new()
	vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 1.4142;
	float edge = smoothstep(0.32, 1.05, dist);
	float dark_vig = edge * 0.55;
	float red_vig = edge * intensity * 0.78 + flash * 0.55;
	vec3 col = mix(vec3(0.0, 0.0, 0.0), vec3(0.68, 0.02, 0.02), clamp(red_vig / max(dark_vig + red_vig, 0.001), 0.0, 1.0));
	COLOR = vec4(col, clamp(dark_vig + red_vig, 0.0, 0.92));
}
"""
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = shader
	vignette_rect.material = vignette_mat
	hud_layer.add_child(vignette_rect)

	# Top-left HUD box
	var top_box := VBoxContainer.new()
	top_box.position = Vector2(28, 22)
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(top_box)

	day_hud_label = Label.new()
	day_hud_label.text = "DAY 1 / 5"
	if horror_font:
		day_hud_label.add_theme_font_override("font", horror_font)
	day_hud_label.add_theme_font_size_override("font_size", 32)
	day_hud_label.add_theme_color_override("font_color", Color(0.88, 0.16, 0.16))
	top_box.add_child(day_hud_label)

	stealth_hud_label = Label.new()
	stealth_hud_label.text = ""
	if ui_font:
		stealth_hud_label.add_theme_font_override("font", ui_font)
	stealth_hud_label.add_theme_font_size_override("font_size", 22)
	stealth_hud_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	top_box.add_child(stealth_hud_label)

	item_hud_label = Label.new()
	item_hud_label.text = "Hands: Empty"
	if ui_font:
		item_hud_label.add_theme_font_override("font", ui_font)
	item_hud_label.add_theme_font_size_override("font_size", 22)
	item_hud_label.add_theme_color_override("font_color", Color(0.95, 0.84, 0.45))
	top_box.add_child(item_hud_label)

	var controls_hint := Label.new()
	controls_hint.text = "[WASD] Move  [Shift] Sprint  [C] Crouch/Hide  [F/G] Pick/Drop  [E] Interact  [T/RMB] Light"
	controls_hint.add_theme_font_size_override("font_size", 14)
	controls_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 0.72))
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_hint.offset_left = -740
	controls_hint.offset_top = 20
	controls_hint.offset_right = -24
	controls_hint.offset_bottom = 48
	controls_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(controls_hint)

	# Bottom-center Stamina Bar
	stamina_bar = ProgressBar.new()
	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0
	stamina_bar.show_percentage = false
	stamina_bar.custom_minimum_size = Vector2(260, 10)
	stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	stamina_bar.offset_left = -130
	stamina_bar.offset_right = 130
	stamina_bar.offset_top = -34
	stamina_bar.offset_bottom = -24
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(stamina_bar)

	# Black fade curtain + Day Title Banner
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(fade_rect)

	var banner_box := VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.offset_left = -360
	banner_box.offset_right = 360
	banner_box.offset_top = -110
	banner_box.offset_bottom = 110
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.add_child(banner_box)

	day_banner_label = Label.new()
	day_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if horror_font:
		day_banner_label.add_theme_font_override("font", horror_font)
	day_banner_label.add_theme_font_size_override("font_size", 96)
	day_banner_label.add_theme_color_override("font_color", Color(0.82, 0.1, 0.1))
	banner_box.add_child(day_banner_label)

	day_sub_label = Label.new()
	day_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ui_font:
		day_sub_label.add_theme_font_override("font", ui_font)
	day_sub_label.add_theme_font_size_override("font_size", 28)
	day_sub_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	banner_box.add_child(day_sub_label)


func trigger_blood_flash(strength: float = 0.8) -> void:
	blood_flash_alpha = maxf(blood_flash_alpha, strength)


func _show_day_intro(day_num: int, subtitle: String) -> void:
	if fade_rect == null:
		return
	day_hud_label.text = "DAY %d / %d" % [day_num, MAX_DAYS]
	day_banner_label.text = "DAY %d" % day_num
	if day_num == MAX_DAYS:
		day_banner_label.text = "LAST DAY"
	day_sub_label.text = subtitle
	fade_rect.visible = true
	fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.35)
	tw.tween_property(fade_rect, "modulate:a", 0.0, 1.1)
	tw.finished.connect(func():
		if is_instance_valid(fade_rect):
			fade_rect.visible = false
	)


func _process(delta: float) -> void:
	if vignette_mat:
		var chase_val: float = 0.0
		if has_node("/root/AudioManager"):
			chase_val = float(get_node("/root/AudioManager").chase_intensity)
		var pulse: float = 0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.008 * (1.0 + chase_val * 1.8))
		vignette_mat.set_shader_parameter("intensity", chase_val * pulse)
		blood_flash_alpha = maxf(blood_flash_alpha - delta * 1.8, 0.0)
		vignette_mat.set_shader_parameter("flash", blood_flash_alpha)

	if player_node and is_instance_valid(player_node):
		if item_hud_label and player_node.has_method("get_held_item_label"):
			item_hud_label.text = player_node.get_held_item_label()
		if stealth_hud_label and player_node.has_method("get_stealth_status"):
			stealth_hud_label.text = player_node.get_stealth_status()
		if stamina_bar and player_node.has_method("get_stamina_ratio"):
			var ratio: float = float(player_node.get_stamina_ratio())
			stamina_bar.value = ratio * 100.0
			stamina_bar.visible = ratio < 0.99


func pmenu() -> void:
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


func _on_robert_clown_kill(death) -> void:
	if death != true or transitioning_day:
		return
	transitioning_day = true
	trigger_blood_flash(1.0)

	if current_day >= MAX_DAYS:
		if fade_rect:
			fade_rect.visible = true
			fade_rect.modulate.a = 0.0
			var tw_end := create_tween()
			tw_end.tween_property(fade_rect, "modulate:a", 1.0, 0.65)
			await tw_end.finished
		get_tree().paused = false
		Engine.time_scale = 1.0
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file("res://scenes/death_scene/death_scene.tscn")
		return

	# Granny-style Day Advance: fade out, reset positions, keep house progress!
	current_day += 1
	if fade_rect:
		day_banner_label.text = "KNOCKED OUT..."
		day_sub_label.text = ""
		fade_rect.visible = true
		fade_rect.modulate.a = 0.0
		var tw_out := create_tween()
		tw_out.tween_property(fade_rect, "modulate:a", 1.0, 0.7)
		await tw_out.finished

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").set_chase_intensity(0.0)

	if player_node and is_instance_valid(player_node):
		player_node.global_transform = player_spawn_transform
		if player_node.has_method("reset_for_new_day"):
			player_node.reset_for_new_day()

	if enemy_node and is_instance_valid(enemy_node):
		enemy_node.global_transform = enemy_spawn_transform
		if enemy_node.has_method("reset_for_new_day"):
			enemy_node.reset_for_new_day(current_day)

	transitioning_day = false
	var sub: String = "Be careful! Only %d days left." % (MAX_DAYS - current_day + 1)
	if current_day == MAX_DAYS:
		sub = "FINAL DAY! Escape now or never wake up..."
	_show_day_intro(current_day, sub)
