extends Control
# 全局只保存钱、库存、日期和菜谱；各页面通过 game 直接访问。
const Card = preload("res://card.gd")
const FloatingWindow = preload("res://floating_window.gd")
var rules = preload("res://cooking_rules.gd").new()
var PRICES = {}
var BASE_TAGS = {}
var money = 300
var day = 1
var phase = "早晨"
var inventory = {}
var detail_card = null
var notice_window
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
var notice: Label
var note_time = 0.0
var menu
var menu_content: VBoxContainer
var menu_type = ""
var inspect_text = ""

func _ready():
	for food in rules.database["foods"]:
		PRICES[food] = rules.database["foods"][food]["price"]
		BASE_TAGS[food] = " / ".join(rules.database["foods"][food]["tags"].keys())
		inventory[food] = 2
	inventory["番茄"] = 6
	inventory["鸡蛋"] = 6
	inventory["牛奶"] = 6
	inventory["小麦"] = 4
	var ui_theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	font.font_weight = 400
	ui_theme.default_font = font
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", Color("41483e"))
	theme = ui_theme
	panel(self, Rect2(0, 0, 1280, 720), "faf9f6")
	panel(self, Rect2(0, 0, 100, 720), "f0efe9")
	panel(self, Rect2(99, 0, 1, 720), "dedcd4")
	for i in range(4):
		var page = ["餐厅", "后厨", "农场", "畜棚"][i]
		nav_buttons[page] = button(self, page, Rect2(18, 32 + i * 48, 64, 32), show_page.bind(page))
	button(self, "升级", Rect2(18, 490, 64, 30), open_menu.bind("升级"))
	button(self, "仓库", Rect2(18, 570, 64, 30), open_menu.bind("仓库"))
	button(self, "商店", Rect2(18, 610, 64, 30), open_menu.bind("商店"))
	button(self, "?", Rect2(34, 664, 32, 28), open_menu.bind("帮助"))
	header = label(self, "", Rect2(144, 24, 1090, 32), 17)
	panel(self, Rect2(144, 76, 1092, 1), "e4e1da")
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
	notice_window = FloatingWindow.new()
	notice_window.game = self
	notice_window.title = "提示"
	notice_window.size_index = 0
	notice_window.position = Vector2(868, 380)
	add_child(notice_window)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_window.content.add_child(notice)
	notice_window.hide()
	show_page("餐厅")
	notify("接手这家歇业的小餐厅。先去后厨打开食材箱取食材，再回来营业。")

func label(parent, text_value, rect, font_size = 15):
	var node = Label.new()
	node.text = text_value
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("41483e"))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func style_button(node):
	node.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box = StyleBoxFlat.new()
		box.bg_color = Color("faf9f6")
		box.border_color = Color("ccc9c1")
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.content_margin_left = 10
		box.content_margin_right = 10
		if state in ["hover", "pressed", "disabled"]:
			box.bg_color = Color("e6e9e2")
			box.border_color = Color("87917f")
		node.add_theme_stylebox_override(state, box)
		node.add_theme_color_override("font_" + state + "_color", Color("41483e"))
	node.add_theme_color_override("font_color", Color("41483e"))

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
	card.kind = kind
	card.clicked.connect(track_detail_card)
	card.caption = caption
	card.drag_area = area
	parent.add_child(card)
	card.position = point
	card.clamp_to_area()
	return card

func show_page(page):
	current_page = page
	for key in pages:
		pages[key].visible = key == page
		nav_buttons[key].disabled = key == page
	if is_instance_valid(menu):
		menu.hide()
	inspect_text = ""
	if is_instance_valid(notice_window):
		notice_window.hide()
	if page == "畜棚":
		barn.update_visible()
		if barn.home_cards.is_empty():
			notify("先建鸡舍，再点击鸡舍进入饲养栏")
	elif page == "农场" and farm.plots.is_empty():
		notify("点击购买，先买田地和种子")

func _process(delta):
	header.text = current_page + "                         第 " + str(day) + " 天 · " + phase + "                         金币 " + str(money)
	if note_time > 0:
		note_time -= delta
		if note_time <= 0:
			notice.text = ""
			notice_window.hide()

