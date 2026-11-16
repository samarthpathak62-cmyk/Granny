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
var dark_mode_enabled: bool = false
var diff_name: String = "NORMAL"
var diff_color: Color = Color(0.95, 0.85, 0.42)

# PSX Retro Shader
var psx_layer: CanvasLayer = null
var psx_rect: ColorRect = null
var psx_mat: ShaderMaterial = null
var psx_enabled: bool = true

# Granny HUD & Horror Overlay
var hud_layer: CanvasLayer = null
var vignette_rect: ColorRect = null
var vignette_mat: ShaderMaterial = null
var fade_rect: ColorRect = null
var day_banner_label: Label = null
var day_sub_label: Label = null
var day_hud_label: Label = null
var mode_hud_label: Label = null
var item_hud_label: Label = null
var stealth_hud_label: Label = null
var stamina_bar: ProgressBar = null
var blood_flash_alpha: float = 0.0

# Escape Note UI & physical table placement
const EscapeNoteScript = preload("res://scripts/escape_note.gd")
const EscapeNoteUIScript = preload("res://scripts/escape_note_ui.gd")
var note_layer: CanvasLayer = null
var note_open: bool = false
var note_cooldown: float = 0.0


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	pause = false
	if pausemenu:
		pausemenu.hide()

	if has_node("/root/GameSettings"):
		var gs = get_node("/root/GameSettings")
		dark_mode_enabled = bool(gs.dark_mode)
		diff_name = str(gs.get_difficulty_name())
		diff_color = gs.get_difficulty_color()

	if player_node == null:
		player_node = get_tree().get_first_node_in_group("player") as Node3D
	if enemy_node == null:
		enemy_node = get_tree().get_first_node_in_group("enemy") as Node3D

	if player_node:
		player_spawn_transform = player_node.global_transform
		if player_node.has_method("play_wakeup_animation"):
			player_node.play_wakeup_animation()
	if enemy_node:
		enemy_spawn_transform = enemy_node.global_transform

	_apply_lighting_mode()
	_build_psx_postprocess()
	_build_granny_hud()
	_build_escape_note_ui()
	call_deferred("_spawn_escape_notes_on_tables")
	_show_day_intro(current_day, "%s MODE%s — Check tables for the Escape Note!" % [
		diff_name,
		" (DARK)" if dark_mode_enabled else ""
	])


func _apply_lighting_mode() -> void:
	var world_env: WorldEnvironment = find_child("WorldEnvironment", true, false) as WorldEnvironment
	var env: Environment = null
	if world_env:
		if world_env.environment == null:
			world_env.environment = Environment.new()
		env = world_env.environment

	if dark_mode_enabled:
		if env:
			env.fog_enabled = true
			env.fog_light_color = Color(0.03, 0.04, 0.06, 1.0)
			env.fog_light_energy = 0.55
			env.fog_density = 0.055
			env.background_energy_multiplier = 0.08
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.18, 0.20, 0.24, 1.0)
			env.ambient_light_energy = 0.16
	else:
		# Classic Granny Normal Visibility: everything inside the house clearly visible without darkness
		if env:
			env.fog_enabled = false
			env.background_energy_multiplier = 1.0
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.84, 0.82, 0.78, 1.0)
			env.ambient_light_energy = 1.25

		if get_node_or_null("NormalModeFillLight") == null:
			var fill := DirectionalLight3D.new()
			fill.name = "NormalModeFillLight"
			fill.light_color = Color(1.0, 0.96, 0.90)
			fill.light_energy = 0.45
			fill.shadow_enabled = false
			fill.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
			add_child(fill)


func _build_psx_postprocess() -> void:
	psx_layer = CanvasLayer.new()
	psx_layer.layer = 1
	add_child(psx_layer)

	psx_rect = ColorRect.new()
	psx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	psx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var psx_shader := Shader.new()
	psx_shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 target_resolution = vec2(640.0, 360.0);
uniform float color_levels = 48.0;
uniform float dither_strength = 0.35;
uniform float scanline_strength = 0.03;
uniform float chroma_base = 0.0002;
uniform float terror_chroma = 0.0;
uniform float dark_vignette = 0.0;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	);
	return (m[idx] / 16.0) - 0.5;
}

