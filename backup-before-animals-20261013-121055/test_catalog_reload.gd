extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	if not "--test-reload" in OS.get_cmdline_user_args() or not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var restored = game.catalog.count_known() == 2 and game.catalog.creative_count() == 1 and game.catalog.entries.size() == 4
	var quiet = not game.feedback.discovering and game.feedback.discoveries.is_empty()
	var settings = is_equal_approx(game.feedback.volume, 0.31)
	print("RESTART: records=", restored, ", no_replay=", quiet, ", volume=", settings)
	game.queue_free()
	await process_frame
	quit(0 if restored and quiet and settings else 1)
