class_name Keepsakes
extends Node2D
## What her trips leave in the house: postcards pinned on her wall (cards addressed to others stay in the album),
## Dali's tie-dye cloth hung on the wall as a picture, souvenirs on the 16-slot cabinet, interactive props on the
## coffee / dining table (brewed Longjing tea, Suichang zongzi, Xianghu radish), and click animations.

var world: World
var travel: Travel
var notes: Notes
var _cards := {}                     # texture name -> small framed thumbnail
var _labels := []                    # [Rect2, text_or_callable]
var _souvenir_hits := []             # [Rect2, place_id]
var _souvenir_nodes := {}            # place_id -> {sprite, base_pos, base_rot, base_scale, top}
var _fx_node := Node2D.new()
var _fx_place := ""
var _fx_t := 0.0
var _fx_dur := 4.0
var _tea_t := 0.0                    # >0: steaming Longjing teacup on coffee table
var _snack := ""                     # "suichang" / "xianghu"
var _snack_t := 0.0                  # >0: snack dish on dining table
var _snow_lamp := false              # Xuexiang snow cottage warm light toggled on
var _anim_clock := 0.0

const TAG := Color(0.97, 0.93, 0.82)
const TAG_INK := Color(0.45, 0.36, 0.3, 0.7)


func setup(w: World, t: Travel, n: Notes) -> void:
	world = w
	travel = t
	notes = n
	z_index = -7
	travel.changed.connect(_rebuild)
	notes.changed.connect(_rebuild)


func label_at(p: Vector2) -> String:
	for l in _labels:
		if l[0].has_point(p):
			return l[1] if l[1] is String else l[1].call()
	return ""


## Which individual souvenir is under a world point (or "").
func souvenir_at(p: Vector2) -> String:
	for h in _souvenir_hits:
		if (h[0] as Rect2).has_point(p):
			return str(h[1])
	return ""


func _ready() -> void:
	_fx_node.z_index = 2
	add_child(_fx_node)
	_rebuild()


func info() -> Dictionary:
	return world.data.get("keepsakes", {})


## Which keepsake area (wall, shelf, table) is at a world point, or "".
func hit(p: Vector2) -> String:
	for k in ["wall", "shelf", "table"]:
		var a: Array = info().get(k + "_rect", [])
		if a.size() == 4 and Rect2(a[0], a[1], a[2], a[3]).has_point(p):
			return k
	return ""


## Triggers a visual interaction on an owned souvenir (and table props for tea / snacks).
func trigger(place_id: String) -> void:
	_fx_place = place_id
	_fx_dur = 6.4 if place_id == "xiamen" else (3.4 if place_id == "dunhuang" else 3.0)
	_fx_t = _fx_dur
	match place_id:
		"hangzhou":
			_tea_t = 180.0
		"suichang", "xianghu":
			_snack = place_id
			_snack_t = 180.0
		"xuexiang":
			_snow_lamp = not _snow_lamp
			_rebuild()


func is_snow_lamp_on() -> bool:
	return _snow_lamp


