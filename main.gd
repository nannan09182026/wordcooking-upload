extends Control
# 全局只保存钱、库存、日期和菜谱；各页面通过 game 直接访问。
const Card = preload("res://card.gd")
const FloatingWindow = preload("res://floating_window.gd")
var feedback
var catalog
var status_label: Label
var rules = preload("res://cooking_rules.gd").new()
var PRICES = {}
var BASE_TAGS = {}
var money = 300
var day = 1
var phase = "早晨"
var inventory = {}
var shops = {"中级": false, "高级": false}
var detail_card = null
var tray_capacity = 3
var recipes = []
var staff = {"前台": false, "主厨": false, "传菜": false}
var learned = {}
var daily_income = 0
var daily_tips = 0
var daily_cost = 0
var current_page = "餐厅"
var pages = {}
var nav_buttons = {}
var kitchen
var farm
var barn
var dining
var header: Label
var menu
var menu_content: VBoxContainer
var menu_type = ""
var inspect_text = ""
var slot_id = 0 # 0 为直接运行 main.tscn 的测试模式；正式游戏从开始界面选择1～3。
var title_screen = null
var save_system = preload("res://save_game.gd").new()
var last_save_ok = true
var save_status = ""
var supplies # 食材箱和采购簿的界面
var menu_veil: ColorRect
var veil_tween
var page_help: Control
var page_help_text: Label
var page_help_seen = {"农场": false, "畜棚": false}

func _ready():
	for food in rules.database["foods"]:
		PRICES[food] = rules.database["foods"][food]["price"]
		BASE_TAGS[food] = " / ".join(rules.database["foods"][food]["tags"].keys())
		inventory[food] = 2 if rules.database["foods"][food].get("tier", 0) == 0 else 0
	inventory["番茄"] = 6
	inventory["鸡蛋"] = 6
	inventory["牛奶"] = 6
	inventory["小麦"] = 4
	feedback = load("res://feedback.gd").new()
	feedback.game = self
	add_child(feedback)
	catalog = load("res://catalog.gd").new()
	catalog.game = self
	add_child(catalog)
	var ui_theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	font.font_weight = 400
	ui_theme.default_font = font
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", Color("4a3428"))
	for control_type in ["VScrollBar", "HSlider"]:
		for style_name in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed", "slider", "grabber_area", "grabber_area_highlight"]:
			var style = StyleBoxFlat.new()
			style.bg_color = Color("d2a27e") if "grabber" in style_name else Color("f8ebdd")
			style.set_corner_radius_all(3)
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 3
			style.content_margin_bottom = 3
			ui_theme.set_stylebox(style_name, control_type, style)
	theme = ui_theme
	panel(self, Rect2(0, 0, 1280, 720), "fff8f0")
	panel(self, Rect2(0, 0, 100, 720), "f8ebdd")
	panel(self, Rect2(99, 0, 1, 720), "e5ccb4")
	for i in range(4):
		var page = ["餐厅", "后厨", "农场", "畜棚"][i]
		nav_buttons[page] = button(self, page, Rect2(18, 32 + i * 48, 64, 32), show_page.bind(page))
	button(self, "图鉴", Rect2(18, 440, 64, 30), open_menu.bind("图鉴"))
	button(self, "设置", Rect2(18, 530, 64, 30), open_menu.bind("设置"))
	button(self, "升级", Rect2(18, 485, 64, 30), open_menu.bind("升级"))
	button(self, "仓库", Rect2(18, 570, 64, 30), open_menu.bind("仓库"))
	button(self, "商店", Rect2(18, 610, 64, 30), open_menu.bind("商店"))
	button(self, "?", Rect2(34, 664, 32, 28), open_menu.bind("帮助"))
	header = label(self, "", Rect2(144, 26, 240, 32), 18)
	status_label = label(self, "", Rect2(830, 28, 396, 28), 14)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel(self, Rect2(144, 76, 1092, 1), "ecd9c7")
	kitchen = load("res://kitchen.gd").new()
	farm = load("res://farm.gd").new()
	barn = load("res://barn.gd").new()
	dining = load("res://dining.gd").new()
	pages = {"餐厅": dining, "后厨": kitchen, "农场": farm, "畜棚": barn}
	for page in pages:
		var node = pages[page]
		node.game = self
		node.name = {"餐厅": "Restaurant", "后厨": "Kitchen", "农场": "Farm", "畜棚": "Barn"}[page]
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(node)
	build_menu()
	supplies = load("res://supplies.gd").new()
	supplies.name = "Supplies"
	supplies.game = self
	add_child(supplies)
	build_page_help()
	show_page("餐厅")
	notify("接手这家歇业的小餐厅。先去后厨打开食材箱取食材，再回来营业。")

