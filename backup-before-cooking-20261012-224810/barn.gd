extends Control
# 畜棚：设施页与饲养栏分开，动物主动靠近饲料。
const TYPES = ["鸡", "兔", "猪"]
const HOMES = {"鸡": "鸡舍", "兔": "兔舍", "猪": "猪圈"}
const BABIES = {"鸡": "小鸡", "兔": "小兔", "猪": "小猪"}
const PRODUCTS = {"鸡": "鸡蛋", "兔": "兔肉", "猪": "猪肉"}
const EGG_SECONDS = 14.0
var game
var home_page: Control
var pen_page: Control
var home_cards = {}
var built = {"鸡": false, "兔": false, "猪": false}
var upgraded = {"鸡": false, "兔": false, "猪": false}
var current = ""
var animals = []
var feed = 0
var feed_card
var feed_menu: Control
var purchase_menu: Control
var foods = []
var produce = []
var collector
var time = 0.0
var moving = []

func _ready():
	home_page = Control.new()
	home_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(home_page)
	for i in range(TYPES.size()):
		var type = TYPES[i]
		game.button(home_page, "建" + HOMES[type] + " · 40", Rect2(146, 100 + i * 44, 132, 30), build_home.bind(type))
	pen_page = Control.new()
	pen_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pen_page)
	game.button(pen_page, "返回", Rect2(146, 100, 86, 30), leave_pen)
	game.button(pen_page, "购买", Rect2(146, 144, 86, 30), toggle_purchase)
	game.button(pen_page, "投喂", Rect2(146, 188, 86, 30), toggle_feed)
	game.button(pen_page, "收集", Rect2(146, 232, 86, 30), toggle_collect)
	game.button(pen_page, "升级", Rect2(146, 276, 86, 30), upgrade_home)
	feed_menu = Control.new()
	feed_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pen_page.add_child(feed_menu)
	feed_card = game.make_card(feed_menu, "feed_source", "饲料 × 0", Vector2(146, 350), Rect2(138, 148, 1088, 458))
	feed_card.dropped.connect(drop_feed_source)
	feed_card.clicked.connect(func(_c): game.inspect("把饲料从这里拖到右侧饲养栏，每次消耗 1 份"))
	feed_menu.hide()
	purchase_menu = Control.new()
	purchase_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pen_page.add_child(purchase_menu)
	game.button(purchase_menu, "幼崽 · 15", Rect2(306, 96, 130, 30), buy_animal)
	game.button(purchase_menu, "饲料 × 1 · 2", Rect2(450, 96, 150, 30), buy_feed)
	purchase_menu.hide()
	collector = game.make_card(pen_page, "collector", "收集箱", Vector2(790, 606), Rect2(286, 148, 940, 500))
	collector.movable = false
	collector.hide()
	collector.clicked.connect(func(_c): game.inspect("把鸡蛋或出栏产物拖入收集箱，送入仓库"))
	pen_page.hide()

func build_home(type):
	if built[type]:
		game.notify("已经建好，点击右侧的" + HOMES[type] + "进入")
		return
	if not game.spend(40):
		return
	built[type] = true
	var card = game.make_card(home_page, "home", HOMES[type], Vector2(400 + TYPES.find(type) * 240, 280))
	card.movable = false
	card.clicked.connect(func(_c): enter_pen(type))
	home_cards[type] = card
	game.notify("已建好" + HOMES[type] + "，点击进入")

func enter_pen(type):
	current = type
	home_page.hide()
	pen_page.show()
	update_visible()
	game.notify(HOMES[type] + " · 购买幼崽和饲料，再点投喂")

func leave_pen():
	current = ""
	home_page.show()
	pen_page.hide()

func update_visible():
	for card in animals + foods + produce:
		card.visible = card.data["type"] == current

func toggle_purchase():
	purchase_menu.visible = not purchase_menu.visible
	feed_menu.hide()

func toggle_feed():
	feed_menu.visible = not feed_menu.visible
	purchase_menu.hide()
	update_feed()

func update_feed():
	feed_card.caption = "饲料 × " + str(feed)
	feed_card.refresh()

func buy_feed():
	if game.spend(2):
		feed += 1
		update_feed()

func buy_animal():
	if current == "":
		return
	var count = 0
	for animal in animals:
		if animal.data["type"] == current:
			count += 1
	if count >= (6 if upgraded[current] else 3):
		game.notify("饲养栏已满，升级可扩至 6 只")
		return
	if not game.spend(15):
		return
	var card = game.make_card(pen_page, "animal", BABIES[current], Vector2(410 + count * 120, 280))
	card.data = {"type": current, "growth": 0, "meal": false, "egg_time": 0.0, "rest": 0.0, "base": card.position, "offset": float(animals.size())}
	card.progress = 0.0
	card.refresh()
	card.clicked.connect(click_animal)
	card.dropped.connect(func(c): c.data["base"] = c.position)
	animals.append(card)