func _process(delta: float) -> void:
	var dirty := false
	_anim_clock += delta
	if _fx_t > 0.0:
		_fx_t = maxf(_fx_t - delta, 0.0)
		dirty = true
		if _souvenir_nodes.has(_fx_place):
			var d: Dictionary = _souvenir_nodes[_fx_place]
			var sp: Sprite2D = d["sprite"]
			if is_instance_valid(sp):
				if _fx_t > 0.0:
					var w := sin(_anim_clock * 9.0) * minf(_fx_t, 1.0)
					sp.rotation_degrees = float(d["base_rot"]) + w * (4.5 if _fx_place == "dali" else 7.0)
					var pulse := 1.0 + maxf(0.0, sin(_anim_clock * 7.0)) * 0.07 * minf(_fx_t, 1.0)
					sp.scale = (d["base_scale"] as Vector2) * pulse
				else:
					sp.rotation_degrees = float(d["base_rot"])
					sp.scale = d["base_scale"]
	if _tea_t > 0.0:
		_tea_t = maxf(_tea_t - delta, 0.0)
		dirty = true
	if _snack_t > 0.0:
		_snack_t = maxf(_snack_t - delta, 0.0)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var k := info()
	# 1) Steaming West Lake Longjing teacup on the coffee table
	if _tea_t > 0.0:
		var ta: Array = k.get("tea_at", [167, 535])
		var tc := Vector2(float(ta[0]), float(ta[1]))
		draw_circle(tc + Vector2(0, 1.2), 3.6, Color(0.2, 0.15, 0.1, 0.25))     # saucer shadow
		draw_circle(tc + Vector2(0, 0.6), 3.3, Color(0.95, 0.96, 0.94))         # white porcelain saucer
		draw_circle(tc + Vector2(0, -0.6), 2.4, Color(0.98, 0.99, 0.96))        # cup rim
		draw_circle(tc + Vector2(0, -0.8), 1.7, Color(0.56, 0.74, 0.42))        # clear green Longjing tea
		for i in 3:
			var ph := fmod(_anim_clock * 0.7 + i * 0.33, 1.0)
			var wy := tc.y - 2.8 - ph * 6.5
			var wx := tc.x + sin(_anim_clock * 2.6 + i * 2.1) * 1.4
			draw_circle(Vector2(wx, wy), 0.85 * (1.0 - ph * 0.5), Color(1, 1, 1, (1.0 - ph) * 0.55))

	# 2) Suichang zongzi or Xianghu radish dish on the dining table
	if _snack_t > 0.0:
		var sa: Array = k.get("snack_at", [368, 565])
		var sc := Vector2(float(sa[0]), float(sa[1]))
		draw_circle(sc + Vector2(0, 1.0), 4.2, Color(0.2, 0.15, 0.1, 0.22))
		if _snack == "suichang":
			draw_circle(sc, 3.8, Color(0.84, 0.72, 0.48))                       # bamboo plate
			draw_line(sc + Vector2(-2.2, 0.3), sc + Vector2(2.2, -0.7), Color(0.32, 0.56, 0.28), 2.2)
			draw_line(sc + Vector2(-0.2, -1.6), sc + Vector2(0.2, 1.0), Color(0.88, 0.78, 0.52), 0.7)
		else:
			draw_circle(sc, 3.6, Color(0.95, 0.94, 0.90))                       # small ceramic dish
			for j in 5:
				var off := Vector2(cos(j * 1.25) * 1.4, sin(j * 1.25) * 1.1 - 0.3)
				draw_circle(sc + off, 0.95, Color(0.76, 0.52, 0.26))            # crisp amber radish slices

	# 3) Floating particles above whichever souvenir was just interacted with
	if _fx_t > 0.0 and _souvenir_nodes.has(_fx_place):
		var top: Vector2 = _souvenir_nodes[_fx_place]["top"]
		var fade := clampf(_fx_t / 0.8, 0.0, 1.0)
		match _fx_place:
			"xiamen":
				for i in 3:
					var ph := fmod(_anim_clock * 0.55 + i * 0.33, 1.0)
					var pos := top + Vector2(sin(_anim_clock * 2.4 + i * 2.0) * 3.5 + (i - 1) * 3.2, -1.5 - ph * 10.0)
					var a := (1.0 - ph) * fade
					_draw_music_note(pos, i % 2 == 1, a)
			"dunhuang":
				for i in 6:
					var ph := fmod(_anim_clock * 0.65 + i * 0.17, 1.0)
					var pos := top + Vector2((i - 2.5) * 2.2 + sin(_anim_clock * 3.0 + i) * 1.8, 3.0 - ph * 7.0)
					draw_circle(pos, 0.75, Color(0.98, 0.84, 0.45, (1.0 - ph) * fade * 0.9))
			"shanghai":
				for i in 6:
					var ang := _anim_clock * 2.8 + i * TAU / 6.0
					var pos := top + Vector2(cos(ang) * 4.2, 4.0 + sin(ang * 1.3) * 3.2 - (1.0 - _fx_t / _fx_dur) * 3.0)
					draw_circle(pos, 0.7, Color(1.0, 0.88, 0.96, fade * 0.9))
			"chengdu":
				var ph := 1.0 - (_fx_t / _fx_dur)
				var pos := top + Vector2(sin(_anim_clock * 3.0) * 1.5, -ph * 8.0)
				draw_circle(pos + Vector2(-0.9, 0), 1.1, Color(0.98, 0.45, 0.58, fade))
				draw_circle(pos + Vector2(0.9, 0), 1.1, Color(0.98, 0.45, 0.58, fade))
				draw_polygon(PackedVector2Array([pos + Vector2(-1.9, 0.3), pos + Vector2(1.9, 0.3), pos + Vector2(0, 2.5)]),
					PackedColorArray([Color(0.98, 0.45, 0.58, fade), Color(0.98, 0.45, 0.58, fade), Color(0.98, 0.45, 0.58, fade)]))
			"huangshan":
				for i in 5:
					var ph := fmod(_anim_clock * 0.9 + i * 0.2, 1.0)
					var pos := top + Vector2((i - 2) * 1.8, -2.0 + ph * 5.0)
					draw_circle(pos, 0.65, Color(0.72, 0.92, 1.0, (1.0 - ph) * fade * 0.85))
			_:
				for i in 3:
					var ang := _anim_clock * 2.2 + i * TAU / 3.0
					var pos := top + Vector2(cos(ang) * 3.5, 2.0 + sin(ang) * 2.0)
					draw_circle(pos, 0.7, Color(1.0, 0.95, 0.72, fade * 0.85))


