class_name AlbumPanel
extends Control
## The travel album: one page per trip (newest first) — her postcard (click to turn it over), the photo she
## brought back, the souvenir, who the postcard was addressed to, and a recipient filter bar when cards were
## sent to specific people (妈妈, 姐姐...).

var travel: Travel
var _all_pages: Array = []
var _pages: Array = []
var _filter := "*"                   # "*" = all, "" = kept for home, else recipient name
var _i := 0
var _card := PostcardView.new()
var _hint := Label.new()
var _filter_box := HBoxContainer.new()
var _photo := TextureRect.new()
var _photo_frame := ColorRect.new()
var _photo_note := Label.new()
var _title := Label.new()
var _info := Label.new()
var _souvenir := TextureRect.new()
var _prev := Button.new()
var _next := Button.new()
var _empty := Label.new()
var _tex_cache := {}
var _dim := ColorRect.new()


func _ready() -> void:
	size = Vector2(1280, 800)
	_dim.color = Color(0.12, 0.1, 0.14, 0.82)
	_dim.size = size
	add_child(_dim)
	var page := ColorRect.new()
	page.color = Color(0.93, 0.89, 0.8)
	page.position = Vector2(60, 50)
	page.size = Vector2(1160, 700)
	add_child(page)

	fit(get_viewport().get_visible_rect().size)

	_title.position = Vector2(100, 70)
	_label_style(_title, 34)
	add_child(_title)

	_filter_box.position = Vector2(520, 72)
	_filter_box.add_theme_constant_override("separation", 8)
	add_child(_filter_box)

	_card.position = Vector2(100, 140)
	_card.size = Vector2(540, 360)
	_card.flipped.connect(_update_hint)
	add_child(_card)
	_hint.position = Vector2(100, 510)
	_label_style(_hint, 16)
	_hint.modulate.a = 0.72
	add_child(_hint)

	_photo_frame.color = Color.WHITE
	_photo_frame.position = Vector2(680, 140)
	_photo_frame.size = Vector2(500, 345)
	_photo_frame.rotation_degrees = 1.5
	add_child(_photo_frame)
	_photo.position = Vector2(14, 14)
	_photo.size = Vector2(472, 300)
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo_frame.add_child(_photo)
	_photo_note.position = Vector2(14, 120)
	_photo_note.size = Vector2(472, 60)
	_photo_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_style(_photo_note, 22)
	_photo_frame.add_child(_photo_note)

	_info.position = Vector2(100, 556)
	_info.size = Vector2(920, 150)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_style(_info, 22)
	add_child(_info)
	_souvenir.position = Vector2(1060, 540)
	_souvenir.size = Vector2(120, 120)
	_souvenir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_souvenir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_souvenir)

	_empty.position = Vector2(100, 360)
	_empty.size = Vector2(1080, 80)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.text = "还没有旅行过。\n她想出门的时候，会自己出发的。"
	_label_style(_empty, 28)
	add_child(_empty)

	for b in [_prev, _next]:
		b.add_theme_font_size_override("font_size", 24)
		add_child(b)
	_prev.text = "‹ 上一次"
	_prev.position = Vector2(100, 690)
	_prev.pressed.connect(func(): _turn(1))
	_next.text = "下一次 ›"
	_next.position = Vector2(1060, 690)
	_next.pressed.connect(func(): _turn(-1))
	var close := Button.new()
	close.text = "合上"
	close.add_theme_font_size_override("font_size", 24)
	close.position = Vector2(1120, 66)
	close.pressed.connect(func(): visible = false)
	add_child(close)


func fit(vis: Vector2) -> void:
	position = ((vis - size) / 2.0).floor()
	_dim.position = -position
	_dim.size = vis


func _label_style(l: Label, s: int) -> void:
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", Color(0.25, 0.22, 0.28))


