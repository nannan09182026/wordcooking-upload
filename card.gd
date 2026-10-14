extends Panel
# 一张卡片。只负责显示和鼠标操作，不负责料理规则。

signal clicked(card)
signal dropped(card)
signal double_clicked(card)

const DRAG_DISTANCE = 8.0
var kind = "ingredient" # ingredient / tool / dish
var tool_name = ""
var items = [] # 每份食材是 {"name": "番茄", "process": "切"}
var tags = []
var cooking_method = ""
var drag_area = Rect2()
var pressed = false
var dragging = false
var press_mouse = Vector2.ZERO
var start_position = Vector2.ZERO
var title_label: Label
var caption = ""
var data = {}
var movable = true
var progress = -1.0
var progress_bar: ProgressBar
var dish_name = ""
var detail_text = ""
var expanded = false
var small_position = Vector2.ZERO
var double_clickable = false
var double_press = false
var click_timer: Timer
var feedback

func _ready():
	title_label = Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 15)
	add_child(title_label)
	click_timer = Timer.new()
	click_timer.one_shot = true
	click_timer.wait_time = 0.28
	click_timer.timeout.connect(func(): clicked.emit(self))
	add_child(click_timer)
	progress_bar = ProgressBar.new()
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 4)
	progress_bar.top_level = false
	# 生长进度沿用杏橙色，背景保留低对比的奶油色。
	var track = StyleBoxFlat.new()
	track.bg_color = Color("f1dfcc")
	track.set_corner_radius_all(2)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color("e5a365")
	fill.set_corner_radius_all(2)
	progress_bar.add_theme_stylebox_override("background", track)
	progress_bar.add_theme_stylebox_override("fill", fill)
	add_child(progress_bar)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(hover.bind(true))
	mouse_exited.connect(hover.bind(false))
	refresh()

func hover(inside):
	if not pressed:
		var style = get_theme_stylebox("panel").duplicate()
		style.border_color = Color("b85722") if inside else Color("d6b99f")
		add_theme_stylebox_override("panel", style)

func refresh():
	if not is_instance_valid(title_label):
		return
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.custom_minimum_size = Vector2.ZERO
	var box = StyleBoxFlat.new()
	box.bg_color = Color("fffdfa")
	box.border_color = Color("d6b99f")
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	if kind == "tool":
		box.bg_color = Color("fff0e1")
	elif kind == "dish":
		box.bg_color = Color("fff0e1")
		box.border_width_left = 3
		box.border_color = Color("c1ad79")
	box.shadow_size = 2
	box.shadow_color = Color(0.2, 0.25, 0.15, 0.045)
	add_theme_stylebox_override("panel", box)
	title_label.add_theme_color_override("font_color", Color("4a3428"))
	if caption != "":
		title_label.text = caption
		custom_minimum_size = Vector2(80, 36)
	elif kind == "tool":
		title_label.text = tool_name
		custom_minimum_size = Vector2(52, 36)
	elif kind == "dish":
		# 每行最多三个标签，保留小文字块的尺寸。
		var lines = []
		for i in range(0, tags.size(), 3):
			lines.append(" / ".join(tags.slice(i, i + 3)))
		title_label.text = dish_name if dish_name != "" else "料理"
		custom_minimum_size = Vector2(112, 40)
	else:
		var counts = {}
		for item in items:
			var key = item.get("form", item["name"])
			if item["process"] != "":
				key += " [" + item["process"] + "]"
			counts[key] = counts.get(key, 0) + 1
		var lines = []
		for key in counts:
			if items.size() > 1:
				lines.append(key + " x" + str(counts[key]))
			else:
				lines.append(key)
		title_label.text = "\n".join(lines)
		custom_minimum_size = Vector2(76, 36)
		if items.size() > 1:
			custom_minimum_size = Vector2(116, 58)
		if data.get("intermediate", "") != "":
			title_label.text = data["intermediate"] + " × " + str(items.size()) + "份"
	if expanded:
		title_label.text += "\n\n" + detail_text + "\n\n再次单击收起"
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_label.custom_minimum_size.x = 270
		custom_minimum_size = Vector2(294, 140)
	# 根据文字重新计算尺寸，避免多行分组挤出边框。
	# 手动按最终宽度测量文字，避免先按小卡宽度换行导致详情异常变高。
	var font = title_label.get_theme_font("font")
	var text_size = font.get_multiline_string_size(title_label.text, HORIZONTAL_ALIGNMENT_CENTER, 270 if expanded else -1, 15)
	size = Vector2(maxf(custom_minimum_size.x, text_size.x + 24), maxf(custom_minimum_size.y, text_size.y + 18))
	title_label.position = Vector2(12, 8)
	title_label.size = size - Vector2(24, 16)
	if expanded:
		position.x = clampf(position.x, 104, maxf(104, 1260 - size.x))
		position.y = clampf(position.y, 80, maxf(80, 660 - size.y))
	else:
		clamp_to_area()
	progress_bar.visible = progress >= 0
	progress_bar.value = progress * 100