func _rebuild() -> void:
	for c in get_children():
		if c != _fx_node:
			c.queue_free()
	_labels.clear()
	_souvenir_hits.clear()
	_souvenir_nodes.clear()
	var k := info()
	if k.is_empty():
		return
	# 1) Postcards kept for home: newest first, in the wall's slots
	var slots: Array = k.get("wall_slots", [])
	var cards := travel.wall_trips()
	cards.reverse()
	var size: Array = k.get("card_size", [20, 14])
	for i in mini(cards.size(), slots.size()):
		var p: Dictionary = travel.places.get(cards[i]["place"], {})
		var tex := _thumb(p.get("postcard", ""))
		if tex:
			var at := Vector2(slots[i][0], slots[i][1])
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = true
			s.scale = Vector2(float(size[0]) / tex.get_width(), float(size[1]) / tex.get_height())
			s.position = at
			s.rotation_degrees = [-4.0, 3.0, -2.0, 5.0, -3.0, 2.0][i % 6]
			add_child(s)
			_tag(at + Vector2(size[0] * 0.5 - 5.0, size[1] * 0.5 - 1.5), -s.rotation_degrees * 1.5)
			_labels.append([Rect2(at - Vector2(size[0], size[1]) * 0.5, Vector2(size[0], size[1] + 2)),
				travel.trip_label(cards[i], "postcard_at")])

	# 2) Souvenirs: Dali's tie-dye cloth hangs on the wall; all others stand on the 16-slot cabinet
	var shelf: Array = k.get("shelf_slots", [])
	var souvenirs := travel.souvenirs()
	var shelf_text := travel.shelf_labels()
	var shelf_idx := 0
	for idx in souvenirs.size():
		var pid: String = str(souvenirs[idx])
		var name: String = travel.places.get(pid, {}).get("souvenir_tex", "")
		var label_str: String = shelf_text[idx] + " · 点一下试试"
		if pid == "dali":
			var wa: Array = k.get("wall_art_at", [395, 389])
			var wsize := float(k.get("wall_art_size", 13))
			var at := Vector2(float(wa[0]), float(wa[1]))
			if name != "" and ResourceLoader.exists(Travel.DIR + name):
				var s := Sprite2D.new()
				s.texture = load(Travel.DIR + name)
				var sc := wsize / maxf(float(s.texture.get_width()), float(s.texture.get_height()))
				s.scale = Vector2.ONE * sc
				s.centered = true
				s.position = at
				add_child(s)
				var rw := s.texture.get_width() * sc
				var rh := s.texture.get_height() * sc
				var rect := Rect2(at.x - rw * 0.5 - 2.0, at.y - rh * 0.5 - 2.0, rw + 4.0, rh + 4.0)
				_labels.append([rect, label_str])
				_souvenir_hits.append([rect, pid])
				_souvenir_nodes[pid] = {"sprite": s, "base_pos": at, "base_rot": 0.0, "base_scale": s.scale,
					"top": at + Vector2(0, -rh * 0.5)}
			else:
				# clean indigo-and-white fallback swatch if texture not imported yet
				var cloth := _make_tiedye_fallback(at, wsize)
				var rect := Rect2(at.x - wsize * 0.5 - 2.0, at.y - wsize * 0.5 - 2.0, wsize + 4.0, wsize + 4.0)
				_labels.append([rect, label_str])
				_souvenir_hits.append([rect, pid])
				_souvenir_nodes[pid] = {"sprite": cloth, "base_pos": at, "base_rot": 0.0, "base_scale": cloth.scale,
					"top": at + Vector2(0, -wsize * 0.5)}
			continue

		if shelf_idx >= shelf.size():
			continue
		if name != "" and ResourceLoader.exists(Travel.DIR + name):
			var s := Sprite2D.new()
			s.texture = load(Travel.DIR + name)
			var big := float(k.get("souvenir_h", 11))
			s.scale = Vector2.ONE * (big / sqrt(float(s.texture.get_width() * s.texture.get_height())))
			s.centered = false
			s.offset = Vector2(-s.texture.get_width() * 0.5, -s.texture.get_height())
			var at := Vector2(float(shelf[shelf_idx][0]), float(shelf[shelf_idx][1]))
			s.position = at
			add_child(s)
			if pid == "xuexiang" and _snow_lamp and ResourceLoader.exists("res://assets/generated/glow_warm.png"):
				var glow := Sprite2D.new()
				glow.texture = load("res://assets/generated/glow_warm.png")
				var gmat := CanvasItemMaterial.new()
				gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				glow.material = gmat
				glow.modulate = Color(1.0, 0.82, 0.42, 0.75)
				glow.scale = Vector2.ONE * (22.0 / float(glow.texture.get_width()))
				glow.position = at + Vector2(0, -big * 0.45)
				add_child(glow)
			_tag(at + Vector2(3.5, -1.0), 6.0)
			var w := s.texture.get_width() * s.scale.x
			var h := s.texture.get_height() * s.scale.y
			var rect := Rect2(at.x - maxf(w * 0.5, 6.0), at.y - maxf(h, 10.0), maxf(w, 12.0), maxf(h, 10.0) + 3.0)
			_labels.append([rect, label_str])
			_souvenir_hits.append([rect, pid])
			_souvenir_nodes[pid] = {"sprite": s, "base_pos": at, "base_rot": 0.0, "base_scale": s.scale,
				"top": at + Vector2(0, -h)}
			shelf_idx += 1

	# 3) Steaming tea / dining snack hover labels when active
	if _tea_t > 0.0:
		var ta: Array = k.get("tea_at", [167, 535])
		_labels.append([Rect2(float(ta[0]) - 5.0, float(ta[1]) - 6.0, 10.0, 10.0), "刚泡好的西湖龙井，还冒着热气"])
	if _snack_t > 0.0:
		var sa: Array = k.get("snack_at", [368, 565])
		var sname := "剥开的遂昌长粽" if _snack == "suichang" else "一碟萧山萝卜干"
		_labels.append([Rect2(float(sa[0]) - 5.0, float(sa[1]) - 5.0, 10.0, 10.0), sname])

	# 4) Coffee-table note
	if notes.on_table:
		var at: Array = k.get("table_at", [0, 0])
		var paper := Vector2(at[0] + 14, at[1] - 3)
		_note(paper)
		_labels.append([Rect2(paper - Vector2(5, 4), Vector2(10, 8)), notes.caption])

	# 5) Coffee-table magazine
	var m: String = travel.data["magazine"]
	if m != "":
		var name: String = travel.places.get(m, {}).get("magazine_tex", "")
		var at: Array = k.get("table_at", [0, 0])
		if name != "" and ResourceLoader.exists(Travel.DIR + name):
			var s := Sprite2D.new()
			s.texture = load(Travel.DIR + name)
			s.scale = Vector2.ONE * (float(k.get("magazine_w", 20)) / s.texture.get_width())
			s.position = Vector2(at[0], at[1])
			s.rotation_degrees = -8.0
			add_child(s)
		else:
			var r := ColorRect.new()
			r.color = Color(0.85, 0.4, 0.35)
			r.size = Vector2(16, 11)
			r.position = Vector2(at[0] - 8, at[1] - 6)
			r.rotation_degrees = -8.0
			add_child(r)
	queue_redraw()


