class_name Keepsakes
extends Node2D
## What her trips leave in the house: postcards pinned on the postcard wall, souvenirs on the shelf, and the
## travel magazine the user put on the coffee table. Places come from world.json "keepsakes" (world pixels).

var world: World
var travel: Travel
var notes: Notes
var _cards := {}                     # texture name -> small framed thumbnail
var _labels := []                    # [Rect2, "11月12日·杭州"] for the mouse: which trip each thing came from

const TAG := Color(0.97, 0.93, 0.82)
const TAG_INK := Color(0.45, 0.36, 0.3, 0.7)


func setup(w: World, t: Travel, n: Notes) -> void:
	world = w
	travel = t
	notes = n
	z_index = -7
	travel.changed.connect(_rebuild)
	notes.changed.connect(_rebuild)


## What the thing under the mouse is: "11月12日·杭州" for a postcard, the souvenir and its trip, or the notes.
func label_at(p: Vector2) -> String:
	for l in _labels:
		if l[0].has_point(p):
			return l[1] if l[1] is String else l[1].call()
	return ""


func _ready() -> void:
	_rebuild()


func info() -> Dictionary:
	return world.data.get("keepsakes", {})


## Which keepsake (wall, shelf, table) is at a world point, or "".
func hit(p: Vector2) -> String:
	for k in ["wall", "shelf", "table"]:
		var a: Array = info().get(k + "_rect", [])
		if a.size() == 4 and Rect2(a[0], a[1], a[2], a[3]).has_point(p):
			return k
	return ""


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_labels.clear()
	var k := info()
	if k.is_empty():
		return
	# postcards: newest first, in the wall's slots, each with a little paper tag (the mouse shows its trip)
	var slots: Array = k.get("wall_slots", [])
	var cards := travel.trips_with_postcards()
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
	# souvenirs standing on the shelves, a tag in front of each
	var shelf: Array = k.get("shelf_slots", [])
	var souvenirs := travel.souvenirs()
	var shelf_text := travel.shelf_labels()
	for i in mini(souvenirs.size(), shelf.size()):
		var name: String = travel.places.get(souvenirs[i], {}).get("souvenir_tex", "")
		if name != "" and ResourceLoader.exists(Travel.DIR + name):
			var s := Sprite2D.new()
			s.texture = load(Travel.DIR + name)
			# about the same size each (by area), so a tall fan on its handle is not smaller than a round jar
			var big := float(k.get("souvenir_h", 12))
			s.scale = Vector2.ONE * (big / sqrt(float(s.texture.get_width() * s.texture.get_height())))
			s.centered = false
			s.offset = Vector2(-s.texture.get_width() * 0.5, -s.texture.get_height())
			var at := Vector2(shelf[i][0], shelf[i][1])
			s.position = at
			add_child(s)
			_tag(at + Vector2(4.0, -1.0), 6.0)
			var w := s.texture.get_width() * s.scale.x
			var h := s.texture.get_height() * s.scale.y
			_labels.append([Rect2(at.x - w * 0.5, at.y - h, w, h + 2), shelf_text[i]])
	# a note on the coffee table: one she has not read, or one she left
	if notes.on_table:
		var at: Array = k.get("table_at", [0, 0])
		var paper := Vector2(at[0] + 14, at[1] - 3)
		_note(paper)
		_labels.append([Rect2(paper - Vector2(5, 4), Vector2(10, 8)), notes.caption])
	# the magazine on the coffee table
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


## A little paper tag (too small to read in the room; the mouse shows the words).
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


## A folded note on the table, a few lines of writing on it.
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


## The postcard picture with a white border, small (made once).
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
