extends Control
# 餐厅：接单、上菜、评分、菜谱、定价、员工、日结。
const PEOPLE = [
	{"name": "林小姐", "likes": ["酥脆", "超浓", "细腻"]},
	{"name": "周先生", "likes": ["温润", "细腻", "超浓"]},
	{"name": "陈阿姨", "likes": ["家常", "超浓", "细腻"]}
]
var game
var guests = []
var dishes = []
var opening_button: Button
var summary_label: Label
var arrived = 0
var served = 0
var refused = 0
var limit = 5
var arrival_time = 0.0
var staff_time = 0.0
var last_summary = ""
var price_level = 0
var today_menu = []
var served_records = []
var selected_guest = null
var selected_dish = null
var tray_label: Label

func _ready():
	opening_button = game.button(self, "开始营业", Rect2(144, 96, 110, 30), day_action)
	game.button(self, "菜谱", Rect2(272, 96, 76, 30), game.open_menu.bind("菜谱"))
	game.button(self, "顾客", Rect2(366, 96, 76, 30), game.open_menu.bind("顾客"))
	game.button(self, "员工", Rect2(460, 96, 76, 30), game.open_menu.bind("员工"))
	game.button(self, "退单", Rect2(554, 96, 76, 30), cancel_selected)
	game.button(self, "退回后厨", Rect2(648, 96, 108, 30), return_dish)
	game.button(self, "后厨 →", Rect2(1110, 96, 110, 30), game.show_page.bind("后厨"))
	summary_label = game.label(self, "", Rect2(148, 590, 1060, 64), 14)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tray_label = game.label(self, "出餐台 0 / 3", Rect2(306, 394, 360, 30), 14)
	game.panel(self, Rect2(306, 429, 872, 1), "dedcd4")
	begin_morning()

func begin_morning():
	opening_button.text = "开始营业"
	summary_label.text = ""
	arrived = 0
	served = 0
	refused = 0
	served_records.clear()

func day_action():
	if game.phase == "早晨":
		open_day()
	elif game.phase == "营业中":
		if not guests.is_empty():
			game.notify("还有客人，请上菜或选中客人点退单，再打烊")
			return
		close_day()
	else:
		game.open_menu("结算")

func open_day():
	if game.kitchen.prepared_count() < 2:
		game.notify("先到后厨备至少两份食材")
		return false
	game.phase = "营业中"
	opening_button.text = "打烊结算"
	price_level = 0
	today_menu.clear()
	for i in range(game.recipes.size()):
		if game.recipes[i]["listed"]:
			today_menu.append({"index": i, "markup": game.recipes[i]["markup"]})
			price_level += game.recipes[i]["markup"]
	if not today_menu.is_empty():
		price_level = int(round(float(price_level) / today_menu.size()))
	# 明确而可预测的价格需求关系，低价增加来客、高价减少来客。
	limit = clampi(5 - int(price_level / 10.0), 2, 8)
	arrival_time = 0
	if price_level >= 20:
		game.notify("路过的客人：有点贵…… 今日预计 " + str(limit) + " 位客人")
	else:
		game.notify("已营业，今日预计 " + str(limit) + " 位客人")
	spawn_guest()
	return true

func spawn_guest():
	if game.phase != "营业中" or arrived >= limit or guests.size() >= 3:
		return
	var person_index = (arrived + game.day - 1) % PEOPLE.size()
	var ingredient = ["番茄", "鸡蛋", "土豆"][arrived % 3]
	var quote_markup = 0
	var quote_base = 0
	if not today_menu.is_empty():
		var listed = today_menu[arrived % today_menu.size()]
		var recipe = game.recipes[listed["index"]]
		ingredient = recipe["items"][0]["name"]
		quote_markup = listed["markup"]
		quote_base = recipe["base"]
	var slot = 0
	while slot < 3:
		var occupied = false
		for guest in guests:
			if guest.data["slot"] == slot:
				occupied = true
		if not occupied:
			break
		slot += 1
	var card = game.make_card(self, "guest", PEOPLE[person_index]["name"] + " [待接单]", Vector2(340 + slot * 280, 230))
	card.movable = false
	card.data = {"person": person_index, "ingredient": ingredient, "accepted": false, "slot": slot, "markup": quote_markup, "base": quote_base}
	card.clicked.connect(click_guest)
	guests.append(card)
	arrived += 1
	if game.staff["前台"]:
		accept_order(card)

