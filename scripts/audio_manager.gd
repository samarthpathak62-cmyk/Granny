extends Node

const SOUND_PATHS: Dictionary = {
	"menu_music": "res://assets/sounds/menu_music.mp3",
	"horror_ambience": "res://assets/sounds/horror_ambience.mp3",
	"heartbeat": "res://assets/sounds/heartbeat.mp3",
	"footstep_player": "res://assets/sounds/footstep_player_0.ogg",
	"footstep_clown": "res://assets/sounds/footstep_clown_0.ogg",
	"pickup": "res://assets/sounds/pickup.ogg",
	"drop": "res://assets/sounds/drop.mp3",
	"door_open": "res://assets/sounds/door_open.mp3",
	"door_locked": "res://assets/sounds/door_locked.ogg",
	"unlock": "res://assets/sounds/unlock.ogg",
	"plank_break": "res://assets/sounds/plank_break.mp3",
	"clown_alert": "res://assets/sounds/clown_alert.mp3",
	"clown_jumpscare": "res://assets/sounds/clown_jumpscare.mp3",
	"clown_hum": "res://assets/sounds/clown_hum.mp3",
	"ui_click": "res://assets/sounds/ui_click.wav",
	"ui_hover": "res://assets/sounds/ui_hover.wav",
	"victory": "res://assets/sounds/victory.mp3",
	"trap_snap": "res://assets/sounds/trap_snap.mp3",
	"boat_escape": "res://assets/sounds/boat_escape.mp3",
	"note_open": "res://assets/sounds/note_open.ogg",
	"note_close": "res://assets/sounds/note_close.ogg",
	"house_creak": "res://assets/sounds/house_creak.mp3",
	"death_sting": "res://assets/sounds/death_sting.mp3",
}

const SOUND_VARIANTS: Dictionary = {
	"footstep_player": [
		"res://assets/sounds/footstep_player_0.ogg",
		"res://assets/sounds/footstep_player_1.ogg",
		"res://assets/sounds/footstep_player_2.ogg",
		"res://assets/sounds/footstep_player_3.ogg",
		"res://assets/sounds/footstep_player_4.ogg",
	],
	"footstep_clown": [
		"res://assets/sounds/footstep_clown_0.ogg",
		"res://assets/sounds/footstep_clown_1.ogg",
		"res://assets/sounds/footstep_clown_2.ogg",
		"res://assets/sounds/footstep_clown_3.ogg",
		"res://assets/sounds/footstep_clown_4.ogg",
	],
	"door_open": [
		"res://assets/sounds/door_open.mp3",
		"res://assets/sounds/door_open_2.ogg",
	],
	"clown_hum": [
		"res://assets/sounds/clown_hum.mp3",
		"res://assets/sounds/clown_hum_2.mp3",
	],
}

var streams: Dictionary = {}
var variant_streams: Dictionary = {}
var last_variant_idx: Dictionary = {}
var ambience_player: AudioStreamPlayer = null
var current_music_key: String = ""
var heartbeat_player: AudioStreamPlayer = null
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_3d_pool: Array[AudioStreamPlayer3D] = []

var chase_intensity: float = 0.0
var heartbeat_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preload_sounds()
	_setup_players()
	start_menu_music()


func _get_bus_name(preferred: String) -> StringName:
	var idx: int = AudioServer.get_bus_index(preferred)
	if idx >= 0:
		return StringName(preferred)
	return &"Master"


func _preload_sounds() -> void:
	for key in SOUND_PATHS.keys():
		var path: String = str(SOUND_PATHS[key])
		if ResourceLoader.exists(path):
			var res: Resource = ResourceLoader.load(path)
			if res is AudioStream:
				streams[key] = res

	for key in SOUND_VARIANTS.keys():
		var paths: Array = SOUND_VARIANTS[key]
		var loaded: Array[AudioStream] = []
		for p in paths:
			var p_str: String = str(p)
			if ResourceLoader.exists(p_str):
				var res: Resource = ResourceLoader.load(p_str)
				if res is AudioStream:
					loaded.append(res as AudioStream)
		if not loaded.is_empty():
			variant_streams[key] = loaded


