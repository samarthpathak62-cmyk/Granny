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

var title_header: Control = null
var title_lbl: Label = null
var mode_panel: PanelContainer = null
var diff_buttons: Array[Button] = []
var dark_mode_btn: Button = null
var mode_desc_label: Label = null
var dark_desc_label: Label = null
var submenu_scrim: ColorRect = null
var scrim_rect_material: ShaderMaterial = null

# Granny-style live 3D horror menu diorama state
var menu_camera: Camera3D = null
var menu_clown: Node3D = null
var menu_skeleton: Skeleton3D = null
var head_bone_idx: int = -1
var spine_bone_idx: int = -1
var head_base_rot: Quaternion = Quaternion.IDENTITY
var spine_base_rot: Quaternion = Quaternion.IDENTITY
var key_spot: SpotLight3D = null
var rim_omni: OmniLight3D = null
var flicker_timer: float = 0.0
var head_twitch_timer: float = 2.4
var head_twitch_target: float = 0.0
var head_twitch_curr: float = 0.0
var menu_time: float = 0.0
var cam_base_pos: Vector3 = Vector3(-0.22, 1.46, 0.95)


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.set_chase_intensity(0.0)
		am.start_menu_music(-10.0)

	menu.visible = true
	options.visible = false
	audio.visible = false
	graphics.visible = false

	_build_granny_3d_backdrop()
	_build_granny_overlay_and_header()
	_style_main_menu_buttons()
	_style_submenus()
	_build_mode_selector_ui()
	_connect_button_hover_sfx(self)
	_apply_dark_mode_to_ui(_get_dark_mode())

	if fullscreen_check:
		fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if vsync_check:
		vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED

	_sync_slider(0, master_slider)
	_sync_slider(1, music_slider)
	_sync_slider(2, sfx_slider)


