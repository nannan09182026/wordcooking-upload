extends Control
# 界面和规则集中在这里。先保持直观，不拆分复杂系统。

const Card = preload("res://card.gd")
const WORK_AREA = Rect2(132, 116, 436, 470)
const TABLE_AREA = Rect2(132, 116, 1128, 470)
const INGREDIENT_NAMES = ["番茄", "鸡蛋", "土豆", "小麦", "兔肉", "猪肉"]
var game
var take_buttons = []
var equipment_upgraded = false
const MAX_CARDS = 20
const MAX_GROUP = 6

var card_layer: Control
var status_label: Label
var info_label: Label
var selected_card = null
var cards = []
var pantry: Control
var notice_timer: Timer
var last_notice = ""

func _ready():
	build_interface()
	reset_table()

func build_interface():
	game.panel(self, Rect2(574, 148, 1, 438), "e4e1da")
	game.button(self, "备料", Rect2(144, 94, 70, 30), toggle_pantry)
	game.button(self, "放回", Rect2(226, 94, 70, 30), return_selected)
	game.button(self, "端菜", Rect2(308, 94, 70, 30), carry_selected)
	game.button(self, "整理", Rect2(390, 94, 70, 30), reset_table)
	game.button(self, "扩建 · 60", Rect2(478, 94, 104, 30), upgrade_equipment)
	game.button(self, "?", Rect2(1190, 94, 30, 30), toggle_help)
	card_layer = Control.new()
	card_layer.name = "Cards"
	card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card_layer)
	pantry = Control.new()
	pantry.name = "PantryMenu"
	pantry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pantry)
	for i in range(INGREDIENT_NAMES.size()):
		var food = INGREDIENT_NAMES[i]
		var button = game.button(pantry, food, Rect2(610 + (i % 3) * 190, 94 + (i / 3) * 38, 180, 30), add_ingredient.bind(food))
		take_buttons.append(button)
	pantry.hide()
	status_label = game.label(self, "", Rect2(144, 606, 1080, 28), 14)
	info_label = game.label(self, "", Rect2(144, 638, 1080, 30), 14)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_timer = Timer.new()
	notice_timer.one_shot = true
	notice_timer.wait_time = 3.0
	notice_timer.timeout.connect(clear_notice)
	add_child(notice_timer)

func toggle_pantry():
	pantry.visible = not pantry.visible

func toggle_help():
	selected_card = null
	if info_label.text != "":
		info_label.text = ""
	else:
		info_label.text = "食材拖到切 / 榨进行处理；食材叠放成组，再拖到煮 / 炸 / 炒。\n单击查看说明，再次单击关闭。点击「备料」从仓库拿取；单击成品后点「端菜」。"

func _process(_delta):
	for i in range(take_buttons.size()):
		var food = INGREDIENT_NAMES[i]
		take_buttons[i].text = food + " × " + str(game.inventory[food])
		take_buttons[i].disabled = game.inventory[food] <= 0
	# 提示只短暂出现，不长期占用桌面。
	if status_label.text != last_notice:
		last_notice = status_label.text
		if last_notice != "":
			notice_timer.start()

func clear_notice():
	status_label.text = ""

func reset_table():
	# 整理只归还食材并重新摆好工具，成品保留，防止凭空刷食材。
	for card in cards.duplicate():
		if card.kind == "ingredient":
			for item in card.items:
				game.inventory[item["name"]] += 1
			remove_card(card)
		elif card.kind == "tool":
			remove_card(card)
	selected_card = null
	info_label.text = ""
	pantry.hide()
	for i in range(5):
		var tool = create_card("tool", [])
		tool.tool_name = ["切", "榨", "煮", "炸", "炒"][i]
		tool.drag_area = WORK_AREA
		tool.position = Vector2(214 + i * 132, 224) if i < 2 else Vector2(180 + (i - 2) * 110, 394)
		tool.refresh()
	status_label.text = ""

func return_selected():
	if not is_instance_valid(selected_card) or selected_card.kind != "ingredient":
		game.notify("先单击选中要放回的食材或食材组")
		return
	for item in selected_card.items:
		game.inventory[item["name"]] += 1
	remove_card(selected_card)
	game.notify("已放回仓库；处理状态清除")

func carry_selected():
	if not is_instance_valid(selected_card) or selected_card.kind != "dish":
		game.notify("先单击选中料理，再端菜")
		return
	if game.dining.add_dish(selected_card):
		remove_card(selected_card)
		game.show_page("餐厅")

func prepared_count():
	var total = 0
	for card in cards:
		if card.kind in ["ingredient", "dish"]:
			total += card.items.size()
	return total

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
	if game.inventory[ingredient_name] <= 0:
		game.notify("仓库没有 " + ingredient_name + "，可到商店购买或自行生产")
		return
	if cards.size() >= (32 if equipment_upgraded else MAX_CARDS):
		status_label.text = "桌面最多 20 张卡片（含工具），请先组合、烹饪或重置。"
		return
	game.inventory[ingredient_name] -= 1
	var card = create_card("ingredient", [{"name": ingredient_name, "process": ""}])
	place_near(card, Vector2(690 + (INGREDIENT_NAMES.find(ingredient_name) % 3) * 155, 224))
	status_label.text = "已补充 " + ingredient_name + ""

func upgrade_equipment():
	if game.day < 2 or equipment_upgraded:
		game.notify("第 2 天起可扩建一次，工作台容量由 20 增至 32 张")
		return
	if game.spend(60):
		equipment_upgraded = true
		game.notify("后厨已扩建，可摆放 32 张卡片")

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
	card.data["recipe"] = game.record_recipe(card)
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
	# 食材本身的标签也参与成品，避免换食材后标签完全不变。
	for item in items:
		var base_tag = game.BASE_TAGS[item["name"]]
		if not result.has(base_tag):
			result.append(base_tag)
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
		info_label.text = card.title_label.text.replace("\n", "；") + " · " + game.BASE_TAGS[card.items[0]["name"]] + " · 可处理或叠放"

func auto_cook(recipe_index):
	# 主厨只从桌面备料取用，不凭空生成；先检查齐全再统一扣除。
	var recipe = game.recipes[recipe_index]
	var candidates = []
	for card in cards:
		if card.kind == "ingredient":
			for item in card.items:
				candidates.append({"card": card, "item": item, "used": false})
	var chosen = []
	for wanted in recipe["items"]:
		var found = -1
		for i in range(candidates.size()):
			if not candidates[i]["used"] and candidates[i]["item"]["name"] == wanted["name"]:
				found = i
				break
		if found == -1:
			return false
		candidates[found]["used"] = true
		chosen.append(found)
	for index in chosen:
		var source = candidates[index]
		source["card"].items.erase(source["item"])
	for card in cards.duplicate():
		if card.kind == "ingredient":
			if card.items.is_empty():
				remove_card(card)
			else:
				card.refresh()
	var dish = create_card("dish", recipe["items"])
	dish.cooking_method = recipe["method"]
	dish.tags = recipe["tags"].duplicate()
	dish.data["recipe"] = recipe_index
	dish.refresh()
	place_near(dish, Vector2(700, 400))
	return true
