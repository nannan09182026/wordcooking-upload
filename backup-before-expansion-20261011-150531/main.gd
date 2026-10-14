extends Control
# 界面和规则集中在这里。先保持直观，不拆分复杂系统。

const Card = preload("res://card.gd")
const WORK_AREA = Rect2(132, 116, 436, 470)
const TABLE_AREA = Rect2(132, 116, 1128, 470)
const INGREDIENT_NAMES = ["番茄", "鸡蛋", "土豆"]
const MAX_CARDS = 20
const MAX_GROUP = 6

var restaurant: Control
var card_layer: Control
var placeholder: Label
var status_label: Label
var info_label: Label
var selected_card = null
var nav_buttons = []
var cards = []
var pantry: Control
var notice_timer: Timer
var last_notice = ""

func _ready():
	build_interface()
	reset_table()

func make_label(parent, text_value, rect, font_size = 15):
	var label = Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("354139"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func make_button(parent, text_value, rect):
	var button = Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("faf9f6")
		style.border_color = Color("ccc9c1")
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		if state in ["hover", "pressed", "disabled"]:
			style.bg_color = Color("e6e9e2")
			style.border_color = Color("87917f")
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_" + state + "_color", Color("41483e"))
	button.add_theme_color_override("font_color", Color("41483e"))
	parent.add_child(button)
	return button

func make_panel(parent, node_name, rect, color):
	var panel = ColorRect.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.color = Color(color)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)

func build_interface():
	# 使用系统常规字重，避免中文默认回退字体显得过粗。
	var ui_theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	font.font_weight = 400
	ui_theme.default_font = font
	ui_theme.default_font_size = 15
	theme = ui_theme
	make_panel(self, "Background", Rect2(0, 0, 1280, 720), "faf9f6")
	make_panel(self, "Sidebar", Rect2(0, 0, 100, 720), "f0efe9")
	make_panel(self, "SidebarLine", Rect2(99, 0, 1, 720), "dedcd4")
	for i in range(3):
		var page = ["餐厅", "农场", "畜棚"][i]
		var button = make_button(self, page, Rect2(18, 36 + i * 52, 64, 32))
		button.name = page
		button.pressed.connect(show_page.bind(page))
		nav_buttons.append(button)
	restaurant = Control.new()
	restaurant.name = "Restaurant"
	restaurant.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(restaurant)
	make_label(restaurant, "后厨", Rect2(144, 31, 120, 28), 18)
	make_panel(restaurant, "HeaderLine", Rect2(144, 76, 1092, 1), "e4e1da")
	make_panel(restaurant, "AreaDivider", Rect2(574, 116, 1, 470), "e4e1da")
	var pantry_button = make_button(restaurant, "食材 +", Rect2(1030, 30, 80, 30))
	pantry_button.pressed.connect(toggle_pantry)
	var reset_button = make_button(restaurant, "重置", Rect2(1122, 30, 54, 30))
	reset_button.pressed.connect(reset_table)
	var help_button = make_button(restaurant, "?", Rect2(1188, 30, 30, 30))
	help_button.pressed.connect(toggle_help)
	card_layer = Control.new()
	card_layer.name = "Cards"
	card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	restaurant.add_child(card_layer)
	# 食材菜单默认折叠，需要补充时才展开。
	pantry = Control.new()
	pantry.name = "PantryMenu"
	pantry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	restaurant.add_child(pantry)
	for i in range(INGREDIENT_NAMES.size()):
		var ingredient_name = INGREDIENT_NAMES[i]
		var button = make_button(pantry, ingredient_name + " +", Rect2(946 + i * 94, 86, 84, 30))
		button.pressed.connect(add_ingredient.bind(ingredient_name))
	pantry.hide()
	status_label = make_label(restaurant, "", Rect2(144, 600, 1080, 28), 14)
	status_label.add_theme_color_override("font_color", Color("82867a"))
	info_label = make_label(restaurant, "", Rect2(144, 644, 1040, 56), 14)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_timer = Timer.new()
	notice_timer.one_shot = true
	notice_timer.wait_time = 3.0
	notice_timer.timeout.connect(clear_notice)
	add_child(notice_timer)
	placeholder = make_label(self, "", Rect2(540, 300, 300, 100), 18)
	placeholder.name = "Placeholder"
	show_page("餐厅")

func toggle_pantry():
	pantry.visible = not pantry.visible

func toggle_help():
	selected_card = null
	if info_label.text != "":
		info_label.text = ""
	else:
		info_label.text = "食材拖到切 / 榨进行处理；食材叠放成组，再拖到煮 / 炸 / 炒。\n单击查看说明，再次单击关闭。点击右上角「食材 +」补充。"

func _process(_delta):
	# 提示只短暂出现，不长期占用桌面。
	if status_label.text != last_notice:
		last_notice = status_label.text
		if last_notice != "":
			notice_timer.start()

func clear_notice():
	status_label.text = ""

func show_page(page):
	restaurant.visible = page == "餐厅"
	placeholder.visible = page != "餐厅"
	placeholder.text = page + " · 暂未开放"
	for button in nav_buttons:
		button.disabled = button.text == page

func reset_table():
	for card in cards:
		card.queue_free()
	cards.clear()
	selected_card = null
	info_label.text = ""
	pantry.hide()
	for i in range(5):
		var tool = create_card("tool", [])
		tool.tool_name = ["切", "榨", "煮", "炸", "炒"][i]
		tool.drag_area = WORK_AREA
		if i < 2:
			tool.position = Vector2(214 + i * 132, 224)
		else:
			tool.position = Vector2(180 + (i - 2) * 110, 394)
		tool.refresh()
	for ingredient_name in INGREDIENT_NAMES:
		add_ingredient(ingredient_name)
	status_label.text = ""

