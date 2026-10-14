extends SceneTree
var game
var k
var checks = 0
var failures = 0

func _initialize():
	call_deferred("run")

func check(ok, message):
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func center(node):
	return node.global_position + node.size / 2

func motion(point):
	var event = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func mouse(point, down, twice = false):
	var event = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.double_click = twice
	root.push_input(event, true)

func click(node):
	var point = center(node)
	motion(point)
	mouse(point, true)
	mouse(point, false)
	await create_timer(0.32).timeout

func double_click(node):
	var point = center(node)
	motion(point)
	mouse(point, true)
	mouse(point, false)
	mouse(point, true, true)
	mouse(point, false)
	await create_timer(0.32).timeout

func drag(node, point):
	motion(center(node))
	mouse(center(node), true)
	motion(point)
	mouse(point, false)
	await process_frame

func tool(name):
	for card in k.cards:
		if card.kind == "tool" and card.tool_name == name:
			return card
	return null

func clear_notices():
	game.feedback.toast.hide()
	game.page_help.hide()
	game.menu.hide()

func clear_table():
	for card in k.cards.duplicate():
		if card.kind != "tool":
			k.remove_card(card)
		else:
			card.collapse()
	clear_notices()

func ingredient(food):
	game.inventory[food] = maxi(50, game.inventory[food])
	k.add_ingredient(food)
	return k.cards.back()