func accept_order(guest):
	guest.data["accepted"] = true
	guest.caption = PEOPLE[guest.data["person"]]["name"] + "\n想吃 " + guest.data["ingredient"]
	if guest.data["base"] > 0:
		guest.caption += " · " + str(int(round(guest.data["base"] * (1.0 + guest.data["markup"] / 100.0)))) + " 金币"
	guest.refresh()
	game.notify("已接单：含 " + guest.data["ingredient"] + " 的料理")

func click_guest(guest):
	selected_guest = guest
	if not guest.data["accepted"]:
		accept_order(guest)
	else:
		game.inspect(PEOPLE[guest.data["person"]]["name"] + " · 想吃含 " + guest.data["ingredient"] + " 的料理")

func cancel_selected():
	if not is_instance_valid(selected_guest) or not guests.has(selected_guest):
		game.notify("先单击选中客人，再退单")
		return
	refused += 1
	guests.erase(selected_guest)
	selected_guest.hide()
	selected_guest.queue_free()
	selected_guest = null
	game.notify("已退单，不收取费用")

func add_dish(source):
	if dishes.size() >= game.tray_capacity:
		game.notify("传菜台已满，先上菜")
		return false
	var dish = game.make_card(self, "dish", "", Vector2(350, 460), Rect2(286, 148, 940, 440))
	dish.items = source.items.duplicate(true)
	dish.tags = source.tags.duplicate()
	dish.cooking_method = source.cooking_method
	dish.data = source.data.duplicate(true)
	dish.dish_name = source.dish_name
	dish.refresh()
	dish.dropped.connect(drop_dish)
	dish.clicked.connect(click_dish)
	dishes.append(dish)
	update_tray()
	return true

func click_dish(dish):
	selected_dish = dish
	game.inspect(game.dish_detail(dish) + "\n拖给已接单客人")

func return_dish():
	if not is_instance_valid(selected_dish) or not dishes.has(selected_dish):
		game.notify("先单击选中要退回的料理")
		return
	var k = game.kitchen
	if k.cards.size() >= k.capacity():
		game.notify("后厨桌面已满，请先出餐或丢弃")
		return
	var returned = k.create_card("dish", selected_dish.items)
	returned.tags = selected_dish.tags.duplicate()
	returned.cooking_method = selected_dish.cooking_method
	returned.data = selected_dish.data.duplicate(true)
	returned.dish_name = selected_dish.dish_name
	returned.refresh()
	k.place_near(returned, Vector2(700, 440))
	dishes.erase(selected_dish)
	selected_dish.hide()
	selected_dish.queue_free()
	selected_dish = null
	update_tray()
	game.notify("已退回后厨")

func drop_dish(dish):
	for guest in guests:
		if Rect2(guest.position, guest.size).has_point(dish.position + dish.size / 2):
			if not serve(dish, guest):
				dish.position = dish.start_position
			return
	update_tray()

func has_ingredient(dish, ingredient):
	for item in dish.items:
		if item["name"] == ingredient:
			return true
	return false