func _draw_music_note(p: Vector2, beamed: bool, alpha: float) -> void:
	var dark := Color(0.22, 0.16, 0.26, alpha * 0.75)
	var gold := Color(1.0, 0.92, 0.52, alpha)
	draw_circle(p, 1.35, dark)
	draw_circle(p, 0.95, gold)
	draw_line(p + Vector2(0.8, 0), p + Vector2(0.8, -3.6), dark, 1.2)
	draw_line(p + Vector2(0.8, 0), p + Vector2(0.8, -3.6), gold, 0.7)
	if beamed:
		var p2 := p + Vector2(2.6, 0.5)
		draw_circle(p2, 1.35, dark)
		draw_circle(p2, 0.95, gold)
		draw_line(p2 + Vector2(0.8, 0), p2 + Vector2(0.8, -3.5), dark, 1.2)
		draw_line(p2 + Vector2(0.8, 0), p2 + Vector2(0.8, -3.5), gold, 0.7)
		draw_line(p + Vector2(0.6, -3.5), p2 + Vector2(1.0, -3.4), gold, 0.9)
	else:
		draw_line(p + Vector2(0.8, -3.6), p + Vector2(2.3, -2.3), gold, 0.85)


func _make_tiedye_fallback(at: Vector2, wsize: float) -> Sprite2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			if y < 3:
				img.set_pixel(x, y, Color(0.68, 0.50, 0.32))
			elif x >= 2 and x < 30 and y >= 3 and y < 30:
				var d := Vector2(x - 15.5, y - 16.5).length()
				var ring := absf(d - 7.5) < 1.8 or absf(d - 2.0) < 1.6
				img.set_pixel(x, y, Color(0.96, 0.97, 0.99) if ring else Color(0.16, 0.32, 0.62))
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.centered = true
	s.scale = Vector2.ONE * (wsize / 32.0)
	s.position = at
	add_child(s)
	return s


