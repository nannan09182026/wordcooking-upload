extends SceneTree
# 开发检查：模拟真实鼠标按下、移动、松开，并检查结果。
# 不参与正常游戏。命令行加 --script res://test_workbench.gd 运行。
var game
var failures = 0

func _initialize():
	call_deferred("run_checks")

func check(condition, message):
	if condition:
		print("PASS: ", message)
	else:
		push_error("FAIL: " + message)
		failures += 1

func mouse_button(point, down):
	var event = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)

func motion(point):
	var event = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func drag(card, target_point):
	var from = card.position + card.size / 2
	motion(from)
	mouse_button(from, true)
	motion(target_point)
	mouse_button(target_point, false)
	await process_frame

func run_checks():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://prototype-preview.png")
	check(game.cards.size() == 8, "initial five tools and three ingredients")
	var cut = game.cards[0]
	var juice = game.cards[1]
	var fry = game.cards[3]
	var tomato = game.cards[5]
	var old_position = tomato.position
	var point = tomato.position + tomato.size / 2
	motion(point)
	mouse_button(point, true)
	motion(point + Vector2(3, 2))
	mouse_button(point + Vector2(3, 2), false)
	check(game.selected_card == tomato and tomato.position == old_position, "small movement is click")
	mouse_button(point, true)
	mouse_button(point, false)
	check(game.info_label.text == "", "second click closes explanation")
	await drag(tomato, juice.position + juice.size / 2)
	check(tomato.items[0]["process"] == "榨", "mouse drag applies juice")
	check(not Rect2(tomato.position, tomato.size).intersects(Rect2(juice.position, juice.size)), "processed ingredient placed beside tool")
	game.add_ingredient("番茄")
	await process_frame
	var second = game.cards.back()
	await drag(second, tomato.position + tomato.size / 2)
	check(tomato.items.size() == 2, "mouse drop merges ingredients")
	await drag(game.cards[6], tomato.position + tomato.size / 2)
	check(tomato.items.size() == 3, "group accepts another ingredient")
	await drag(tomato, fry.position + fry.size / 2)
	check(tomato.kind == "dish", "mouse drop cooks a group")
	check(tomato.tags == ["超浓", "细腻", "酥脆"], "dish has exact expected tags")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://cooking-preview.png")
	await drag(cut, Vector2(1150, 680))
	check(game.WORK_AREA.encloses(Rect2(cut.position, cut.size)), "tool stays within left area")
	game.show_page("农场")
	check(game.placeholder.visible and not game.restaurant.visible, "farm placeholder")
	game.show_page("畜棚")
	check(game.placeholder.text.begins_with("畜棚"), "barn placeholder")
	game.show_page("餐厅")
	check(game.restaurant.visible and tomato.kind == "dish", "return preserves workbench")
	var plain = [{"name": "鸡蛋", "process": ""}, {"name": "土豆", "process": "切"}]
	check(game.calculate_tags(plain, "煮") == ["温润"], "boil without duplicate or juice")
	check(game.calculate_tags(plain, "炒") == ["炒制"], "stir fry tag")
	game.reset_table()
	await process_frame
	check(game.cards.size() == 8 and game.selected_card == null, "reset restores clean table")
	print("WORKBENCH CHECKS: ", failures, " failures")
	quit(failures)
