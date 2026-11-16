class_name World
extends Node2D
## The little home: one whole hand-drawn picture as the map (assets/ai_home/, built by tools/ai_home.py; world.json
## "res" says how many picture pixels make one world pixel), y-sorted companion, walk grid, day/night and moonlight
## tint, seasons, weather, indoor and outdoor lights.
## Shared pictures (bubbles, icons, glows, birds) come from assets/generated/.

const DIR := "res://assets/generated/"
const DATA_DIR := "res://assets/ai_home/"

var data: Dictionary
var style_filter := CanvasItem.TEXTURE_FILTER_LINEAR
var data_res := 1.0              # this world's own pictures: texture pixels per world pixel
var doorway := Rect2()           # the companion fades out while passing through it
var tile := 16
var size := Vector2i(28, 17)
var spots: Dictionary = {}
var astar := AStarGrid2D.new()
var sort_root := Node2D.new()
var scenes: Dictionary = {}      # spot -> Sprite2D: that piece of the room with the companion drawn in
var scene_on := false            # one of them is showing (the companion sprite is hidden)
var monitor_on := false
var tv_on := false
var lamp_on := true
var nobody_home := false         # she is out (not come in yet, or travelling): lights and scenes off
var season := "summer"
var indoor := Rect2()            # inside the house (pixels)
var outdoor := Rect2()           # the open-air part (whole world when not set)
var areas: Dictionary = {}       # name -> Rect2: separate maps (yard, inside the house), one screen each
var portals: Array = []          # [[cell a, cell b]]: stepping from one to the other changes map
var rooms: Dictionary = {}       # name -> Rect2 (pixels)
var water := Rect2()
var trees: Array[Vector2] = []
var weather := Weather.new()
var lights_layer := CanvasLayer.new()

var _tint := CanvasModulate.new()
var _lights: Array = []          # [{sprite, when}]
var occupied_room := ""          # the room the companion is in (set by main)
var _dark := 0.0

# hour -> tint; interpolated. Night is then shaded by the moon (see _night_color).
const TINTS := [
	[0.0, Color(0.36, 0.40, 0.66)],
	[5.0, Color(0.36, 0.40, 0.66)],
	[6.5, Color(0.92, 0.78, 0.74)],
	[8.0, Color(1, 1, 1)],
	[16.5, Color(1, 1, 1)],
	[18.0, Color(1.0, 0.84, 0.70)],
	[19.5, Color(0.56, 0.52, 0.74)],
	[20.5, Color(0.40, 0.43, 0.68)],
	[24.0, Color(0.36, 0.40, 0.66)],
]
const NIGHT_NEW_MOON := Color(0.29, 0.32, 0.56)
const NIGHT_FULL_MOON := Color(0.44, 0.50, 0.76)


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR + "world.json"))
	data_res = float(data.get("res", 1.0))
	style_filter = CanvasItem.TEXTURE_FILTER_NEAREST if data.get("filter", "linear") == "nearest" \
		else CanvasItem.TEXTURE_FILTER_LINEAR
	tile = int(data["tile"])
	size = Vector2i(int(data["size"][0]), int(data["size"][1]))
	spots = data["spots"]
	season = Almanac.season()
	indoor = _rect(data.get("indoor", [0, 0, 0, 0]))
	water = _rect(data.get("water", [0, 0, 0, 0]))
	doorway = _rect(data.get("doorway", [0, 0, 0, 0]))
	outdoor = _rect(data.get("outdoor", [0, 0, size.x * tile, size.y * tile]))
	for k in data.get("areas", {}):
		areas[k] = _rect(data["areas"][k])
	for p in data.get("portals", []):
		portals.append([Vector2i(int(p[0][0]), int(p[0][1])), Vector2i(int(p[1][0]), int(p[1][1]))])
	for k in data.get("rooms", {}):
		rooms[k] = _rect(data["rooms"][k]["rect"])
	for t in data.get("trees", []):
		trees.append(Vector2(t[0], t[1]))

	add_child(_tint)

	var ground := _sprite(data["ground"])
	ground.z_index = -10
	add_child(ground)

	weather.setup(self)

	sort_root.y_sort_enabled = true
	add_child(sort_root)

	# a piece of the room redrawn with the companion in it (sofa, bed...), shown while it is at that spot
	for k in spots:
		if spots[k].has("scene"):
			var sc: Dictionary = spots[k]["scene"]
			var s := _sprite(sc["texture"])
			s.position = Vector2(float(sc["x"]), float(sc["y"]))
			s.z_index = -8
			s.visible = false
			add_child(s)
			scenes[k] = s

	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(tile, tile)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	var rows: Array = data["blocked"]
	for y in size.y:
		var row: String = rows[y]
		for x in size.x:
			if row[x] == "#":
				astar.set_point_solid(Vector2i(x, y), true)

	add_child(weather)

	lights_layer.layer = 1
	lights_layer.follow_viewport_enabled = true
	add_child(lights_layer)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for l in data["lights"]:
		var g := Sprite2D.new()
		g.texture = tex(l["texture"])
		g.position = Vector2(l["x"], l["y"])
		var r := float(l["radius"])
		g.scale = Vector2.ONE * (r * 2.0 / g.texture.get_width())
		g.material = add_mat
		g.modulate.a = 0.0
		lights_layer.add_child(g)
		_lights.append({"sprite": g, "when": l["when"]})
	_update_light()


