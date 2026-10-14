extends "res://test_cooking.gd"
var title

func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	title = load("res://start.tscn").instantiate()
	title.saves.prefix = "user://test_slots_" + str(Time.get_ticks_usec()) + "_"
	root.add_child(title)
	await process_frame
	check(title.slot_buttons.size() == 3 and title.active_game == null, "title displays three empty slots without running a game")
	await snapshot("title-empty-preview")
	await click(title.ingredients[0]["node"])
	check(title.ingredients[0]["node"].text == "酸酸甜甜", "title food card responds to click")
	title.reduced = true
	await process_frame
	await process_frame # 帧开始信号早于节点的 _process，等完整的一帧后再检查。
	check(title.ingredients[0]["node"].position == title.ingredients[0]["base"], "reduced motion stops floating cards")
	title.reduced = false
	await click(title.slot_buttons[0])
	await create_timer(0.4).timeout
	game = title.active_game
	if game == null:
		check(false, "start failed: " + title.status.text)
		quit(1)
		return
	k = game.kitchen
	game.farm.set_process(false)
	game.barn.set_process(false)
	game.dining.set_process(false)
	check(game.slot_id == 1 and not title.login.visible, "slot click enters game and hides title")
	check(title.saves.read_slot(1)["day"] == 1, "new game writes initial morning checkpoint")
	game.money = 1800
	game.day = 3
	game.kitchen.equipment_upgraded = true
	game.tray_capacity = 6
	game.dining.update_tray()
	game.show_page("后厨")
	game.feedback.toast.hide()
	var tomato = ingredient("番茄")
	k.use_tool(tomato, tool("切"))
	var egg = ingredient("鸡蛋")
	tomato.items.append_array(egg.items)
	k.remove_card(egg)
	k.use_tool(tomato, tool("炒"))
	game.recipes[tomato.data["recipe"]]["listed"] = true
	game.recipes[tomato.data["recipe"]]["markup"] = 20
	game.dining.add_dish(tomato)
	k.remove_card(tomato)
	var raw = ingredient("土豆")
	raw.items.append(game.rules.raw_item("鸡蛋"))
	raw.position = Vector2(800, 260)
	raw.refresh()
	var flour = ingredient("小麦")
	k.use_tool(flour, tool("磨"))
	tool("切").position = Vector2(170, 210)
	game.farm.buy_plot()
	game.farm.plots[0].data = {"crop": "番茄", "elapsed": 7.5, "large": true}
	game.farm.update_plot(game.farm.plots[0])
	game.farm.seeds["土豆"] = 4
	game.farm.create_produce("小麦", Vector2(570, 300))
	for species in game.barn.TYPES:
		game.barn.build_home(species)
		game.barn.enter_pen(species)
		game.barn.buy_animal()
	game.barn.upgraded["鸡"] = true
	var chicken = game.barn.animals[0]
	chicken.data["growth"] = 2
	chicken.data["meal"] = true
	chicken.data["egg_time"] = 5.5
	game.barn.feed = 5
	game.barn.place_feed(Vector2(550, 400))
	game.barn.spawn_product("鸡", Vector2(600, 450))
	game.barn.leave_pen()
	game.staff["前台"] = true
	game.staff["主厨"] = true
	game.learned = {"林小姐": ["细腻"]}
	game.daily_income = 31
	game.daily_tips = 5
	game.show_page("餐厅")
	check(game.dining.open_day(), "populated game can open restaurant")
	game.dining.selected_guest = game.dining.guests[0]
	game.dining.cancel_selected()
	var before_money = game.money
	check(game.dining.close_day(), "closing day reaches settlement")
	check(game.money == before_money - 12 and game.last_save_ok, "wages deducted once before autosave")
	var saved = title.saves.read_slot(1)
	check(saved != null and saved["phase"] == "夜晚" and saved["day"] == 3, "night checkpoint recorded")
	var stock_matches = true
	for food in game.inventory:
		stock_matches = stock_matches and saved["inventory"][food] == game.inventory[food]
	check(saved["money"] == game.money and stock_matches, "money and warehouse saved")
	check(not game.dining.close_day() and game.money == saved["money"], "repeated close cannot charge wages again")
	await snapshot("saved-settlement-preview")
	var saved_money = game.money
	title.return_to_title()
	await process_frame
	check(title.login.visible and title.slot_buttons[0].text.contains("第 3 天"), "return shows saved day on slot")
	await snapshot("title-saved-preview")
	await title.select_slot(1)
	game = title.active_game
	k = game.kitchen
	check(game.phase == "夜晚" and game.menu_type == "结算", "continue resumes settlement without replaying day")
	check(game.money == saved_money and game.day == 3, "loading never charges wages or changes day")
	check(game.recipes[0]["markup"] == 20 and game.recipes[0]["listed"], "recipe listing and price restored")
	check(game.catalog.entries.size() == saved["catalog"].size() and not game.feedback.discovering, "catalog restored without discovery replay")
	check(game.staff["前台"] and game.staff["主厨"] and game.learned["林小姐"] == ["细腻"], "staff and known guest preferences restored")
	check(game.kitchen.equipment_upgraded and game.tray_capacity == 6, "expansions restored")
	check(game.dining.dishes.size() == 1 and game.dining.dishes[0].dish_name == "番茄炒蛋", "tray recipe reference restored")
	var restored_group = null
	var restored_flour = null
	for card in k.cards:
		if card.kind == "ingredient" and card.items.size() == 2:
			restored_group = card
		if card.kind == "ingredient" and card.items[0]["name"] == "小麦":
			restored_flour = card
	check(restored_group != null and restored_group.position == Vector2(800, 260), "raw group and table position restored")
	check(restored_flour != null and restored_flour.items[0]["form"] == "面粉", "processed intermediate restored")
	check(tool("切").position == Vector2(170, 210), "tool position restored")
	check(game.farm.plots[0].data["elapsed"] == 7.5 and game.farm.plots[0].data["large"], "field progress and expansion restored")
	check(game.farm.seeds["土豆"] == 4 and game.farm.produce.size() == 1, "seeds and uncollected crops restored")
	check(game.barn.animals.size() == 3 and game.barn.feed == 4 and game.barn.foods.size() == 1, "animals and feed restored")
	check(game.barn.animals[0].data["egg_time"] == 5.5 and game.barn.produce.size() == 1, "egg timer and uncollected product restored")
	check(game.barn.home_cards["鸡"].caption == "大鸡舍" and game.barn.voice_count == 0, "expanded homes restored silently")
	await create_timer(0.25).timeout
	check(game.farm.plots[0].data["elapsed"] == 7.5 and game.barn.animals[0].data["egg_time"] == 5.5, "night settlement freezes growth timers")
	game.next_day()
	check(game.day == 4 and game.phase == "早晨" and game.daily_cost == 0, "next day advances once and resets daily counters")
	game.farm.set_process(false)
	game.barn.set_process(false)
	game.dining.set_process(false)
	game.show_page("后厨")
	game.feedback.toast.hide()
	var old_count = k.cards.size()
	await double_click(restored_group)
	check(k.cards.size() == old_count + 1, "restored ingredient signals support double split")
	game.show_page("餐厅")
	game.dining.open_day()
	var guest = game.dining.guests[0]
	check(game.dining.serve(game.dining.dishes[0], guest), "restored dish can be served and priced")
	game.money = 9999
	title.return_to_title()
	await process_frame
	await title.select_slot(2)
	game = title.active_game
	check(game.money == 300 and game.day == 1 and game.recipes.is_empty() and game.farm.plots.is_empty(), "second slot starts independently")
	check(title.saves.read_slot(1)["money"] == saved_money, "midday changes do not overwrite closing checkpoint")
	game.farm.set_process(false)
	game.barn.set_process(false)
	game.dining.set_process(false)
	game.phase = "营业中"
	game.staff["前台"] = true
	var good_prefix = game.save_system.prefix
	game.save_system.prefix = "user://missing_save_test_directory/slot_"
	game.dining.close_day()
	check(not game.last_save_ok and game.phase == "夜晚", "save failure is visible at settlement")
	var paid_balance = game.money
	game.next_day()
	check(game.phase == "夜晚" and game.day == 1, "failed save blocks next day until retry")
	game.save_system.prefix = good_prefix
	game.retry_save()
	check(game.last_save_ok and game.money == paid_balance, "retry saves without charging wages twice")
	# 再存一次产生有效备份；损坏主文件只在隔离的测试档内制造。
	game.autosave()
	var file = FileAccess.open(title.saves.path(2), FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	check(title.saves.read_slot(2) != null and title.saves.recovered, "corrupted primary recovers backup")
	file = FileAccess.open(title.saves.path(2) + ".bak", FileAccess.WRITE)
	file.store_string("broken too")
	file.close()
	title.return_to_title()
	await process_frame
	check(title.slot_buttons[1].disabled and title.slot_buttons[1].text.contains("原文件已保留"), "two corrupt files lock slot without overwriting")
	await title.select_slot(2)
	check(title.active_game == null, "cannot silently replace unreadable slot")
	var damaged = saved.duplicate(true)
	damaged["animals"][0]["base"] = "invalid position"
	check(not title.saves.valid_state(damaged), "nested corrupt animal data rejected")
	damaged = saved.duplicate(true)
	damaged["tray"][0]["data"]["recipe"] = 999
	check(not title.saves.valid_state(damaged), "invalid recipe reference rejected before restoring")
	damaged = saved.duplicate(true)
	damaged["inventory"]["unknown"] = 1
	check(not title.saves.valid_state(damaged), "unknown stock field rejected")
	check(title.saves.read_slot(1)["money"] == saved_money, "corruption in another slot cannot affect first slot")
	await click(title.slot_buttons[2])
	await create_timer(0.4).timeout
	check(title.active_game != null and title.active_game.slot_id == 3 and title.active_game.money == 300, "third slot opens new shop despite broken second slot")
	# 记录隔离前缀供另一个游戏进程执行重启检查。
	var manifest = FileAccess.open("res://save_test_manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"prefix": title.saves.prefix, "money": saved_money}))
	manifest.close()
	print("SAVE CHECKS: ", checks, " checks, ", failures, " failures")
	title.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(failures)
