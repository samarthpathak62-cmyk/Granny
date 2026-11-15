extends Node

const SOUND_PATHS: Dictionary = {
	"horror_ambience": "res://assets/sounds/horror_ambience.wav",
	"heartbeat": "res://assets/sounds/heartbeat.wav",
	"footstep_player": "res://assets/sounds/footstep_player.wav",
	"footstep_clown": "res://assets/sounds/footstep_clown.wav",
	"pickup": "res://assets/sounds/pickup.wav",
	"drop": "res://assets/sounds/drop.wav",
	"door_open": "res://assets/sounds/door_open.wav",
	"door_locked": "res://assets/sounds/door_locked.wav",
	"unlock": "res://assets/sounds/unlock.wav",
	"plank_break": "res://assets/sounds/plank_break.wav",
	"clown_alert": "res://assets/sounds/clown_alert.wav",
	"clown_jumpscare": "res://assets/sounds/clown_jumpscare.wav",
	"clown_hum": "res://assets/sounds/clown_hum.wav",
	"ui_click": "res://assets/sounds/ui_click.wav",
	"victory": "res://assets/sounds/victory.wav",
}

var streams: Dictionary = {}
var ambience_player: AudioStreamPlayer = null
var heartbeat_player: AudioStreamPlayer = null
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_3d_pool: Array[AudioStreamPlayer3D] = []

var chase_intensity: float = 0.0
var heartbeat_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preload_sounds()
	_setup_players()
	start_ambience()


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

	for i in range(10):
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


func _on_ambience_finished() -> void:
	if ambience_player and ambience_player.stream:
		ambience_player.play()


func start_ambience(volume_db: float = -10.0) -> void:
	if ambience_player == null or not streams.has("horror_ambience"):
		return
	var amb_stream: AudioStream = streams["horror_ambience"] as AudioStream
	if amb_stream is AudioStreamWAV:
		var wav: AudioStreamWAV = amb_stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		if wav.data.size() > 0:
			wav.loop_end = int(wav.data.size() / 2)
	ambience_player.stream = amb_stream
	ambience_player.volume_db = volume_db
	if not ambience_player.playing:
		ambience_player.play()


func set_chase_intensity(intensity: float) -> void:
	chase_intensity = clampf(intensity, 0.0, 1.0)
	if ambience_player:
		ambience_player.volume_db = lerpf(-11.0, -5.0, chase_intensity)


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
	if not streams.has(sound_name):
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
	target.stream = streams[sound_name] as AudioStream
	target.volume_db = volume_db
	target.pitch_scale = pitch_scale
	target.play()


func play_sfx_3d(sound_name: String, world_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0, max_dist: float = 24.0) -> void:
	if not streams.has(sound_name):
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
	target.stream = streams[sound_name] as AudioStream
	target.global_position = world_pos
	target.volume_db = volume_db
	target.pitch_scale = pitch_scale
	target.max_distance = max_dist
	target.play()
