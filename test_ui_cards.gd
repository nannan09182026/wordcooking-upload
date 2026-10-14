extends "res://test_polish.gd"
var supplies

func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	k = game.kitchen
	supplies = game.supplies
	game.farm.set_process(false)
	game.barn.set_process(false)
	game.dining.set_process(false)
	game.show_page("后厨")
	game.feedback.toast.hide()
	game.open_menu("食材箱")
	await create_timer(0.2).timeout
	check(game.menu_veil.visible and game.menu_veil.modulate.a == 1, "opening menu fades in white veil")
	check(supplies.food_sources.size() == 6, "pantry initially shows six vegetables")
	await snapshot("pantry-cards-preview")
	var before_stock = game.inventory["番茄"]
	await click(supplies.food_sources["番茄"])
	check(game.inventory["番茄"] == before_stock - 1 and k.cards.back().items[0]["name"] == "番茄", "click takes one food")
	check(not game.menu.visible and not game.menu_veil.visible, "click take reveals placed food")
	game.open_menu("食材箱")
	await process_frame
	var source = supplies.food_sources["土豆"]
	before_stock = game.inventory["土豆"]
	await drag(source, Vector2(1090, 300))
	check(game.inventory["土豆"] == before_stock - 1 and k.cards.back().items[0]["name"] == "土豆", "drag takes one food onto workspace")
	check(k.cards.back().position.distance_to(Vector2(1052, 282)) < 5, "drag uses pointer drop position")
	check(game.menu.modulate.a == 1 and game.menu_veil.modulate.a == 1, "drag restores window and veil")
	await process_frame
	before_stock = game.inventory["番茄"]
	await drag(supplies.food_sources["番茄"], Vector2(40, 250))
	check(game.inventory["番茄"] == before_stock, "outside table drop consumes nothing")
	await drag(supplies.food_sources["番茄"], game.menu.position + Vector2(150, 120))
	check(game.inventory["番茄"] == before_stock, "drop back into window consumes nothing")
	await drag(supplies.food_sources["番茄"], center(k.bin))
	check(game.inventory["番茄"] == before_stock, "drag to trash does not take food out of pantry")
	motion(center(supplies.food_sources["番茄"]))
	mouse(center(supplies.food_sources["番茄"]), true)
	motion(Vector2(1090, 500))
	check(game.menu.modulate.a < 0.2 and game.menu_veil.modulate.a == 0, "drag fades menu and removes veil for placement")
	var cancel = InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	mouse(Vector2(1090, 500), false)
	check(game.inventory["番茄"] == before_stock and game.menu.modulate.a == 1, "escape cancels ingredient drag without stock change")
	await drag(supplies.food_sources["番茄"], center(tool("切")))
	check(game.inventory["番茄"] == before_stock - 1 and k.cards.back().items[0]["process"] == "切", "drag from pantry onto tool processes ingredient")
	var fillers = []
	while k.cards.size() < k.capacity():
		fillers.append(k.create_card("ingredient", [game.rules.raw_item("小麦")]))
	await process_frame
	before_stock = game.inventory["番茄"]
	await drag(supplies.food_sources["番茄"], Vector2(1090, 500))
	check(game.inventory["番茄"] == before_stock and k.cards.size() == k.capacity(), "full workbench refuses drag without consuming stock")
	for card in fillers:
		k.remove_card(card)
	game.feedback.toast.hide()
	supplies.choose_pantry("蛋奶")
	await process_frame
	check(supplies.food_sources.keys() == ["鸡蛋", "牛奶", "奶酪"], "category changes food list")
	game.inventory["牛奶"] = 0
	game.refresh_menu()
	await process_frame
	var count = k.cards.size()
	await click(supplies.food_sources["牛奶"])
	check(k.cards.size() == count and game.inventory["牛奶"] == 0, "empty stock cannot spawn")
	# 遮罩点击关闭，但不能顺便取食材或点工具。
	mouse(Vector2(1200, 650), true)
	mouse(Vector2(1200, 650), false)
	await process_frame
	check(not game.menu.visible and not game.menu_veil.visible, "outside click closes modal and veil")
	game.open_menu("商店")
	await process_frame
	await click(k.ingredient_box)
	check(not game.menu.visible and game.menu_type == "商店", "veil closing click cannot open underlying ingredient box")
	game.open_menu("商店")
	await create_timer(0.2).timeout
	check(supplies.shop_cards.size() == 14, "shop contains all fourteen foods")
	await snapshot("shop-cards-preview")
	var old_money = game.money
	var old_cost = game.daily_cost
	before_stock = game.inventory["番茄"]
	await click(supplies.shop_cards["番茄"]["plus"])
	await click(supplies.shop_cards["番茄"]["buy"])
	check(game.money == old_money - 2 * game.PRICES["番茄"] and game.daily_cost == old_cost + 2 * game.PRICES["番茄"], "quantity purchase charges correct amount once")
	check(game.inventory["番茄"] == before_stock + 2 and supplies.quantities["番茄"] == 2, "purchase adds exact stock and preserves quantity")
	check(not game.feedback.toast.visible, "purchase feedback does not show blocking text")
	supplies.choose_shop("水果")
	await process_frame
	check(supplies.shop_cards.keys() == ["苹果", "草莓"], "shop category filters goods")
	game.money = 0
	supplies.update_shop()
	before_stock = game.inventory["苹果"]
	check(supplies.shop_cards["苹果"]["buy"].disabled and supplies.shop_cards["苹果"]["plus"].disabled, "unaffordable actions disabled")
	supplies.purchase("苹果")
	check(game.inventory["苹果"] == before_stock and game.money == 0, "insufficient balance cannot purchase")
	game.menu.size_index = 0
	game.menu.apply_size()
	game.refresh_menu()
	await snapshot("shop-small-preview")
	check(game.menu_content.get_child(0).columns == 1, "small shop uses one column")
	game.menu.cycle_size()
	await process_frame
	check(game.menu_content.get_child(0).columns == 2, "resizing shop reflows columns")
	game.menu.hide()
	# 提示应锚定按钮，点击按钮的不同位置不改变提示位置。
	await click(k.outlet)
	var anchored = game.feedback.toast.position
	check(game.feedback.toast.visible and game.feedback.outlet_help, "outlet click opens anchored help")
	await click(k.outlet)
	check(not game.feedback.toast.visible, "second outlet click closes help")
	mouse(k.outlet.global_position + Vector2(8, 9), true)
	mouse(k.outlet.global_position + Vector2(8, 9), false)
	await process_frame
	check(game.feedback.toast.position == anchored, "different click position keeps help fixed")
	await snapshot("outlet-help-preview")
	mouse(Vector2(650, 640), true)
	mouse(Vector2(650, 640), false)
	await process_frame
	check(not game.feedback.toast.visible, "blank click dismisses outlet help")
	make_dish(["番茄", "鸡蛋"], "炒")
	make_dish(["鱼", "苹果"], "烤")
	game.open_menu("图鉴")
	await create_timer(0.2).timeout
	check(game.catalog.card_grid.columns == 3, "catalog medium window uses three columns")
	var locked = 0
	var unlocked = 0
	var found_card = null
	for card in game.catalog.card_grid.get_children():
		if card.disabled:
			locked += 1
		else:
			unlocked += 1
			if card.get_meta("dish_name") == "番茄炒蛋":
				found_card = card
	check(locked == game.rules.database["recipes"].size() - 1 and unlocked == 2, "catalog distinguishes discovered and unknown cards")
	await snapshot("catalog-cards-preview")
	await click(found_card)
	check(game.catalog.selected == "番茄炒蛋", "recipe card opens preparation detail")
	game.catalog.choose("")
	game.menu.cycle_size()
	await process_frame
	check(game.catalog.card_grid.columns == 4, "large catalog uses four columns")
	game.menu.cycle_size()
	await snapshot("catalog-small-preview")
	check(game.catalog.card_grid.columns == 1, "small catalog uses one column")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	check(not game.menu.visible and not game.menu_veil.visible, "escape dismisses window and veil")
	print("UI CARD CHECKS: ", checks, " checks, ", failures, " failures")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(failures)