func label(parent, text_value, rect, font_size = 15):
	var node = Label.new()
	node.text = text_value
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("4a3428"))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func style_button(node):
	node.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box = StyleBoxFlat.new()
		box.bg_color = Color("fff8f0")
		box.border_color = Color("e5ccb4")
		box.set_border_width_all(1)
		box.set_corner_radius_all(4)
		box.content_margin_left = 10
		box.content_margin_right = 10
		if state in ["hover", "pressed", "disabled"]:
			box.bg_color = Color("ffe0c2")
			box.border_color = Color("c9793f")
		if state == "pressed":
			box.bg_color = Color("f6cda7")
		if state == "disabled":
			box.bg_color = Color("f2f1ec")
			box.border_color = Color("e2dfd6")
		if state == "focus":
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = Color("b85722")
		node.add_theme_stylebox_override(state, box)
		node.add_theme_color_override("font_" + state + "_color", Color("4a3428"))
	node.add_theme_color_override("font_disabled_color", Color("92968c"))
	node.add_theme_color_override("font_color", Color("4a3428"))
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.button_down.connect(feedback.button_down.bind(node))
	node.button_up.connect(feedback.button_up.bind(node))
	node.mouse_exited.connect(feedback.button_up.bind(node))
	node.pressed.connect(feedback.click_sound)

