extends Node
# 图鉴只保存发现记录和设置，不保存金币、库存或当日营业。
var game
var entries = []
var filter = "全部"
var selected = ""
var save_path = "user://cooking_catalog.json"
var save_ok = true
var card_grid: GridContainer

func _ready():
	if "--test-mode" in OS.get_cmdline_user_args():
		save_path = "user://test_catalog.json"
		if "--test-reload" in OS.get_cmdline_user_args():
			load_data()
	else:
		load_data()

func known(name):
	for recipe in game.rules.database["recipes"]:
		if recipe["name"] == name:
			return true
	return false

func category(method):
	return {"炒": "热菜", "炸": "小吃", "煮": "汤粥", "烤": "烘焙", "搅拌": "饮品"}.get(method, "其他")

func count_known():
	var names = []
	for entry in entries:
		if known(entry["name"]) and not names.has(entry["name"]):
			names.append(entry["name"])
	return names.size()

func discover(recipe):
	var first_name = true
	for entry in entries:
		if entry["key"] == recipe["key"]:
			return false
		if entry["name"] == recipe["name"]:
			first_name = false
	entries.append(recipe.duplicate(true))
	save_data()
	if first_name:
		game.feedback.announce(recipe)
	return first_name

func valid_entry(entry):
	if not entry is Dictionary:
		return false
	for field in ["key", "name", "method"]:
		if not entry.get(field) is String:
			return false
	if not game.rules.COOK_TAGS.has(entry["method"]):
		return false
	if not entry.get("items") is Array or entry["items"].is_empty() or entry["items"].size() > 6:
		return false
	for item in entry["items"]:
		if not item is Dictionary or not game.PRICES.has(item.get("name", "")):
			return false
		if not item.get("form") is String or not item.get("process") is String or not item.get("history") is Array:
			return false
		for step in item["history"]:
			if not game.rules.PROCESS_TAGS.has(step):
				return false
	return true

func load_data():
	var data = null
	for path in [save_path, save_path + ".bak"]:
		if FileAccess.file_exists(path):
			var parser = JSON.new()
			if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary:
				if parser.data.get("version") == 1 and parser.data.get("entries") is Array:
					data = parser.data
					break
	if data == null:
		return
	entries.clear()
	var keys = []
	for entry in data["entries"]:
		if not valid_entry(entry):
			continue
		var key = game.recipe_key(entry["items"], entry["method"])
		if keys.has(key):
			continue
		keys.append(key)
		# 重新计算派生数据，防止旧版本价格或手动损坏的权重影响经营。
		entry["key"] = key
		entry["name"] = game.rules.dish_name(entry["items"], entry["method"])
		entry["weights"] = game.rules.weights(entry["items"], entry["method"])
		entry["tags"] = entry["weights"].keys()
		var cost = 0
		for item in entry["items"]:
			cost += game.PRICES[item["name"]]
		entry["base"] = cost * 2 + 4
		entry["listed"] = false
		entry["markup"] = 0
		entries.append(entry)
	game.recipes = entries.duplicate(true)
	var settings = data.get("settings", {})
	if settings is Dictionary:
		var value = settings.get("volume", 0.55)
		if value is float or value is int:
			game.feedback.volume = clampf(value, 0, 1)
		game.feedback.muted = settings.get("muted", false) == true
		game.feedback.reduced_motion = settings.get("reduced_motion", false) == true

func save_data():
	# 正式存档的图鉴由每日存档保存。此文件只更新公共设置，并保留旧版图鉴。
	var saved_entries = entries
	if game.slot_id > 0:
		saved_entries = []
		for old_path in [save_path, save_path + ".bak"]:
			if not FileAccess.file_exists(old_path):
				continue
			var previous = JSON.new()
			if previous.parse(FileAccess.get_file_as_string(old_path)) == OK and previous.data is Dictionary and previous.data.get("entries") is Array:
				saved_entries = previous.data["entries"]
				break
	var data = {"version": 1, "entries": saved_entries, "settings": {"volume": game.feedback.volume, "muted": game.feedback.muted, "reduced_motion": game.feedback.reduced_motion}}
	var file = FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		save_ok = false
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	# 保留上一次有效文件。损坏文件不覆盖备份。
	if FileAccess.file_exists(save_path):
		var old = JSON.new()
		if old.parse(FileAccess.get_file_as_string(save_path)) == OK:
			DirAccess.copy_absolute(save_path, save_path + ".bak")
	save_ok = DirAccess.rename_absolute(save_path + ".tmp", save_path) == OK
	return save_ok