func _setup_players() -> void:
	var music_bus: StringName = _get_bus_name("Music")
	var sfx_bus: StringName = _get_bus_name("Sound Fx")

	ambience_player = AudioStreamPlayer.new()
	ambience_player.bus = music_bus
	ambience_player.volume_db = -10.0
	add_child(ambience_player)
	ambience_player.finished.connect(_on_ambience_finished)

	heartbeat_player = AudioStreamPlayer.new()
	heartbeat_player.bus = sfx_bus
	heartbeat_player.volume_db = -8.0
	if streams.has("heartbeat"):
		heartbeat_player.stream = streams["heartbeat"] as AudioStream
	add_child(heartbeat_player)

	for i in range(12):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = sfx_bus
		add_child(p)
		sfx_pool.append(p)

	for i in range(8):
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.bus = sfx_bus
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 3.2
		p3.max_distance = 24.0
		add_child(p3)
		sfx_3d_pool.append(p3)


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		if wav.data.size() > 0:
			wav.loop_end = int(wav.data.size() / 2)


func _on_ambience_finished() -> void:
	if ambience_player and ambience_player.stream:
		ambience_player.play()


func _play_music_track(key: String, volume_db: float = -10.0) -> void:
	if ambience_player == null:
		return
	if not streams.has(key):
		return
	var track: AudioStream = streams[key] as AudioStream
	_enable_loop(track)
	if current_music_key != key or ambience_player.stream != track:
		current_music_key = key
		ambience_player.stop()
		ambience_player.stream = track
		ambience_player.volume_db = volume_db
		ambience_player.play()
	else:
		ambience_player.volume_db = volume_db
		if not ambience_player.playing:
			ambience_player.play()


func start_menu_music(volume_db: float = -10.0) -> void:
	if streams.has("menu_music"):
		_play_music_track("menu_music", volume_db)
	else:
		start_ambience(volume_db)


func start_ambience(volume_db: float = -10.0) -> void:
	_play_music_track("horror_ambience", volume_db)


func set_chase_intensity(intensity: float) -> void:
	chase_intensity = clampf(intensity, 0.0, 1.0)
	if ambience_player and current_music_key == "horror_ambience":
		ambience_player.volume_db = lerpf(-11.0, -5.0, chase_intensity)


func _pick_stream(sound_name: String) -> AudioStream:
	if variant_streams.has(sound_name):
		var arr: Array = variant_streams[sound_name]
		if arr.size() > 1:
			var prev: int = int(last_variant_idx.get(sound_name, -1))
			var idx: int = randi() % arr.size()
			if idx == prev:
				idx = (idx + 1) % arr.size()
			last_variant_idx[sound_name] = idx
			return arr[idx] as AudioStream
		elif arr.size() == 1:
			return arr[0] as AudioStream
	if streams.has(sound_name):
		return streams[sound_name] as AudioStream
	return null


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if chase_intensity <= 0.08 or heartbeat_player == null or heartbeat_player.stream == null:
		heartbeat_timer = 0.0
		return
	heartbeat_timer -= delta
	if heartbeat_timer <= 0.0:
		var interval: float = lerpf(1.15, 0.48, chase_intensity)
		heartbeat_timer = interval
		heartbeat_player.volume_db = lerpf(-18.0, 1.5, chase_intensity)
		heartbeat_player.pitch_scale = lerpf(0.92, 1.24, chase_intensity)
		heartbeat_player.play()


func play_sfx(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var s: AudioStream = _pick_stream(sound_name)
	if s == null:
		return
	var target: AudioStreamPlayer = null
	for p in sfx_pool:
		if not p.playing:
			target = p
			break
	if target == null and not sfx_pool.is_empty():
		target = sfx_pool[0]
	if target == null:
		return
	target.bus = _get_bus_name("Sound Fx")
	target.stream = s
	target.volume_db = volume_db
	target.pitch_scale = pitch_scale
	target.play()


func play_sfx_3d(sound_name: String, world_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0, max_dist: float = 24.0) -> void:
	var s: AudioStream = _pick_stream(sound_name)
	if s == null:
		return
	var target: AudioStreamPlayer3D = null
	for p3 in sfx_3d_pool:
		if not p3.playing:
			target = p3
			break
	if target == null and not sfx_3d_pool.is_empty():
		target = sfx_3d_pool[0]
	if target == null:
		return
	target.bus = _get_bus_name("Sound Fx")
	target.stream = s
	target.global_position = world_pos
	target.volume_db = volume_db
	target.pitch_scale = pitch_scale
	target.max_distance = max_dist
	target.play()
