extends Node
# 轻量反馈：短音效、非阻挡提示、排队的新料理发现动画。
var game
var volume = 0.55
var muted = false
var reduced_motion = false
var players = []
var sounds = {}
var last_played = {}
var toast: Panel
var toast_label: Label
var toast_tween
var discovery: Panel
var discovery_title: Label
var discovery_tags: Label
var discoveries = []
var discovering = false
var drag_target = null
var outlet_help = false
var help_anchor = null

func _ready():
	for sound in ["click", "pickup", "drop", "merge", "cut", "juice", "grind", "mix", "boil", "fry", "stir", "bake", "complete", "discover", "serve", "coin", "harvest", "collect", "error"]:
		sounds[sound] = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://audio/" + sound + ".wav"))
	for i in range(6):
		var player = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	toast = make_panel(Vector2(430, 70), Color("f8f6ee"), Color("c7c1ae"))
	toast_label = game.label(toast, "", Rect2(16, 10, 398, 50), 14)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discovery = make_panel(Vector2(536, 62), Color("faf6e9"), Color("c7ae71"))
	discovery.position = Vector2(690, 650)
	game.label(discovery, "发现新料理", Rect2(18, 6, 200, 18), 12)
	discovery_title = game.label(discovery, "", Rect2(18, 25, 210, 28), 18)
	discovery_tags = game.label(discovery, "", Rect2(240, 12, 278, 44), 12)
	discovery_tags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func make_panel(dimensions, fill, edge):
	var panel = Panel.new()
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 40
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_size = 5
	style.shadow_color = Color(0.2, 0.22, 0.15, 0.08)
	panel.add_theme_stylebox_override("panel", style)
	game.add_child(panel)
	panel.hide()
	return panel

func play(sound):
	if muted or volume <= 0 or not sounds.has(sound):
		return
	var now = Time.get_ticks_msec()
	if now - last_played.get(sound, -1000) < 90:
		return
	last_played[sound] = now
	for player in players:
		if not player.playing:
			player.stream = sounds[sound]
			player.volume_db = linear_to_db(volume) - 8
			player.pitch_scale = randf_range(0.97, 1.03) if sound != "discover" else 1.0
			player.play()
			return

func set_volume(value):
	volume = value
	if is_instance_valid(game.barn):
		game.barn.animal_player.volume_db = linear_to_db(maxf(0.0001, volume)) - 8
		if volume <= 0:
			game.barn.silence_animals()
	for player in players:
		player.volume_db = linear_to_db(maxf(0.0001, volume)) - 8
	game.catalog.save_data()

func toggle_mute():
	muted = not muted
	if muted:
		if is_instance_valid(game.barn):
			game.barn.silence_animals()
		for player in players:
			player.stop()
	game.catalog.save_data()
	game.refresh_menu()

func toggle_motion():
	reduced_motion = not reduced_motion
	game.catalog.save_data()
	game.refresh_menu()

func show_toast(message):
	outlet_help = false
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_label.text = message
	var invalid = "不足" in message or "不能" in message or "已满" in message or "不符合" in message
	var style = toast.get_theme_stylebox("panel").duplicate()
	style.border_color = Color("b78c7f") if invalid else Color("c7c1ae")
	toast.add_theme_stylebox_override("panel", style)
	if invalid:
		play("error")
	var point = game.get_global_mouse_position() + Vector2(16, 26)
	toast.position = Vector2(clampf(point.x, 116, 834), clampf(point.y, 84, 570))
	toast.modulate.a = 1
	toast.show()
	toast_tween = create_tween()
	toast_tween.tween_interval(3.4 if message.length() < 55 else 6.0)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.2)
	toast_tween.tween_callback(toast.hide)

func toggle_outlet_help(anchor):
	if toast.visible and outlet_help:
		toast.hide()
		outlet_help = false
		return
	show_toast("将料理拖到「出餐！」，再到餐厅拖给顾客。\n出餐台装满时，料理会留在后厨。")
	toast_tween.kill()
	outlet_help = true
	help_anchor = anchor
	toast.position = anchor.global_position + Vector2(anchor.size.x - toast.size.x, anchor.size.y + 10)

