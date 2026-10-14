extends Node
# 食材箱负责取料，采购簿负责购买。数量只在操作成功后扣除。
const GROUPS = {
	"蔬菜": ["番茄", "土豆", "胡萝卜", "洋葱", "辣椒", "蘑菇"],
	"水果": ["苹果", "草莓", "蓝莓"],
	"谷物": ["小麦", "稻米"],
	"蛋奶": ["鸡蛋", "牛奶", "奶酪"],
	"肉类": ["猪肉", "兔肉", "鱼", "牛肉", "虾仁", "龙虾", "扇贝"],
	"调味": ["蜂蜜", "可可豆", "松露", "藏红花", "香草荚"]
}
var game
var pantry_category = "蔬菜"
var shop_category = "全部"
var shop_tier = 0
var unlock_button = null
var warehouse_filter = "全部"
var warehouse_selected = ""
var warehouse_cards = {}
var warehouse_scroll: ScrollContainer
var warehouse_offset = 0
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
	style.bg_color = Color("fffdfa")
	style.border_color = Color("e5ccb4")
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
		style.bg_color = Color("ffe0c2")
		style.border_color = Color("c9793f")
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
	unlock_button = null
	game.menu.tiers.show()
	for i in range(3):
		var tier_button = action(game.menu.tiers, ["基础", "中级", "高级"][i], choose_tier.bind(i))
		mark_tab(tier_button, shop_tier == i)
	game.menu.title_bar.text = "采购簿"
	game.menu.tabs.show()
	for category in ["全部"] + GROUPS.keys():
		var tab = action(game.menu.tabs, category, choose_shop.bind(category))
		mark_tab(tab, category == shop_category)
	game.menu.header_info.text = "余额  %d" % game.money
	game.menu.apply_size()
	if shop_tier > 0 and not game.shops[["中级", "高级"][shop_tier - 1]]:
		var name = ["中级", "高级"][shop_tier - 1]
		var needed_day = 4 if shop_tier == 1 else 8
		var needed_recipes = 8 if shop_tier == 1 else 18
		var cost = 180 if shop_tier == 1 else 480
		game.menu_line(name + "采购资格")
		game.menu_line("第 %d / %d 天 · 正式菜谱 %d / %d" % [game.day, needed_day, game.catalog.count_known(), needed_recipes])
		if shop_tier == 2 and not game.shops["中级"]:
			game.menu_line("先解锁中级商店")
		game.menu_line("解锁后可购买：" + "、".join(tier_foods(shop_tier)))
		unlock_button = action(game.menu_content, "解锁 · %d 金币" % cost, unlock_tier)
		primary(unlock_button)
		unlock_button.disabled = not can_unlock(shop_tier)
		return
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
			if game.rules.database["foods"][food].get("tier", 0) != shop_tier:
				continue
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
			stock.add_theme_color_override("font_color", Color("806b5a"))
			text(column, "%d 金币 / 份" % game.PRICES[food], 13)
			var line = HSeparator.new()
			line.modulate = Color("e5ccb4")
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
			primary(buy)
			shop_cards[food] = {"card": card, "stock": stock, "minus": minus, "plus": plus, "amount": amount, "buy": buy}
	if shop_cards.is_empty():
		game.menu_line("本级商店暂无此类商品")
	update_shop()

func update_shop():
	game.menu.header_info.text = "余额  %d" % game.money
	if is_instance_valid(unlock_button):
		unlock_button.disabled = not can_unlock(shop_tier)
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
	if not can_buy(food) or not shop_cards.has(food):
		return
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

func primary(button):
	for state in ["normal", "hover", "pressed"]:
		var style = button.get_theme_stylebox(state).duplicate()
		style.bg_color = Color("b85722") if state == "normal" else Color("a64d1d")
		style.border_color = style.bg_color
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("fffdfa"))

func tier_foods(tier):
	var result = []
	for food in game.rules.database["foods"]:
		if game.rules.database["foods"][food].get("tier", 0) == tier:
			result.append(food)
	return result