func _load_texture_safe(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is Texture2D:
			return res as Texture2D
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.new()
		if img.load(abs_path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _make_box_mesh(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi


func _get_dark_mode() -> bool:
	if has_node("/root/GameSettings"):
		return bool(get_node("/root/GameSettings").dark_mode)
	return false


func _build_granny_3d_backdrop() -> void:
	var is_dark: bool = _get_dark_mode()
	var vp_container := SubViewportContainer.new()
	vp_container.name = "HorrorBackdrop3D"
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_container)
	move_child(vp_container, 0)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	vp_container.add_child(vp)

	var world_root := Node3D.new()
	world_root.name = "GrannyTitleStage"
	vp.add_child(world_root)

	# Dark horror atmosphere + fog
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	if is_dark:
		# Pitch-dark game dark mode: barely visible, only lit by flickering lamp
		env.background_color = Color(0.005, 0.004, 0.006)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.05, 0.04, 0.05)
		env.ambient_light_energy = 0.14
		env.fog_enabled = true
		env.fog_light_color = Color(0.015, 0.010, 0.012)
		env.fog_light_energy = 0.35
		env.fog_density = 0.28
	else:
		env.background_color = Color(0.012, 0.010, 0.014)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.14, 0.12, 0.14)
		env.ambient_light_energy = 0.42
		env.fog_enabled = true
		env.fog_light_color = Color(0.03, 0.02, 0.025)
		env.fog_light_energy = 0.65
		env.fog_density = 0.15

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world_root.add_child(world_env)

	# Camera looking down the eerie corridor toward Robert on the right
	menu_camera = Camera3D.new()
	menu_camera.position = cam_base_pos
	menu_camera.fov = 46.0
	world_root.add_child(menu_camera)
	menu_camera.look_at(Vector3(0.30, 1.38, -2.50), Vector3.UP)

	# Weathered wood & grimy wallpaper materials from house textures
	var wood_mat := StandardMaterial3D.new()
	var wood_tex := _load_texture_safe("res://Model_static/house/WoodPlanks_01.jpg")
	if wood_tex:
		wood_mat.albedo_texture = wood_tex
		wood_mat.uv1_scale = Vector3(3.0, 4.0, 1.0)
	wood_mat.albedo_color = Color(0.32, 0.27, 0.23)
	wood_mat.roughness = 0.88

	var wall_mat := StandardMaterial3D.new()
	var wall_tex := _load_texture_safe("res://Model_static/house/house02-4167be13566ed59214ff21c0756662d0_wallpaper-flowers-ornament.png")
	if wall_tex:
		wall_mat.albedo_texture = wall_tex
		wall_mat.uv1_scale = Vector3(2.5, 1.6, 1.0)
	wall_mat.albedo_color = Color(0.28, 0.24, 0.22)
	wall_mat.roughness = 0.92

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.10, 0.08, 0.07)
	trim_mat.roughness = 0.85

	# Floor, ceiling, corridor walls, and back doorframe
	var floor_mesh := _make_box_mesh(Vector3(6.5, 0.2, 10.0), wood_mat)
	floor_mesh.position = Vector3(0.2, -0.1, -2.2)
	world_root.add_child(floor_mesh)

	var ceil_mesh := _make_box_mesh(Vector3(6.5, 0.2, 10.0), trim_mat)
	ceil_mesh.position = Vector3(0.2, 3.3, -2.2)
	world_root.add_child(ceil_mesh)

	var left_wall := _make_box_mesh(Vector3(0.2, 3.5, 10.0), wall_mat)
	left_wall.position = Vector3(-2.3, 1.65, -2.2)
	world_root.add_child(left_wall)

	var right_wall := _make_box_mesh(Vector3(0.2, 3.5, 10.0), wall_mat)
	right_wall.position = Vector3(2.5, 1.65, -2.2)
	world_root.add_child(right_wall)

	var back_wall := _make_box_mesh(Vector3(5.6, 3.5, 0.2), trim_mat)
	back_wall.position = Vector3(0.2, 1.65, -5.6)
	world_root.add_child(back_wall)

	# Doorway partition wall with open doorway on right-center behind Robert
	var div_left := _make_box_mesh(Vector3(2.5, 3.4, 0.18), wall_mat)
	div_left.position = Vector3(-1.1, 1.6, -3.5)
	world_root.add_child(div_left)

	var div_right := _make_box_mesh(Vector3(1.1, 3.4, 0.18), wall_mat)
	div_right.position = Vector3(2.0, 1.6, -3.5)
	world_root.add_child(div_right)

	var div_top := _make_box_mesh(Vector3(1.5, 1.0, 0.18), wall_mat)
	div_top.position = Vector3(0.78, 2.85, -3.5)
	world_root.add_child(div_top)

	var jamb_l := _make_box_mesh(Vector3(0.11, 2.45, 0.24), trim_mat)
	jamb_l.position = Vector3(0.12, 1.22, -3.5)
	world_root.add_child(jamb_l)

	var jamb_r := _make_box_mesh(Vector3(0.11, 2.45, 0.24), trim_mat)
	jamb_r.position = Vector3(1.45, 1.22, -3.5)
	world_root.add_child(jamb_r)

	# Cracked-open wooden door leaf behind Robert
	var door_leaf := _make_box_mesh(Vector3(1.22, 2.38, 0.08), wood_mat)
	door_leaf.position = Vector3(0.95, 1.19, -4.05)
	door_leaf.rotation_degrees = Vector3(0.0, 38.0, 0.0)
	world_root.add_child(door_leaf)

	# Real 3D Robert The Clown model (AI script stripped so only visual rig renders)
	var clown_packed: PackedScene = load("res://scenes/enemy/robert_clown.tscn") as PackedScene
	if clown_packed:
		var clown_inst := clown_packed.instantiate()
		clown_inst.set_script(null)
		var nav_ag := clown_inst.get_node_or_null("NavigationAgent3D")
		if nav_ag:
			nav_ag.queue_free()
		var col_shape := clown_inst.get_node_or_null("CollisionShape3D")
		if col_shape:
			col_shape.queue_free()
		var atree := clown_inst.get_node_or_null("AnimationTree") as AnimationTree
		if atree:
			atree.active = false

		if clown_inst is Node3D:
			menu_clown = clown_inst as Node3D
			world_root.add_child(menu_clown)
			menu_clown.position = Vector3(0.72, 0.0, -2.55)
			menu_clown.look_at(Vector3(cam_base_pos.x + 0.15, 0.0, cam_base_pos.z), Vector3.UP)

			menu_skeleton = menu_clown.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
			if menu_skeleton:
				head_bone_idx = menu_skeleton.find_bone("mixamorig_Head")
				spine_bone_idx = menu_skeleton.find_bone("mixamorig_Spine2")
				if head_bone_idx >= 0:
					head_base_rot = menu_skeleton.get_bone_pose_rotation(head_bone_idx)
				if spine_bone_idx >= 0:
					spine_base_rot = menu_skeleton.get_bone_pose_rotation(spine_bone_idx)

	# Flickering cold tungsten overhead spotlight illuminating Robert's face & suit
	key_spot = SpotLight3D.new()
	key_spot.position = Vector3(0.35, 2.85, -1.10)
	key_spot.light_color = Color(0.92, 0.88, 0.78)
	key_spot.light_energy = 7.5
	key_spot.spot_range = 9.5
	key_spot.spot_angle = 36.0
	key_spot.spot_attenuation = 1.2
	key_spot.shadow_enabled = true
	world_root.add_child(key_spot)
	key_spot.look_at(Vector3(0.72, 1.42, -2.55), Vector3.UP)

	# Eerie blood-red horror backlight from behind the cracked doorway
	rim_omni = OmniLight3D.new()
	rim_omni.position = Vector3(0.85, 1.75, -3.95)
	rim_omni.light_color = Color(0.92, 0.08, 0.08)
	rim_omni.light_energy = 4.2
	rim_omni.omni_range = 5.5
	world_root.add_child(rim_omni)

	# Soft cold moonlight rim from front-left so metallic tuxedo still catches silhouette
	var cold_fill := OmniLight3D.new()
	cold_fill.position = Vector3(-0.75, 1.65, -0.85)
	cold_fill.light_color = Color(0.32, 0.40, 0.56)
	cold_fill.light_energy = 1.25
	cold_fill.omni_range = 6.5
	world_root.add_child(cold_fill)

	# Drifting dust / ash motes in the corridor light
	var dust := CPUParticles3D.new()
	dust.position = Vector3(0.45, 1.45, -1.8)
	dust.amount = 36
	dust.lifetime = 5.5
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.8, 1.3, 2.2)
	dust.gravity = Vector3(0.0, 0.015, 0.0)
	dust.initial_velocity_min = 0.04
	dust.initial_velocity_max = 0.14
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.014
	pmesh.height = 0.028
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.75, 0.72, 0.68, 0.35)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmesh.material = pmat
	dust.mesh = pmesh
	world_root.add_child(dust)