func open(trip: Dictionary = {}, initial_filter := "*") -> void:
	_all_pages = travel.trips_with_postcards()
	_all_pages.reverse()
	_filter = initial_filter
	_rebuild_filters()
	_apply_filter(trip)
	travel.mark_seen()
	visible = true
	_show()


func set_filter(who: String) -> void:
	_filter = who
	_rebuild_filters()
	_apply_filter({})
	_show()


func _rebuild_filters() -> void:
	for c in _filter_box.get_children():
		c.queue_free()
	var recipients: Array[String] = []
	for t in _all_pages:
		var who := str(t.get("to", "")).strip_edges()
		if who != "" and not recipients.has(who):
			recipients.append(who)
	if recipients.is_empty():
		_filter = "*"
		_filter_box.visible = false
		return
	_filter_box.visible = true
	var tabs := [["*", "全部"], ["", "留在家里的"]]
	for who in recipients:
		tabs.append([who, "寄给" + who])
	for pair in tabs:
		var key: String = pair[0]
		var b := Button.new()
		b.text = ("• " if _filter == key else "") + str(pair[1])
		b.add_theme_font_size_override("font_size", 17)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): set_filter(key))
		_filter_box.add_child(b)


func _apply_filter(trip: Dictionary) -> void:
	if _filter == "*":
		_pages = _all_pages.duplicate()
	else:
		_pages = _all_pages.filter(func(t): return str(t.get("to", "")).strip_edges() == _filter)
	_i = maxi(_pages.find(trip), 0) if not trip.is_empty() else 0


func turn_card() -> void:
	_card.back = not _card.back
	_card.queue_redraw()
	_update_hint()


func _update_hint() -> void:
	_hint.text = "背面留言 · 点明信片翻回正面风景" if _card.back else "正面风景 · 点明信片翻到背面看字"


func _turn(d: int) -> void:
	_i = clampi(_i + d, 0, _pages.size() - 1)
	_show()


func _tex(name: String) -> Texture2D:
	if name == "" or not ResourceLoader.exists(Travel.DIR + name):
		return null
	if not _tex_cache.has(name):
		_tex_cache[name] = load(Travel.DIR + name)
	return _tex_cache[name]


func _show() -> void:
	var has := not _pages.is_empty()
	for n in [_card, _hint, _photo_frame, _info, _souvenir, _title]:
		n.visible = has
	_empty.visible = not has
	if not has:
		_empty.text = "还没有旅行过。\n她想出门的时候，会自己出发的。" if _all_pages.is_empty() else "这一栏里还没有明信片。"
	_prev.visible = has and _i < _pages.size() - 1
	_next.visible = has and _i > 0
	if not has:
		return
	var t: Dictionary = _pages[_i]
	var p: Dictionary = travel.places.get(t["place"], {})
	var idx_in_all := _all_pages.find(t)
	var num := _all_pages.size() - idx_in_all if idx_in_all >= 0 else _pages.size() - _i
	_title.text = "%s　第 %d 次旅行" % [p.get("name", t["place"]), num]
	_card.show_trip(p, t, _tex(p.get("postcard", "")), travel.scenic_note(t))
	_update_hint()
	var photo := _tex(t["photo"])
	_photo.texture = photo
	_photo_note.text = "" if photo else ("她还在路上，照片回来再看" if not t["home"] else "这次没有带照片回来")
	var to_who := str(t.get("to", "")).strip_edges()
	var lines := ["%s 出发" % Travel.day_text(t["left"])]
	lines.append("%s 回家" % Travel.day_text(t["back"]) if t["home"] else "还在旅行中，明信片先寄到了")
	lines.append("寄给：" + (to_who if to_who != "" else "家里的你"))
	if t["home"] and t["souvenir"] != "":
		lines.append("带回来：" + t["souvenir"] + ("（已挂墙上）" if str(t["place"]) == "dali" else ""))
	_info.text = "　".join(lines)
	_souvenir.texture = _tex(p.get("souvenir_tex", "")) if t["home"] and t["souvenir"] != "" else null
