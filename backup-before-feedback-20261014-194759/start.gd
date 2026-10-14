extends Control
# 开始界面：三张存档卡 + 文字食材的小互动。正式运行入口是 start.tscn。
var saves = preload("res://save_game.gd").new()
var login: Control
var art: Control
var veil: ColorRect
var status: Label
var slot_buttons = []
var ingredients = []
var active_game = null
var busy = false
var elapsed = 0.0
var click_player: AudioStreamPlayer
var quiet = false
var volume = 0.55
var reduced = false
const SHOP_NAMES = ["番茄小店", "麦香小店", "蛋花小店"]

func _ready():
	var ui = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	ui.default_font = font
	ui.default_font_size = 15
	ui.set_color("font_color", "Label", Color("41483e"))
	theme = ui
	click_player = AudioStreamPlayer.new()
	click_player.stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://audio/click.wav"))
	add_child(click_player)
	login = Control.new()
	login.name = "TitlePage"
	login.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(login)
	var paper = ColorRect.new()
	paper.color = Color("faf9f6")
	paper.size = Vector2(1280, 720)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	login.add_child(paper)
	art = Control.new()
	art.name = "BowlArt"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(draw_art)
	login.add_child(art)
	text_label("小 店 日 记", Vector2(138, 124), 13)
	text_label("文字料理", Vector2(132, 164), 44)
	text_label("把小日子，慢慢煮好。", Vector2(138, 231), 17)
	text_label("今天，也要好好吃饭", Vector2(239, 526), 16)
	text_label("选择你的小店", Vector2(730, 139), 24)
	text_label("每天打烊，自动记下今天的故事。", Vector2(730, 183), 14)
	for i in range(3):
		var slot = make_button("", Rect2(718, 238 + i * 118, 430, 100), select_slot.bind(i + 1))
		slot.name = "SaveSlot" + str(i + 1)
		slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot.add_theme_font_size_override("font_size", 16)
		slot_buttons.append(slot)
	var names = ["番茄", "小麦", "鸡蛋"]
	var positions = [Vector2(180, 339), Vector2(397, 302), Vector2(460, 399)]
	for i in range(3):
		var card = make_button(names[i], Rect2(positions[i], Vector2(86, 38)), touch_ingredient.bind(i))
		card.name = "Food" + str(i + 1)
		card.pivot_offset = card.size / 2
		ingredients.append({"node": card, "base": positions[i], "name": names[i], "tween": null})
	make_button("退出", Rect2(1130, 48, 70, 30), get_node("/root/Music").request_quit)
	status = text_label("选一张存档卡，推开小店的门。", Vector2(730, 610), 13)
	status.size = Vector2(440, 60)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	veil = ColorRect.new()
	veil.name = "SceneFade"
	veil.color = Color("faf9f6")
	veil.size = Vector2(1280, 720)
	veil.z_index = 100
	veil.hide()
	add_child(veil)
	refresh_slots()
	read_preferences()

func text_label(value, point, font_size):
	var label = Label.new()
	label.text = value
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	login.add_child(label)
	return label

func make_button(caption, rect, action):
	var button = Button.new()
	button.text = caption
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("fffdf7")
		style.border_color = Color("d4d0c4")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 22 if rect.size.x > 200 else 12
		style.content_margin_right = 16
		if state == "hover":
			style.bg_color = Color("f1f2e8")
			style.border_color = Color("99a68b")
			style.shadow_size = 5
			style.shadow_color = Color(0.3, 0.35, 0.2, 0.06)
		if state == "pressed":
			style.bg_color = Color("e5eadb")
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("aab797")
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("454d40"))
	button.add_theme_color_override("font_hover_color", Color("454d40"))
	button.add_theme_color_override("font_pressed_color", Color("454d40"))
	button.add_theme_color_override("font_disabled_color", Color("96988c"))
	button.pressed.connect(play_click)
	button.pressed.connect(action)
	login.add_child(button)
	return button

func read_preferences():
	var file_path = "user://test_catalog.json" if "--test-mode" in OS.get_cmdline_user_args() else "user://cooking_catalog.json"
	if not FileAccess.file_exists(file_path):
		return
	var json = JSON.new()
	if json.parse(FileAccess.get_file_as_string(file_path)) != OK or not json.data is Dictionary:
		return
	var settings = json.data.get("settings", {})
	if not settings is Dictionary:
		return
	quiet = settings.get("muted", false) == true
	reduced = settings.get("reduced_motion", false) == true
	if saves.number(settings.get("volume"), 0, 1):
		volume = settings["volume"]

func play_click():
	if not quiet and volume > 0:
		click_player.volume_db = linear_to_db(volume) - 8
		click_player.play()

func touch_ingredient(index):
	var item = ingredients[index]
	var card = item["node"]
	if item["tween"] and item["tween"].is_valid():
		item["tween"].kill()
	card.text = ["酸酸甜甜", "麦香满满", "圆圆满满"][index]
	card.scale = Vector2.ONE if reduced else Vector2(1.08, 1.08)
	var tween = create_tween()
	item["tween"] = tween
	tween.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.65)
	tween.tween_callback(func(): card.text = item["name"])