func _tag(at: Vector2, degrees: float) -> void:
	var tag := Node2D.new()
	tag.position = at
	tag.rotation_degrees = degrees
	var r := ColorRect.new()
	r.color = TAG
	r.size = Vector2(7, 3)
	r.position = Vector2(-3.5, -1.5)
	tag.add_child(r)
	var ink := ColorRect.new()
	ink.color = TAG_INK
	ink.size = Vector2(5, 1)
	ink.position = Vector2(-2.5, -0.5)
	tag.add_child(ink)
	add_child(tag)


func _note(at: Vector2) -> void:
	var n := Node2D.new()
	n.position = at
	n.rotation_degrees = 12.0
	var shade := ColorRect.new()
	shade.color = Color(0.2, 0.15, 0.1, 0.25)
	shade.size = Vector2(5.5, 4)
	shade.position = Vector2(-2.25, -1.5)
	n.add_child(shade)
	var paper := ColorRect.new()
	paper.color = Color(0.99, 0.97, 0.9)
	paper.size = Vector2(5.5, 4)
	paper.position = Vector2(-2.75, -2)
	n.add_child(paper)
	for y in [-0.75, 0.75]:
		var line := ColorRect.new()
		line.color = Color(0.35, 0.45, 0.7, 0.7)
		line.size = Vector2(3.5 if y < 0.0 else 2.5, 0.6)
		line.position = Vector2(-1.75, y - 0.3)
		n.add_child(line)
	add_child(n)


func _thumb(name: String) -> Texture2D:
	if name == "" or not ResourceLoader.exists(Travel.DIR + name):
		return null
	if not _cards.has(name):
		var img := (load(Travel.DIR + name) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(96, 64, Image.INTERPOLATE_LANCZOS)
		var framed := Image.create(104, 72, false, Image.FORMAT_RGBA8)
		framed.fill(Color(0.98, 0.96, 0.9))
		framed.blit_rect(img, Rect2i(0, 0, 96, 64), Vector2i(4, 4))
		_cards[name] = ImageTexture.create_from_image(framed)
	return _cards[name]
