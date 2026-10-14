extends RefCounted
# 三份独立存档。只保存数据，节点在读取时重新创建。
var prefix = "user://restaurant_"
var error_text = ""
var recovered = false
var database = JSON.parse_string(FileAccess.get_file_as_string("res://food_data.json"))
const METHODS = ["切", "榨", "磨", "搅拌", "煮", "炒", "炸", "烤"]
const SPECIES = ["鸡", "兔", "猪"]

func _init():
	if "--test-mode" in OS.get_cmdline_user_args():
		prefix = "user://test_restaurant_"

func path(slot):
	return prefix + str(slot) + ".json"

func exists(slot):
	return FileAccess.file_exists(path(slot)) or FileAccess.file_exists(path(slot) + ".bak")

func read_file(file_path):
	if not FileAccess.file_exists(file_path):
		return null
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(file_path)) != OK:
		return null
	parser.data = migrate(parser.data)
	if not valid_state(parser.data):
		return null
	return parser.data

func read_slot(slot):
	error_text = ""
	recovered = false
	var data = read_file(path(slot))
	if data == null:
		data = read_file(path(slot) + ".bak")
		recovered = data != null
	if data == null and exists(slot):
		error_text = "这份存档暂时无法读取，原文件已保留。"
	return data

func write_slot(slot, data):
	if slot < 1 or slot > 3 or not valid_state(data):
		error_text = "存档数据不完整，未覆盖上次进度。"
		return false
	var target = path(slot)
	var file = FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if file == null:
		error_text = "无法写入存档，请检查存储空间和权限，再重试。"
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var written = file.get_error() == OK
	file.close()
	if not written or read_file(target + ".tmp") == null:
		error_text = "存档写入未完成，上次进度仍保留。"
		return false
	# 仅把有效主文件备份；恢复备份时不会用损坏文件盖掉它。
	if read_file(target) != null:
		if DirAccess.copy_absolute(target, target + ".bak") != OK:
			error_text = "暂时无法备份旧进度，请重试。"
			return false
	if DirAccess.rename_absolute(target + ".tmp", target) != OK:
		error_text = "无法替换存档，上次进度仍保留。"
		return false
	error_text = ""
	return true

func point(value):
	return Vector2(value[0], value[1])

func pair(value):
	return [value.x, value.y]

func card_state(card):
	return {"kind": card.kind, "position": pair(card.small_position if card.expanded else card.position), "tool": card.tool_name, "items": card.items.duplicate(true), "method": card.cooking_method, "name": card.dish_name, "tags": card.tags.duplicate(), "data": card.data.duplicate(true)}

func capture(game):
	var kitchen_cards = []
	for card in game.kitchen.cards:
		kitchen_cards.append(card_state(card))
	var tray = []
	for card in game.dining.dishes:
		tray.append(card_state(card))
	var plots = []
	for card in game.farm.plots:
		plots.append({"position": pair(card.position), "data": card.data.duplicate(true)})
	var crops = []
	for card in game.farm.produce:
		crops.append({"position": pair(card.position), "crop": card.data["crop"]})
	var animals = []
	for card in game.barn.animals:
		var data = card.data.duplicate(true)
		data["base"] = pair(card.data["base"])
		data["target"] = pair(card.data["target"])
		data["sway"] = 0.0
		animals.append(data)
	var feed_cards = []
	for card in game.barn.foods:
		feed_cards.append({"position": pair(card.position), "type": card.data["type"]})
	var products = []
	for card in game.barn.produce:
		products.append({"position": pair(card.position), "type": card.data["type"]})
	return {"version": 2, "shops": game.shops.duplicate(), "saved_at": Time.get_datetime_string_from_system(false, true), "day": game.day, "phase": game.phase, "money": game.money, "inventory": game.inventory.duplicate(true), "recipes": game.recipes.duplicate(true), "catalog": game.catalog.entries.duplicate(true), "staff": game.staff.duplicate(), "learned": game.learned.duplicate(true), "tray_capacity": game.tray_capacity, "income": game.daily_income, "tips": game.daily_tips, "cost": game.daily_cost, "summary": game.dining.last_summary, "kitchen_upgraded": game.kitchen.equipment_upgraded, "kitchen": kitchen_cards, "tray": tray, "seeds": game.farm.seeds.duplicate(), "plots": plots, "crops": crops, "built": game.barn.built.duplicate(), "upgraded": game.barn.upgraded.duplicate(), "feed": game.barn.feed, "animals": animals, "feed_cards": feed_cards, "products": products}

func restore_card(game, saved):
	var card = game.kitchen.create_card(saved["kind"], saved["items"])
	card.tool_name = saved["tool"]
	card.cooking_method = saved["method"]
	card.dish_name = saved["name"]
	card.tags = saved["tags"].duplicate()
	card.data = saved["data"].duplicate(true)
	if card.kind == "dish":
		card.data["recipe"] = int(card.data["recipe"])
	card.double_clickable = card.kind == "ingredient"
	if card.kind == "tool":
		card.drag_area = game.kitchen.WORK_AREA
	card.position = point(saved["position"])
	card.refresh()
	return card