func drop_feed_source(card):
	var point = card.position + card.size / 2
	if Rect2(306, 150, 890, 420).has_point(point):
		place_feed(point)
	card.position = Vector2(146, 350)
	update_feed()

func place_feed(point):
	if feed <= 0:
		game.notify("先购买饲料")
		return false
	if foods.size() >= 18:
		game.notify("地上饲料足够，等动物吃完再投喂")
		return false
	feed -= 1
	var card = game.make_card(pen_page, "feed", "饲料", point)
	card.data = {"type": current}
	card.clicked.connect(func(_c): game.inspect("动物会靠近并吃掉饲料"))
	foods.append(card)
	return true

func advance(delta):
	time += delta
	for animal in animals.duplicate():
		var data = animal.data
		if animal.pressed:
			data["base"] = animal.position
			continue
		data["rest"] = maxf(0, data["rest"] - delta)
		if data["growth"] >= 2 and data["type"] == "鸡" and data["meal"]:
			data["egg_time"] += delta
			animal.progress = data["egg_time"] / EGG_SECONDS
			if data["egg_time"] >= EGG_SECONDS and produce.size() < 48:
				spawn_product("鸡", animal.position + Vector2(70, 30))
				data["meal"] = false
				data["egg_time"] = 0.0
				animal.progress = -1
		var hungry = data["growth"] < 2 or (data["type"] == "鸡" and not data["meal"])
		if hungry and data["rest"] <= 0:
			var nearest = null
			var distance = INF
			for food in foods:
				if food.data["type"] == data["type"] and not food.pressed:
					var d = data["base"].distance_to(food.position)
					if d < distance:
						distance = d
						nearest = food
			if nearest != null:
				data["base"] = data["base"].move_toward(nearest.position, 85 * delta)
				if data["base"].distance_to(nearest.position) < 16:
					eat(animal, nearest)
		animal.position = data["base"] + Vector2(0, -absf(sin(time * 4 + data["offset"])) * 5)
		animal.clamp_to_area()

func _process(delta):
	advance(delta)

func eat(animal, food):
	foods.erase(food)
	food.hide()
	food.queue_free()
	var data = animal.data
	data["rest"] = 1.0
	if data["growth"] < 2:
		data["growth"] += 1
		animal.progress = data["growth"] / 2.0
		if data["growth"] >= 2:
			animal.caption = data["type"]
			animal.progress = -1
			if data["type"] == "鸡":
				data["meal"] = true
			else:
				animal.caption += " [可出栏]"
	else:
		data["meal"] = true
	animal.refresh()

func click_animal(animal):
	if animal.data["type"] != "鸡" and animal.data["growth"] >= 2:
		if produce.size() > 45:
			game.notify("先收集产物")
			return
		for i in range(3):
			spawn_product(animal.data["type"], animal.position + Vector2(i * 85 - 70, 55))
		animals.erase(animal)
		animal.hide()
		animal.queue_free()
		game.notify("已出栏，产物可拖入收集箱")
	else:
		game.inspect(animal.caption + " · " + ("吃两份饲料后长大" if animal.data["growth"] < 2 else "吃饲料后产蛋"))

func spawn_product(type, point):
	var card = game.make_card(pen_page, "produce", PRODUCTS[type], point, Rect2(286, 148, 940, 500))
	card.data = {"type": type}
	card.dropped.connect(drop_product)
	card.clicked.connect(func(c): game.inspect(PRODUCTS[c.data["type"]] + " · 拖入收集箱"))
	card.visible = type == current
	produce.append(card)

func toggle_collect():
	collector.visible = not collector.visible

func drop_product(card):
	if collector.visible and Rect2(collector.position, collector.size).has_point(card.position + card.size / 2):
		game.inventory[PRODUCTS[card.data["type"]]] += 1
		produce.erase(card)
		card.hide()
		card.queue_free()
		game.notify("已收入仓库")

func upgrade_home():
	if game.day < 2 or upgraded[current]:
		game.notify("第 2 天起可升级一次，容量从 3 变为 6")
		return
	if game.spend(45):
		upgraded[current] = true
		home_cards[current].caption = "大" + HOMES[current]
		home_cards[current].refresh()
		game.notify("已扩建，最多可养 6 只")