func _process(delta):
	if not login.visible:
		return
	elapsed += delta
	for i in range(ingredients.size()):
		var item = ingredients[i]
		item["node"].position = item["base"] + Vector2(0, 0 if reduced else sin(elapsed * 1.35 + i * 1.8) * 5)
		item["node"].rotation = 0 if reduced else sin(elapsed * 0.8 + i) * 0.025
	art.queue_redraw()

func draw_art():
	var line = Color("c5c4b4")
	art.draw_line(Vector2(648, 140), Vector2(648, 590), Color("e5e2d9"), 1, true)
	# 只有线条的小碗：豆豆眼与浅浅的笑，仍是纸面文字桌的风格。
	art.draw_arc(Vector2(342, 413), 96, 0, PI, 64, line, 2, true)
	art.draw_line(Vector2(246, 413), Vector2(438, 413), line, 2, true)
	art.draw_circle(Vector2(323, 448), 2.5, Color("7a8270"))
	art.draw_circle(Vector2(361, 448), 2.5, Color("7a8270"))
	art.draw_arc(Vector2(342, 449), 9, 0.15, PI - 0.15, 20, Color("7a8270"), 1.5, true)
	art.draw_line(Vector2(315, 510), Vector2(369, 510), line, 2, true)
	for i in range(3):
		var points = PackedVector2Array()
		for j in range(18):
			var drift = 0 if reduced else sin(elapsed * 1.3 + j * 0.28 + i) * 3
			points.append(Vector2(312 + i * 30 + drift, 394 - j * 2.1))
		art.draw_polyline(points, Color("dddbce"), 1.3, true)
	for i in range(5):
		var center = Vector2(150 + i * 94, 290 + (i % 2) * 215)
		var alpha = 0.45 if reduced else 0.3 + (sin(elapsed + i) + 1) * 0.12
		var color = Color(0.70, 0.66, 0.49, alpha)
		art.draw_line(center - Vector2(4, 0), center + Vector2(4, 0), color, 1, true)
		art.draw_line(center - Vector2(0, 4), center + Vector2(0, 4), color, 1, true)

func refresh_slots():
	for i in range(3):
		var data = saves.read_slot(i + 1)
		var button = slot_buttons[i]
		button.disabled = false
		var caption = "%02d   %s\n" % [i + 1, SHOP_NAMES[i]]
		if data != null:
			caption += "第 %d 天 · %s     金币 %d\n" % [data["day"], "已打烊" if data["phase"] == "夜晚" else "早晨", data["money"]]
			caption += "从备份继续" if saves.recovered else "继续小店  ·  " + data["saved_at"]
		elif saves.exists(i + 1):
			caption += "存档暂时无法读取\n原文件已保留"
			button.disabled = true
		else:
			caption += "空白存档  ·  开一家新店"
		button.text = caption

func select_slot(slot):
	if busy:
		return
	var data = saves.read_slot(slot)
	var from_backup = saves.recovered
	if data == null and saves.exists(slot):
		status.text = saves.error_text
		return
	busy = true
	veil.modulate.a = 0
	veil.show()
	var fade = create_tween()
	fade.tween_property(veil, "modulate:a", 1.0, 0.08 if reduced else 0.22)
	await fade.finished
	var game = load("res://main.tscn").instantiate()
	game.slot_id = slot
	game.save_system.prefix = saves.prefix
	game.title_screen = self
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	var ok = true
	if data != null:
		ok = saves.restore(game, data)
		game.save_status = ("已从备份恢复 · " if from_backup else "已读取存档 · ") + "第 %d 天" % game.day
	else:
		# 只在第一份新档继承旧版本的图鉴；其他档案从零开始。
		if slot != 1:
			game.recipes.clear()
			game.catalog.entries.clear()
		ok = saves.write_slot(slot, saves.capture(game))
	if not ok:
		game.queue_free()
		status.text = saves.error_text if saves.error_text != "" else "存档未能读取，原进度没有改变。"
		veil.hide()
		busy = false
		return
	active_game = game
	login.hide()
	game.process_mode = Node.PROCESS_MODE_INHERIT
	if game.phase == "夜晚":
		game.open_menu("结算")
	game.feedback.toast.hide()
	var reveal = create_tween()
	reveal.tween_property(veil, "modulate:a", 0.0, 0.08 if reduced else 0.22)
	await reveal.finished
	veil.hide()
	busy = false

func return_to_title():
	if busy:
		return
	if is_instance_valid(active_game):
		active_game.barn.silence_animals()
		active_game.hide()
		active_game.process_mode = Node.PROCESS_MODE_DISABLED
		active_game.queue_free()
		active_game = null
	login.show()
	refresh_slots()
	read_preferences()
	status.text = "选一张存档卡，推开小店的门。"

func _exit_tree():
	if is_instance_valid(click_player):
		click_player.stop()
		click_player.stream = null
