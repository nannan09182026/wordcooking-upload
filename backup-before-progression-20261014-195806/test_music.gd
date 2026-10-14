extends SceneTree
var checks = 0
var failures = 0
func _initialize():
	call_deferred("run")
func check(ok, description):
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", description)
func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	await process_frame
	var music = root.get_node("Music")
	music.settings_path = "user://test_music_run_" + str(Time.get_ticks_usec()) + ".json"
	check(music.players.size() == 2 and abs(music.length - 139.9335) < 0.01, "original stereo track loaded at full duration")
	check(not music.players[0].playing, "test mode does not auto start music")
	music.start_music()
	await create_timer(0.4).timeout
	check(music.level > 0 and music.level < music.volume, "entry gradually fades in")
	await create_timer(1.8).timeout
	check(is_equal_approx(music.level, 0.35), "entry reaches intended quiet background level")
	music.players[music.active].seek(music.length - 2.3)
	await create_timer(0.65).timeout
	check(music.blending and music.players[0].playing and music.players[1].playing, "end overlaps next beginning")
	var total = db_to_linear(music.players[0].volume_db) + db_to_linear(music.players[1].volume_db)
	check(abs(total - music.level) < 0.01, "crossfade does not double combined gain")
	await create_timer(2).timeout
	check(music.loop_count == 1 and music.active == 1 and not music.players[0].playing, "loop finishes handover and stops old voice")
	music.toggle_mute()
	await create_timer(0.4).timeout
	check(is_zero_approx(music.level) and music.players[music.active].playing, "mute fades out without resetting playhead")
	music.set_volume(0.27)
	music.toggle_mute()
	await create_timer(0.4).timeout
	check(is_equal_approx(music.level, 0.27), "unmute fades back to selected volume")
	music.volume = 0.8
	music.load_settings()
	check(is_equal_approx(music.volume, 0.27) and not music.muted, "music preference saved and restored independently")
	var title = load("res://start.tscn").instantiate()
	title.saves.prefix = "user://test_music_slot_" + str(Time.get_ticks_usec()) + "_"
	root.add_child(title)
	await process_frame
	var initial = music.players[music.active].get_playback_position()
	await title.select_slot(1)
	var game = title.active_game
	check(game != null, "start screen still opens shop")
	for page in ["后厨", "农场", "畜棚", "餐厅"]:
		game.show_page(page)
		await process_frame
	check(music.players[music.active].get_playback_position() > initial and music.loop_count == 1, "page and save entry keep continuous music")
	game.feedback.volume = 0.61
	game.feedback.muted = true
	check(is_equal_approx(music.volume, 0.27) and not music.muted, "sound effect settings do not change background music")
	game.open_menu("设置")
	await process_frame
	check(game.menu.visible, "music controls coexist with existing settings window")
	title.return_to_title()
	await process_frame
	check(music.players[music.active].playing, "return to title keeps same music player")
	title.queue_free()
	music.fade_out()
	await create_timer(0.2).timeout
	check(music.level > 0 and music.level < 0.27, "exit fades instead of cutting abruptly")
	await create_timer(0.6).timeout
	check(is_zero_approx(music.level) and not music.players[0].playing and not music.players[1].playing, "exit fade ends with both players stopped")
	print("MUSIC CHECKS: ", checks, " checks, ", failures, " failures")
	quit(failures)