func choose_tier(tier):
	shop_tier = tier
	game.menu.scroll.scroll_vertical = 0
	game.refresh_menu()

func can_buy(food):
	if not game.PRICES.has(food):
		return false
	var tier = game.rules.database["foods"][food].get("tier", 0)
	return tier == 0 or game.shops["中级" if tier == 1 else "高级"]

func can_unlock(tier):
	if tier == 1:
		return not game.shops["中级"] and game.day >= 4 and game.catalog.count_known() >= 8 and game.money >= 180
	if tier == 2:
		return game.shops["中级"] and not game.shops["高级"] and game.day >= 8 and game.catalog.count_known() >= 18 and game.money >= 480
	return false

func unlock_tier():
	if not can_unlock(shop_tier):
		return
	var name = "中级" if shop_tier == 1 else "高级"
	if game.spend(180 if shop_tier == 1 else 480):
		game.shops[name] = true
		game.feedback.play("complete")
		game.refresh_menu()

func choose_warehouse(tag):
	warehouse_filter = tag
	warehouse_selected = ""
	warehouse_offset = 0
	game.refresh_menu()

func inspect_stock(food):
	warehouse_offset = warehouse_scroll.scroll_vertical
	warehouse_selected = "" if warehouse_selected == food else food
	game.refresh_menu()

func stock_matches(food):
	if warehouse_filter == "全部":
		return true
	if warehouse_filter == "有库存":
		return game.inventory[food] > 0
	var data = game.rules.database["foods"][food]
	# 酸甜和清甜也归入甜味，避免玩家漏看水果。
	if warehouse_filter == "甜":
		return data["tags"].has("甜") or data["tags"].has("酸甜") or data["tags"].has("清甜")
	if warehouse_filter == "酸":
		return data["tags"].has("酸") or data["tags"].has("酸甜")
	return data["tags"].has(warehouse_filter) or data.get("uses", []).has(warehouse_filter)

func build_warehouse():
	# 左右两栏分别滚动，外层不再显示第三条滚动条。
	game.menu.scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	warehouse_cards.clear()
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = game.menu.scroll.size.y - 8
	row.add_theme_constant_override("separation", 16)
	game.menu_content.add_child(row)
	var left = ScrollContainer.new()
	left.custom_minimum_size.x = 92
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(left)
	var filters = VBoxContainer.new()
	filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_theme_constant_override("separation", 7)
	left.add_child(filters)
	for tag in ["全部", "有库存"]:
		mark_tab(action(filters, tag, choose_warehouse.bind(tag)), tag == warehouse_filter)
	var groups = {"风味": ["甜", "酸", "鲜香", "奶香", "谷香"], "口感": ["多汁", "细腻", "饱腹"], "用途": ["烘焙", "饮品", "汤品"]}
	for group in groups:
		text(filters, group, 12).add_theme_color_override("font_color", Color("806b5a"))
		for tag in groups[group]:
			mark_tab(action(filters, tag, choose_warehouse.bind(tag)), tag == warehouse_filter)
	warehouse_scroll = ScrollContainer.new()
	warehouse_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warehouse_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(warehouse_scroll)
	var grid = GridContainer.new()
	grid.columns = [1, 2, 3][game.menu.size_index]
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	warehouse_scroll.add_child(grid)
	for food in game.inventory:
		if not stock_matches(food):
			continue
		var data = game.rules.database["foods"][food]
		var caption = food + "（%d）" % game.inventory[food] + "\n\n" + " · ".join(data["tags"].keys().slice(0, 2))
		caption += "\n适合" + "、".join(data.get("uses", []))
		if food == warehouse_selected:
			caption += "\n\n" + game.weight_text(data["tags"]) + "\n\n再次点击收起"
		var card = action(grid, caption, inspect_stock.bind(food))
		card.custom_minimum_size.y = 132 if food != warehouse_selected else 220
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_font_size_override("font_size", 14)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warehouse_cards[food] = card
	if warehouse_cards.is_empty():
		text(grid, "暂无符合标签的食材", 14)
	warehouse_scroll.set_deferred("scroll_vertical", warehouse_offset)
