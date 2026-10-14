extends Control
# 配方和权重由 cooking_rules.gd 计算，这里只处理桌面交互。
const Card = preload("res://card.gd")
const WORK_AREA = Rect2(132, 148, 436, 474)
const TABLE_AREA = Rect2(132, 90, 1128, 564)
const MAX_CARDS = 24
const MAX_GROUP = 6
var game
var cards = []
var equipment_upgraded = false
var outlet: Button
var bin: Button
var ingredient_box: Button
var selected_card = null

func _ready():
	game.panel(self, Rect2(574, 148, 1, 474), "e4e1da")
	ingredient_box = game.button(self, "食材箱", Rect2(642, 96, 100, 36), game.open_menu.bind("食材箱"))
	outlet = game.button(self, "出餐！", Rect2(1110, 96, 116, 36), explain_outlet)
	bin = game.button(self, "垃圾桶", Rect2(1130, 606, 96, 36), explain_bin)
	var names = ["切", "榨", "磨", "搅拌", "煮", "炒", "炸", "烤"]
	for i in range(names.size()):
		var tool = create_card("tool", [])
		tool.tool_name = names[i]
		tool.drag_area = WORK_AREA
		tool.position = Vector2(176 + (i % 4) * 96, 230 if i < 4 else 418)
		tool.refresh()

func explain_outlet():
	game.notify("把完成的料理拖到「出餐！」。餐厅出餐台初始可放 3 份，装满时料理保留在后厨。")

func explain_bin():
	game.notify("拖入食材、半成品或料理可丢弃，不返还库存。工具不能丢弃。")

func capacity():
	return 36 if equipment_upgraded else MAX_CARDS

func create_card(kind, items):
	var card = Card.new()
	card.kind = kind
	card.items = items.duplicate(true)
	card.drag_area = TABLE_AREA
	card.double_clickable = kind == "ingredient"
	card.clicked.connect(on_card_clicked)
	card.double_clicked.connect(split_group)
	card.dropped.connect(on_card_dropped)
	add_child(card)
	cards.append(card)
	return card

func add_ingredient(food):
	if game.inventory[food] <= 0:
		game.notify("食材箱没有 " + food + "，可去商店购买或收集产物")
		return false
	if cards.size() >= capacity():
		game.notify("桌面已满，可合并食材、出餐或丢弃")
		return false
	game.inventory[food] -= 1
	var card = create_card("ingredient", [game.rules.raw_item(food)])
	place_near(card, Vector2(680, 220))
	return true

func upgrade_equipment():
	if game.day < 2 or equipment_upgraded:
		game.notify("第 2 天起可扩建后厨一次：24 → 36 张文字块")
		return
	if game.spend(60):
		equipment_upgraded = true
		game.refresh_menu()

func prepared_count():
	var total = 0
	for card in cards:
		if card.kind in ["ingredient", "dish"]:
			total += card.items.size()
	for dish in game.dining.dishes:
		total += dish.items.size()
	return total

func remove_card(card):
	if selected_card == card:
		selected_card = null
	cards.erase(card)
	card.hide()
	card.queue_free()

func split_group(card):
	if card.kind != "ingredient" or card.items.size() < 2:
		return
	if not game.rules.untouched(card.items):
		game.notify("这组含处理过的食材，不能拆分")
		return
	if cards.size() + card.items.size() - 1 > capacity():
		game.notify("桌面空间不足，先出餐或丢弃，再拆分")
		return
	card.collapse()
	var point = card.position
	var ingredients = card.items.duplicate(true)
	remove_card(card)
	for item in ingredients:
		var single = create_card("ingredient", [item])
		place_near(single, point)

func on_card_dropped(card):
	card.collapse()
	var point = card.position + card.size / 2
	if card.kind == "tool":
		return
	if Rect2(bin.position, bin.size).has_point(point):
		remove_card(card)
		return
	if Rect2(outlet.position, outlet.size).has_point(point):
		if card.kind != "dish":
			game.notify("这里只接收完成的料理")
		elif game.dining.add_dish(card):
			remove_card(card)
			return
		place_near(card, card.start_position)
		return
	if card.kind != "ingredient":
		return
	var layers = get_children()
	layers.reverse()
	for target in layers:
		if target == card or not cards.has(target):
			continue
		if not Rect2(target.position, target.size).has_point(point):
			continue
		if target.kind == "tool":
			use_tool(card, target)
			return
		if target.kind == "ingredient":
			if card.items.size() + target.items.size() > MAX_GROUP:
				game.notify("每组最多 6 份，未合并的食材已保留")
				place_near(card, card.start_position)
				return
			target.collapse()
			target.items.append_array(card.items.duplicate(true))
			remove_card(card)
			update_ingredient(target)
			place_near(target, target.position)
			return