func notify(message):
	if not is_instance_valid(notice):
		return
	notice.text = message
	note_time = 8.0
	notice_window.show()
	notice_window.move_to_front()

func track_detail_card(card):
	detail_card = card

func inspect(message):
	if is_instance_valid(detail_card):
		detail_card.toggle_detail(message)
	else:
		notify(message)

func weight_text(weights):
	var words = []
	for tag in weights:
		words.append(tag + " +" + str(int(weights[tag])))
	return " / ".join(words)

func dish_detail(card):
	return card.dish_name + " · " + card.cooking_method + "\n" + recipe_text({"items": card.items}) + "\n" + weight_text(card.data.get("weights", {}))

func spend(amount):
	if money < amount:
		notify("金币不足，需要 " + str(amount))
		return false
	money -= amount
	daily_cost += amount
	return true

func build_menu():
	menu = FloatingWindow.new()
	menu.game = self
	menu.title = "管理"
	menu.name = "ManagementWindow"
	menu.position = Vector2(340, 146)
	add_child(menu)
	menu_content = menu.content
	menu.hide()

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
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	style_button(node)
	node.pressed.connect(action)
	menu_content.add_child(node)
	return node

func open_menu(kind):
	if menu.visible and menu_type == kind:
		menu.hide()
		return
	menu_type = kind
	refresh_menu()
	menu.show()
	menu.move_to_front()

func refresh_menu():
	for child in menu_content.get_children():
		menu_content.remove_child(child)
		child.queue_free()
	menu.title_bar.text = menu_type
	if menu_type == "食材箱":
		for food in inventory:
			var item_button = menu_action(food + " × " + str(inventory[food]) + "  取一份", take_food.bind(food))
			item_button.disabled = inventory[food] <= 0 or current_page != "后厨"
		return
	if menu_type == "升级":
		menu_line("扩建 · 第 2 天起解锁")
		menu_action("后厨 24 → 36 张 · 60金币" if not kitchen.equipment_upgraded else "后厨已扩建", kitchen.upgrade_equipment).disabled = kitchen.equipment_upgraded
		menu_action("出餐台 3 → 6 份 · 45金币" if tray_capacity == 3 else "出餐台已扩建", upgrade_tray).disabled = tray_capacity == 6
		return
	if menu_type == "仓库":
		for food in inventory:
			menu_line(food + " × " + str(inventory[food]) + "    ·    " + BASE_TAGS[food])
	elif menu_type == "商店":
		for food in PRICES:
			menu_action(food + " × 1     " + str(PRICES[food]) + " 金币", buy_food.bind(food))
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
		menu_action("进入下一天", next_day)
	else:
		menu_line("餐厅：早晨去后厨备料，回来开门；点顾客接单，做菜后拖入出餐，再回餐厅，拖给顾客。打烊后结算。")
		menu_line("后厨：打开食材箱取食材；切 / 榨 / 磨 / 搅拌可处理整组。完成料理拖到右上「出餐！」，再去餐厅出餐台拖给顾客。")
		menu_line("农场：购买田地和种子；点击种植，从二级栏拖出种子到田地。成熟后点田地，作物散开；打开收集箱逐个拖入。")
		menu_line("畜棚：建鸡舍，点击进入；买小鸡和饲料，点投喂拖出饲料。小鸡吃两份长大，成年鸡吃饲料后产蛋；鸡蛋拖进收集箱。兔猪长大后可点击出栏获得肉。")
		menu_line("第 2 天可升级空田和设施，第 3 天开放雇员。卡片单击原地展开，再次单击收起；整组未处理的食材可双击拆分。垃圾桶会消耗拖入物品，不退还库存。")
		menu_line("拖动窗口标题栏移动；点右上方 □ 在小、中、大三档循环。升级在左下角。")
		menu_line("当前为可玩原型，退出游戏不保存。生长计时只在游戏运行期间进行。")

func buy_food(food):
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
	if phase != "夜晚":
		return
	day += 1
	phase = "早晨"
	daily_income = 0
	daily_tips = 0
	daily_cost = 0
	menu.hide()
	dining.begin_morning()
	notify("新的一天，先从食材箱取料再营业")