func _build_granny_overlay_and_header() -> void:
	# Left-to-right horror gradient + vignette shader overlay so text pops over the 3D scene
	var scrim_rect := ColorRect.new()
	scrim_rect.name = "GrannyHorrorScrim"
	scrim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim_shader := Shader.new()
	scrim_shader.code = """
shader_type canvas_item;
void fragment() {
	float left_fade = 1.0 - smoothstep(0.18, 0.68, UV.x);
	float vig = smoothstep(0.35, 1.15, length(UV - vec2(0.5)) * 1.4142);
	float scan = 0.035 * (0.5 + 0.5 * sin(UV.y * 720.0));
	float alpha = clamp(left_fade * 0.84 + vig * 0.58 + scan, 0.0, 0.94);
	vec3 col = mix(vec3(0.015, 0.012, 0.016), vec3(0.06, 0.0, 0.0), vig * 0.25);
	COLOR = vec4(col, alpha);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = scrim_shader
	scrim_rect.material = smat
	scrim_rect_material = smat
	add_child(scrim_rect)
	move_child(scrim_rect, 1)

	# Submenu dark backdrop shown only when Options / Graphics / Audio is open
	submenu_scrim = ColorRect.new()
	submenu_scrim.name = "SubmenuScrim"
	submenu_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	submenu_scrim.color = Color(0.02, 0.015, 0.02, 0.82)
	submenu_scrim.visible = false
	submenu_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(submenu_scrim)
	move_child(submenu_scrim, 2)

	var horror_font: Font = load("res://assets/FONTS/HelpMe.ttf") as Font
	var ui_font: Font = load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font

	# Top-left Granny-style Title + Clown Logo Emblem
	title_header = Control.new()
	title_header.name = "TitleHeader"
	title_header.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title_header.offset_left = 56.0
	title_header.offset_top = 44.0
	title_header.offset_right = 920.0
	title_header.offset_bottom = 200.0
	title_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 22)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_header.add_child(hbox)

	var logo_frame := PanelContainer.new()
	logo_frame.custom_minimum_size = Vector2(118, 118)
	var lstyle := StyleBoxFlat.new()
	lstyle.bg_color = Color(0.03, 0.02, 0.02, 1.0)
	lstyle.border_color = Color(0.72, 0.12, 0.12, 0.95)
	lstyle.set_border_width_all(3)
	lstyle.set_corner_radius_all(6)
	lstyle.set_content_margin_all(4)
	lstyle.shadow_color = Color(0.45, 0.0, 0.0, 0.65)
	lstyle.shadow_size = 10
	logo_frame.add_theme_stylebox_override("panel", lstyle)
	logo_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(logo_frame)

	var logo_rect := TextureRect.new()
	logo_rect.custom_minimum_size = Vector2(110, 110)
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	logo_rect.texture = _load_texture_safe("res://assets/clown_logo.png")
	logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_frame.add_child(logo_rect)

	var title_stack := VBoxContainer.new()
	title_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	title_stack.add_theme_constant_override("separation", 2)
	title_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(title_stack)

	title_lbl = Label.new()
	title_lbl.text = "ROBERT THE CLOWN"
	if horror_font:
		title_lbl.add_theme_font_override("font", horror_font)
	title_lbl.add_theme_font_size_override("font_size", 68)
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.11, 0.11))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	title_lbl.add_theme_constant_override("shadow_offset_x", 4)
	title_lbl.add_theme_constant_override("shadow_offset_y", 5)
	title_stack.add_child(title_lbl)

	var tagline := Label.new()
	tagline.text = "5 DAYS TO ESCAPE THE HOUSE  •  DON'T MAKE A SOUND"
	if ui_font:
		tagline.add_theme_font_override("font", ui_font)
	tagline.add_theme_font_size_override("font_size", 22)
	tagline.add_theme_color_override("font_color", Color(0.76, 0.72, 0.66))
	tagline.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	tagline.add_theme_constant_override("shadow_offset_x", 2)
	tagline.add_theme_constant_override("shadow_offset_y", 2)
	title_stack.add_child(tagline)


func _make_granny_button_style(bg: Color, border: Color, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_w + 3
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 24
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _apply_dark_mode_to_ui(is_dark: bool) -> void:
	# Granny dark mode: UI panel, scrim and buttons go pitch dark like the in-game dark mode
	if scrim_rect_material:
		var mat := scrim_rect_material as ShaderMaterial
		var scrim_shader := Shader.new()
		if is_dark:
			# Pitch-dark scrim: crush everything to near-black with a faint blood-red edge
			scrim_shader.code = """
