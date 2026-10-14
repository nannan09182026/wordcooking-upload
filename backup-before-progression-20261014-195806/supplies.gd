extends Node
# 食材箱负责取料，采购簿负责购买。数量只在操作成功后扣除。
const GROUPS = {
	"蔬菜": ["番茄", "土豆", "胡萝卜", "洋葱", "辣椒"],
	"水果": ["苹果", "草莓"],
	"谷物": ["小麦", "稻米"],
	"蛋奶": ["鸡蛋", "牛奶"],
	"肉类": ["猪肉", "兔肉", "鱼"]
}
var game
var pantry_category = "蔬菜"
var shop_category = "全部"
var quantities = {}
var shop_cards = {}
var food_sources = {}
var source_food = ""
var source_node = null
var press_point = Vector2.ZERO
var dragging = false
var ghost: Label

func text(parent, value, font_size = 14):
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func action(parent, value, callback):
	var button = Button.new()
	button.text = value
	button.custom_minimum_size.y = 30
	game.style_button(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func paper(parent):
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color("fffdf8")
	style.border_color = Color("d7d3c8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func mark_tab(button, selected):
	if selected:
		var style = button.get_theme_stylebox("normal").duplicate()
		style.bg_color = Color("e3e9dc")
		style.border_color = Color("a0ad94")
		button.add_theme_stylebox_override("normal", style)

func choose_pantry(category):
	pantry_category = category
	game.menu.scroll.scroll_vertical = 0
	game.refresh_menu()

func choose_shop(category):
	shop_category = category
	game.menu.scroll.scroll_vertical = 0
	game.refresh_menu()

func build_pantry():
	food_sources.clear()
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	game.menu_content.add_child(row)
	var categories = VBoxContainer.new()
	categories.custom_minimum_size.x = 78
	categories.add_theme_constant_override("separation", 8)
	row.add_child(categories)
	for category in GROUPS:
		var tab = action(categories, category, choose_pantry.bind(category))
		mark_tab(tab, pantry_category == category)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	row.add_child(column)
	text(column, pantry_category + " · 食材", 15)
	var grid = GridContainer.new()
	grid.columns = [1, 2, 4][game.menu.size_index]
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	for food in GROUPS[pantry_category]:
		var card = paper(grid)
		card.custom_minimum_size.y = 54
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var caption = text(card, food + "（" + str(game.inventory[food]) + "）", 15)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if game.inventory[food] <= 0:
			card.modulate = Color("c4c4bb")
		card.gui_input.connect(source_input.bind(food, card))
		food_sources[food] = card

func build_shop():
	shop_cards.clear()
	game.menu.title_bar.text = "采购簿"
	game.menu.tabs.show()
	for category in ["全部"] + GROUPS.keys():
		var tab = action(game.menu.tabs, category, choose_shop.bind(category))
		mark_tab(tab, category == shop_category)
	game.menu.header_info.text = "余额  %d" % game.money
	game.menu.apply_size()
	var grid = GridContainer.new()
	grid.columns = [1, 2, 3][game.menu.size_index]
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	game.menu_content.add_child(grid)
	for category in GROUPS:
		if shop_category != "全部" and category != shop_category:
			continue
		for food in GROUPS[category]:
			if not quantities.has(food):
				quantities[food] = 1
			var card = paper(grid)
			var column = VBoxContainer.new()
			column.add_theme_constant_override("separation", 10)
			card.add_child(column)
			var heading = HBoxContainer.new()
			column.add_child(heading)
			text(heading, food, 17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var stock = text(heading, "", 12)
			stock.add_theme_color_override("font_color", Color("838777"))
			text(column, "%d 金币 / 份" % game.PRICES[food], 13)
			var line = HSeparator.new()
			line.modulate = Color("d7d3c8")
			column.add_child(line)
			var controls = HBoxContainer.new()
			controls.add_theme_constant_override("separation", 7)
			column.add_child(controls)
			var minus = action(controls, "−", change_quantity.bind(food, -1))
			var amount = text(controls, "1")
			amount.custom_minimum_size.x = 20
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var plus = action(controls, "+", change_quantity.bind(food, 1))
			var buy = action(controls, "", purchase.bind(food))
			buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			shop_cards[food] = {"card": card, "stock": stock, "minus": minus, "plus": plus, "amount": amount, "buy": buy}
	update_shop()

func update_shop():
	game.menu.header_info.text = "余额  %d" % game.money
	for food in shop_cards:
		var view = shop_cards[food]
		if not is_instance_valid(view["card"]):
			continue
		var amount = quantities[food]
		view["stock"].text = "库存（%d）" % game.inventory[food]
		view["amount"].text = str(amount)
		view["minus"].disabled = amount <= 1
		view["plus"].disabled = (amount + 1) * game.PRICES[food] > game.money or amount >= 99
		view["buy"].text = "购买 · %d" % (amount * game.PRICES[food])
		view["buy"].disabled = amount * game.PRICES[food] > game.money

func change_quantity(food, change):
	var amount = quantities.get(food, 1) + change
	if amount < 1 or amount > 99 or (change > 0 and amount * game.PRICES[food] > game.money):
		return
	quantities[food] = amount
	update_shop()

func purchase(food):
	var amount = quantities.get(food, 1)
	var cost = amount * game.PRICES[food]
	if game.money < cost:
		update_shop()
		return
	game.money -= cost
	game.daily_cost += cost
	game.inventory[food] += amount
	update_shop()
	game.feedback.play("coin")
	var card = shop_cards[food]["card"]
	if card.has_meta("purchase_tween"):
		card.get_meta("purchase_tween").kill()
	card.modulate = Color("dfead2")
	var tween = create_tween()
	card.set_meta("purchase_tween", tween)
	tween.tween_property(card, "modulate", Color.WHITE, 0.3)
	game.feedback.pulse(shop_cards[food]["stock"])

func _process(_delta):
	if game.menu.visible and game.menu_type == "商店":
		update_shop()
	if source_food != "" and (not game.menu.visible or game.menu_type != "食材箱"):
		cancel_drag()

func source_input(event, food, card):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if game.inventory[food] <= 0 or game.current_page != "后厨":
			return
		source_food = food
		source_node = card
		press_point = card.get_global_transform() * event.position
		dragging = false
		card.accept_event()

func _input(event):
	if source_food == "":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var point = game.get_canvas_transform().affine_inverse() * event.position
		if not dragging and point.distance_to(press_point) >= 8:
			dragging = true
			game.menu.modulate.a = 0.12
			if game.veil_tween and game.veil_tween.is_valid():
				game.veil_tween.kill()
			game.menu_veil.modulate.a = 0
			ghost = game.label(game, source_food, Rect2(point, Vector2(88, 38)))
			ghost.z_index = 60
			ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			game.feedback.play("pickup")
		if dragging:
			ghost.position = point - ghost.size / 2
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var food = source_food
		var point = game.get_canvas_transform().affine_inverse() * event.position
		var was_dragging = dragging
		var valid = game.kitchen.TABLE_AREA.has_point(point) and not game.menu.get_global_rect().has_point(point)
		valid = valid and not game.kitchen.bin.get_global_rect().has_point(point) and not game.kitchen.outlet.get_global_rect().has_point(point)
		cancel_drag()
		get_viewport().set_input_as_handled()
		if not was_dragging:
			if game.kitchen.add_ingredient(food):
				game.menu.hide()
		elif valid and game.kitchen.add_ingredient(food):
			var card = game.kitchen.cards.back()
			card.position = point - card.size / 2
			card.clamp_to_area()
			game.kitchen.on_card_dropped(card)
			game.feedback.play("drop")
			game.refresh_menu()

func cancel_drag():
	source_food = ""
	source_node = null
	dragging = false
	if is_instance_valid(ghost):
		ghost.queue_free()
	game.menu.modulate.a = 1
	game.menu_veil.modulate.a = 1

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and source_food != "":
		cancel_drag()
