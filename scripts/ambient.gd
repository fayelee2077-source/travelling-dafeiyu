class_name Ambient
extends Node2D
## Small life around the house, by season, time and weather (look only, nothing to play):
## birds that hop about and fly off when the companion comes near, butterflies (spring, summer),
## fireflies (summer nights), falling leaves (autumn) or petals (spring), and the pond: sun
## glints, a fish jumping now and then, and the moon and stars reflected at night.

signal fish_jumped

const BIRD_FRAMES := {"stand": 0, "peck": 1, "up": 2, "down": 3}
const LEAF_COLORS := {
	"autumn": [Color8(227, 134, 40), Color8(200, 66, 48), Color8(242, 190, 70), Color8(170, 100, 52)],
	"spring": [Color8(250, 196, 214), Color8(236, 150, 180), Color8(255, 236, 242)],
}
const BUTTERFLY_COLORS := [Color8(250, 246, 236), Color8(242, 200, 92), Color8(240, 160, 190)]

var world: World
var companion: Companion

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _glow := Node2D.new()             # drawn additively on the light layer
var _bird_tex: Texture2D
var _birds: Array = []                # {sprite, state, t, vel, next}
var _birds_back_at := 8.0
var _butterflies: Array = []          # {pos, vel, home, color, t}
var _fireflies: Array = []            # {pos, home, phase, rate}
var _leaves: Array = []               # {pos, land_y, sway, phase, color, rest}
var _leaf_t := 0.0
var _glints: Array = []               # {pos, t}
var _glint_t := 0.0
var _ripples: Array = []              # {pos, t}
var _fish := {}                       # {from, to, t}
var _fish_at := 20.0
var _stars: Array = []                # Vector2 in the pond


func setup(w: World, c: Companion) -> void:
	world = w
	companion = c


func _ready() -> void:
	_rng.randomize()
	z_index = 14
	_bird_tex = load(World.DIR + "birds.png")
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add_mat
	_glow.draw.connect(_draw_glow)
	world.lights_layer.add_child(_glow)

	var w := world.water
	for i in 7:
		_stars.append(Vector2(_rng.randf_range(w.position.x + 2, w.end.x - 2), _rng.randf_range(w.position.y + 2, w.end.y - 2)).round())
	if world.season in ["spring", "summer"]:
		for i in 3:
			var home := _flower_home(i)
			_butterflies.append({"pos": home + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-10, 4)),
				"vel": Vector2.ZERO, "home": home, "color": BUTTERFLY_COLORS[i % 3], "t": _rng.randf() * 10.0})
			if _day() < 0.7 or not _fair():
				_butterflies[-1]["pos"].y = -10.0
	if world.season == "summer":
		for i in 10:
			var home := _firefly_home()
			_fireflies.append({"pos": home, "home": home, "phase": _rng.randf() * TAU, "rate": _rng.randf_range(1.2, 2.4)})


func _flower_home(i: int) -> Vector2:
	var homes: Array = world.data.get("flower_homes", [[56, 200], [310, 64], [130, 214]])
	var h: Array = homes[i % homes.size()]
	return Vector2(h[0], h[1])


func _firefly_home() -> Vector2:
	var w := world.water
	if _rng.randf() < 0.6:
		return Vector2(_rng.randf_range(w.position.x - 20, w.end.x + 10), _rng.randf_range(w.position.y - 16, w.end.y + 12))
	var a: Array = world.data.get("firefly_area", [260, 40, 160, 80])
	return Vector2(_rng.randf_range(a[0], a[0] + a[2]), _rng.randf_range(a[1], a[1] + a[3]))


func birds_in_yard() -> int:
	return _birds.filter(func(b): return b["state"] == "ground").size()


func _day() -> float:
	return 1.0 - Almanac.night_weight(Settings.hour_now())