## A picture from this world's folder, or the shared one.
func tex(name: String) -> Texture2D:
	if ResourceLoader.exists(DATA_DIR + name):
		return load(DATA_DIR + name)
	return load(DIR + name)


## Texture pixels per world pixel of a picture (the world's own pictures are drawn finer).
func res_of(name: String) -> float:
	return data_res if ResourceLoader.exists(DATA_DIR + name) else 1.0


## A sprite (top-left anchored) showing a picture at world size, however finely it is drawn.
func _sprite(name: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	s.centered = false
	var r := res_of(name)
	s.scale = Vector2.ONE / r
	s.texture_filter = style_filter if r != 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST
	return s


## Shows the scene of one spot ("" = none). Returns whether that spot has one.
func show_scene(spot: String) -> bool:
	for k in scenes:
		scenes[k].visible = k == spot
	scene_on = scenes.has(spot)
	return scene_on


## The companion picture and frame size for this world.
func companion_look() -> Dictionary:
	return data.get("companion", {"texture": "companion.png", "frame": 16, "speed": 1.0})


## Is this point out of the sky (inside the house).
func under_roof(p: Vector2) -> bool:
	return indoor.has_point(p)


func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


func world_size_px() -> Vector2:
	return Vector2(size * tile)


## Feet position (bottom centre) of a cell.
func feet(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * tile + tile * 0.5, (cell.y + 1) * tile)


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / tile), floori((pos.y - 1.0) / tile))


func is_walkable(pos: Vector2) -> bool:
	var c := cell_of(pos)
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


## Which map a point is on ("" when the world is a single map).
func area_at(pos: Vector2) -> String:
	for k in areas:
		if (areas[k] as Rect2).has_point(pos):
			return k
	return ""


## The map rectangle a point is on (the whole world when there is only one).
func area_rect(pos: Vector2) -> Rect2:
	var a := area_at(pos)
	return areas[a] if a != "" else Rect2(Vector2.ZERO, world_size_px())


func room_at(pos: Vector2) -> String:
	for k in rooms:
		if (rooms[k] as Rect2).has_point(pos):
			return k
	return ""


## Path between cells; across maps it goes through a portal (the step over it is not next door:
## the companion treats it as going through the door).
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var a := area_at(feet(from))
	var b := area_at(feet(to))
	if a != b:
		for p in portals:
			for i in 2:
				var here: Vector2i = p[i]
				var there: Vector2i = p[1 - i]
				if area_at(feet(here)) == a and area_at(feet(there)) == b:
					var out := _grid_path(from, here)
					if out.is_empty() and from != here:
						break
					out.append(there)
					out.append_array(_grid_path(there, to))
					return out
	return _grid_path(from, to)


func _grid_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to:
		return out
	if not astar.is_in_boundsv(from) or not astar.is_in_boundsv(to):
		return out
	var solid_from := astar.is_point_solid(from)
	if solid_from:
		astar.set_point_solid(from, false)
	var path := astar.get_id_path(from, to)
	if solid_from:
		astar.set_point_solid(from, true)
	for i in range(1, path.size()):
		out.append(path[i])
	return out


## 0 in daylight .. 1 in the darkest night (weather included).
func darkness() -> float:
	return _dark


## How much the moon is shining right now, 0..1 (night, clear sky, phase).
func moonlight() -> float:
	return Almanac.night_weight(Settings.hour_now()) * Almanac.moon_light() * (1.0 - weather.cloud)


func tint_at(h: float) -> Color:
	var c: Color = TINTS[0][1]
	for i in range(1, TINTS.size()):
		if h <= TINTS[i][0]:
			var a: Array = TINTS[i - 1]
			var b: Array = TINTS[i]
			var t: float = (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			c = (a[1] as Color).lerp(b[1], t)
			break
	var moon := Almanac.moon_light() * (1.0 - weather.cloud)
	return c.lerp(NIGHT_NEW_MOON.lerp(NIGHT_FULL_MOON, moon), Almanac.night_weight(h))


func _process(_delta: float) -> void:
	if nobody_home:
		lamp_on = false
		monitor_on = false
		tv_on = false
		if scene_on:
			show_scene("")
	var c := tint_at(Settings.hour_now()) * weather.tint()
	_tint.color = c
	_dark = clampf((1.0 - c.v) / 0.6, 0.0, 1.0)
	_update_light()


func _update_light() -> void:
	for l in _lights:
		var target := 0.0
		var s: Sprite2D = l["sprite"]
		match l["when"]:
			"evening":
				target = _dark * 0.7 if lamp_on else 0.0
			"outdoor":
				# garden lamps come on at dusk (and on dark rainy days), off after sunrise
				target = clampf((_dark - 0.22) / 0.35, 0.0, 1.0) * 0.8
		s.modulate.a = move_toward(s.modulate.a, target, 0.05)