func restore(game, data):
	# 只恢复到新创建的游戏，切换存档时旧游戏会整体释放。
	if not valid_state(data) or not game.farm.plots.is_empty() or not game.barn.animals.is_empty():
		return false
	game.day = int(data["day"])
	game.phase = data["phase"]
	game.money = int(data["money"])
	game.shops = data["shops"].duplicate()
	game.inventory = data["inventory"].duplicate(true)
	for food in game.inventory:
		game.inventory[food] = int(game.inventory[food])
	game.recipes = data["recipes"].duplicate(true)
	game.catalog.entries = data["catalog"].duplicate(true)
	game.staff = data["staff"].duplicate()
	game.learned = data["learned"].duplicate(true)
	game.tray_capacity = int(data["tray_capacity"])
	game.daily_income = int(data["income"])
	game.daily_tips = int(data["tips"])
	game.daily_cost = int(data["cost"])
	game.dining.last_summary = data["summary"]
	game.kitchen.equipment_upgraded = data["kitchen_upgraded"]
	for card in game.kitchen.cards.duplicate():
		game.kitchen.remove_card(card)
	for saved in data["kitchen"]:
		restore_card(game, saved)
	for saved in data["tray"]:
		var card = restore_card(game, saved)
		game.dining.add_dish(card)
		game.kitchen.remove_card(card)
	game.farm.seeds = data["seeds"].duplicate()
	for crop in game.farm.seeds:
		game.farm.seeds[crop] = int(game.farm.seeds[crop])
	for saved in data["plots"]:
		game.farm.create_plot(point(saved["position"]), saved["data"])
	for saved in data["crops"]:
		game.farm.create_produce(saved["crop"], point(saved["position"]))
	game.barn.upgraded = data["upgraded"].duplicate()
	for type in SPECIES:
		if data["built"][type]:
			game.barn.create_home(type)
	for saved in data["animals"]:
		var state = saved.duplicate(true)
		state["base"] = point(saved["base"])
		state["target"] = point(saved["target"])
		game.barn.create_animal(saved["type"], state["base"], state)
	for saved in data["feed_cards"]:
		game.barn.current = saved["type"]
		game.barn.feed += 1
		game.barn.place_feed(point(saved["position"]))
	game.barn.feed = int(data["feed"])
	for saved in data["products"]:
		game.barn.spawn_product(saved["type"], point(saved["position"]))
	game.barn.leave_pen()
	game.barn.update_feed()
	game.dining.update_tray()
	game.dining.opening_button.text = "查看结算" if game.phase == "夜晚" else "开始营业"
	game.feedback.toast.hide()
	return true

# 校验在修改游戏前完成。坏档尝试备份，两份都坏则保留原文件。
func number(value, low = 0.0, high = 1000000000.0):
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

func valid_point(value):
	return value is Array and value.size() == 2 and number(value[0], -2000, 4000) and number(value[1], -2000, 4000)

func counts(value, names, booleans = false):
	if not value is Dictionary:
		return false
	for key in value:
		if not names.has(key):
			return false
	for name in names:
		if booleans:
			if not value.get(name) is bool:
				return false
		elif not number(value.get(name)):
			return false
	return true

func valid_items(items):
	if not items is Array or items.is_empty() or items.size() > 6:
		return false
	for item in items:
		if not item is Dictionary or not database["foods"].has(item.get("name", "")):
			return false
		if not item.get("history") is Array or not item.get("form") is String or not item.get("process") is String:
			return false
		for step in item["history"]:
			if not step in ["切", "榨", "磨", "搅拌"]:
				return false
	return true

func weights_valid(weights):
	if not weights is Dictionary:
		return false
	for key in weights:
		if not key is String or not number(weights[key]):
			return false
	return true

func valid_recipe(recipe):
	if not recipe is Dictionary or not valid_items(recipe.get("items")):
		return false
	for field in ["key", "name", "method"]:
		if not recipe.get(field) is String:
			return false
	if not recipe["method"] in ["搅拌", "煮", "炒", "炸", "烤"] or not recipe.get("tags") is Array:
		return false
	for tag in recipe["tags"]:
		if not tag is String:
			return false
	return weights_valid(recipe.get("weights")) and number(recipe.get("base")) and number(recipe.get("markup"), -30, 50) and recipe.get("listed") is bool