func _fair() -> bool:
	return world.weather.rain < 0.2 and world.weather.snow < 0.4


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	_t += delta
	_update_birds(delta)
	_update_butterflies(delta)
	_update_leaves(delta)
	_update_pond(delta)
	for f in _fireflies:
		f["pos"] = f["home"] + Vector2(sin(_t * 0.5 + f["phase"]) * 10.0, cos(_t * 0.37 + f["phase"] * 1.7) * 6.0)
	queue_redraw()
	_glow.queue_redraw()


func _update_birds(delta: float) -> void:
	var welcome := _day() > 0.6 and _fair()
	if _birds.is_empty() and welcome and _t > _birds_back_at:
		_birds_arrive()
	for b in _birds:
		var s: Sprite2D = b["sprite"]
		b["t"] += delta
		match b["state"]:
			"in":
				s.position = s.position.move_toward(b["land"], 70.0 * delta)
				s.frame = BIRD_FRAMES["up"] if int(_t * 10.0) % 2 == 0 else BIRD_FRAMES["down"]
				if s.position == b["land"]:
					b["state"] = "ground"
					b["next"] = _rng.randf_range(0.5, 1.5)
					s.z_index = 0
			"ground":
				var near := s.position.distance_to(companion.position) < 30.0
				if near or not welcome:
					_bird_flee(b)
					continue
				if b["t"] > b["next"]:
					b["t"] = 0.0
					b["next"] = _rng.randf_range(0.6, 2.2)
					var roll := _rng.randf()
					if roll < 0.45:
						s.frame = BIRD_FRAMES["peck"]
					elif roll < 0.85:
						var to := s.position + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-3, 3)).round()
						if world.is_walkable(to) and not world.under_roof(to):
							s.flip_h = to.x < s.position.x
							var tw := create_tween()
							tw.tween_property(s, "position", to, 0.15)
							s.frame = BIRD_FRAMES["stand"]
					else:
						s.frame = BIRD_FRAMES["stand"]
						s.flip_h = not s.flip_h
				elif b["t"] > 0.3 and s.frame == BIRD_FRAMES["peck"]:
					s.frame = BIRD_FRAMES["stand"]
			"out":
				s.position += b["vel"] * delta
				s.frame = BIRD_FRAMES["up"] if int(_t * 12.0) % 2 == 0 else BIRD_FRAMES["down"]
	for b in _birds.filter(func(b): return b["state"] == "out" and b["t"] > 4.0):
		b["sprite"].queue_free()
		_birds.erase(b)
		if _birds.is_empty():
			_birds_back_at = _t + _rng.randf_range(25.0, 70.0)


func _birds_arrive() -> void:
	# land somewhere open and well away from the companion
	var o := world.outdoor
	var land := Vector2.ZERO
	for i in 20:
		var p := Vector2(_rng.randf_range(o.position.x + 40, o.end.x - 40), _rng.randf_range(o.position.y + o.size.y * 0.45, o.end.y - 30)).round()
		if world.is_walkable(p) and not world.under_roof(p) and not world.water.grow(6).has_point(p) \
				and p.distance_to(companion.position) > 70.0:
			land = p
			break
	if land == Vector2.ZERO:
		_birds_back_at = _t + 15.0
		return
	for i in _rng.randi_range(2, 3):
		var s := Sprite2D.new()
		s.texture = _bird_tex
		s.hframes = 4
		s.centered = false
		s.offset = Vector2(-4, -7)
		s.z_index = 16
		var spot := land + Vector2(i * 7 - 7, _rng.randi_range(-3, 3))
		if not world.is_walkable(spot):
			spot = land
		s.position = spot + Vector2(_rng.randf_range(-80, 80), -140).round()
		s.flip_h = s.position.x > spot.x
		world.sort_root.add_child(s)
		_birds.append({"sprite": s, "state": "in", "t": 0.0, "land": spot, "next": 1.0, "vel": Vector2.ZERO})


func _bird_flee(b: Dictionary) -> void:
	var s: Sprite2D = b["sprite"]
	var away := 1.0 if s.position.x >= companion.position.x else -1.0
	b["state"] = "out"
	b["t"] = 0.0
	b["vel"] = Vector2(away * _rng.randf_range(50, 80), -_rng.randf_range(55, 80))
	s.flip_h = away < 0
	s.z_index = 16