func update_ingredient(card):
	card.data["intermediate"] = game.rules.intermediate_name(card.items)
	card.refresh()

func use_tool(card, tool):
	if card.kind != "ingredient":
		return
	var method = tool.tool_name
	if method in ["切", "榨", "磨", "搅拌"]:
		game.rules.process_items(card.items, method)
		if method == "搅拌" and game.rules.is_drink(card.items):
			finish_dish(card, method)
		else:
			update_ingredient(card)
			place_near(card, tool.position + Vector2(0, 62))
		return
	finish_dish(card, method)

func finish_dish(card, method):
	card.kind = "dish"
	card.double_clickable = false
	card.cooking_method = method
	card.data.erase("intermediate")
	card.data["weights"] = game.rules.weights(card.items, method)
	card.tags = card.data["weights"].keys()
	card.dish_name = game.rules.dish_name(card.items, method)
	card.data["recipe"] = game.record_recipe(card)
	card.refresh()
	place_near(card, Vector2(710, 450))

func on_card_clicked(card):
	selected_card = card
	var description = ""
	if card.kind == "tool":
		if game.rules.PROCESS_TAGS.has(card.tool_name):
			description = "处理单份或整组食材；保留之前的处理状态。\n"
			description += game.weight_text(game.rules.PROCESS_TAGS[card.tool_name])
			if card.tool_name == "搅拌":
				description += "\n水果与牛奶可调成饮品；面粉与牛奶会成为面团，加入蛋则为面糊。"
		else:
			description = "将食材或半成品拖到这里烹饪。\n" + game.weight_text(game.rules.COOK_TAGS[card.tool_name])
	elif card.kind == "dish":
		description = game.dish_detail(card)
	else:
		for item in card.items:
			description += item.get("form", item["name"]) + " · " + (item["process"] if item["process"] != "" else "未处理") + "\n"
		var weights = {}
		for item in card.items:
			game.rules.add_weights(weights, game.rules.database["foods"][item["name"]]["tags"])
			for step in game.rules.history(item):
				game.rules.add_weights(weights, game.rules.PROCESS_TAGS[step])
		description += game.weight_text(weights)
		description += "\n整组未处理时双击拆开。" if game.rules.untouched(card.items) else "\n已处理，不能拆开。"
	card.toggle_detail(description)

func place_near(card, preferred):
	var best = preferred
	var distance = INF
	for y in range(164, 560, 28):
		for x in range(144, 1180, 28):
			var candidate = Vector2(x, y)
			var rect = Rect2(candidate, card.size)
			if not Rect2(132, 148, 1128, 440).encloses(rect):
				continue
			var free = true
			for other in cards:
				if other != card and rect.grow(7).intersects(Rect2(other.position, other.size)):
					free = false
					break
			if free and candidate.distance_squared_to(preferred) < distance:
				distance = candidate.distance_squared_to(preferred)
				best = candidate
	card.position = best
	card.clamp_to_area()

func auto_cook(recipe_index):
	# 先找齐未处理备料再扣除，不改造玩家的半成品。
	var recipe = game.recipes[recipe_index]
	var candidates = []
	for card in cards:
		if card.kind == "ingredient" and game.rules.untouched(card.items):
			for item in card.items:
				candidates.append({"card": card, "item": item, "used": false})
	var chosen = []
	for wanted in recipe["items"]:
		var found = -1
		for i in range(candidates.size()):
			if not candidates[i]["used"] and candidates[i]["item"]["name"] == wanted["name"]:
				found = i
				break
		if found < 0:
			return false
		candidates[found]["used"] = true
		chosen.append(found)
	# 如果只从大组里拿走部分食材，还要为成品预留一张卡的位置。
	var used_counts = {}
	for index in chosen:
		var source_card = candidates[index]["card"]
		used_counts[source_card] = used_counts.get(source_card, 0) + 1
	var emptied = 0
	for source_card in used_counts:
		if used_counts[source_card] == source_card.items.size():
			emptied += 1
	if cards.size() - emptied + 1 > capacity():
		return false
	for index in chosen:
		var source = candidates[index]
		source["card"].items.erase(source["item"])
	for card in cards.duplicate():
		if card.kind == "ingredient":
			if card.items.is_empty():
				remove_card(card)
			else:
				card.collapse()
				card.refresh()
	var dish = create_card("ingredient", recipe["items"])
	finish_dish(dish, recipe["method"])
	return true