shader_type canvas_item;
void fragment() {
	float left_fade = 1.0 - smoothstep(0.10, 0.75, UV.x);
	float vig = smoothstep(0.28, 1.05, length(UV - vec2(0.5)) * 1.4142);
	float scan = 0.03 * (0.5 + 0.5 * sin(UV.y * 720.0));
	float alpha = clamp(left_fade * 0.94 + vig * 0.80 + scan, 0.0, 0.98);
	vec3 col = mix(vec3(0.010, 0.008, 0.011), vec3(0.03, 0.0, 0.0), vig * 0.3);
	COLOR = vec4(col, alpha);
}
			"""
		else:
			scrim_shader.code = """
shader_type canvas_item;
void fragment() {
	float left_fade = 1.0 - smoothstep(0.18, 0.68, UV.x);
	float vig = smoothstep(0.35, 1.15, length(UV - vec2(0.5)) * 1.4142);
	float scan = 0.035 * (0.5 + 0.5 * sin(UV.y * 720.0));
	float alpha = clamp(left_fade * 0.84 + vig * 0.58 + scan, 0.0, 0.94);
	vec3 col = mix(vec3(0.015, 0.012, 0.016), vec3(0.06, 0.0, 0.0), vig * 0.25);
	COLOR = vec4(col, alpha);
}
"""
		mat.shader = scrim_shader
	if submenu_scrim:
		submenu_scrim.color = Color(0.008, 0.006, 0.01, 0.92) if is_dark else Color(0.02, 0.015, 0.02, 0.82)
	if mode_panel:
		var panel_style := StyleBoxFlat.new()
		panel_style.set_corner_radius_all(6)
		panel_style.set_border_width_all(2)
		panel_style.set_content_margin_all(16)
		if is_dark:
			panel_style.bg_color = Color(0.025, 0.02, 0.025, 0.94)
			panel_style.border_color = Color(0.45, 0.08, 0.08, 0.9)
		else:
			panel_style.bg_color = Color(0.05, 0.04, 0.05, 0.86)
			panel_style.border_color = Color(0.58, 0.12, 0.12, 0.88)
		mode_panel.add_theme_stylebox_override("panel", panel_style)

	# Restyle main menu buttons darker in dark mode
	_restyle_menu_buttons_for_dark(is_dark)


func _restyle_menu_buttons_for_dark(is_dark: bool) -> void:
	var normal_play := _make_granny_button_style(Color(0.24, 0.03, 0.03, 0.92), Color(0.85, 0.16, 0.16, 0.95), 2)
	var hover_play := _make_granny_button_style(Color(0.42, 0.05, 0.05, 0.98), Color(1.0, 0.32, 0.28, 1.0), 2)
	var normal_std := _make_granny_button_style(Color(0.07, 0.06, 0.07, 0.86), Color(0.38, 0.26, 0.24, 0.85), 1)
	var hover_std := _make_granny_button_style(Color(0.18, 0.05, 0.05, 0.95), Color(0.82, 0.20, 0.20, 0.95), 2)
	if is_dark:
		normal_play = _make_granny_button_style(Color(0.05, 0.02, 0.03, 0.95), Color(0.55, 0.10, 0.10, 0.95), 2)
		hover_play = _make_granny_button_style(Color(0.14, 0.03, 0.03, 0.98), Color(0.80, 0.18, 0.18, 1.0), 2)
		normal_std = _make_granny_button_style(Color(0.035, 0.03, 0.035, 0.95), Color(0.22, 0.12, 0.12, 0.9), 1)
		hover_std = _make_granny_button_style(Color(0.08, 0.03, 0.03, 0.98), Color(0.60, 0.14, 0.14, 0.95), 2)
	for child in menu.get_children():
		if child is Button:
			var btn: Button = child as Button
			if btn.name == "NewGame":
				btn.add_theme_stylebox_override("normal", normal_play)
				btn.add_theme_stylebox_override("hover", hover_play)
				btn.add_theme_stylebox_override("pressed", hover_play)
			else:
				btn.add_theme_stylebox_override("normal", normal_std)
				btn.add_theme_stylebox_override("hover", hover_std)
				btn.add_theme_stylebox_override("pressed", hover_std)


func _style_main_menu_buttons() -> void:
	# Left-aligned Granny-style button stack
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.offset_left = 60.0
	menu.offset_right = 440.0
	menu.offset_top = 210.0
	menu.offset_bottom = 520.0
	menu.add_theme_constant_override("separation", 12)

	var normal_play := _make_granny_button_style(Color(0.24, 0.03, 0.03, 0.92), Color(0.85, 0.16, 0.16, 0.95), 2)
	var hover_play := _make_granny_button_style(Color(0.42, 0.05, 0.05, 0.98), Color(1.0, 0.32, 0.28, 1.0), 2)
	var normal_std := _make_granny_button_style(Color(0.07, 0.06, 0.07, 0.86), Color(0.38, 0.26, 0.24, 0.85), 1)
	var hover_std := _make_granny_button_style(Color(0.18, 0.05, 0.05, 0.95), Color(0.82, 0.20, 0.20, 0.95), 2)

	for child in menu.get_children():
		if child is Button:
			var btn: Button = child as Button
			btn.custom_minimum_size = Vector2(360, 58)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if btn.name == "NewGame":
				btn.text = "PLAY"
				btn.add_theme_stylebox_override("normal", normal_play)
				btn.add_theme_stylebox_override("hover", hover_play)
				btn.add_theme_stylebox_override("pressed", hover_play)
				btn.add_theme_color_override("font_color", Color(0.98, 0.88, 0.82))
				btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
			elif btn.name == "WatchMode":
				btn.text = "WATCH MODE"
				btn.add_theme_stylebox_override("normal", normal_play)
				btn.add_theme_stylebox_override("hover", hover_play)
				btn.add_theme_stylebox_override("pressed", hover_play)
				btn.add_theme_color_override("font_color", Color(0.98, 0.88, 0.82))
				btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
			else:
				if btn.name == "LoadGame":
					btn.text = "HOUSE SELECT"
				elif btn.name == "options":
					btn.text = "OPTIONS"
				elif btn.name == "exit":
					btn.text = "QUIT"
				btn.add_theme_stylebox_override("normal", normal_std)
				btn.add_theme_stylebox_override("hover", hover_std)
				btn.add_theme_stylebox_override("pressed", hover_std)
				btn.add_theme_color_override("font_color", Color(0.86, 0.82, 0.78))
				btn.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.52))


func _style_submenus() -> void:
	var btn_norm := _make_granny_button_style(Color(0.08, 0.06, 0.07, 0.92), Color(0.55, 0.16, 0.16, 0.9), 2)
	var btn_hov := _make_granny_button_style(Color(0.24, 0.05, 0.05, 0.98), Color(0.92, 0.24, 0.24, 1.0), 2)
	for container_node in [options, graphics, audio]:
		if container_node == null:
			continue
		var stack_nodes: Array[Node] = [container_node]
		while not stack_nodes.is_empty():
			var n: Node = stack_nodes.pop_back()
			if n is Button:
				var b: Button = n as Button
				b.add_theme_stylebox_override("normal", btn_norm)
				b.add_theme_stylebox_override("hover", btn_hov)
				b.add_theme_stylebox_override("pressed", btn_hov)
				b.add_theme_color_override("font_color", Color(0.92, 0.86, 0.82))
				b.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
			elif n is Label:
				var lbl: Label = n as Label
				lbl.add_theme_color_override("font_color", Color(0.90, 0.84, 0.78))
			for c in n.get_children():
				stack_nodes.append(c)


func _build_mode_selector_ui() -> void:
	var ui_font: Font = load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font

	mode_panel = PanelContainer.new()
	mode_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mode_panel.offset_left = 60.0
	mode_panel.offset_right = 760.0
	mode_panel.offset_top = -310.0
	mode_panel.offset_bottom = -34.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.05, 0.86)
	style.border_color = Color(0.58, 0.12, 0.12, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	mode_panel.add_theme_stylebox_override("panel", style)
	add_child(mode_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	mode_panel.add_child(vbox)

	var diff_header := Label.new()
	diff_header.text = "DIFFICULTY"
	diff_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if ui_font:
		diff_header.add_theme_font_override("font", ui_font)
	diff_header.add_theme_font_size_override("font_size", 28)
	diff_header.add_theme_color_override("font_color", Color(0.92, 0.84, 0.72))
	vbox.add_child(diff_header)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var diff_defs: Array[Dictionary] = [
		{"id": 0, "label": "EASY"},
		{"id": 1, "label": "NORMAL"},
		{"id": 2, "label": "HARD"},
		{"id": 3, "label": "EXTREME"},
	]
	diff_buttons.clear()
	for d in diff_defs:
		var btn := Button.new()
		btn.text = str(d["label"])
		btn.custom_minimum_size = Vector2(154, 46)
		if ui_font:
			btn.add_theme_font_override("font", ui_font)
		btn.add_theme_font_size_override("font_size", 26)
		var diff_id: int = int(d["id"])
		btn.pressed.connect(func(): _on_difficulty_selected(diff_id))
		btn_row.add_child(btn)
		diff_buttons.append(btn)

	mode_desc_label = Label.new()
	mode_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mode_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc_label.add_theme_font_size_override("font_size", 16)
	mode_desc_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	vbox.add_child(mode_desc_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var dark_row := HBoxContainer.new()
	dark_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	dark_row.add_theme_constant_override("separation", 16)
	vbox.add_child(dark_row)

	dark_mode_btn = Button.new()
	dark_mode_btn.custom_minimum_size = Vector2(260, 44)
	if ui_font:
		dark_mode_btn.add_theme_font_override("font", ui_font)
	dark_mode_btn.add_theme_font_size_override("font_size", 24)
	dark_mode_btn.pressed.connect(_on_dark_mode_toggled)
	dark_row.add_child(dark_mode_btn)

	dark_desc_label = Label.new()
	dark_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dark_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dark_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dark_desc_label.add_theme_font_size_override("font_size", 15)
	dark_desc_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	dark_row.add_child(dark_desc_label)

	_refresh_mode_ui()


func _on_difficulty_selected(diff_id: int) -> void:
	_play_click()
	if has_node("/root/GameSettings"):
		var gs = get_node("/root/GameSettings")
		gs.difficulty = diff_id
	_refresh_mode_ui()


func _on_dark_mode_toggled() -> void:
	_play_click()
	if has_node("/root/GameSettings"):
		var gs = get_node("/root/GameSettings")
		gs.dark_mode = not bool(gs.dark_mode)
	_refresh_mode_ui()


func _refresh_mode_ui() -> void:
	var cur_diff: int = 1
	var is_dark: bool = false
	var desc_text: String = ""
	if has_node("/root/GameSettings"):
		var gs = get_node("/root/GameSettings")
		cur_diff = int(gs.difficulty)
		is_dark = bool(gs.dark_mode)
		desc_text = str(gs.get_difficulty_description())

	_apply_dark_mode_to_ui(is_dark)

	var colors: Array[Color] = [
		Color(0.45, 0.90, 0.52),
		Color(0.95, 0.85, 0.42),
		Color(0.95, 0.45, 0.22),
		Color(0.95, 0.14, 0.18),
	]

	for i in range(diff_buttons.size()):
		var b: Button = diff_buttons[i]
		var selected: bool = (i == cur_diff)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(5)
		st.set_border_width_all(2 if selected else 1)
		if selected:
			st.bg_color = Color(colors[i].r * 0.32, colors[i].g * 0.32, colors[i].b * 0.32, 0.95)
			st.border_color = colors[i]
			b.add_theme_color_override("font_color", colors[i])
		else:
			st.bg_color = Color(0.10, 0.09, 0.11, 0.82)
			st.border_color = Color(0.32, 0.28, 0.30, 0.8)
			b.add_theme_color_override("font_color", Color(0.75, 0.74, 0.76))
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)

	if mode_desc_label:
		mode_desc_label.text = desc_text
		mode_desc_label.add_theme_color_override("font_color", colors[clampi(cur_diff, 0, 3)])

	if dark_mode_btn:
		dark_mode_btn.text = "DARK MODE: ON" if is_dark else "DARK MODE: OFF"
		var dst := StyleBoxFlat.new()
		dst.set_corner_radius_all(5)
		dst.set_border_width_all(2)
		if is_dark:
			dst.bg_color = Color(0.24, 0.05, 0.06, 0.95)
			dst.border_color = Color(0.90, 0.22, 0.25)
			dark_mode_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		else:
			dst.bg_color = Color(0.12, 0.16, 0.20, 0.9)
			dst.border_color = Color(0.55, 0.72, 0.85)
			dark_mode_btn.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98))
		dark_mode_btn.add_theme_stylebox_override("normal", dst)
		dark_mode_btn.add_theme_stylebox_override("hover", dst)
		dark_mode_btn.add_theme_stylebox_override("pressed", dst)

	if dark_desc_label:
		if is_dark:
			dark_desc_label.text = "Pitch-dark house, Torch [RMB/T], gritty PSX horror."
			dark_desc_label.add_theme_color_override("font_color", Color(0.95, 0.58, 0.58))
		else:
			dark_desc_label.text = "Classic Granny indoor visibility, clean PSX shader."
			dark_desc_label.add_theme_color_override("font_color", Color(0.78, 0.88, 0.94))


func _sync_slider(bus_index: int, slider: HSlider) -> void:
	if slider == null or bus_index >= AudioServer.bus_count:
		return
	if AudioServer.is_bus_mute(bus_index):
		slider.set_value_no_signal(0.0)
	else:
		var lin := db_to_linear(AudioServer.get_bus_volume_db(bus_index))
		slider.set_value_no_signal(clampf(lin, 0.0, 1.0))


func _process(delta: float) -> void:
	menu_time += delta

	if mode_panel:
		mode_panel.visible = menu.visible
	if title_header:
		title_header.visible = menu.visible
	if submenu_scrim:
		submenu_scrim.visible = not menu.visible

	if title_lbl:
		var pulse: float = 0.84 + 0.16 * sin(menu_time * 2.2)
		title_lbl.add_theme_color_override("font_color", Color(0.88 * pulse + 0.10, 0.10, 0.10))

	# Creepy Granny-style flickering light + camera breathing + Robert head twitch
	if key_spot:
		flicker_timer -= delta
		if flicker_timer <= 0.0:
			var is_dip: bool = randf() < 0.22
			key_spot.light_energy = randf_range(0.7, 2.2) if is_dip else randf_range(6.2, 8.8)
			flicker_timer = randf_range(0.04, 0.14) if is_dip else randf_range(0.12, 0.65)
	if rim_omni:
		rim_omni.light_energy = 3.8 + 0.8 * sin(menu_time * 1.9)

	if menu_camera:
		menu_camera.position = cam_base_pos + Vector3(
			sin(menu_time * 0.45) * 0.035,
			sin(menu_time * 0.85) * 0.018,
			cos(menu_time * 0.35) * 0.025
		)

	if menu_skeleton:
		if spine_bone_idx >= 0:
			var breath := Quaternion(Vector3.RIGHT, sin(menu_time * 1.4) * 0.025)
			menu_skeleton.set_bone_pose_rotation(spine_bone_idx, spine_base_rot * breath)
		if head_bone_idx >= 0:
			head_twitch_timer -= delta
			if head_twitch_timer <= 0.0:
				head_twitch_timer = randf_range(1.6, 3.8)
				head_twitch_target = randf_range(-0.22, 0.24)
			head_twitch_curr = lerpf(head_twitch_curr, head_twitch_target, clampf(delta * 9.0, 0.0, 1.0))
			var head_offset := Quaternion(Vector3.FORWARD, head_twitch_curr) * Quaternion(Vector3.UP, sin(menu_time * 0.7) * 0.10)
			menu_skeleton.set_bone_pose_rotation(head_bone_idx, head_base_rot * head_offset)

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


func _play_hover() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_hover", -10.0, 1.0)


func _connect_button_hover_sfx(root: Node) -> void:
	for child in root.get_children():
		if child is BaseButton:
			var btn: BaseButton = child as BaseButton
			if not btn.mouse_entered.is_connected(_play_hover):
				btn.mouse_entered.connect(_play_hover)
		_connect_button_hover_sfx(child)


func _on_new_game_pressed():
	_play_click()
	get_tree().paused = false
	Engine.time_scale = 1.0
	# Granny flow: PLAY -> house select screen -> pick house -> enter game
	get_tree().change_scene_to_file("res://scenes/load_game_menu.tscn")


func _on_watch_mode_pressed():
	_play_click()
	get_tree().paused = false
	Engine.time_scale = 1.0
	# Launch straight into the house with Watch Mode (game plays itself, you watch)
	if has_node("/root/GameSettings"):
		get_node("/root/GameSettings").watch_mode = true
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