func _update_butterflies(delta: float) -> void:
	var out := _day() < 0.7 or not _fair()
	for f in _butterflies:
		f["t"] += delta
		var pull: Vector2 = (f["home"] - f["pos"]) * 0.6
		if out:
			pull += Vector2(0, -60)            # leave the screen when it gets dark or rainy
		f["vel"] = (f["vel"] + (Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 90.0 + pull) * delta).limit_length(16.0)
		f["pos"] += f["vel"] * delta
		if f["pos"].y < -10.0:
			f["pos"].y = -10.0


func _update_leaves(delta: float) -> void:
	var colors: Array = LEAF_COLORS.get(world.season, [])
	if not colors.is_empty() and _fair() and not world.trees.is_empty():
		_leaf_t -= delta
		if _leaf_t <= 0.0:
			_leaf_t = _rng.randf_range(0.5, 1.6) if world.season == "autumn" else _rng.randf_range(1.2, 3.0)
			var tree: Vector2 = world.trees[_rng.randi() % world.trees.size()]
			var start := tree + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-4, 4))
			_leaves.append({"pos": start, "land_y": start.y + _rng.randf_range(18, 34), "sway": _rng.randf_range(4, 9),
				"phase": _rng.randf() * TAU, "x0": start.x, "color": colors[_rng.randi() % colors.size()], "rest": 0.0})
	for l in _leaves:
		if l["pos"].y < l["land_y"]:
			l["pos"].y += 9.0 * delta
			l["x0"] += 4.0 * delta                 # a light breeze
			l["pos"].x = l["x0"] + sin(_t * 1.8 + l["phase"]) * l["sway"]
		else:
			l["rest"] += delta
	_leaves = _leaves.filter(func(l): return l["rest"] < 3.0)


func _update_pond(delta: float) -> void:
	var w := world.water
	var sunny := _day() > 0.6 and world.weather.cloud < 0.6
	_glint_t -= delta
	if sunny and _glint_t <= 0.0:
		_glint_t = _rng.randf_range(0.25, 0.6)
		_glints.append({"pos": Vector2(_rng.randf_range(w.position.x + 2, w.end.x - 2), _rng.randf_range(w.position.y + 2, w.end.y - 2)).round(), "t": 0.0})
	for g in _glints:
		g["t"] += delta
	_glints = _glints.filter(func(g): return g["t"] < 0.7)

	if _fish.is_empty() and _t > _fish_at and _day() > 0.3:
		var from := Vector2(_rng.randf_range(w.position.x + 8, w.end.x - 20), _rng.randf_range(w.position.y + 6, w.end.y - 4)).round()
		_fish = {"from": from, "to": from + Vector2(12 * (1 if _rng.randf() < 0.5 else -1), 0), "t": 0.0}
		if not w.has_point(_fish["to"]):
			_fish["to"] = from - (_fish["to"] - from)
		_ripples.append({"pos": from, "t": 0.0})
		fish_jumped.emit()
	if not _fish.is_empty():
		_fish["t"] += delta
		if _fish["t"] >= 0.7:
			_ripples.append({"pos": _fish["to"], "t": 0.0})
			_fish = {}
			_fish_at = _t + _rng.randf_range(25.0, 70.0)
	for r in _ripples:
		r["t"] += delta
	_ripples = _ripples.filter(func(r): return r["t"] < 1.2)


# ------------------------------------------------------------------ drawing

func _px(p: Vector2, c: Color, node: CanvasItem = self) -> void:
	node.draw_rect(Rect2(p.round(), Vector2.ONE), c)


func _ring(at: Vector2, r: float, c: Color, node: CanvasItem = self) -> void:
	var n := int(4 + r * 4)
	for i in n:
		var a := TAU * i / n
		_px(at + Vector2(cos(a) * r, sin(a) * r * 0.55), c, node)


