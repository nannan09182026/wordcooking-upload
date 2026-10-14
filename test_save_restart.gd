extends "res://test_cooking.gd"
# 单独启动一次 Godot，确认文件真正落盘，而不是只存在于内存。
func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://save_test_manifest.json"))
	var title = load("res://start.tscn").instantiate()
	title.saves.prefix = manifest["prefix"]
	root.add_child(title)
	await process_frame
	check(title.slot_buttons[0].text.contains("第 3 天"), "fresh process reads slot summary from disk")
	await click(title.slot_buttons[0])
	await create_timer(0.4).timeout
	game = title.active_game
	if game == null:
		check(false, "fresh process enters saved game")
		quit(1)
		return
	check(game.day == 3 and game.phase == "夜晚" and game.money == manifest["money"], "restart preserves day and wages")
	check(game.barn.animals.size() == 3 and game.farm.plots.size() == 1, "restart restores animals and fields")
	check(game.recipes.size() == 1 and game.catalog.entries.size() == 1 and game.dining.dishes.size() == 1, "restart restores recipe catalog and tray")
	check(game.barn.voice_count == 0 and not game.feedback.discovering, "restart does not replay animal or discovery effects")
	await snapshot("restart-settlement-preview")
	print("RESTART CHECKS: ", checks, " checks, ", failures, " failures")
	title.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(failures)
