extends Control
# 全局只保存钱、库存、日期和菜谱；各页面通过 game 直接访问。
const Card = preload("res://card.gd")
const PRICES = {"番茄": 2, "鸡蛋": 2, "土豆": 2, "小麦": 2, "兔肉": 4, "猪肉": 4}
const BASE_TAGS = {"番茄": "酸甜", "鸡蛋": "鲜香", "土豆": "饱腹", "小麦": "谷物", "兔肉": "鲜香", "猪肉": "丰腴"}
var money = 300
var day = 1
var phase = "早晨"
var inventory = {"番茄": 6, "鸡蛋": 6, "土豆": 4, "小麦": 0, "兔肉": 0, "猪肉": 0}
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
var menu: PanelContainer
var menu_content: VBoxContainer
var menu_type = ""
var inspect_text = ""

func _ready():
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
	notice = label(self, "", Rect2(150, 674, 1080, 34), 14)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_menu()
	show_page("餐厅")
	notify("接手这家歇业的小餐厅。先去后厨从仓库备料，再回来营业。")

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

func notify(message):
	if not is_instance_valid(notice):
		return
	notice.text = message
	note_time = 6.0

func inspect(message):
	if inspect_text == message:
		inspect_text = ""
		notice.text = ""
	else:
		inspect_text = message
		notify(message)
		note_time = 0

func spend(amount):
	if money < amount:
		notify("金币不足，需要 " + str(amount))
		return false
	money -= amount
	daily_cost += amount
	return true

func build_menu():
	menu = PanelContainer.new()
	menu.name = "ManagementMenu"
	menu.position = Vector2(298, 146)
	menu.size = Vector2(840, 494)
	var box = StyleBoxFlat.new()
	box.bg_color = Color("f4f3ed")
	box.border_color = Color("a6a89e")
	box.set_border_width_all(1)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	menu.add_theme_stylebox_override("panel", box)
	add_child(menu)
	var scroll = ScrollContainer.new()
	menu.add_child(scroll)
	menu_content = VBoxContainer.new()
	menu_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_content.add_theme_constant_override("separation", 12)
	scroll.add_child(menu_content)
	menu.hide()

func menu_line(text_value):
	var node = Label.new()
	node.text = text_value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size.x = 760
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
	menu_action(menu_type + " · 关闭 ×", menu.hide)
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
		menu_line("餐厅：早晨去后厨备料，回来开门；点顾客接单，做菜后端回餐厅，拖给顾客。打烊后结算。")
		menu_line("后厨：从仓库取食材；单份拖到切 / 榨，食材叠放成组后煮 / 炸 / 炒。选中成品点端菜。")
		menu_line("农场：购买田地和种子；点击种植，从二级栏拖出种子到田地。成熟后点田地，作物散开；打开收集箱逐个拖入。")
		menu_line("畜棚：建鸡舍，点击进入；买小鸡和饲料，点投喂拖出饲料。小鸡吃两份长大，成年鸡吃饲料后产蛋；鸡蛋拖进收集箱。兔猪长大后可点击出栏获得肉。")
		menu_line("第 2 天可升级空田和设施，第 3 天开放雇员。所有卡片单击查看、再次单击关闭；拖动超过 8 像素才算拖动。")
		menu_line("当前为可玩原型，退出游戏不保存。生长计时只在游戏运行期间进行。")

func buy_food(food):
	if spend(PRICES[food]):
		inventory[food] += 1
		notify("已购买 " + food)

func recipe_key(items, method):
	var parts = []
	for item in items:
		parts.append(item["name"] + ":" + item["process"])
	parts.sort()
	return method + "|" + "|".join(parts)

func record_recipe(card):
	var key = recipe_key(card.items, card.cooking_method)
	for i in range(recipes.size()):
		if recipes[i]["key"] == key:
			return i
	var cost = 0
	for item in card.items:
		cost += PRICES[item["name"]]
	recipes.append({"key": key, "name": "料理 " + str(recipes.size() + 1), "items": card.items.duplicate(true), "method": card.cooking_method, "tags": card.tags.duplicate(), "base": cost * 2 + 4, "markup": 0, "listed": false})
	notify("发现新菜谱，可在餐厅上架")
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
	notify("新的一天，先备料再营业")
