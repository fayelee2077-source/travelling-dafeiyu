class_name SettingsPanel
extends Control
## Long-press settings: pair code, computer address, zoom, what to do when the computer goes away.

signal saved(link_changed: bool)

var _status := Label.new()
var _code := LineEdit.new()
var _host := LineEdit.new()
var _zoom_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _weather_buttons: Dictionary = {}
var _sound_buttons: Dictionary = {}
var _body_buttons: Dictionary = {}
var _view_buttons: Dictionary = {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(46, 30, 24, 245)
	style.border_color = Color8(232, 196, 140)
	style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	box.add_theme_stylebox_override("panel", style)
	box.position = Vector2(240, 12)
	box.custom_minimum_size = Vector2(800, 0)
	add_child(box)
	# in the middle of a window of any shape (laid out for 1280 x 800)
	resized.connect(func(): box.position = ((size - Vector2(1280, 800)) / 2.0).floor() + Vector2(240, 12))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)

	v.add_child(_label("设置", 34))
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_color_override("font_color", Color8(255, 210, 120))
	v.add_child(_status)

	_code.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code.max_length = 12
	_code.placeholder_text = "电脑上 DSH 插件的配对码"
	v.add_child(_row("配对码", _code))

	_host.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_host.placeholder_text = "留空 = 自动找"
	v.add_child(_row("电脑地址", _host))

	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 12)
	var zg := ButtonGroup.new()
	for z in [3, 4, 5]:
		var b := _toggle("%d 倍" % z, zg)
		_zoom_buttons[z] = b
		zoom_row.add_child(b)
	v.add_child(_row("近景大小", zoom_row))

	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 12)
	var vg := ButtonGroup.new()
	for m in [["far", "整张图"], ["near", "跟着伙伴"]]:
		var b := _toggle(m[1], vg)
		_view_buttons[m[0]] = b
		view_row.add_child(b)
	v.add_child(_row("平时看", view_row))

	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 12)
	var bg := ButtonGroup.new()
	for m in [[1.0, "大（两格）"], [0.75, "中"], [0.625, "小"]]:
		var b := _toggle(m[1], bg)
		_body_buttons[m[0]] = b
		body_row.add_child(b)
	v.add_child(_row("人物大小", body_row))

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	var mg := ButtonGroup.new()
	for m in [["freeze", "停在最后一帧"], ["loop", "继续自己玩"]]:
		var b := _toggle(m[1], mg)
		_mode_buttons[m[0]] = b
		mode_row.add_child(b)
	v.add_child(_row("电脑断开时", mode_row))

	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 12)
	var wg := ButtonGroup.new()
	for m in [["season", "跟季节变化"], ["clear", "一直晴天"]]:
		var b := _toggle(m[1], wg)
		_weather_buttons[m[0]] = b
		weather_row.add_child(b)
	v.add_child(_row("天气", weather_row))

	var sound_row := HBoxContainer.new()
	sound_row.add_theme_constant_override("separation", 12)
	var sg := ButtonGroup.new()
	for m in [["on", "开"], ["off", "关"]]:
		var b := _toggle(m[1], sg)
		_sound_buttons[m[0]] = b
		sound_row.add_child(b)
	v.add_child(_row("环境声音", sound_row))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 16)
	var cancel := _button("取消")
	cancel.pressed.connect(func(): visible = false)
	var ok := _button("保存")
	ok.pressed.connect(_save)
	actions.add_child(cancel)
	actions.add_child(ok)
	v.add_child(actions)


func open(status: String) -> void:
	_status.text = status
	_code.text = Settings.pair_code
	_host.text = Settings.host_ip
	_zoom_buttons[Settings.zoom].button_pressed = true
	_mode_buttons[Settings.on_disconnect].button_pressed = true
	_weather_buttons[Settings.weather_mode].button_pressed = true
	_sound_buttons[Settings.sound].button_pressed = true
	_body_buttons[Settings.body_scale].button_pressed = true
	_view_buttons[Settings.view].button_pressed = true
	visible = true


func set_status(text: String) -> void:
	_status.text = text


func _save() -> void:
	var code := _code.text.strip_edges()
	var host := _host.text.strip_edges()
	var link_changed := code != Settings.pair_code or host != Settings.host_ip
	Settings.pair_code = code
	Settings.host_ip = host
	for z in _zoom_buttons:
		if _zoom_buttons[z].button_pressed:
			Settings.zoom = z
	for m in _mode_buttons:
		if _mode_buttons[m].button_pressed:
			Settings.on_disconnect = m
	for m in _weather_buttons:
		if _weather_buttons[m].button_pressed:
			Settings.weather_mode = m
	for m in _sound_buttons:
		if _sound_buttons[m].button_pressed:
			Settings.sound = m
	for m in _body_buttons:
		if _body_buttons[m].button_pressed:
			Settings.body_scale = m
	for m in _view_buttons:
		if _view_buttons[m].button_pressed:
			Settings.view = m
	Settings.save_settings()
	visible = false
	saved.emit(link_changed)


func _label(text: String, font_size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color8(255, 245, 230))
	return l


func _row(title: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var l := _label(title)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is LineEdit:
		control.add_theme_font_size_override("font_size", 28)
		control.custom_minimum_size = Vector2(0, 52)
	h.add_child(control)
	return h


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size = Vector2(150, 56)
	return b


func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := _button(text)
	b.toggle_mode = true
	b.button_group = group
	return b