func create_card(kind, items):
	var card = Card.new()
	card.name = "Card"
	card.kind = kind
	card.items = items.duplicate(true)
	card.drag_area = TABLE_AREA
	card.clicked.connect(on_card_clicked)
	card.dropped.connect(on_card_dropped)
	card_layer.add_child(card)
	cards.append(card)
	return card

func add_ingredient(ingredient_name):
	if cards.size() >= MAX_CARDS:
		status_label.text = "桌面最多 20 张卡片（含工具），请先组合、烹饪或重置。"
		return
	var card = create_card("ingredient", [{"name": ingredient_name, "process": ""}])
	place_near(card, Vector2(720 + INGREDIENT_NAMES.find(ingredient_name) * 140, 224))
	status_label.text = "已补充 " + ingredient_name + ""

func remove_card(card):
	if selected_card == card:
		selected_card = null
		info_label.text = ""
	cards.erase(card)
	card.hide()
	card.queue_free()

func on_card_dropped(card):
	if card.kind != "ingredient":
		return
	# 使用卡片中心判断目标；从最上层卡片开始找，避免同时触发两个目标。
	var center = card.position + card.size / 2
	var layers = card_layer.get_children()
	layers.reverse()
	for target in layers:
		if target == card or not cards.has(target):
			continue
		if not Rect2(target.position, target.size).has_point(center):
			continue
		if target.kind == "tool":
			use_tool(card, target)
			return
		if target.kind == "ingredient":
			if target.items.size() + card.items.size() > MAX_GROUP:
				status_label.text = "每组最多 6 份食材"
				place_near(card, card.start_position)
				return
			target.items.append_array(card.items.duplicate(true))
			remove_card(card)
			target.refresh()
			place_near(target, target.position)
			status_label.text = "已组合，共 " + str(target.items.size()) + " 份食材"
			update_info()
			return

func use_tool(card, tool):
	if tool.tool_name in ["切", "榨"]:
		if card.items.size() > 1:
			status_label.text = "请先处理单份食材，再叠放成组。"
		else:
			# 本原型只保留最近一次处理：榨之后再切，会变成 [切]。
			card.items[0]["process"] = tool.tool_name
			card.refresh()
			status_label.text = "已" + tool.tool_name + "好 " + card.items[0]["name"] + ""
		place_near(card, tool.position + Vector2(0, tool.size.y + 12))
		update_info()
		return
	if card.items.size() < 2:
		status_label.text = "先把至少两份食材叠放成组，再拖到烹饪工具。"
		place_near(card, tool.position + Vector2(0, tool.size.y + 12))
		return
	card.kind = "dish"
	card.cooking_method = tool.tool_name
	card.tags = calculate_tags(card.items, tool.tool_name)
	card.refresh()
	place_near(card, Vector2(626, 400))
	status_label.text = "完成：未知料理 · " + " / ".join(card.tags)
	update_info()

func calculate_tags(items, method):
	var counts = {}
	var result = []
	var has_juiced = false
	for item in items:
		var ingredient_name = item["name"]
		counts[ingredient_name] = counts.get(ingredient_name, 0) + 1
		if item["process"] == "榨":
			has_juiced = true
	for ingredient_name in counts:
		if counts[ingredient_name] >= 2:
			result.append("超浓")
			break
	if has_juiced:
		result.append("细腻")
	result.append({"炸": "酥脆", "炒": "炒制", "煮": "温润"}[method])
	return result

func place_near(card, preferred):
	# 在桌面网格里找离目标最近的空位，不让处理后的食材盖住工具。
	var best_position = Vector2.ZERO
	var best_distance = INF
	for y in range(164, 570, 24):
		for x in range(144, 1248, 24):
			var candidate = Vector2(x, y)
			var rect = Rect2(candidate, card.size)
			if not TABLE_AREA.encloses(rect):
				continue
			var free = true
			for other in cards:
				if other != card and rect.grow(6).intersects(Rect2(other.position, other.size)):
					free = false
					break
			if free and candidate.distance_squared_to(preferred) < best_distance:
				best_distance = candidate.distance_squared_to(preferred)
				best_position = candidate
	if best_distance < INF:
		card.position = best_position
	else:
		card.position = preferred
		status_label.text += "（桌面拥挤，可拖开卡片或重置。）"
	card.clamp_to_area()

func on_card_clicked(card):
	if selected_card == card:
		selected_card = null
		info_label.text = ""
	else:
		selected_card = card
		update_info()

func update_info():
	if not is_instance_valid(selected_card):
		return
	var card = selected_card
	if card.kind == "tool":
		if card.tool_name in ["切", "榨"]:
			info_label.text = card.tool_name + " · 处理单份食材，替换原有处理状态。"
		else:
			info_label.text = card.tool_name + " · 将食材组拖到此处烹饪。"
	elif card.kind == "dish":
		info_label.text = "未知料理 · " + card.cooking_method + " · 使用 " + str(card.items.size()) + " 份食材\n标签：" + " / ".join(card.tags) + ""
	else:
		info_label.text = card.title_label.text.replace("\n", "；") + "\n可拖到工具上处理，或与其他食材叠放。"
