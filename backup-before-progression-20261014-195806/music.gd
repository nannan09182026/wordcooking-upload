extends Node
# 两个播放器轮流接力，在结尾交叉淡化；页面切换不会重新创建音乐。
const FADE_IN = 2.0
const CROSSFADE = 2.0
const FADE_OUT = 0.6
var volume = 0.35
var muted = false
var players = []
var active = 0
var length = 0.0
var blending = false
var blend_time = 0.0
var level: float = 0.0
var envelope
var closing = false
var loop_count = 0
var settings_path = "user://music_settings.json"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	if "--test-mode" in OS.get_cmdline_user_args():
		settings_path = "user://test_music_settings.json"
	else:
		load_settings()
	var stream = load("res://audio/pixel_kitchen_loop.wav")
	if stream == null:
		push_error("背景音乐加载失败")
		return
	length = stream.get_length()
	for i in range(2):
		var player = AudioStreamPlayer.new()
		player.name = "MusicA" if i == 0 else "MusicB"
		player.stream = stream
		player.volume_db = -80
		add_child(player)
		player.finished.connect(recover_end.bind(i))
		players.append(player)
	if not "--test-mode" in OS.get_cmdline_user_args():
		start_music()

func start_music():
	if players.is_empty() or players[active].playing or closing:
		return
	level = 0.0
	players[active].play()
	ramp(0.0 if muted else volume, FADE_IN)

func ramp(target: float, seconds: float):
	if envelope and envelope.is_valid():
		envelope.kill()
	envelope = create_tween()
	envelope.tween_property(self, "level", target, seconds)

func _process(delta):
	if players.size() != 2:
		return
	var other = 1 - active
	if blending:
		blend_time += delta
		var fraction = clampf(blend_time / CROSSFADE, 0, 1)
		set_gain(active, level * (1 - fraction))
		set_gain(other, level * fraction)
		if fraction >= 1:
			players[active].stop()
			active = other
			blending = false
			loop_count += 1
	else:
		set_gain(active, level)
		set_gain(other, 0)
		if not closing and players[active].playing and players[active].get_playback_position() >= length - CROSSFADE:
			players[other].play()
			blend_time = 0
			blending = true

func set_gain(index, gain):
	players[index].volume_db = linear_to_db(maxf(0.0001, gain))

func recover_end(index):
	# 极低帧率导致错过交接时仍可继续播放，不会永久停止。
	if index == active and not blending and not closing:
		start_music()

func set_volume(value):
	volume = clampf(value, 0, 1)
	if not closing:
		ramp(0.0 if muted else volume, 0.2)
	save_settings()

func toggle_mute():
	muted = not muted
	if not closing:
		ramp(0.0 if muted else volume, 0.3)
	save_settings()

func load_settings():
	for path in [settings_path, settings_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var json = JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			continue
		var value = json.data.get("volume")
		if not (value is int or value is float) or not is_finite(float(value)) or not json.data.get("muted") is bool:
			continue
		volume = clampf(value, 0, 1)
		muted = json.data["muted"]
		return

func save_settings():
	var file = FileAccess.open(settings_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"volume": volume, "muted": muted}))
	file.close()
	if FileAccess.file_exists(settings_path):
		DirAccess.copy_absolute(settings_path, settings_path + ".bak")
	DirAccess.rename_absolute(settings_path + ".tmp", settings_path)

func fade_out():
	closing = true
	ramp(0, FADE_OUT)
	await envelope.finished
	for player in players:
		player.stop()
	blending = false

func request_quit():
	if closing:
		return
	await fade_out()
	get_tree().quit.call_deferred()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

func _exit_tree():
	for player in players:
		player.stop()
		player.stream = null