func _input(event):
	if not toast.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point = game.get_canvas_transform().affine_inverse() * event.position
		if outlet_help and is_instance_valid(help_anchor) and help_anchor.get_global_rect().has_point(point):
			return
		if not toast.get_global_rect().has_point(point):
			toast.hide()

func pulse(node, success = true):
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if node.has_meta("feedback_tween"):
		var previous = node.get_meta("feedback_tween")
		if previous and previous.is_valid():
			previous.kill()
	node.pivot_offset = node.size / 2
	node.scale = Vector2.ONE if reduced_motion else Vector2(1.045, 1.045)
	node.modulate = Color("e5ecd9") if success else Color("edc9bf")
	var tween = node.create_tween().set_parallel(true)
	node.set_meta("feedback_tween", tween)
	tween.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate", Color.WHITE, 0.3)
	if not success and not reduced_motion:
		node.rotation = -0.025
		tween.tween_property(node, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_ELASTIC)

func button_down(node):
	if reduced_motion:
		return
	node.pivot_offset = node.size / 2
	node.scale = Vector2(0.97, 0.94)

func click_sound():
	if not outlet_help:
		toast.hide()
	play("click")

func button_up(node):
	if is_instance_valid(node):
		node.scale = Vector2.ONE

func announce(recipe):
	discoveries.append(recipe.duplicate(true))
	if not discovering:
		show_next()

func show_next():
	if discoveries.is_empty():
		discovering = false
		discovery.hide()
		return
	discovering = true
	var recipe = discoveries.pop_front()
	discovery_title.text = recipe["name"]
	discovery_tags.text = " / ".join(recipe["tags"].slice(0, 3)) + "\n已收录图鉴"
	discovery_tags.visible_characters = 0
	discovery.modulate.a = 0
	discovery.scale = Vector2.ONE if reduced_motion else Vector2(0.98, 0.98)
	discovery.show()
	play("discover")
	var tween = create_tween()
	tween.tween_property(discovery, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(discovery, "scale", Vector2.ONE, 0.15)
	tween.tween_property(discovery_tags, "visible_characters", discovery_tags.text.length(), 0.35)
	tween.tween_interval(0.7)
	tween.tween_property(discovery, "modulate:a", 0.0, 0.25)
	tween.tween_callback(show_next)

func highlight(target):
	if is_instance_valid(drag_target) and drag_target != target:
		drag_target.modulate = Color.WHITE
	drag_target = target
	if is_instance_valid(target):
		target.modulate = Color("cdddbe")

func preview(card):
	if card.get_parent().has_method("preview_drop"):
		card.get_parent().preview_drop(card)
		return
	var target = null
	var point = card.global_position + card.size / 2
	if game.current_page == "农场":
		if card.kind == "seed" and game.farm.seeds.get(card.data.get("crop"), 0) > 0:
			for plot in game.farm.plots:
				if plot.data["crop"] == "" and Rect2(plot.global_position, plot.size).has_point(point):
					target = plot
		elif card.kind == "produce" and game.farm.collector.visible:
			var box = game.farm.collector
			if Rect2(box.global_position, box.size).has_point(point):
				target = box
	elif game.current_page == "畜棚" and card.kind == "produce" and game.barn.collector.visible:
		var box = game.barn.collector
		if Rect2(box.global_position, box.size).has_point(point):
			target = box
	highlight(target)

func reveal_card(card):
	pulse(card)
	card.modulate = Color("fff0c9")
	if not reduced_motion:
		card.scale = Vector2(1.07, 1.07)

func collect(card, destination):
	# 用一份只显示的文字影子飞入箱子；原物品立即结算，避免再次收集。
	play("collect")
	if reduced_motion:
		return
	var ghost = game.label(game, card.title_label.text, Rect2(card.global_position, card.size), 14)
	ghost.z_index = 30
	var tween = ghost.create_tween().set_parallel(true)
	tween.tween_property(ghost, "position", destination, 0.22).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(ghost.queue_free)

func _exit_tree():
	for player in players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	sounds.clear()
