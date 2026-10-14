extends "res://test_cooking.gd"
func cook(recipe):
	clear_table()
	var units = []
	for food in recipe["ingredients"]:
		var card = k.create_card("ingredient", [game.rules.raw_item(food)])
		for step in recipe["prep"].get(food, []):
			k.use_tool(card, tool(step))
		units.append_array(card.items.duplicate(true))
		k.remove_card(card)
	var dish = k.create_card("ingredient", units)
	if recipe["mix"]:
		k.use_tool(dish, tool("搅拌"))
	k.use_tool(dish, tool(recipe["method"]))
	return dish
func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	k = game.kitchen
	game.farm.set_process(false)
	game.barn.set_process(false)
	game.dining.set_process(false)
	game.show_page("后厨")
	clear_notices()
	var ui = game.supplies
	check(game.inventory.size() == 26 and game.rules.database["recipes"].size() == 46, "26 foods and 46 official recipes")
	check(game.inventory["牛肉"] == 0 and game.inventory["松露"] == 0, "premium stock is not given free")
	game.open_menu("仓库")
	await create_timer(0.2).timeout
	check(ui.warehouse_cards.size() == 26, "warehouse shows all stock without duplicates")
	ui.choose_warehouse("有库存")
	await process_frame
	check(ui.warehouse_cards.size() == 14, "in-stock filter excludes unavailable premium stock")
	ui.choose_warehouse("奶香")
	await process_frame
	check(ui.warehouse_cards.has("牛奶") and ui.warehouse_cards.has("奶酪") and not ui.warehouse_cards.has("牛肉"), "taste filter uses ingredient tags")
	await click(ui.warehouse_cards["奶酪"])
	check(ui.warehouse_selected == "奶酪", "stock card expands detail")
	await process_frame
	await click(ui.warehouse_cards["奶酪"])
	check(ui.warehouse_selected == "", "stock card closes detail")
	ui.choose_warehouse("饮品")
	await process_frame
	check(ui.warehouse_cards.has("香草荚") and ui.warehouse_cards.has("可可豆"), "usage filter includes new drink ingredients")
	check(not ui.warehouse_cards.has("小麦") and not ui.warehouse_cards.has("鸡蛋"), "drink usage excludes wheat and eggs")
	await snapshot("orange-warehouse")
	ui.choose_warehouse("甜")
	check(ui.warehouse_cards.has("草莓") and ui.warehouse_cards.has("苹果"), "sweet filter includes sweet and sour fruit")
	ui.choose_warehouse("全部")
	game.menu.size_index = 0
	game.menu.apply_size()
	game.refresh_menu()
	await create_timer(0.2).timeout
	check(ui.warehouse_scroll.get_child(0).columns == 1, "small warehouse uses one column")
	check(ui.warehouse_scroll.get_global_rect().end.x <= game.menu.get_global_rect().end.x - 10, "warehouse columns stay inside small window")
	check(game.menu.scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "warehouse avoids redundant outer scrolling")
	await snapshot("orange-warehouse-small")
	game.open_menu("商店")
	ui.choose_tier(1)
	await create_timer(0.2).timeout
	check(game.menu.tabs.position.y + game.menu.tabs.size.y <= game.menu.scroll.position.y, "small shop category tabs do not overlap content")
	check(game.menu.scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "shop restores content scrolling after warehouse")
	await snapshot("orange-shop-locked-small")
	game.menu.size_index = 1
	game.menu.apply_size()
	game.refresh_menu()
	await snapshot("orange-shop-locked")
	check(not ui.can_buy("牛肉") and ui.shop_cards.is_empty(), "locked store does not expose purchasable goods")
	game.buy_food("牛肉")
	check(game.inventory["牛肉"] == 0, "legacy purchase path also respects store lock")
	game.day = 4
	game.money = 1000
	check(not ui.can_unlock(1), "day and money alone cannot unlock")
	for recipe in game.rules.database["recipes"].slice(0, 8):
		cook(recipe)
	game.open_menu("商店")
	ui.choose_tier(1)
	check(ui.can_unlock(1), "eight different official recipes qualify for middle store")
	game.day = 3
	check(not ui.can_unlock(1), "early day still blocks unlock")
	game.day = 4
	var money_before = game.money
	ui.unlock_tier()
	check(game.shops["中级"] and game.money == money_before - 180, "middle unlock charges once")
	ui.unlock_tier()
	check(game.money == money_before - 180, "repeat unlock cannot charge again")
	check(ui.shop_cards.size() == 6, "middle store has exactly six goods")
	await process_frame
	await click(ui.shop_cards["牛肉"]["buy"])
	check(game.inventory["牛肉"] == 1 and game.money == money_before - 188, "new ingredient purchase updates stock and money")
	ui.choose_tier(2)
	check(not ui.can_unlock(2), "advanced store requires further progression")
	for recipe in game.rules.database["recipes"].slice(8, 18):
		cook(recipe)
	game.day = 8
	game.money = 479
	check(not ui.can_unlock(2), "insufficient unlock fee is rejected")
	game.money = 1000
	game.open_menu("商店")
	ui.choose_tier(2)
	ui.unlock_tier()
	check(game.shops["高级"] and game.money == 520 and ui.shop_cards.size() == 6, "advanced store unlocks six ingredients for 480")
	await create_timer(0.2).timeout
	await snapshot("orange-shop-advanced")
	for recipe in game.rules.database["recipes"].slice(30):
		var dish = cook(recipe)
		check(dish.kind == "dish" and dish.dish_name == recipe["name"], "full recipe chain: " + recipe["name"])
		check(game.rules.rarity(dish.dish_name, dish.items) == recipe["rarity"], "recipe rarity: " + recipe["name"])
	game.open_menu("图鉴")
	game.menu.size_index = 2
	game.menu.apply_size()
	game.refresh_menu()
	await create_timer(0.2).timeout
	var rainbow = 0
	for card in game.catalog.card_grid.get_children():
		if card.has_node("RainbowRarity"):
			rainbow += 1
	check(rainbow == 2, "only two discovered legendary recipes get rainbow ribbon")
	check(game.rules.rarity("自创混合", [game.rules.raw_item("松露")]) == 2, "free creation cannot become legendary")
	game.catalog.choose_filter(4)
	game.feedback.discoveries.clear()
	await create_timer(1.6).timeout
	await snapshot("orange-catalog")
	# 独立写入旧版和新版测试文件，验证迁移与解锁持久化。
	var saves = game.save_system
	saves.prefix = "user://test_progression_" + str(Time.get_ticks_usec()) + "_"
	var current = saves.capture(game)
	check(saves.write_slot(1, current), "v2 progression save writes successfully")
	var loaded = saves.read_slot(1)
	check(loaded["shops"]["高级"] and loaded["inventory"]["牛肉"] == 1, "store unlock and premium inventory survive disk roundtrip")
	var legacy = current.duplicate(true)
	legacy["version"] = 1
	legacy.erase("shops")
	for food in game.rules.database["foods"]:
		if game.rules.database["foods"][food].get("tier", 0) > 0:
			legacy["inventory"].erase(food)
	# 使用旧版允许的菜谱，模拟真正的旧文件。
	legacy["recipes"] = []
	legacy["catalog"] = []
	legacy["kitchen"] = legacy["kitchen"].filter(func(card): return card["kind"] == "tool")
	var file = FileAccess.open(saves.path(2), FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var upgraded = saves.read_slot(2)
	check(upgraded != null and upgraded["version"] == 2 and upgraded["inventory"]["松露"] == 0 and not upgraded["shops"]["中级"], "v1 save gains empty premium stock and locked stores")
	check(JSON.parse_string(FileAccess.get_file_as_string(saves.path(2)))["version"] == 1, "reading old save never rewrites source file")
	legacy["inventory"].erase("番茄")
	check(not saves.valid_state(saves.migrate(legacy)), "migration does not disguise missing original stock")
	var restored = load("res://main.tscn").instantiate()
	root.add_child(restored)
	check(saves.restore(restored, loaded) and restored.shops["高级"] and restored.inventory["牛肉"] == 1, "saved progression restores a fresh game")
	restored.queue_free()
	print("PROGRESSION CHECKS: ", checks, " checks, ", failures, " failures")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(failures)
