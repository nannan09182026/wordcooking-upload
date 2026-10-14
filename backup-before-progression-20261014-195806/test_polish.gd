extends "res://test_cooking.gd"
# 使用 --test-mode，仅写 test_catalog.json，绝不修改正式图鉴。
func make_dish(foods, method, prep = ""):
	var items = []
	for food in foods:
		items.append(game.rules.raw_item(food))
	var card = k.create_card("ingredient", items)
	if prep != "":
		k.use_tool(card, tool(prep))
	k.use_tool(card, tool(method))
	return card

func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		push_error("Run with -- --test-mode")
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
	game.feedback.toast.hide()
	check(game.catalog.entries.is_empty(), "test mode starts with isolated empty catalog")
	check(game.feedback.sounds.size() == 19, "nineteen sound streams loaded")
	for sound in game.feedback.sounds.values():
		check(sound != null and sound.get_length() > 0.04 and sound.get_length() < 1.0, "sound stream duration valid")
	var dish = make_dish(["番茄", "鸡蛋"], "炒")
	check(game.catalog.count_known() == 1 and game.feedback.discovering, "first dish recorded and discovery starts")
	check(game.feedback.discovery.mouse_filter == Control.MOUSE_FILTER_IGNORE, "discovery never blocks input")
	await create_timer(0.6).timeout
	await snapshot("polish-discovery")
	var queue_size = game.feedback.discoveries.size()
	make_dish(["番茄", "鸡蛋"], "炒")
	check(game.catalog.entries.size() == 1 and game.feedback.discoveries.size() == queue_size, "repeat recipe does not repeat discovery")
	make_dish(["番茄", "鸡蛋"], "炒", "切")
	check(game.catalog.entries.size() == 2 and game.catalog.count_known() == 1, "variant grouped under same named dish")
	make_dish(["鱼", "苹果"], "烤")
	check(game.catalog.creative_count() == 1, "free combination goes to my creations")
	make_dish(["土豆"], "烤")
	check(game.feedback.discoveries.size() >= 1, "successive discoveries queued")
	check(game.catalog.save_ok and FileAccess.file_exists(game.catalog.save_path), "atomic catalog save succeeds")
	game.feedback.set_volume(0.31)
	game.feedback.toggle_mute()
	game.feedback.toggle_motion()
	game.catalog.entries.clear()
	game.catalog.load_data()
	check(game.catalog.entries.size() == 4 and game.catalog.count_known() == 2, "load restores variants and known progress")
	check(is_equal_approx(game.feedback.volume, 0.31) and game.feedback.muted and game.feedback.reduced_motion, "settings reload")
	check(game.recipes.size() == 4 and not game.recipes[0]["listed"], "catalog restores recipe book without automatic listing")
	var before_queue = game.feedback.discoveries.size()
	game.catalog.load_data()
	check(game.feedback.discoveries.size() == before_queue, "loading never replays discoveries")
	game.feedback.play("click")
	var playing = 0
	for player in game.feedback.players:
		if player.playing:
			playing += 1
	check(playing == 0, "mute stops active players and new playback")
	game.feedback.toggle_mute()
	game.feedback.last_played.clear()
	game.feedback.play("click")
	game.feedback.play("click")
	playing = 0
	for player in game.feedback.players:
		if player.playing:
			playing += 1
	check(playing == 1, "same sound has playback cooldown")
	for sound in game.feedback.sounds:
		game.feedback.play(sound)
	playing = 0
	for player in game.feedback.players:
		if player.playing:
			playing += 1
	check(playing <= 6, "voice limit enforced")
	game.catalog.save_data()
	var broken = FileAccess.open(game.catalog.save_path, FileAccess.WRITE)
	broken.store_string("{invalid")
	broken.close()
	game.catalog.entries.clear()
	game.catalog.load_data()
	check(game.catalog.entries.size() == 4, "corrupt primary catalog recovers from backup")
	check(not game.catalog.valid_entry({"name": "broken"}), "malformed record rejected")
	game.catalog.save_data()
	game.open_menu("图鉴")
	await process_frame
	check(game.menu_type == "图鉴", "catalog menu opens")
	var hidden_rows = 0
	for child in game.catalog.card_grid.get_children():
		if child is Button and child.disabled:
			hidden_rows += 1
	check(hidden_rows == 28, "undiscovered dishes hide names and recipes")
	await snapshot("polish-catalog")
	game.catalog.choose_filter(6)
	check(game.catalog.card_grid.get_child_count() == 1, "my creations filter isolates one unique creation")
	game.catalog.choose("番茄炒蛋")
	check(game.menu_content.get_child_count() == 9, "detail displays both preparation variants")
	game.menu.size_index = 0
	game.menu.apply_size()
	await snapshot("polish-catalog-small")
	game.open_menu("设置")
	await snapshot("polish-settings")
	game.menu.hide()
	game.feedback.reduced_motion = false
	clear_table()
	var tomato = ingredient("番茄")
	var target = tool("切")
	tomato.position = target.position
	k.preview_drop(tomato)
	check(game.feedback.drag_target == target, "valid tool highlights during drag")
	game.feedback.highlight(null)
	tomato.position = Vector2(720, 240)
	await drag(tomato, center(target))
	check(tomato.items[0]["process"] == "切" and game.feedback.drag_target == null, "animated drag processes ingredient and clears highlight")
	await create_timer(0.35).timeout
	check(tomato.scale.is_equal_approx(Vector2.ONE), "drop animation restores scale")
	await snapshot("polish-kitchen")
	game.dining.add_dish(make_dish(["番茄", "鸡蛋"], "炒"))
	game.show_page("餐厅")
	var slots = 0
	for slot in game.dining.tray_slots:
		if slot.visible:
			slots += 1
	check(slots == 3, "three visible tray slots initially")
	await snapshot("polish-dining")
	game.day = 2
	game.money = 500
	game.upgrade_tray()
	slots = 0
	for slot in game.dining.tray_slots:
		if slot.visible:
			slots += 1
	check(slots == 6, "tray upgrade shows six slots")
	game.menu.hide()
	game.notify("出餐台已满，请先给顾客上菜。")
	check(game.feedback.toast.visible and not game.menu.visible, "routine feedback is a nonblocking toast")
	check(game.feedback.toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "toast cannot intercept drag")
	print("POLISH CHECKS: ", checks, " checks, ", failures, " failures")
	game.queue_free()
	await process_frame
	await process_frame
	quit(failures)
