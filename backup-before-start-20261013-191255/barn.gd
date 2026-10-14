extends Control
# 畜棚：设施页与饲养栏分开，动物主动靠近饲料。
const TYPES = ["鸡", "兔", "猪"]
const HOMES = {"鸡": "鸡舍", "兔": "兔舍", "猪": "猪圈"}
const BABIES = {"鸡": "小鸡", "兔": "小兔", "猪": "小猪"}
const PRODUCTS = {"鸡": "鸡蛋", "兔": "兔肉", "猪": "猪肉"}
const EGG_SECONDS = 14.0
const PEN_AREA = Rect2(306, 158, 890, 416)
const WALK_SPEED = {"鸡": 38.0, "兔": 52.0, "猪": 27.0}
const VOICES = {"鸡": "chicken", "兔": "rabbit", "猪": "pig"}
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
var animal_player: AudioStreamPlayer
var animal_sounds = {}
var voice_gap = 0.0
var voice_animal = null
var last_voice = ""
var voice_count = 0 # 便于验证是否真正触发声音，不参与经营计算。

func _ready():
	animal_player = AudioStreamPlayer.new()
	add_child(animal_player)
	for name in ["chicken_baby", "chicken_adult", "rabbit_baby", "rabbit_adult", "pig_baby", "pig_adult", "grown"]:
		animal_sounds[name] = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://audio/animal_" + name + ".wav"))
	visibility_changed.connect(on_visibility_changed)
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
	if current == type and pen_page.visible:
		return
	silence_animals()
	current = type
	home_page.hide()
	pen_page.show()
	update_visible()
	greet_pen()
	game.notify(HOMES[type] + " · 购买幼崽和饲料，再点投喂")

func leave_pen():
	silence_animals()
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
	var card = game.make_card(pen_page, "animal", BABIES[current], Vector2(410 + (count % 3) * 160, 260 + (count / 3) * 125), PEN_AREA)
	card.data = {"type": current, "growth": 0, "meal": false, "egg_time": 0.0, "rest": 0.0, "base": card.position, "target": card.position, "wait": randf_range(0.8, 2.4), "call_wait": randf_range(6.0, 12.0), "sway": 0.0, "walk_phase": randf_range(0, TAU)}
	card.progress = 0.0
	card.refresh()
	card.clicked.connect(click_animal)
	card.dropped.connect(drop_animal)
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
	voice_gap = maxf(0, voice_gap - delta)
	if game.feedback.muted or game.feedback.volume <= 0:
		silence_animals()
	animal_player.volume_db = linear_to_db(maxf(0.0001, game.feedback.volume)) - 8
	for animal in animals.duplicate():
		var data = animal.data
		# 看详情或拖动时停止自主行动，防止卡片逃离鼠标。
		if animal.pressed or animal.expanded:
			data["sway"] = 0.0
			animal.rotation = 0
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
		var nearest = null
		if hungry and data["rest"] <= 0:
			var distance = INF
			for food in foods:
				if food.data["type"] == data["type"] and not food.pressed:
					var d = data["base"].distance_to(food.position)
					if d < distance:
						distance = d
						nearest = food
		var previous = data["base"]
		if nearest != null:
			data["target"] = clamp_point(nearest.position, animal.size)
			data["base"] = data["base"].move_toward(data["target"], 85 * delta)
			if Rect2(data["base"], animal.size).grow(6).intersects(Rect2(nearest.position, nearest.size)):
				eat(animal, nearest)
				data["target"] = data["base"]
				data["wait"] = randf_range(1.2, 2.8)
		elif data["rest"] <= 0:
			data["wait"] -= delta
			if data["wait"] <= 0:
				if data["base"].distance_to(data["target"]) < 3:
					choose_walk_target(animal)
				else:
					data["base"] = data["base"].move_toward(data["target"], WALK_SPEED[data["type"]] * delta)
					if data["base"].distance_to(data["target"]) < 3:
						data["wait"] = randf_range(1.5, 4.0)
		data["base"] = clamp_point(data["base"], animal.size)
		animal.position = data["base"]
		var walking = previous.distance_to(data["base"]) > 0.01
		# 行走才有很轻的步态；停下时不再原地蹦跶。
		data["walk_phase"] += delta * (11 if data["type"] == "兔" else 7)
		animal.rotation = 0
		if walking and not game.feedback.reduced_motion:
			animal.rotation = sin(data["walk_phase"]) * 0.012
		update_voice(animal, delta)

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
			# 隐藏页面仍继续成长，但声音和摆动不排队、不补播。
			speak(animal, true)
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
		if voice_animal == animal:
			silence_animals()
		animals.erase(animal)
		animal.hide()
		animal.queue_free()
		game.notify("已出栏，产物可拖入收集箱")
	else:
		game.inspect(animal.caption + " · " + ("吃两份饲料后长大" if animal.data["growth"] < 2 else "吃饲料后产蛋"))