func _draw() -> void:
	for r in _ripples:
		_ring(r["pos"], 1.0 + r["t"] * 5.0, Color(0.88, 0.95, 1.0, 0.7 * (1.0 - r["t"] / 1.2)))
	for g in _glints:
		var k: float = 1.0 - absf(g["t"] - 0.35) / 0.35
		_px(g["pos"], Color(1, 1, 1, k))
		if k > 0.6:
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_px(g["pos"] + d, Color(1, 1, 1, (k - 0.6) * 1.5))
	if not _fish.is_empty():
		var t: float = _fish["t"] / 0.7
		var p: Vector2 = _fish["from"].lerp(_fish["to"], t) + Vector2(0, -sin(t * PI) * 7.0)
		var dir := signf(_fish["to"].x - _fish["from"].x)
		_px(p, Color8(196, 210, 226))
		_px(p + Vector2(-dir, 0), Color8(150, 168, 196))
		_px(p + Vector2(dir, 0), Color8(226, 234, 244))
	for l in _leaves:
		var c: Color = l["color"]
		c.a = 1.0 - maxf(l["rest"] - 2.0, 0.0)
		if world.under_roof(l["pos"]):
			continue
		_px(l["pos"], c)
		if l["rest"] > 0.0 or int(_t * 4.0 + l["phase"]) % 2 == 0:
			_px(l["pos"] + Vector2(1, 0), c.darkened(0.15))
	for f in _butterflies:
		var p: Vector2 = f["pos"].round()
		if world.under_roof(p):
			continue
		var c: Color = f["color"]
		_px(p, Color8(63, 38, 49))
		if int(f["t"] * 8.0) % 2 == 0:
			_px(p + Vector2(-1, -1), c); _px(p + Vector2(1, -1), c)
			_px(p + Vector2(-1, 0), c); _px(p + Vector2(1, 0), c)
		else:
			_px(p + Vector2(0, -1), c)


func _draw_glow() -> void:
	var night := Almanac.night_weight(Settings.hour_now())
	var clear := 1.0 - world.weather.cloud
	if night > 0.0 and clear > 0.0:
		for i in _stars.size():
			var tw := 0.5 + 0.5 * sin(_t * (1.3 + i * 0.37) + i)
			_px(_stars[i], Color(0.7, 0.8, 1.0, 0.35 * tw * night * clear), _glow)
		_draw_moon(night * clear)
	if world.season == "summer" and night > 0.3 and world.weather.rain < 0.2:
		for f in _fireflies:
			var a := maxf(sin(_t * f["rate"] + f["phase"]), 0.0) * night
			if a <= 0.01:
				continue
			var p: Vector2 = f["pos"]
			_px(p, Color(0.9, 1.0, 0.5, a), _glow)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_px(p + d, Color(0.65, 0.95, 0.3, a * 0.55), _glow)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(2, 0), Vector2(-2, 0)]:
				_px(p + d, Color(0.5, 0.8, 0.25, a * 0.2), _glow)


## The moon's reflection in the pond, in its real phase, shimmering on the water.
func _draw_moon(k: float) -> void:
	var phase := Almanac.moon_phase()
	var light := Almanac.moon_light()
	if light < 0.03:
		return
	var w := world.water
	var c := Vector2(w.end.x - 18, w.position.y + 12)
	var r := 3.4
	for dy in range(-3, 4):
		var half := sqrt(maxf(r * r - dy * dy, 0.0))
		var xt := half * cos(TAU * phase)
		var shimmer := roundf(sin(_t * 2.2 + dy * 1.3) * 0.6)
		for dx in range(-3, 4):
			if absf(dx) > half:
				continue
			var lit := dx > xt if phase < 0.5 else dx < -xt
			if lit:
				_px(c + Vector2(dx + shimmer, dy), Color(0.85, 0.9, 1.0, 0.75 * k), _glow)
	for i in 3:
		var y := c.y + 5 + i * 2
		var n := 5 - i
		var x0 := c.x - n / 2.0 + sin(_t * 1.7 + i) * 1.5
		for x in n:
			_px(Vector2(x0 + x, y), Color(0.7, 0.8, 1.0, 0.25 * k * light), _glow)
