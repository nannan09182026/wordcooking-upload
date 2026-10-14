extends SceneTree
# 可重复的鼠标交互检查；advance 只用来快进生长，不跳过投放、合成、收集。
var game
var failures = 0
var checks = 0

func _initialize():
	call_deferred("run")

func check(condition, message):
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func motion(point):
	var event = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func button_at(point, pressed):
	var event = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func click(node):
	var point = node.global_position + node.size / 2
	motion(point)
	button_at(point, true)
	button_at(point, false)
	await process_frame

func drag(card, point):
	var from = card.global_position + card.size / 2
	motion(from)
	button_at(from, true)
	motion(point)
	button_at(point, false)
	await process_frame

func center(node):
	return node.global_position + node.size / 2

func screenshot(filename):
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://" + filename + ".png")

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	# 关闭自动处理，让计时测试可重复；所有鼠标仍经过真实输入系统。
	game.farm.set_process(false)
	game.barn.set_process(false)
	game.dining.set_process(false)
	check(game.current_page == "餐厅" and game.nav_buttons.size() == 4, "four independent sidebar pages")
	check(not game.dining.open_day(), "cannot open without preparation")
	await click(game.nav_buttons["后厨"])
	var k = game.kitchen
	check(k.visible and not game.dining.visible, "kitchen independent from dining")
	check(k.cards.size() == 5, "kitchen contains only tools, no free ingredients")
	k.toggle_pantry()
	await process_frame
	await click(k.take_buttons[0])
	var tomato = k.cards.back()
	check(game.inventory["番茄"] == 5 and tomato.items[0]["name"] == "番茄", "UI preparation debits warehouse")
	k.toggle_pantry()
	var point = center(tomato)
	motion(point)
	button_at(point, true)
	motion(point + Vector2(3, 2))
	button_at(point + Vector2(3, 2), false)
	check(k.selected_card == tomato, "small movement remains click")
	await click(tomato)
	check(k.selected_card == null, "second click closes card detail")
	await drag(tomato, center(k.cards[1]))
	check(tomato.items[0]["process"] == "榨", "juice via actual mouse drop")
	check(not Rect2(tomato.position, tomato.size).intersects(Rect2(k.cards[1].position, k.cards[1].size)), "processing finds nearby free position")
	k.add_ingredient("番茄")
	await process_frame
	await drag(k.cards.back(), center(tomato))
	check(tomato.items.size() == 2, "ingredients stack")
	k.add_ingredient("鸡蛋")
	await process_frame
	await drag(k.cards.back(), center(tomato))
	check(tomato.items.size() == 3, "group accepts further ingredients")
	await drag(tomato, center(k.cards[3]))
	check(tomato.kind == "dish" and tomato.tags == ["超浓", "细腻", "酥脆", "酸甜", "鲜香"], "fry tags include ingredient, quantity, processing and method")
	check(game.recipes.size() == 1 and not game.recipes[0]["listed"], "new recipe recorded but not automatically listed")
	game.record_recipe(tomato)
	check(game.recipes.size() == 1, "same recipe not duplicated")
	game.open_menu("菜谱")
	await process_frame
	await screenshot("recipes-preview")
	game.menu.hide()
	await drag(k.cards[0], Vector2(1180, 600))
	check(k.WORK_AREA.encloses(Rect2(k.cards[0].position, k.cards[0].size)), "tools constrained to left zone")
	check(k.calculate_tags([{"name": "土豆", "process": "切"}, {"name": "鸡蛋", "process": ""}], "煮") == ["温润", "饱腹", "鲜香"], "boil distinct ingredients")
	check(k.calculate_tags([{"name": "土豆", "process": "切"}, {"name": "鸡蛋", "process": ""}], "炒") == ["炒制", "饱腹", "鲜香"], "stir fry distinct ingredients")
	await screenshot("kitchen-preview")
	await click(game.nav_buttons["餐厅"])
	await click(game.dining.opening_button)
	check(game.phase == "营业中" and game.dining.guests.size() == 1, "open after preparation creates customer")
	var guest = game.dining.guests[0]
	check(not guest.data["accepted"], "manual receptionist required initially")
	await click(guest)
	check(guest.data["accepted"] and guest.data["ingredient"] == "番茄", "customer requests ingredient, not recipe")
	await click(game.nav_buttons["后厨"])
	await click(tomato)
	k.carry_selected()
	await process_frame
	check(game.current_page == "餐厅" and game.dining.dishes.size() == 1 and not k.cards.has(tomato), "carry transfers dish exactly once")
	var tray_dish = game.dining.dishes[0]
	game.dining.click_dish(tray_dish)
	game.dining.return_dish()
	check(game.dining.dishes.is_empty() and k.cards.back().kind == "dish", "dish can return to kitchen without duplication")
	k.selected_card = k.cards.back()
	k.carry_selected()
	await process_frame
	var balance = game.money
	await screenshot("dining-preview")
	await drag(game.dining.dishes[0], center(guest))
	check(game.dining.served == 1 and game.dining.dishes.is_empty(), "mouse serve consumes dish and completes order")
	check(game.money > balance and game.daily_tips == 10, "majority preferences produce extra tips")
	check(game.learned["林小姐"].size() == 3, "preferences learned through feedback")
	game.dining.spawn_guest()
	var waiting = game.dining.guests[0]
	check(not game.dining.close_day(), "cannot settle with outstanding guest")
	game.dining.accept_order(waiting)
	game.dining.click_guest(waiting)
	check(game.dining.guests.has(waiting), "click accepted customer inspects without cancellation")
	game.dining.cancel_selected()
	check(game.dining.refused == 1, "cancel order is available without payment")
	game.dining.close_day()
	check(game.phase == "夜晚" and game.menu.visible, "daily settlement displayed")
	var after_close = game.money
	game.dining.close_day()
	check(game.money == after_close, "settlement cannot be paid twice")
	game.next_day()
	check(game.day == 2 and game.phase == "早晨", "next morning resets daily totals")
	# 农场：空白开始、购买、拖种、成熟、散落、拖箱入库。
	await click(game.nav_buttons["农场"])
	var farm = game.farm
	check(farm.plots.is_empty(), "farm initially empty")
	farm.buy_plot()
	farm.buy_seed("小麦")
	farm.toggle_seeds()
	await process_frame
	await drag(farm.seed_cards[0], center(farm.plots[0]))
	check(farm.seeds["小麦"] == 0 and farm.plots[0].data["crop"] == "小麦", "drag seed plants and consumes stock")
	check(not farm.plant(farm.plots[0], "番茄"), "occupied land rejects planting")
	farm.advance(9)
	check(farm.plots[0].progress > 0 and farm.plots[0].progress < 1, "crop progress advances")
	await screenshot("farm-growing-preview")
	farm.advance(10)
	check(farm.plots[0].caption == "成熟的小片小麦", "mature plot changes label")
	await click(farm.plots[0])
	await create_timer(0.4).timeout
	check(farm.produce.size() == 3 and farm.plots[0].data["crop"] == "", "harvest scatters three crops and clears land")
	var crop = farm.produce[0]
	var crop_point = center(farm.collector)
	await drag(crop, crop_point)
	check(farm.produce.size() == 3 and game.inventory["小麦"] == 0, "closed collection box does not collect")
	farm.toggle_collect()
	await process_frame
	# 已在目标处的卡片先挪开，再拖入。
	await drag(crop, Vector2(700, 500))
	await drag(crop, crop_point)
	check(farm.produce.size() == 2 and game.inventory["小麦"] == 1, "crop reaches collector and enters warehouse")
	for other in farm.produce.duplicate():
		await drag(other, crop_point)
	farm.upgrade_plot(farm.plots[0])
	check(farm.plots[0].data["large"], "day two permits land upgrade")
	farm.buy_seed("番茄")
	farm.plant(farm.plots[0], "番茄")
	farm.advance(20)
	await click(farm.plots[0])
	await create_timer(0.4).timeout
	check(farm.produce.size() == 7, "large plot yields seven scattered crops")
	await screenshot("farm-preview")
	await click(game.nav_buttons["后厨"])
	var wheat_stock = game.inventory["小麦"]
	k.add_ingredient("小麦")
	check(game.inventory["小麦"] == wheat_stock - 1 and k.cards.back().items[0]["name"] == "小麦", "farm harvest usable in kitchen")
	k.selected_card = k.cards.back()
	k.return_selected()
	check(game.inventory["小麦"] == wheat_stock, "return ingredient restores exactly one unit")
	# 畜棚。
	await click(game.nav_buttons["畜棚"])
	var barn = game.barn
	check(barn.home_cards.is_empty(), "barn initially empty")
	barn.build_home("鸡")
	await process_frame
	await click(barn.home_cards["鸡"])
	check(barn.current == "鸡" and barn.pen_page.visible, "click coop enters pen with local actions")
	barn.buy_animal()
	barn.buy_feed()
	barn.buy_feed()
	barn.toggle_feed()
	await process_frame
	await drag(barn.feed_card, Vector2(520, 300))
	check(barn.feed == 1 and barn.foods.size() == 1, "feed drag consumes one stock and places food")
	var chicken = barn.animals[0]
	var first_pos = chicken.position
	barn.advance(0.2)
	check(chicken.position != first_pos, "animal hops and approaches food")
	for i in range(50):
		barn.advance(0.1)
	check(chicken.data["growth"] == 1 and barn.foods.is_empty(), "chick eats first food and grows")
	await drag(barn.feed_card, Vector2(580, 300))
	for i in range(65):
		barn.advance(0.1)
	check(chicken.data["growth"] == 2 and chicken.caption == "鸡", "second meal matures chick")
	game.show_page("农场")
	barn.advance(15)
	check(barn.produce.size() == 1, "mature chicken produces egg while another page visible")
	game.show_page("畜棚")
	barn.toggle_collect()
	await process_frame
	var eggs_before = game.inventory["鸡蛋"]
	await screenshot("barn-preview")
	await drag(barn.produce[0], center(barn.collector))
	check(game.inventory["鸡蛋"] == eggs_before + 1 and barn.produce.is_empty(), "egg dragged into collector reaches warehouse")
	barn.advance(50)
	check(barn.produce.is_empty(), "chicken needs another meal before next egg")
	barn.upgrade_home()
	check(barn.upgraded["鸡"], "coop upgrade works")
	# 非法资金购买不能增加资产。
	var saved_money = game.money
	game.money = 0
	var before_plots = farm.plots.size()
	farm.buy_plot()
	check(farm.plots.size() == before_plots and game.money == 0, "insufficient funds never creates asset")
	game.money = 500
	for type in ["兔", "猪"]:
		barn.leave_pen()
		barn.build_home(type)
		barn.enter_pen(type)
		barn.buy_animal()
		var animal = barn.animals.back()
		for meal in range(2):
			barn.buy_feed()
			barn.place_feed(animal.position + Vector2(30, 0))
			for i in range(30):
				barn.advance(0.1)
		check(animal.data["growth"] == 2, type + " grows from actual feeding")
		await process_frame
		await click(animal)
		check(not barn.animals.has(animal), type + " dispatch consumes animal once")
		if not barn.collector.visible:
			barn.toggle_collect()
		for product in barn.produce.duplicate():
			if product.data["type"] == type:
				await drag(product, center(barn.collector))
		check(game.inventory[barn.PRODUCTS[type]] == 3, type + " products collected")
	# 定价与雇员；仍使用真实桌面食材扣除。
	game.show_page("后厨")
	k.upgrade_equipment()
	check(k.equipment_upgraded, "kitchen equipment upgrade expands capacity")
	var cost_before = game.money
	k.upgrade_equipment()
	check(game.money == cost_before, "equipment upgrade cannot charge twice")
	k.add_ingredient("番茄")
	k.add_ingredient("番茄")
	k.add_ingredient("鸡蛋")
	game.recipes[0]["listed"] = true
	game.recipes[0]["markup"] = 20
	game.show_page("餐厅")
	game.dining.open_day()
	check(game.dining.limit == 3, "20 percent markup lowers daily demand to three")
	var expensive = game.dining.guests[0]
	game.dining.accept_order(expensive)
	var old_markup = expensive.data["markup"]
	game.recipes[0]["markup"] = -20
	check(expensive.data["markup"] == old_markup, "accepted quote unaffected by later price change")
	game.dining.click_guest(expensive)
	game.dining.cancel_selected()
	game.dining.close_day()
	game.next_day()
	game.money = 500
	game.hire("前台")
	game.hire("主厨")
	game.hire("传菜")
	check(game.staff.values().count(true) == 3, "day three permits three employee roles")
	game.menu.hide()
	game.dining.open_day()
	check(game.dining.limit == 7, "discount increases demand")
	check(game.dining.guests[0].data["accepted"], "reception employee accepts order")
	var prepared_before = k.prepared_count()
	game.dining.run_staff()
	check(game.dining.served == 1 and k.prepared_count() == prepared_before - 3, "chef and runner consume prepared ingredients and serve")
	game.dining.close_day()
	check(game.dining.last_summary.contains("工资 18"), "daily wages included in settlement")
	await screenshot("settlement-preview")
	var inventory_before = game.inventory.duplicate()
	k.reset_table()
	k.reset_table()
	check(game.inventory == inventory_before, "repeated organize cannot generate ingredients")
	# 额外边界与界面按钮：钱、菜单、错误配料、隐藏页、上限。
	game.next_day()
	game.show_page("后厨")
	game.open_menu("商店")
	await process_frame
	var before_buy = game.inventory["番茄"]
	var before_money = game.money
	await click(game.menu_content.get_child(1))
	check(game.inventory["番茄"] == before_buy + 1 and game.money == before_money - 2, "shop UI debits coins and adds stock")
	game.menu.hide()
	game.open_menu("菜谱")
	await process_frame
	await click(game.menu_content.get_child(5))
	check(game.recipes[0]["markup"] == -10, "recipe price button changes markup by ten")
	await click(game.menu_content.get_child(3))
	check(not game.recipes[0]["listed"], "recipe unlisting button works")
	game.menu.hide()
	for role in game.staff:
		game.staff[role] = false
	k.add_ingredient("土豆")
	var potato = k.cards.back()
	k.add_ingredient("土豆")
	await process_frame
	await drag(k.cards.back(), center(potato))
	var boil_tool = null
	for card in k.cards:
		if card.kind == "tool" and card.tool_name == "煮":
			boil_tool = card
	await drag(potato, center(boil_tool))
	game.show_page("餐厅")
	game.dining.open_day()
	var needs_tomato = game.dining.guests[0]
	game.dining.add_dish(potato)
	k.remove_card(potato)
	var wrong = game.dining.dishes.back()
	await process_frame
	await drag(wrong, center(needs_tomato))
	check(game.dining.dishes.has(wrong) and game.dining.served == 0, "unaccepted order rejects serving without consuming dish")
	await click(needs_tomato)
	await drag(wrong, center(needs_tomato))
	check(game.dining.dishes.has(wrong) and game.dining.served == 0, "wrong ingredient rejected without consuming dish")
	game.show_page("后厨")
	k.add_ingredient("番茄")
	var single = k.cards.back()
	await process_frame
	await drag(single, center(boil_tool))
	check(single.kind == "ingredient", "single ingredient cannot be cooked as a group")
	var before_bad_drop = single.items.duplicate(true)
	await drag(single, Vector2(1050, 480))
	check(single.items == before_bad_drop, "empty-space drop preserves ingredient")
	var mouse_start = center(single)
	motion(mouse_start)
	button_at(mouse_start, true)
	motion(mouse_start + Vector2(30, 30))
	game.show_page("农场")
	button_at(mouse_start + Vector2(30, 30), false)
	check(not single.pressed and not single.dragging, "page change cancels in-progress drag")
	var plot_count = farm.plots.size()
	game.money = 1000
	for i in range(8):
		farm.buy_plot()
	check(farm.plots.size() == 6, "farm respects plot capacity")
	var seed_before = farm.seeds["土豆"]
	farm.toggle_seeds()
	await process_frame
	await drag(farm.seed_cards[2], Vector2(1130, 580))
	check(farm.seeds["土豆"] == seed_before, "invalid seed drop never consumes stock")
	game.show_page("畜棚")
	barn.enter_pen("鸡")
	for i in range(8):
		barn.buy_animal()
	var chickens = 0
	for animal in barn.animals:
		if animal.data["type"] == "鸡":
			chickens += 1
	check(chickens == 6, "upgraded coop enforces six-animal capacity")
	check(barn.foods.is_empty(), "all consumed food removed from world")
	# 备料不足的主厨不得扣除一半材料；分组上限不得吃掉溢出卡。
	game.show_page("后厨")
	game.money = 1000
	k.reset_table()
	game.inventory["番茄"] = 8
	k.add_ingredient("番茄")
	var lone_tomato = k.cards.back()
	var count_before_auto = k.prepared_count()
	check(not k.auto_cook(0) and k.prepared_count() == count_before_auto, "incomplete recipe leaves all prepared stock intact")
	for i in range(5):
		k.add_ingredient("番茄")
		await process_frame
		await drag(k.cards.back(), center(lone_tomato))
	check(lone_tomato.items.size() == 6, "group accepts up to six ingredients")
	k.add_ingredient("番茄")
	var seventh = k.cards.back()
	await process_frame
	await drag(seventh, center(lone_tomato))
	check(lone_tomato.items.size() == 6 and k.cards.has(seventh), "seventh ingredient remains separate without loss")
	var processing_tool = null
	for tool in k.cards:
		if tool.kind == "tool" and tool.tool_name == "榨":
			processing_tool = tool
	await drag(lone_tomato, center(processing_tool))
	check(lone_tomato.items[0]["process"] == "", "processing rejects group without mutating ingredients")
	game.show_page("畜棚")
	game.open_menu("帮助")
	await screenshot("help-preview")
	game.menu.hide()
	print("GAME CHECKS: ", checks, " checks, ", failures, " failures")
	quit(failures)