func serve(dish, guest):
	if game.phase != "营业中" or not guest.data["accepted"]:
		game.notify("先点击客人接单")
		return false
	if not has_ingredient(dish, guest.data["ingredient"]):
		game.notify("客人需要 " + guest.data["ingredient"] + "，这道菜不符合要求")
		return false
	var person = PEOPLE[guest.data["person"]]
	var matched = []
	for tag in person["likes"]:
		if dish.data.get("weights", {}).get(tag, 0) >= 8:
			matched.append(tag)
	var score = mini(5, 2 + matched.size())
	var tip = 0
	if matched.size() >= 2:
		var strength = 0
		for tag in matched:
			strength += dish.data.get("weights", {}).get(tag, 0)
		tip = 4 + matched.size() * 2 + mini(5, int(strength / 30.0))
	var recipe = game.recipes[dish.data["recipe"]]
	var base = guest.data["base"] if guest.data["base"] > 0 else recipe["base"]
	var price = int(round(base * (1.0 + guest.data["markup"] / 100.0)))
	game.money += price + tip
	game.daily_income += price
	game.daily_tips += tip
	var hint = "如果再" + person["likes"][0] + "一点就好了。"
	if not matched.is_empty():
		var known = game.learned.get(person["name"], [])
		for tag in matched:
			if not known.has(tag):
				known.append(tag)
		game.learned[person["name"]] = known
		hint = "我喜欢这份" + matched[0] + "的口感。"
	var feedback = person["name"] + "：" + str(score) + " 星 · " + hint + " 收入 " + str(price) + "，小费 " + str(tip)
	game.notify(feedback)
	summary_label.text = ""
	served_records.append({"score": score, "tip": tip, "price": price})
	served += 1
	guests.erase(guest)
	dishes.erase(dish)
	guest.hide()
	dish.hide()
	guest.queue_free()
	dish.queue_free()
	update_tray()
	return true

func advance(delta):
	if game.phase != "营业中":
		return
	arrival_time += delta
	staff_time += delta
	if arrival_time >= 8:
		arrival_time = 0
		spawn_guest()
	if staff_time >= 4:
		staff_time = 0
		run_staff()

func _process(delta):
	advance(delta)

func run_staff():
	for guest in guests.duplicate():
		if game.staff["前台"] and not guest.data["accepted"]:
			accept_order(guest)
		if not guest.data["accepted"]:
			continue
		var food = guest.data["ingredient"]
		var existing = null
		for dish in dishes:
			if has_ingredient(dish, food):
				existing = dish
				break
		if existing == null:
			for card in game.kitchen.cards:
				if card.kind == "dish" and has_ingredient(card, food):
					existing = card
					break
		if existing == null and game.staff["主厨"]:
			for i in range(game.recipes.size()):
				var recipe = game.recipes[i]
				if not recipe["listed"]:
					continue
				var contains = false
				for item in recipe["items"]:
					if item["name"] == food:
						contains = true
				if contains and game.kitchen.auto_cook(i):
					existing = game.kitchen.cards.back()
					break
		if existing != null and game.staff["传菜"]:
			if game.kitchen.cards.has(existing):
				if not add_dish(existing):
					continue
				game.kitchen.remove_card(existing)
				existing = dishes.back()
			serve(existing, guest)

func close_day():
	if game.phase != "营业中" or not guests.is_empty():
		return false
	game.phase = "夜晚"
	var wages = 0
	for role in game.staff:
		if game.staff[role]:
			wages += 6
	# 余额不足时付出剩余金币并解除雇用，不制造无法继续经营的负债。
	var paid = mini(wages, game.money)
	game.money -= paid
	game.daily_cost += paid
	var warning = ""
	if paid < wages:
		for role in game.staff:
			game.staff[role] = false
		warning = "\n余额不足，员工已离职。"
	last_summary = "第 " + str(game.day) + " 天\n接待 " + str(served) + " 位 · 退单 " + str(refused) + " 位\n营业收入 " + str(game.daily_income) + " · 小费 " + str(game.daily_tips) + "\n今日支出 " + str(game.daily_cost) + "（含工资 " + str(paid) + "）\n今日净变化 " + str(game.daily_income + game.daily_tips - game.daily_cost) + " · 余额 " + str(game.money) + warning
	opening_button.text = "查看结算"
	game.open_menu("结算")
	return true

func update_tray():
	tray_label.text = "出餐台 " + str(dishes.size()) + " / " + str(game.tray_capacity)
	for i in range(dishes.size()):
		var dish = dishes[i]
		dish.collapse()
		dish.position = Vector2(350 + (i % 3) * 270, 458 + (i / 3) * 70)