void fragment() {
	vec2 pixel_pos = floor(SCREEN_UV * target_resolution);
	vec2 snapped_uv = (pixel_pos + 0.5) / target_resolution;

	float chroma_off = (chroma_base + terror_chroma * (chroma_base * 6.0 + 0.0022)) * length(SCREEN_UV - 0.5);
	float r = texture(screen_texture, snapped_uv + vec2(chroma_off, 0.0)).r;
	float g = texture(screen_texture, snapped_uv).g;
	float b = texture(screen_texture, snapped_uv - vec2(chroma_off, 0.0)).b;
	vec3 col = vec3(r, g, b);

	// 4x4 Bayer ordered dithering + 15-bit PS1 color quantization
	float dither = bayer4(pixel_pos) * (dither_strength / color_levels);
	col = floor((col + dither) * color_levels + 0.5) / color_levels;
	col = clamp(col, vec3(0.0), vec3(1.0));

	// Subtle CRT scanlines
	float scan = 1.0 - scanline_strength * (0.5 + 0.5 * sin(pixel_pos.y * 3.14159265));
	col *= scan;

	// Extra PSX horror edge crush in Dark Mode
	if (dark_vignette > 0.001) {
		float edge = smoothstep(0.35, 1.05, length(SCREEN_UV - 0.5) * 1.4142);
		col *= (1.0 - edge * dark_vignette);
	}

	COLOR = vec4(col, 1.0);
}
"""
	psx_mat = ShaderMaterial.new()
	psx_mat.shader = psx_shader
	if dark_mode_enabled:
		# EXTREME gritty PSX horror shader in Dark Mode
		psx_mat.set_shader_parameter("target_resolution", Vector2(340.0, 192.0))
		psx_mat.set_shader_parameter("color_levels", 18.0)
		psx_mat.set_shader_parameter("dither_strength", 1.25)
		psx_mat.set_shader_parameter("scanline_strength", 0.16)
		psx_mat.set_shader_parameter("chroma_base", 0.0014)
		psx_mat.set_shader_parameter("dark_vignette", 0.28)
	else:
		# Normal clean PSX shader when Dark Mode is OFF
		psx_mat.set_shader_parameter("target_resolution", Vector2(640.0, 360.0))
		psx_mat.set_shader_parameter("color_levels", 48.0)
		psx_mat.set_shader_parameter("dither_strength", 0.35)
		psx_mat.set_shader_parameter("scanline_strength", 0.03)
		psx_mat.set_shader_parameter("chroma_base", 0.0002)
		psx_mat.set_shader_parameter("dark_vignette", 0.0)

	psx_rect.material = psx_mat
	psx_rect.visible = psx_enabled
	psx_layer.add_child(psx_rect)


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
uniform float base_dark : hint_range(0.0, 1.0) = 0.55;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 1.4142;
	float edge = smoothstep(0.32, 1.05, dist);
	float dark_vig = edge * base_dark;
	float red_vig = edge * intensity * 0.78 + flash * 0.55;
	vec3 col = mix(vec3(0.0, 0.0, 0.0), vec3(0.68, 0.02, 0.02), clamp(red_vig / max(dark_vig + red_vig, 0.001), 0.0, 1.0));
	COLOR = vec4(col, clamp(dark_vig + red_vig, 0.0, 0.92));
}
"""
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = shader
	vignette_mat.set_shader_parameter("base_dark", 0.62 if dark_mode_enabled else 0.14)
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

	mode_hud_label = Label.new()
	mode_hud_label.text = "%s%s" % [diff_name, " • DARK MODE" if dark_mode_enabled else ""]
	if ui_font:
		mode_hud_label.add_theme_font_override("font", ui_font)
	mode_hud_label.add_theme_font_size_override("font_size", 19)
	mode_hud_label.add_theme_color_override("font_color", diff_color)
	top_box.add_child(mode_hud_label)

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
	if dark_mode_enabled:
		controls_hint.text = "[WASD] Move  [Shift] Sprint  [C] Crouch/Hide  [F/G] Pick/Drop  [E] Interact  [Tab] Note  [T/RMB] Torch  [F3] PSX"
	else:
		controls_hint.text = "[WASD] Move  [Shift] Sprint  [C] Crouch/Hide  [F/G] Pick/Drop  [E] Interact  [Tab] Note  [F3] PSX"
	controls_hint.add_theme_font_size_override("font_size", 14)
	controls_hint.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 0.78))
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_hint.offset_left = -880
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
	banner_box.offset_left = -380
	banner_box.offset_right = 380
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			psx_enabled = !psx_enabled
			if psx_rect:
				psx_rect.visible = psx_enabled
			if player_node and player_node.has_method("_show_hint"):
				player_node._show_hint("PSX Shader: " + ("ON" if psx_enabled else "OFF"), 1.5)
		elif event.keycode == KEY_TAB and not pause and not transitioning_day and note_cooldown <= 0.0:
			get_viewport().set_input_as_handled()
			if note_open:
				close_escape_note()
			else:
				open_escape_note()