func button(parent, text_value, rect, action):
	var node = Button.new()
	node.text = text_value
	node.position = rect.position
	node.size = rect.size
	style_button(node)
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func panel(parent, rect, color):
	var node = ColorRect.new()
	node.position = rect.position
	node.size = rect.size
	node.color = Color(color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func make_card(parent, kind, caption, point, area = Rect2(286, 148, 940, 458)):
	var card = Card.new()
	card.feedback = feedback
	card.kind = kind
	card.clicked.connect(track_detail_card)
	card.caption = caption
	card.drag_area = area
	parent.add_child(card)
	card.position = point
	card.clamp_to_area()
	return card

func show_page(page):
	page_help.hide()
	var previous_page = current_page
	feedback.highlight(null)
	feedback.toast.hide()
	current_page = page
	for key in pages:
		pages[key].visible = key == page
		nav_buttons[key].disabled = key == page and not key in ["农场", "畜棚"]
		var active_style = nav_buttons[key].get_theme_stylebox("disabled").duplicate()
		active_style.border_width_left = 3
		active_style.bg_color = Color("ffe0c2")
		active_style.border_color = Color("c9793f")
		nav_buttons[key].add_theme_stylebox_override("disabled", active_style)
		nav_buttons[key].add_theme_color_override("font_disabled_color", Color("4a3428"))
		var normal_style = nav_buttons[key].get_theme_stylebox("normal").duplicate()
		normal_style.border_width_left = 3 if key == page else 1
		normal_style.bg_color = Color("ffe0c2") if key == page else Color("fff8f0")
		normal_style.border_color = Color("c9793f") if key == page else Color("e5ccb4")
		nav_buttons[key].add_theme_stylebox_override("normal", normal_style)
	if is_instance_valid(menu):
		menu.hide()
	inspect_text = ""
	if page == "畜棚":
		barn.update_visible()
		if previous_page != page:
			barn.greet_pen()
	if page_help_seen.has(page) and (not page_help_seen[page] or previous_page == page):
		page_help_seen[page] = true
		show_page_help(page)

func _process(_delta):
	header.text = current_page
	status_label.text = "第 %d 天 · %s    /    金币 %d" % [day, phase, money]

func notify(message):
	feedback.show_toast(message)

func track_detail_card(card):
	detail_card = card

func inspect(message):
	if is_instance_valid(detail_card):
		detail_card.toggle_detail(message)
	else:
		notify(message)

func weight_text(weights):
	var words = []
	var lines = []
	for tag in weights:
		words.append(tag + " +" + str(int(weights[tag])))
		if words.size() == 2:
			lines.append(" / ".join(words))
			words.clear()
	if not words.is_empty():
		lines.append(" / ".join(words))
	return "\n".join(lines)

func dish_detail(card):
	return "制作 · " + card.cooking_method + "\n" + recipe_text({"items": card.items}).replace(" + ", "\n") + "\n\n" + weight_text(card.data.get("weights", {}))

func spend(amount):
	if money < amount:
		notify("金币不足，需要 " + str(amount))
		return false
	money -= amount
	daily_cost += amount
	return true

func build_menu():
	menu_veil = ColorRect.new()
	menu_veil.name = "WindowVeil"
	menu_veil.color = Color(0.98, 0.97, 0.94, 0.4)
	menu_veil.size = Vector2(1280, 720)
	menu_veil.gui_input.connect(veil_input)
	add_child(menu_veil)
	menu_veil.hide()
	menu = FloatingWindow.new()
	menu.game = self
	menu.title = "管理"
	menu.name = "ManagementWindow"
	menu.position = Vector2(340, 146)
	add_child(menu)
	menu_content = menu.content
	menu.visibility_changed.connect(sync_veil)
	menu.hide()

func sync_veil():
	if veil_tween and veil_tween.is_valid():
		veil_tween.kill()
	menu_veil.visible = menu.visible
	if menu.visible:
		menu_veil.modulate.a = 0
		veil_tween = create_tween()
		veil_tween.tween_property(menu_veil, "modulate:a", 1.0, 0.01 if feedback.reduced_motion else 0.15)

func veil_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		menu_veil.accept_event()
		if event.pressed:
			menu.hide()

func _input(event):
	if is_instance_valid(page_help) and page_help.visible:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			page_help.hide()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_instance_valid(supplies) and supplies.source_food != "":
			return # 拖出食材时，由食材箱取消拖动。
		menu.hide()
		feedback.toast.hide()
		get_viewport().set_input_as_handled()

func menu_line(text_value):
	var node = Label.new()
	node.text = text_value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_content.add_child(node)
	return node

func menu_action(text_value, action):
	var node = Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 32
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	style_button(node)
	node.pressed.connect(action)
	menu_content.add_child(node)
	return node

func open_menu(kind):
	feedback.toast.hide()
	if menu.visible and menu_type == kind:
		menu.hide()
		return
	menu_type = kind
	refresh_menu()
	menu.show()
	menu.move_to_front()

func refresh_menu():
	menu.reset_header()
	for child in menu_content.get_children():
		menu_content.remove_child(child)
		child.queue_free()
	menu.title_bar.text = menu_type
	if menu_type == "图鉴":
		catalog.build()
		return
	if menu_type == "设置":
		menu_line("声音与动效")
		var music = get_node("/root/Music")
		menu_line("背景音乐")
		menu_action("开启音乐" if music.muted else "关闭音乐", toggle_music)
		var music_slider = HSlider.new()
		music_slider.min_value = 0
		music_slider.max_value = 1
		music_slider.step = 0.01
		music_slider.value = music.volume
		music_slider.custom_minimum_size = Vector2(220, 30)
		music_slider.value_changed.connect(music.set_volume)
		menu_content.add_child(music_slider)

		menu_action("开启音效" if feedback.muted else "静音", feedback.toggle_mute)
		menu_line("音效音量")
		var slider = HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.value = feedback.volume
		slider.custom_minimum_size = Vector2(220, 30)
		slider.value_changed.connect(feedback.set_volume)
		menu_content.add_child(slider)
		menu_action("试听", feedback.play.bind("discover"))
		menu_action("减少动态效果：" + ("开" if feedback.reduced_motion else "关"), feedback.toggle_motion)
		menu_line("打烊结算后自动保存这家小店的全部进度；当天未打烊的操作不会保存。声音设置随时保存。")
		if title_screen != null:
			menu_action("返回开始界面", open_menu.bind("返回确认"))
		return
	if menu_type == "返回确认":
		menu_line("返回后将从最近的打烊存档继续。今天尚未保存的操作会丢弃。")
		menu_action("留在小店", open_menu.bind("设置"))
		menu_action("返回并选择存档", title_screen.return_to_title)
		return
	if menu_type == "食材箱":
		supplies.build_pantry()
		return
	if menu_type == "商店":
		supplies.build_shop()
		return
	if menu_type == "升级":
		menu_line("扩建 · 第 2 天起解锁")
		menu_action("后厨 24 → 36 张 · 60金币" if not kitchen.equipment_upgraded else "后厨已扩建", kitchen.upgrade_equipment).disabled = kitchen.equipment_upgraded
		menu_action("出餐台 3 → 6 份 · 45金币" if tray_capacity == 3 else "出餐台已扩建", upgrade_tray).disabled = tray_capacity == 6
		return
	if menu_type == "仓库":
		supplies.build_warehouse()
	elif menu_type == "菜谱":
		if recipes.is_empty():
			menu_line("尚未发现菜谱。到后厨自由组合，完成料理后自动记录。")
		for i in range(recipes.size()):
			var recipe = recipes[i]
			menu_line(recipe["name"] + " · " + recipe["method"] + " · " + " / ".join(recipe["tags"]) + "\n" + recipe_text(recipe))
			menu_line("基础价 " + str(recipe["base"]) + "    售价 " + str(recipe_price(recipe)) + "    调价 " + str(recipe["markup"]) + "%")
			menu_action("上架" if not recipe["listed"] else "下架", toggle_recipe.bind(i))
			menu_action("降价 10%", change_price.bind(i, -10))
			menu_action("涨价 10%", change_price.bind(i, 10))
	elif menu_type == "员工":
		menu_line("第 3 天起可雇人。每位入职费 50，每天工资 6。可在早晨解雇。")
		menu_line("前台自动接单；主厨用已备食材按上架菜谱制作；传菜员自动端菜并上菜。")
		for role in staff:
			menu_action(role + (" · 已雇用 / 解雇" if staff[role] else " · 雇用 50"), hire.bind(role))
	elif menu_type == "顾客":
		for person in dining.PEOPLE:
			var known = learned.get(person["name"], [])
			menu_line(person["name"] + "    已发现：" + (" / ".join(known) if not known.is_empty() else "？"))
	elif menu_type == "结算":
		menu_line(dining.last_summary)
		if slot_id > 0:
			menu_line(save_status)
			if not last_save_ok:
				menu_action("重试保存", retry_save)
		menu_action("进入下一天", next_day).disabled = not last_save_ok
	else:
		menu_line("餐厅：早晨去后厨备料，回来开门；点顾客接单，做菜后拖入出餐，再回餐厅，拖给顾客。打烊后结算。")
		menu_line("后厨：打开食材箱取食材；切 / 榨 / 磨 / 搅拌可处理整组。完成料理拖到右上「出餐！」，再去餐厅出餐台拖给顾客。")
		menu_line("农场：购买田地和种子；点击种植，从二级栏拖出种子到田地。成熟后点田地，作物散开；打开收集箱逐个拖入。")
		menu_line("畜棚：建鸡舍，点击进入；买小鸡和饲料，点投喂拖出饲料。小鸡吃两份长大，成年鸡吃饲料后产蛋；鸡蛋拖进收集箱。兔猪长大后可点击出栏获得肉。")
		menu_line("第 2 天可升级空田和设施，第 3 天开放雇员。卡片单击原地展开，再次单击收起；整组未处理的食材可双击拆分。垃圾桶会消耗拖入物品，不退还库存。")
		menu_line("拖动窗口标题栏移动；点右上方 □ 在小、中、大三档循环。升级在左下角。")
		menu_line("打烊后自动保存金币、库存、菜谱、农场和动物。继续游戏会回到已保存的结算；进入下一天后继续经营。图鉴随各存档独立保存。")

func buy_food(food):
	if not supplies.can_buy(food):
		return
	if spend(PRICES[food]):
		inventory[food] += 1
		notify("已购买 " + food)

func take_food(food):
	kitchen.add_ingredient(food)
	refresh_menu()

func upgrade_tray():
	if day < 2 or tray_capacity == 6:
		notify("第 2 天起可扩建出餐台一次")
		return
	if spend(45):
		tray_capacity = 6
		dining.update_tray()
		refresh_menu()

func recipe_key(items, method):
	return rules.key(items, method)

func record_recipe(card):
	var key = recipe_key(card.items, card.cooking_method)
	for i in range(recipes.size()):
		if recipes[i]["key"] == key:
			return i
	var cost = 0
	for item in card.items:
		cost += PRICES[item["name"]]
	recipes.append({"key": key, "name": card.dish_name, "items": card.items.duplicate(true), "method": card.cooking_method, "tags": card.tags.duplicate(), "weights": card.data["weights"].duplicate(), "base": cost * 2 + 4, "markup": 0, "listed": false})

	card.set_meta("new_discovery", catalog.discover(recipes.back()))
	return recipes.size() - 1

func recipe_text(recipe):
	var words = []
	for item in recipe["items"]:
		words.append(item["name"] + (" [" + item["process"] + "]" if item["process"] != "" else ""))
	return " + ".join(words)

func recipe_price(recipe):
	return int(round(recipe["base"] * (1.0 + recipe["markup"] / 100.0)))

func toggle_recipe(index):
	recipes[index]["listed"] = not recipes[index]["listed"]
	refresh_menu()

func change_price(index, amount):
	recipes[index]["markup"] = clampi(recipes[index]["markup"] + amount, -30, 50)
	refresh_menu()
	notify("价格影响下一次营业的来客量；已接订单保持报价。")

func hire(role):
	if day < 3 or phase != "早晨":
		notify("第 3 天起，早晨可雇用或解雇")
		return
	if staff[role]:
		staff[role] = false
	elif spend(50):
		staff[role] = true
	refresh_menu()

func next_day():
	if phase != "夜晚" or not last_save_ok:
		return
	day += 1
	phase = "早晨"
	daily_income = 0
	daily_tips = 0
	daily_cost = 0
	menu.hide()
	dining.begin_morning()
	notify("新的一天，先从食材箱取料再营业")

func autosave():
	if slot_id == 0:
		return true
	last_save_ok = save_system.write_slot(slot_id, save_system.capture(self))
	save_status = "已自动保存 · 存档 %02d · 第 %d 天" % [slot_id, day] if last_save_ok else save_system.error_text
	return last_save_ok

func retry_save():
	autosave()
	refresh_menu()

func toggle_music():
	get_node("/root/Music").toggle_mute()
	refresh_menu()

func build_page_help():
	page_help = Control.new()
	page_help.name = "PageHelp"
	page_help.size = Vector2(1280, 720)
	page_help.z_index = 50
	page_help.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(page_help)
	var card = Panel.new()
	card.position = Vector2(410, 250)
	card.size = Vector2(460, 220)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color("fffdfa")
	style.border_color = Color("d6b99f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.08)
	style.shadow_size = 8
	card.add_theme_stylebox_override("panel", style)
	page_help.add_child(card)
	page_help_text = label(card, "", Rect2(28, 24, 404, 140), 16)
	page_help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_help_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var footer = label(card, "点击任意处关闭 · 再点左侧入口可重看", Rect2(28, 178, 404, 22), 12)
	footer.add_theme_color_override("font_color", Color("939184"))
	page_help.hide()

func show_page_help(page):
	feedback.toast.hide()
	page_help_text.text = "农场\n\n购买田地和种子，将种子拖到空田上。\n成熟后点击田地，再把作物拖进收集箱。" if page == "农场" else "畜棚\n\n建好兽舍，点击进入，购买幼崽和饲料。\n投喂帮助幼崽长大，产物拖进收集箱。"
	page_help.show()