func toggle_detail(text_value):
	if expanded:
		collapse()
	else:
		small_position = position
		detail_text = text_value.replace(" / ", "   ·   ")
		expanded = true
		move_to_front()
		refresh()

func collapse():
	if expanded:
		expanded = false
		position = small_position
		refresh()

func _process(_delta):
	# Label 的换行最小高度会延后一帧更新，再对齐一次可消除旧尺寸残留。
	title_label.position = Vector2(12, 8)
	title_label.size = size - Vector2(24, 16)
	if expanded:
		size.y = maxf(custom_minimum_size.y, title_label.get_minimum_size().y + 18)
		position.y = clampf(position.y, 80, maxf(80, 660 - size.y))
	# 进度条画在文字块下边，不占用文字区域。
	if is_instance_valid(progress_bar):
		progress_bar.visible = progress >= 0
		progress_bar.value = progress * 100
		progress_bar.set_deferred("position", Vector2(0, size.y + 4))
		progress_bar.set_deferred("size", Vector2(size.x, 4))

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if feedback:
				feedback.toast.hide()
			double_press = event.double_click and double_clickable
			if double_press:
				click_timer.stop()
			pressed = true
			dragging = false
			press_mouse = get_global_transform() * event.position
			start_position = position
			move_to_front()
			accept_event()

func _input(event):
	if not pressed:
		return
	if event is InputEventMouseMotion:
		# _input 比界面鼠标位置更新更早，直接读取本次事件的位置。
		var mouse_position = get_canvas_transform().affine_inverse() * event.position
		var distance = mouse_position - press_mouse
		if distance.length() >= DRAG_DISTANCE:
			if not dragging:
				click_timer.stop()
				if feedback and movable:
					feedback.play("pickup")
					if not feedback.reduced_motion:
						scale = Vector2(1.025, 1.025)
					var style = get_theme_stylebox("panel").duplicate()
					style.shadow_size = 9
					style.shadow_color = Color(0.2, 0.25, 0.15, 0.15)
					add_theme_stylebox_override("panel", style)
				if expanded:
					collapse()
					start_position = position
			dragging = true
		if dragging and movable:
			position = start_position + distance
			clamp_to_area()
			modulate = Color(1, 1, 1, 0.94)
			if feedback:
				feedback.preview(self)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			pressed = false
			modulate = Color.WHITE
			if dragging and movable:
				scale = Vector2.ONE
				if feedback:
					feedback.highlight(null)
					feedback.play("drop")
				refresh()
				if feedback:
					feedback.pulse(self)
				dropped.emit(self)
			elif not dragging:
				if feedback:
					feedback.play("click")
				if double_press:
					double_clicked.emit(self)
				elif double_clickable:
					click_timer.start()
				else:
					clicked.emit(self)
			dragging = false

func clamp_to_area():
	position.x = clampf(position.x, drag_area.position.x, maxf(drag_area.position.x, drag_area.end.x - size.x))
	position.y = clampf(position.y, drag_area.position.y, maxf(drag_area.position.y, drag_area.end.y - size.y))

func _notification(what):
	# 切出窗口或切换页面时取消拖动，避免回来后卡片粘在鼠标上。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_instance_valid(click_timer):
			click_timer.stop()
		pressed = false
		dragging = false
		modulate = Color.WHITE
		scale = Vector2.ONE