func spawn_product(type, point):
	if pen_is_visible(type):
		game.feedback.play("harvest")
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
		game.feedback.collect(card, collector.global_position)
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

func clamp_point(point, dimensions):
	return Vector2(clampf(point.x, PEN_AREA.position.x, PEN_AREA.end.x - dimensions.x), clampf(point.y, PEN_AREA.position.y, PEN_AREA.end.y - dimensions.y))

func choose_walk_target(animal):
	var data = animal.data
	for attempt in range(10):
		var point = clamp_point(data["base"] + Vector2(randf_range(-170, 170), randf_range(-115, 115)), animal.size)
		if point.distance_to(data["base"]) < 55:
			continue
		var free = true
		for other in animals:
			if other != animal and other.data["type"] == data["type"] and Rect2(point, animal.size).grow(14).intersects(Rect2(other.data["base"], other.size)):
				free = false
				break
		if free:
			data["target"] = point
			return
	data["wait"] = 1.0

func drop_animal(animal):
	animal.position = clamp_point(animal.position, animal.size)
	animal.data["base"] = animal.position
	animal.data["target"] = animal.position
	animal.data["wait"] = 2.0
	animal.data["sway"] = 0.0
	animal.rotation = 0

func pen_is_visible(type):
	return is_visible_in_tree() and pen_page.visible and current == type and game.current_page == "畜棚"

func speak(animal, grown = false, entering = false):
	if not is_instance_valid(animal) or not pen_is_visible(animal.data["type"]):
		return false
	if animal.pressed or animal.expanded or game.feedback.muted or game.feedback.volume <= 0:
		return false
	if not grown and not entering and (voice_gap > 0 or animal_player.playing):
		return false
	var sound = "grown" if grown else VOICES[animal.data["type"]] + ("_adult" if animal.data["growth"] >= 2 else "_baby")
	# 一个独立播放器：切页可立即停止，不打断按钮和料理音效。
	animal_player.stop()
	if is_instance_valid(voice_animal):
		voice_animal.data["sway"] = 0.0
		voice_animal.rotation = 0
	animal_player.stream = animal_sounds[sound]
	animal_player.volume_db = linear_to_db(game.feedback.volume) - 8
	animal_player.pitch_scale = randf_range(0.96, 1.04)
	animal_player.play()
	voice_animal = animal
	last_voice = sound
	voice_count += 1
	voice_gap = 3.0
	animal.data["call_wait"] = randf_range(7.0, 14.0)
	animal.data["sway"] = 0.5 if not game.feedback.reduced_motion else 0.0
	return true

func update_voice(animal, delta):
	var data = animal.data
	if not pen_is_visible(data["type"]):
		data["sway"] = 0.0
		return
	data["call_wait"] -= delta
	if data["call_wait"] <= 0:
		# 没有排队，轮到下一次随机间隔再尝试。
		data["call_wait"] = randf_range(7.0, 14.0)
		speak(animal)
	if data["sway"] > 0:
		data["sway"] = maxf(0, data["sway"] - delta)
		if not game.feedback.reduced_motion:
			animal.pivot_offset = animal.size / 2
			animal.rotation = sin((0.5 - data["sway"]) * TAU * 6) * 0.045 * data["sway"] / 0.5

func silence_animals():
	if is_instance_valid(animal_player):
		animal_player.stop()
	for animal in animals:
		animal.data["sway"] = 0.0
		animal.rotation = 0
	voice_animal = null

func greet_pen():
	for animal in animals:
		if pen_is_visible(animal.data["type"]):
			animal.data["call_wait"] = randf_range(7.0, 14.0)
	for animal in animals:
		if speak(animal, false, true):
			break

func on_visibility_changed():
	if not is_visible_in_tree():
		silence_animals()

func _exit_tree():
	silence_animals()
	if is_instance_valid(animal_player):
		animal_player.stream = null
	animal_sounds.clear()