func choose_filter(index):
	filter = ["全部", "热菜", "汤粥", "小吃", "烘焙", "饮品", "我的创作"][index]
	selected = ""
	game.refresh_menu()

func choose(name):
	selected = name
	game.refresh_menu()

func build():
	game.menu_line("已发现 %d / %d · 我的创作 %d" % [count_known(), game.rules.database["recipes"].size(), creative_count()])
	if not save_ok:
		game.menu_line("图鉴暂未成功写入磁盘，请检查存储空间与权限。")
	if selected != "":
		game.menu_action("← 返回列表", choose.bind(""))
		game.menu_line(selected)
		var variant = 0
		for entry in entries:
			if entry["name"] != selected:
				continue
			variant += 1
			game.menu_line("制作记录 %d · %s · 基础价 %d" % [variant, category(entry["method"]), entry["base"]])
			game.menu_line(game.recipe_text(entry) + "\n最后：" + entry["method"])
			game.menu_line(game.weight_text(entry["weights"]))
		return
	var options = OptionButton.new()
	var categories = ["全部", "热菜", "汤粥", "小吃", "烘焙", "饮品", "我的创作"]
	for item in categories:
		options.add_item(item)
	options.select(categories.find(filter))
	game.style_button(options)
	options.item_selected.connect(choose_filter)
	game.menu_content.add_child(options)
	card_grid = GridContainer.new()
	card_grid.columns = [1, 3, 4][game.menu.size_index]
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_theme_constant_override("h_separation", 12)
	card_grid.add_theme_constant_override("v_separation", 12)
	game.menu_content.add_child(card_grid)
	var shown = []
	var sorted_recipes = []
	var found_names = []
	for entry in entries:
		found_names.append(entry["name"])
	for recipe in game.rules.database["recipes"]:
		if found_names.has(recipe["name"]):
			sorted_recipes.append(recipe)
	for recipe in game.rules.database["recipes"]:
		if not found_names.has(recipe["name"]):
			sorted_recipes.append(recipe)
	for recipe in sorted_recipes:
		if filter == "我的创作" or (filter != "全部" and filter != category(recipe["method"])):
			continue
		var found = false
		for entry in entries:
			if entry["name"] == recipe["name"]:
				found = true
				break
		add_catalog_card(recipe["name"], category(recipe["method"]), found)
		shown.append(recipe["name"])
	if filter in ["全部", "我的创作"]:
		for entry in entries:
			if not known(entry["name"]) and not shown.has(entry["name"]):
				shown.append(entry["name"])
				add_catalog_card(entry["name"], "我的创作", true)
	if shown.is_empty():
		game.menu_line("还没有创作记录。试试自由组合不同食材。")

func add_catalog_card(dish_name, category_name, found):
	var card = Button.new()
	game.style_button(card)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 132)
	card.disabled = not found
	card.set_meta("dish_name", dish_name if found else "")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style = card.get_theme_stylebox(state).duplicate()
		style.bg_color = Color("fffdf7") if found else Color("f0efe9")
		style.border_color = Color("d7c8a2") if found else Color("dedcd3")
		if found and state == "hover":
			style.bg_color = Color("f4f0e1")
		style.border_width_top = 3 if found else 1
		card.add_theme_stylebox_override(state, style)
	card.pressed.connect(choose.bind(dish_name))
	card_grid.add_child(card)
	var column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12
	column.offset_right = -12
	column.offset_top = 16
	column.offset_bottom = -12
	column.add_theme_constant_override("separation", 9)
	card.add_child(column)
	var small = game.supplies.text(column, category_name, 12)
	small.add_theme_color_override("font_color", Color("8b8c7d"))
	var title = game.supplies.text(column, dish_name if found else "？？？", 16)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tags = []
	for entry in entries:
		if entry["name"] == dish_name:
			tags = entry["tags"].slice(0, 2)
			break
	var foot = game.supplies.text(column, " · ".join(tags) if found else "等待发现", 12)
	foot.add_theme_color_override("font_color", Color("818773"))
	foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func creative_count():
	var names = []
	for entry in entries:
		if not known(entry["name"]) and not names.has(entry["name"]):
			names.append(entry["name"])
	return names.size()