func _spawn_escape_notes_on_tables() -> void:
	await get_tree().physics_frame
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return

	# Place the physical Escape Note on both the Basement Table (near starting area)
	# and the Ground Floor Dining Table (near Boat Gear) using exact downward raycasts.
	var candidates: Array = [
		{"from": Vector3(-18.04, 5.7, -19.52), "to": Vector3(-18.04, 4.1, -19.52), "yaw": 14.0},
		{"from": Vector3(-18.65, 9.0, -5.00), "to": Vector3(-18.65, 7.2, -5.00), "yaw": -18.0},
	]
	for cfg in candidates:
		var query := PhysicsRayQueryParameters3D.create(cfg["from"], cfg["to"], 1)
		query.collide_with_bodies = true
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			var note := StaticBody3D.new()
			note.name = "EscapeNote"
			note.set_script(EscapeNoteScript)
			add_child(note)
			note.global_position = hit["position"] + Vector3(0.0, 0.004, 0.0)
			note.rotation_degrees.y = float(cfg["yaw"])


func _build_escape_note_ui() -> void:
	note_layer = CanvasLayer.new()
	note_layer.name = "EscapeNoteLayer"
	note_layer.layer = 12
	note_layer.visible = false
	note_layer.set_script(EscapeNoteUIScript)
	note_layer.set("main_node", self)
	add_child(note_layer)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.02, 0.02, 0.72)
	note_layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	note_layer.add_child(center)

	var paper := PanelContainer.new()
	paper.custom_minimum_size = Vector2(740, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.90, 0.84, 0.69, 0.98)
	style.border_color = Color(0.32, 0.21, 0.12, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(28)
	paper.add_theme_stylebox_override("panel", style)
	center.add_child(paper)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	paper.add_child(vb)

	var horror_font: Font = load("res://assets/FONTS/HelpMe.ttf") as Font
	var ui_font: Font = load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font

	var title := Label.new()
	title.text = "SURVIVOR'S ESCAPE NOTE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if horror_font:
		title.add_theme_font_override("font", horror_font)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.42, 0.07, 0.06))
	vb.add_child(title)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(680, 0)
	if ui_font:
		body.add_theme_font_override("normal_font", ui_font)
		body.add_theme_font_override("bold_font", ui_font)
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_font_size_override("bold_font_size", 22)
	body.add_theme_color_override("default_color", Color(0.14, 0.09, 0.06))
	body.text = (
		"Robert The Clown locked you inside his house. You have [b]5 DAYS[/b] to escape.\n\n"
		+ "[color=#6b1210][b]ROUTE 1 — MAIN FRONT DOOR (Ground Floor)[/b][/color]\n"
		+ "  1. Pick up the [b]Lockpin[/b] in your starting cell to unlock the cell door.\n"
		+ "  2. Smash the wooden plank on the Main Door with the [b]Hammer[/b].\n"
		+ "  3. Find the [b]Master Key[/b] upstairs to unlock the Main Door padlock.\n"
		+ "  4. Open the Main Door to escape! (Use [b]Basement Key[/b] for locked basement doors.)\n\n"
		+ "[color=#12425c][b]ROUTE 2 — SWAMP BOAT (Sewer Dock)[/b][/color]\n"
		+ "  1. Unlock the sewer iron gate using the [b]Grid Gate Key[/b].\n"
		+ "  2. Find the [b]Boat Gear[/b] on the Ground Floor dining table.\n"
		+ "  3. Aim at the Boat at the sewer dock and press [b][E][/b] to install the Boat Gear.\n"
		+ "  4. Press [b][E][/b] again on the Boat to pull the [b]Boat Lever[/b] and escape!\n\n"
		+ "[color=#3a2614][b]SURVIVAL TIPS[/b][/color]\n"
		+ "  • Hold [b][C][/b] to crouch quietly, or hide inside [b]Wardrobes[/b].\n"
		+ "  • Avoid [b]Bear Traps[/b] on the floor (mash [b][E][/b] if caught)."
	)
	vb.add_child(body)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)

	var close_btn := Button.new()
	close_btn.text = "  [E / TAB / ESC]  CLOSE NOTE  "
	close_btn.custom_minimum_size = Vector2(280, 44)
	if ui_font:
		close_btn.add_theme_font_override("font", ui_font)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(close_escape_note)
	btn_row.add_child(close_btn)


func open_escape_note() -> void:
	if note_layer == null or note_open or pause or transitioning_day or note_cooldown > 0.0:
		return
	note_open = true
	note_layer.visible = true
	if note_layer.has_method("mark_opened"):
		note_layer.mark_opened()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0, 0.95)


func close_escape_note() -> void:
	if note_layer == null or not note_open:
		return
	note_open = false
	note_cooldown = 0.20
	note_layer.visible = false
	get_tree().paused = false
	if DisplayServer.is_touchscreen_available():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -4.0, 1.05)


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
	if note_cooldown > 0.0:
		note_cooldown = maxf(note_cooldown - delta, 0.0)
	var chase_val: float = 0.0
	if has_node("/root/AudioManager"):
		chase_val = float(get_node("/root/AudioManager").chase_intensity)

	if psx_mat and psx_enabled:
		psx_mat.set_shader_parameter("terror_chroma", chase_val)

	if vignette_mat:
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
	if note_open:
		close_escape_note()
		return
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
