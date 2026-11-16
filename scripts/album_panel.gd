class_name AlbumPanel
extends Control
## The travel album: one page per trip (newest first) — her postcard (click to turn it over), the photo she
## brought back, the souvenir, and the facts (when she left and came back).

var travel: Travel
var _pages: Array = []
var _i := 0
var _card := PostcardView.new()
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


func _ready() -> void:
	size = Vector2(1280, 800)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.1, 0.14, 0.82)
	dim.size = size
	add_child(dim)
	var page := ColorRect.new()
	page.color = Color(0.93, 0.89, 0.8)
	page.position = Vector2(60, 50)
	page.size = Vector2(1160, 700)
	add_child(page)

	_title.position = Vector2(100, 70)
	_label_style(_title, 36)
	add_child(_title)
	_card.position = Vector2(100, 140)
	_card.size = Vector2(540, 360)
	add_child(_card)
	var hint := Label.new()
	hint.text = "点明信片可以翻到背面"
	hint.position = Vector2(100, 510)
	_label_style(hint, 16)
	hint.modulate.a = 0.6
	add_child(hint)

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

	_info.position = Vector2(100, 560)
	_info.size = Vector2(900, 150)
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


func _label_style(l: Label, s: int) -> void:
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", Color(0.25, 0.22, 0.28))


## Opens on the newest trip (or on the trip given).
func open(trip: Dictionary = {}) -> void:
	_pages = travel.trips_with_postcards()
	_pages.reverse()
	_i = maxi(_pages.find(trip), 0)
	travel.mark_seen()
	visible = true
	_show()


func turn_card() -> void:
	_card.back = not _card.back
	_card.queue_redraw()


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
	for n in [_card, _photo_frame, _info, _souvenir, _title]:
		n.visible = has
	_empty.visible = not has
	_prev.visible = has and _i < _pages.size() - 1
	_next.visible = has and _i > 0
	if not has:
		return
	var t: Dictionary = _pages[_i]
	var p: Dictionary = travel.places.get(t["place"], {})
	_title.text = "%s　第 %d 次旅行" % [p.get("name", t["place"]), _pages.size() - _i]
	_card.show_trip(p, t, _tex(p.get("postcard", "")))
	var photo := _tex(t["photo"])
	_photo.texture = photo
	_photo_note.text = "" if photo else ("她还在路上，照片回来再看" if not t["home"] else "这次没有带照片回来")
	var lines := ["%s 出发" % Travel.day_text(t["left"])]
	lines.append("%s 回家" % Travel.day_text(t["back"]) if t["home"] else "还在旅行中，明信片先寄到了")
	if t["home"] and t["souvenir"] != "":
		lines.append("带回来：" + t["souvenir"])
	_info.text = "　".join(lines)
	_souvenir.texture = _tex(p.get("souvenir_tex", "")) if t["home"] and t["souvenir"] != "" else null
