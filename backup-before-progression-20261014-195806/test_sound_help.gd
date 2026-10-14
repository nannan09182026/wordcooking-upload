extends "res://test_cooking.gd"
func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.feedback.toast.hide()
	check(is_equal_approx(game.feedback.volume, 0.5), "default sound level is fifty percent")
	game.feedback.play("click")
	var old_gain = db_to_linear(linear_to_db(0.5) - 8)
	check(abs(db_to_linear(game.feedback.players[0].volume_db) / old_gain - 3) < 0.001, "button effect amplitude is three times at equal slider value")
	check(is_equal_approx(root.get_node("Music").volume, 0.35), "background music gain remains unchanged")
	await click(game.nav_buttons["农场"])
	check(game.page_help.visible, "first farm visit opens guide")
	check(game.page_help.get_child(0).get_global_rect().get_center() == Vector2(640, 360), "guide is centered")
	await snapshot("farm-help-centered")
	await click(game.page_help_text)
	check(not game.page_help.visible, "click inside guide dismisses it")
	await click(game.nav_buttons["农场"])
	check(game.page_help.visible, "active farm navigation remains clickable to reopen guide")
	await click(game.nav_buttons["畜棚"])
	check(not game.page_help.visible and game.current_page == "农场", "dismissing click never activates underlying navigation")
	await click(game.nav_buttons["畜棚"])
	check(game.page_help.visible and game.current_page == "畜棚", "first barn visit opens its own guide")
	mouse(Vector2(1200, 680), true)
	mouse(Vector2(1200, 680), false)
	await process_frame
	check(not game.page_help.visible, "blank click dismisses guide")
	game.show_page("后厨")
	await click(game.nav_buttons["农场"])
	check(not game.page_help.visible, "later navigation does not repeatedly interrupt with guide")
	await click(game.nav_buttons["农场"])
	check(game.page_help.visible, "repeat page entry explicitly reopens guide")
	game.show_page("后厨")
	check(not game.page_help.visible, "changing page clears old guide")
	print("SOUND HELP CHECKS: ", checks, " checks, ", failures, " failures")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(failures)
