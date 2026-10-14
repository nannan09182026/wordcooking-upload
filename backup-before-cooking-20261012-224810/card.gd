extends PanelContainer
# 一张卡片。只负责显示和鼠标操作，不负责料理规则。

signal clicked(card)
signal dropped(card)

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

func _ready():
	title_label = Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 15)
	add_child(title_label)
	progress_bar = ProgressBar.new()
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 4)
	progress_bar.top_level = false
	add_child(progress_bar)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	refresh()

func refresh():
	var box = StyleBoxFlat.new()
	box.bg_color = Color("fffefa")
	box.border_color = Color("a6a89e")
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	if kind == "tool":
		box.bg_color = Color("eff1eb")
	elif kind == "dish":
		box.bg_color = Color("f4eddb")
	add_theme_stylebox_override("panel", box)
	title_label.add_theme_color_override("font_color", Color("303832"))
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
		title_label.text = "未知料理\n" + "\n".join(lines)
		custom_minimum_size = Vector2(164, 62)
	else:
		var counts = {}
		for item in items:
			var key = item["name"]
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
	# 根据文字重新计算尺寸，避免多行分组挤出边框。
	size = get_combined_minimum_size()
	clamp_to_area()
	progress_bar.visible = progress >= 0
	progress_bar.value = progress * 100

func _process(_delta):
	# 进度条画在文字块下边，不占用文字区域。
	if is_instance_valid(progress_bar):
		progress_bar.visible = progress >= 0
		progress_bar.value = progress * 100
		progress_bar.set_deferred("position", Vector2(0, size.y + 4))
		progress_bar.set_deferred("size", Vector2(size.x, 4))

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
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
			dragging = true
		if dragging and movable:
			position = start_position + distance
			clamp_to_area()
			modulate = Color(1, 1, 1, 0.8)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			pressed = false
			modulate = Color.WHITE
			if dragging and movable:
				dropped.emit(self)
			elif not dragging:
				clicked.emit(self)
			dragging = false

func clamp_to_area():
	position.x = clampf(position.x, drag_area.position.x, maxf(drag_area.position.x, drag_area.end.x - size.x))
	position.y = clampf(position.y, drag_area.position.y, maxf(drag_area.position.y, drag_area.end.y - size.y))

func _notification(what):
	# 切出窗口或切换页面时取消拖动，避免回来后卡片粘在鼠标上。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		pressed = false
		dragging = false
		modulate = Color.WHITE
