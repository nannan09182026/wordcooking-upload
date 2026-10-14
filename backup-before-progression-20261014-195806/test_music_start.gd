extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	if not "--music-start-check" in OS.get_cmdline_user_args():
		quit(1)
		return
	await create_timer(2.3).timeout
	var music = root.get_node("Music")
	var target = 0.0 if music.muted else music.volume
	if not music.players[music.active].playing or abs(music.level - target) > 0.01:
		print("FAIL: automatic startup")
		quit(1)
		return
	print("PASS: normal launch auto plays at saved volume; requesting graceful exit")
	music.request_quit()
