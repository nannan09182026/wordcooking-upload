extends RefCounted
# 纯料理规则。数据在 food_data.json；不操纵节点和金币。
var database = JSON.parse_string(FileAccess.get_file_as_string("res://food_data.json"))
const PROCESS_TAGS = {"切": {"细致": 8, "易熟": 8}, "榨": {"细腻": 12, "液态": 12}, "磨": {"基础材料": 10}, "搅拌": {"融合": 8, "均匀": 8}}
const COOK_TAGS = {"煮": {"温润": 12, "柔和": 8}, "炒": {"香气": 12, "家常": 8}, "炸": {"酥脆": 12, "油香": 8}, "烤": {"焦香": 12, "浓郁": 8}, "搅拌": {"清爽": 8}}

func raw_item(food):
	return {"name": food, "form": food, "process": "", "history": []}

func history(item):
	return item.get("history", [])

func untouched(items):
	for item in items:
		if not history(item).is_empty() or item.get("process", "") != "":
			return false
	return true

func process_items(items, method):
	for item in items:
		if not item.has("history"):
			item["history"] = []
		# 同一处理重复操作不刷权重，状态不会因后续处理被抹掉。
		if not item["history"].has(method):
			item["history"].append(method)
		item["process"] = "·".join(item["history"])
		if method == "磨":
			if item["name"] == "小麦":
				item["form"] = "面粉"
			elif item["name"] == "稻米":
				item["form"] = "米粉"
			elif item["name"] == "土豆":
				item["form"] = "土豆泥"
		if method == "榨":
			item["form"] = item["name"] + "汁"

func counts(items):
	var result = {}
	for item in items:
		result[item["name"]] = result.get(item["name"], 0) + 1
	return result

func has_step(items, food, step):
	for item in items:
		if item["name"] == food and history(item).has(step):
			return true
	return false

func intermediate_name(items):
	var names = counts(items)
	if names.has("牛奶") and has_step(items, "小麦", "磨") and has_step(items, "小麦", "搅拌"):
		return "面糊" if names.has("鸡蛋") else "面团"
	if names.has("牛奶") and has_step(items, "稻米", "磨") and has_step(items, "稻米", "搅拌"):
		return "米糊"
	return ""

func is_drink(items):
	var names = counts(items)
	if not names.has("牛奶"):
		return false
	var fruit = false
	for name in names:
		if not ["牛奶", "苹果", "草莓"].has(name):
			return false
		if name in ["苹果", "草莓"]:
			fruit = true
	return fruit

func weights(items, method):
	var result = {}
	for item in items:
		add_weights(result, database["foods"][item["name"]]["tags"])
		for step in history(item):
			add_weights(result, PROCESS_TAGS[step])
	add_weights(result, COOK_TAGS[method])
	var amounts = counts(items)
	var largest = 1
	for amount in amounts.values():
		largest = maxi(largest, amount)
	if largest >= 3:
		result["极浓"] = 30
	elif largest >= 2:
		result["超浓"] = 20
	# 番茄数量的多汁权重采用文档示例：1份5、2份10、3份20。
	if amounts.get("番茄", 0) >= 3:
		result["多汁"] += (amounts["番茄"] - 2) * 5
	return result

func add_weights(target, source):
	for tag in source:
		target[tag] = target.get(tag, 0) + source[tag]

func matches(items, method, recipe):
	if recipe["method"] != method or items.size() != recipe["ingredients"].size():
		return false
	var expected = {}
	for name in recipe["ingredients"]:
		expected[name] = expected.get(name, 0) + 1
	if counts(items) != expected:
		return false
	for item in items:
		for step in recipe["prep"].get(item["name"], []):
			if not history(item).has(step):
				return false
		if recipe["mix"] and not history(item).has("搅拌"):
			return false
	return true

func dish_name(items, method):
	for recipe in database["recipes"]:
		if matches(items, method, recipe):
			return recipe["name"]
	var amounts = counts(items)
	var names = amounts.keys()
	names.sort() # 相同组合的拖入顺序不改变命名。
	var main_food = names[0]
	for name in names:
		if amounts[name] > amounts[main_food]:
			main_food = name
	var prefix = ""
	if amounts[main_food] >= 3:
		prefix = "极浓"
	elif amounts[main_food] >= 2:
		prefix = "浓"
	var second = ""
	for name in names:
		if name != main_food:
			second = name
			break
	return prefix + main_food + second + {"煮": "汤", "炒": "炒菜", "炸": "炸物", "烤": "烤物", "搅拌": "奶饮"}[method]

func key(items, method):
	var parts = []
	for item in items:
		parts.append(item["name"] + ":" + ",".join(history(item)) + ":" + item.get("form", item["name"]))
	parts.sort()
	return method + "|" + "|".join(parts)
