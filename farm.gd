extends Control
# 农场：种子卡、土地、计时、散落作物、收集箱。
const GROW_SECONDS = 18.0
const CROPS = ["小麦", "番茄", "土豆"]
var game
var plots = []
var seeds = {"小麦": 0, "番茄": 0, "土豆": 0}
var seed_cards = []
var produce = []
var seed_menu: Control
var shop: Control
var collector
var selected_plot = null
var upgrading = false

func _ready():
	game.button(self, "购买", Rect2(146, 100, 86, 30), toggle_shop)
	game.button(self, "种植", Rect2(146, 144, 86, 30), toggle_seeds)
	game.button(self, "收集", Rect2(146, 188, 86, 30), toggle_collect)
	game.button(self, "升级", Rect2(146, 232, 86, 30), toggle_upgrade)
	shop = Control.new()
	shop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shop)
	game.button(shop, "小片田地 · 30", Rect2(260, 96, 160, 30), buy_plot)
	for i in range(CROPS.size()):
		game.button(shop, CROPS[i] + "种子 · 2", Rect2(440 + i * 170, 96, 155, 30), buy_seed.bind(CROPS[i]))
	shop.hide()
	seed_menu = Control.new()
	seed_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(seed_menu)
	seed_menu.hide()
	collector = game.make_card(self, "collector", "收集箱", Vector2(790, 606), Rect2(286, 148, 940, 500))
	collector.movable = false
	collector.hide()
	collector.clicked.connect(func(_card): game.inspect("把散落的作物拖进收集箱，送入仓库"))

func toggle_shop():
	shop.visible = not shop.visible
	seed_menu.hide()
	upgrading = false
	if plots.is_empty():
		game.notify("先买一块田地，再购买种子")

func buy_plot():
	if plots.size() >= 6:
		game.notify("当前最多 6 块田地")
		return
	if not game.spend(30):
		return
	var index = plots.size()
	create_plot(Vector2(380 + (index % 3) * 250, 230 + (index / 3) * 210), {"crop": "", "elapsed": 0.0, "large": false})

func create_plot(point, state):
	var plot = game.make_card(self, "plot", "小片田地", point)
	plot.movable = false
	plot.data = state.duplicate(true)
	plot.clicked.connect(click_plot)
	plots.append(plot)
	update_plot(plot)

func buy_seed(crop):
	if game.spend(2):
		seeds[crop] += 1
		refresh_seeds()
		game.notify("已购买 " + crop + "种子；点种植后拖到土地")

func toggle_seeds():
	seed_menu.visible = not seed_menu.visible
	shop.hide()
	upgrading = false
	refresh_seeds()

func refresh_seeds():
	for card in seed_cards:
		card.queue_free()
	seed_cards.clear()
	for i in range(CROPS.size()):
		var crop = CROPS[i]
		var card = game.make_card(seed_menu, "seed", crop + "种子 × " + str(seeds[crop]), Vector2(146, 306 + i * 58), Rect2(138, 148, 1088, 458))
		card.data = {"crop": crop}
		card.dropped.connect(drop_seed)
		card.clicked.connect(func(c): game.inspect(c.data["crop"] + "种子 · 拖到空田地种植"))
		seed_cards.append(card)

func drop_seed(card):
	var point = card.position + card.size / 2
	for plot in plots:
		if Rect2(plot.position, plot.size).has_point(point):
			plant(plot, card.data["crop"])
			break
	card.position = card.start_position
	refresh_seeds()

func plant(plot, crop):
	if plot.data["crop"] != "":
		game.notify("这块田已有作物")
		return false
	if seeds[crop] <= 0:
		game.notify("种子不足，先购买")
		return false
	seeds[crop] -= 1
	plot.data["crop"] = crop
	plot.data["elapsed"] = 0.0
	update_plot(plot)
	refresh_seeds()
	return true

func update_plot(plot):
	var area = "大片" if plot.data["large"] else "小片"
	var crop = plot.data["crop"]
	if crop == "":
		plot.caption = area + "田地"
		plot.progress = -1
	elif plot.data["elapsed"] >= GROW_SECONDS:
		plot.caption = "成熟的" + area + crop
		plot.progress = -1
	else:
		plot.caption = area + crop + "田"
		plot.progress = plot.data["elapsed"] / GROW_SECONDS
	plot.refresh()
	if plot.data["large"]:
		plot.custom_minimum_size.x = 158
		plot.size = plot.get_combined_minimum_size()

func advance(delta):
	for plot in plots:
		if plot.data["crop"] != "" and plot.data["elapsed"] < GROW_SECONDS:
			plot.data["elapsed"] = minf(GROW_SECONDS, plot.data["elapsed"] + delta)
			update_plot(plot)

func _process(delta):
	if game.phase != "夜晚":
		advance(delta)

func click_plot(plot):
	selected_plot = plot
	if upgrading:
		upgrade_plot(plot)
		return
	if plot.data["crop"] != "" and plot.data["elapsed"] >= GROW_SECONDS:
		harvest(plot)
	else:
		game.inspect(plot.caption + " · " + ("拖入种子种植" if plot.data["crop"] == "" else "正在生长，成熟后点击收获"))

func toggle_upgrade():
	upgrading = not upgrading
	game.notify("选择一块空田升级为大片，花费 45（第 2 天解锁）" if upgrading else "已退出升级")

func upgrade_plot(plot):
	if game.day < 2 or plot.data["large"] or plot.data["crop"] != "":
		game.notify("第 2 天起可升级空的小片田地")
		return
	if game.spend(45):
		plot.data["large"] = true
		update_plot(plot)
		upgrading = false

func harvest(plot):
	var count = 7 if plot.data["large"] else 3
	if produce.size() + count > 48:
		game.notify("先收集地上的作物，再收获")
		return
	game.feedback.play("harvest")
	for i in range(count):
		var crop = plot.data["crop"]
		var card = create_produce(crop, plot.position)
		# 四周留空，避免收获物盖住田地；小田用三处，大田用七处。
		var offsets = [Vector2(-94, 0), Vector2(0, -74), Vector2(plot.size.x + 16, 0), Vector2(104, -74), Vector2(104, 76), Vector2(0, 94), Vector2(-94, 76)]
		var end = plot.position + offsets[i]
		end.x = clampf(end.x, 286, 1140)
		end.y = clampf(end.y, 148, 554)
		var tween = create_tween()
		tween.tween_property(card, "position", end, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	plot.data["crop"] = ""
	update_plot(plot)

func toggle_collect():
	collector.visible = not collector.visible

func create_produce(crop, point):
	var card = game.make_card(self, "produce", crop, point, Rect2(286, 148, 940, 500))
	card.data = {"crop": crop}
	card.dropped.connect(drop_produce)
	card.clicked.connect(func(c): game.inspect(c.data["crop"] + " · 拖入收集箱"))
	produce.append(card)
	return card

func drop_produce(card):
	if collector.visible and Rect2(collector.position, collector.size).has_point(card.position + card.size / 2):
		game.feedback.collect(card, collector.global_position)
		game.inventory[card.data["crop"]] += 1
		produce.erase(card)
		card.hide()
		card.queue_free()
		game.notify("已收入仓库")