func valid_card(card, recipes):
	if not card is Dictionary or not valid_point(card.get("position")) or not card.get("data") is Dictionary:
		return false
	for field in ["kind", "tool", "method", "name"]:
		if not card.get(field) is String:
			return false
	if not card.get("tags") is Array:
		return false
	for tag in card["tags"]:
		if not tag is String:
			return false
	if card["kind"] == "tool":
		return card["tool"] in METHODS and card.get("items") == []
	if not valid_items(card.get("items")) or not card["kind"] in ["ingredient", "dish"]:
		return false
	if card["data"].has("intermediate") and not card["data"]["intermediate"] is String:
		return false
	if card["kind"] == "dish":
		var index = card["data"].get("recipe", -1)
		return number(index, 0, recipes.size() - 1) and index == int(index) and weights_valid(card["data"].get("weights")) and card["method"] in ["搅拌", "煮", "炒", "炸", "烤"]
	return true

func valid_state(data):
	if not data is Dictionary or data.get("version") != 2 or not data.get("phase") in ["早晨", "夜晚"]:
		return false
	if not data.get("saved_at") is String or not data.get("summary") is String:
		return false
	for name in ["day", "money", "income", "tips", "cost", "feed"]:
		if not number(data.get(name)):
			return false
	if data["day"] < 1 or not number(data.get("tray_capacity"), 3, 6) or not data.get("kitchen_upgraded") is bool:
		return false
	if data["tray_capacity"] != 3 and data["tray_capacity"] != 6:
		return false
	if not counts(data.get("inventory"), database["foods"].keys()) or not counts(data.get("seeds"), ["小麦", "番茄", "土豆"]):
		return false
	if not counts(data.get("staff"), ["前台", "主厨", "传菜"], true) or not counts(data.get("built"), SPECIES, true) or not counts(data.get("upgraded"), SPECIES, true):
		return false
	if not counts(data.get("shops"), ["中级", "高级"], true):
		return false
	if data["shops"]["高级"] and not data["shops"]["中级"]:
		return false
	if not data.get("learned") is Dictionary:
		return false
	for name in data["learned"]:
		if not data["learned"][name] is Array:
			return false
		for tag in data["learned"][name]:
			if not tag is String:
				return false
	for field in ["recipes", "catalog", "kitchen", "tray", "plots", "crops", "animals", "feed_cards", "products"]:
		if not data.get(field) is Array:
			return false
	for recipe in data["recipes"] + data["catalog"]:
		if not valid_recipe(recipe):
			return false
	if data["kitchen"].size() > (36 if data["kitchen_upgraded"] else 24) or data["tray"].size() > data["tray_capacity"]:
		return false
	var tools = []
	for card in data["kitchen"] + data["tray"]:
		if not valid_card(card, data["recipes"]):
			return false
		if card["kind"] == "tool":
			tools.append(card["tool"])
	for method in METHODS:
		if tools.count(method) != 1:
			return false
	for card in data["tray"]:
		if card["kind"] != "dish":
			return false
	if data["plots"].size() > 6 or data["crops"].size() > 48 or data["products"].size() > 48 or data["feed_cards"].size() > 18:
		return false
	for plot in data["plots"]:
		if not plot is Dictionary or not valid_point(plot.get("position")) or not plot.get("data") is Dictionary:
			return false
		var state = plot["data"]
		if not state.get("crop") in ["", "小麦", "番茄", "土豆"] or not number(state.get("elapsed"), 0, 18) or not state.get("large") is bool:
			return false
	for crop in data["crops"]:
		if not crop is Dictionary or not valid_point(crop.get("position")) or not crop.get("crop") in ["小麦", "番茄", "土豆"]:
			return false
	for card in data["feed_cards"] + data["products"]:
		if not card is Dictionary or not valid_point(card.get("position")) or not card.get("type") in SPECIES:
			return false
		if not data["built"][card["type"]]:
			return false
	var animal_counts = {"鸡": 0, "兔": 0, "猪": 0}
	for animal in data["animals"]:
		if not animal is Dictionary or not animal.get("type") in SPECIES:
			return false
		if not valid_point(animal.get("base")) or not valid_point(animal.get("target")) or not animal.get("meal") is bool:
			return false
		if not number(animal.get("growth"), 0, 2):
			return false
		for field in ["egg_time", "rest", "wait", "call_wait", "sway", "walk_phase"]:
			if not number(animal.get(field), -100, 1000000000):
				return false
		animal_counts[animal["type"]] += 1
	for type in SPECIES:
		if animal_counts[type] > (6 if data["upgraded"][type] else 3) or (animal_counts[type] > 0 and not data["built"][type]):
			return false
	return true

func migrate(data):
	# 只补旧版不存在的新字段，损坏的原库存仍会被校验拒绝。
	if not data is Dictionary or data.get("version") != 1 or not data.get("inventory") is Dictionary:
		return data
	var upgraded = data.duplicate(true)
	for food in database["foods"]:
		if database["foods"][food].get("tier", 0) > 0 and not upgraded["inventory"].has(food):
			upgraded["inventory"][food] = 0
	upgraded["shops"] = {"中级": false, "高级": false}
	upgraded["version"] = 2
	return upgraded
