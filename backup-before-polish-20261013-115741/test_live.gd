extends SceneTree
# 真实时间冒烟检查：不关闭任何页面的 _process。
var game

func _initialize():
	call_deferred("run")

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.farm.buy_plot()
	game.farm.buy_seed("小麦")
	game.farm.plant(game.farm.plots[0], "小麦")
	game.barn.build_home("鸡")
	game.barn.enter_pen("鸡")
	game.barn.buy_animal()
	game.barn.buy_feed()
	game.barn.buy_feed()
	game.barn.place_feed(Vector2(430, 280))
	game.barn.place_feed(Vector2(500, 280))
	game.kitchen.add_ingredient("番茄")
	game.kitchen.add_ingredient("鸡蛋")
	game.dining.open_day()
	game.show_page("餐厅")
	await create_timer(23).timeout
	var crop_ready = game.farm.plots[0].caption == "成熟的小片小麦"
	var eggs_ready = game.barn.produce.size() == 1
	var guests_ready = game.dining.guests.size() == 3
	var notice_cleared = not game.notice_window.visible
	print("LIVE: crop=", crop_ready, ", egg=", eggs_ready, ", guests=", guests_ready, ", notice=", notice_cleared)
	quit(0 if crop_ready and eggs_ready and guests_ready and notice_cleared else 1)
