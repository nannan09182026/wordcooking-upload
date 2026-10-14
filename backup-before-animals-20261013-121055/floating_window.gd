extends Panel
# 一个普通 Control 窗口：标题栏拖动、三档尺寸、滚动内容。
const SIZES = [Vector2(360, 300), Vector2(620, 440), Vector2(920, 570)]
var game
var title = "窗口"
var size_index = 1
var title_bar: Label
var resize_button: Button
var close_button: Button
var scroll: ScrollContainer
var content: VBoxContainer
var held = false
var start_mouse = Vector2.ZERO
var start_point = Vector2.ZERO

func _ready():
	var box = StyleBoxFlat.new()
	box.bg_color = Color("f7f6f1")
	box.border_color = Color("93998d")
	box.set_border_width_all(1)
	box.shadow_color = Color(0, 0, 0, 0.1)
	box.shadow_size = 6
	add_theme_stylebox_override("panel", box)
	title_bar = Label.new()
	title_bar.text = title
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(title_input)
	add_child(title_bar)
	resize_button = game.button(self, "□", Rect2(), cycle_size)
	resize_button.tooltip_text = "窗口大小：小 → 中 → 大"
	close_button = game.button(self, "×", Rect2(), hide)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	apply_size()

func apply_size():
	size = SIZES[size_index]
	title_bar.position = Vector2(16, 6)
	title_bar.size = Vector2(size.x - 106, 32)
	resize_button.position = Vector2(size.x - 80, 7)
	resize_button.size = Vector2(30, 28)
	close_button.position = Vector2(size.x - 42, 7)
	close_button.size = Vector2(30, 28)
	scroll.position = Vector2(16, 48)
	scroll.size = size - Vector2(32, 64)
	clamp_position()

func cycle_size():
	size_index = (size_index + 1) % SIZES.size()
	apply_size()

func clamp_position():
	position.x = clampf(position.x, 0, 1280 - size.x)
	position.y = clampf(position.y, 0, 720 - size.y)

func title_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		held = true
		start_mouse = title_bar.get_global_transform() * event.position
		start_point = position
		move_to_front()
		accept_event()

func _input(event):
	if not held:
		return
	if event is InputEventMouseMotion:
		position = start_point + get_canvas_transform().affine_inverse() * event.position - start_mouse
		clamp_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		held = false

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held = false