func snapshot(name):
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://" + name + ".png")

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.farm.set_process(false)
	game.barn.set_process(false)
	game.dining.set_process(false)
	k = game.kitchen
	game.show_page("后厨")
	clear_notices()
	check(k.cards.size() == 8, "eight tools and no deprecated kitchen controls")
	for child in k.get_children():
		if child is Button:
			check(not child.text in ["备料", "端菜", "放回", "整理", "扩建"], "removed old button " + child.text)
	await click(k.ingredient_box)
	check(game.menu.visible and game.menu_type == "食材箱", "ingredient box opens window")
	var before = game.inventory["番茄"]
	await click(game.supplies.food_sources["番茄"])
	check(game.inventory["番茄"] == before - 1, "taking ingredient debits warehouse once")
	var tomato = k.cards.back()
	game.open_menu("食材箱")
	var old_size = game.menu.size
	await click(game.menu.resize_button)
	check(game.menu.size != old_size, "window resize button changes size")
	await click(game.menu.resize_button)
	check(game.menu.size_index == 0, "window cycles to small")
	await snapshot("window-small")
	await click(game.menu.resize_button)
	check(game.menu.size == old_size, "three clicks return original size")
	var old_pos = game.menu.position
	await drag(game.menu.title_bar, center(game.menu.title_bar) + Vector2(-90, 50))
	check(game.menu.position == old_pos + Vector2(-90, 50), "title bar moves window")
	await drag(game.menu.title_bar, Vector2(-2000, -2000))
	check(game.menu.position == Vector2.ZERO, "window constrained to viewport")
	await click(game.menu.close_button)
	check(not game.menu.visible, "window close button")
	await click(tomato)
	check(tomato.expanded and tomato.size.x >= 294, "single click expands card in place")
	await snapshot("ingredient-detail")
	await click(tomato)
	check(not tomato.expanded and tomato.size.x < 294, "second click collapses detail")
	var egg = ingredient("鸡蛋")
	await process_frame
	await drag(egg, center(tomato))
	check(tomato.items.size() == 2, "merge raw ingredients")
	await double_click(tomato)
	var singles = []
	for card in k.cards:
		if card.kind == "ingredient":
			singles.append(card)
	check(singles.size() == 2 and singles[0].items.size() == 1, "double click splits raw group")
	check(not singles[0].expanded and not singles[1].expanded, "double click does not leave an expanded detail")
	await drag(singles[0], center(tool("切")))
	await drag(singles[1], center(singles[0]))
	await double_click(singles[0])
	check(k.cards.has(singles[0]) and singles[0].items.size() == 2, "mixed processed group cannot split")
	clear_notices()
	await drag(singles[0], center(k.bin))
	check(not k.cards.has(singles[0]), "trash consumes group without returning inventory")
	var tool_count = k.cards.size()
	var cut = tool("切")
	await drag(cut, center(k.bin))
	check(k.cards.size() == tool_count and k.WORK_AREA.encloses(Rect2(cut.position, cut.size)), "tools cannot be trashed or leave work area")
	cut.position = Vector2(176, 230)
	await click(tool("搅拌"))
	check(tool("搅拌").expanded, "tool explanation expands locally")
	check(tool("搅拌").title_label.size.y + 16 <= tool("搅拌").size.y + 1, "tool detail text fits inside card")
	await snapshot("tool-detail")
	await click(tool("搅拌"))
	# 实际鼠标完成：小麦→面粉→面糊→蛋糕。
	var wheat = ingredient("小麦")
	await process_frame
	await drag(wheat, center(tool("磨")))
	check(wheat.items[0]["form"] == "面粉", "grinding transforms wheat to flour")
	var milk = ingredient("牛奶")
	await process_frame
	await drag(milk, center(wheat))
	var new_egg = ingredient("鸡蛋")
	await process_frame
	await drag(new_egg, center(wheat))
	await drag(wheat, center(tool("搅拌")))
	check(wheat.kind == "ingredient" and wheat.data["intermediate"] == "面糊", "mixing flour milk egg makes batter intermediate")
	await snapshot("batter-preview")
	await drag(wheat, center(tool("烤")))
	check(wheat.kind == "dish" and wheat.dish_name == "原味蛋糕", "baking batter makes named cake")
	await click(wheat)
	check(wheat.detail_text.contains("+"), "dish detail displays tag weights")
	check(wheat.title_label.size.y + 16 <= wheat.size.y + 1, "weighted dish description fits within card")
	await snapshot("cake-detail")
	await click(wheat)
	await drag(wheat, center(k.outlet))
	check(game.dining.dishes.size() == 1 and not k.cards.has(wheat), "drop on outlet transfers cake exactly once")
	check(game.current_page == "后厨", "outlet transfer keeps player in kitchen")
	# 饮品不需要再次加热。
	var berry = ingredient("草莓")
	await process_frame
	await drag(berry, center(tool("榨")))
	var milk2 = ingredient("牛奶")
	await process_frame
	await drag(milk2, center(berry))
	await drag(berry, center(tool("搅拌")))
	check(berry.kind == "dish" and berry.dish_name == "草莓奶昔", "juiced strawberry plus milk becomes drink directly")
	await drag(berry, center(k.outlet))
	var potato = ingredient("土豆")
	await process_frame
	await drag(potato, center(tool("烤")))
	await drag(potato, center(k.outlet))
	check(game.dining.dishes.size() == 3, "initial output tray capacity three")
	var extra = ingredient("土豆")
	await process_frame
	await drag(extra, center(tool("炸")))
	await drag(extra, center(k.outlet))
	check(k.cards.has(extra) and game.dining.dishes.size() == 3, "full tray retains fourth dish without loss")
	clear_notices()
	game.day = 2
	game.money = 200
	game.open_menu("升级")
	await process_frame
	await snapshot("upgrade-window")
	await click(game.menu_content.get_child(2))
	check(game.tray_capacity == 6 and game.money == 155, "upgrade menu expands output tray and debits coins")
	await click(game.menu_content.get_child(1))
	check(k.equipment_upgraded and game.money == 95, "kitchen expansion available only in upgrade window")
	game.menu.hide()
	clear_notices()
	await drag(extra, center(k.outlet))
	check(game.dining.dishes.size() == 4, "upgraded tray accepts fourth dish")
	game.show_page("餐厅")
	clear_notices()
	await snapshot("output-tray")
	game.dining.open_day()
	clear_notices()
	var guest = game.dining.guests[0]
	game.dining.accept_order(guest)
	guest.data["ingredient"] = "小麦"
	clear_notices()
	var cake = game.dining.dishes[0]
	await drag(cake, center(guest))
	check(game.dining.served == 1 and game.dining.dishes.size() == 3, "dish dragged from tray to customer completes service")
	clear_notices()
	# 每个文档配方都通过同一 use_tool 制作；输出用于生成文档。
	game.show_page("后厨")
	clear_table()
	var report = []
	for recipe in game.rules.database["recipes"]:
		var all_items = []
		for food in recipe["ingredients"]:
			var unit = k.create_card("ingredient", [game.rules.raw_item(food)])
			for step in recipe["prep"].get(food, []):
				k.use_tool(unit, tool(step))
			all_items.append_array(unit.items.duplicate(true))
			k.remove_card(unit)
		var group = k.create_card("ingredient", all_items)
		if recipe["mix"]:
			k.use_tool(group, tool("搅拌"))
		k.use_tool(group, tool(recipe["method"]))
		check(group.kind == "dish" and group.dish_name == recipe["name"], "recipe: " + recipe["name"])
		report.append({"name": group.dish_name, "method": group.cooking_method, "weights": group.data["weights"], "base": game.recipes[group.data["recipe"]]["base"]})
		k.remove_card(group)
	var file = FileAccess.open("res://recipe_verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var raw = game.rules.raw_item("番茄")
	var two = game.rules.weights([raw, raw], "煮")
	var three = game.rules.weights([raw, raw, raw], "煮")
	check(two["酸"] == 20 and two["多汁"] == 10 and two["超浓"] == 20, "two tomatoes exact example weights")
	check(three["酸"] == 30 and three["多汁"] == 20 and three["极浓"] == 30, "three tomatoes exact example weights")
	var processed = [game.rules.raw_item("番茄")]
	game.rules.process_items(processed, "切")
	game.rules.process_items(processed, "榨")
	var initial_weights = game.rules.weights(processed, "煮")
	game.rules.process_items(processed, "榨")
	check(game.rules.weights(processed, "煮") == initial_weights, "repeat same processing never farms tag weight")
	check(processed[0]["history"] == ["切", "榨"], "processing history retained")
	var random_items = [game.rules.raw_item("鱼"), game.rules.raw_item("苹果")]
	var name = game.rules.dish_name(random_items, "烤")
	random_items.reverse()
	check(game.rules.dish_name(random_items, "烤") == name and not name.contains("未知"), "unlisted combinations named deterministically")
	# 主厨从大组取料时，满桌不能凭空挤出新卡，也不能先扣料。
	clear_table()
	var chef_recipe = -1
	for i in range(game.recipes.size()):
		if game.recipes[i]["name"] == "番茄炒蛋":
			chef_recipe = i
	var chef_group = k.create_card("ingredient", [game.rules.raw_item("番茄"), game.rules.raw_item("鸡蛋"), game.rules.raw_item("苹果")])
	while k.cards.size() < k.capacity():
		k.create_card("ingredient", [game.rules.raw_item("苹果")])
	check(not k.auto_cook(chef_recipe) and chef_group.items.size() == 3, "chef full table keeps ingredients intact")
	k.remove_card(k.cards.back())
	check(k.auto_cook(chef_recipe) and chef_group.items.size() == 1 and k.cards.back().dish_name == "番茄炒蛋", "chef consumes exact raw items and preserves leftovers")
	clear_table()
	game.inventory["番茄"] = 0
	var before_count = k.cards.size()
	check(not k.add_ingredient("番茄") and k.cards.size() == before_count, "empty inventory cannot create ingredients")
	# 农场与畜棚回归，确认新卡片详情不影响收集。
	game.show_page("农场")
	clear_notices()
	game.money = 400
	game.farm.buy_plot()
	game.farm.buy_seed("小麦")
	game.farm.toggle_seeds()
	await process_frame
	await drag(game.farm.seed_cards[0], center(game.farm.plots[0]))
	check(game.farm.plots[0].data["crop"] == "小麦", "farm seed drag regression")
	game.farm.advance(20)
	await click(game.farm.plots[0])
	await create_timer(0.4).timeout
	game.farm.toggle_collect()
	var stock = game.inventory["小麦"]
	await drag(game.farm.produce[0], center(game.farm.collector))
	check(game.inventory["小麦"] == stock + 1, "farm collection regression")
	game.show_page("畜棚")
	clear_notices()
	game.barn.build_home("鸡")
	game.barn.enter_pen("鸡")
	game.barn.buy_animal()
	game.barn.buy_feed()
	game.barn.buy_feed()
	game.barn.place_feed(Vector2(430, 280))
	game.barn.place_feed(Vector2(450, 280))
	for i in range(250):
		game.barn.advance(0.1)
	check(game.barn.animals[0].data["growth"] == 2 and game.barn.produce.size() == 1, "animal feeding growth and egg regression")
	clear_notices()
	game.barn.toggle_collect()
	var egg_stock = game.inventory["鸡蛋"]
	await process_frame
	await drag(game.barn.produce[0], center(game.barn.collector))
	check(game.inventory["鸡蛋"] == egg_stock + 1, "egg collection regression")
	game.open_menu("帮助")
	await snapshot("help-window")
	check(game.menu.visible and game.menu.get_script() == load("res://floating_window.gd"), "guidance uses draggable resizable windows")
	print("COOKING CHECKS: ", checks, " checks, ", failures, " failures")
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	quit(failures)
