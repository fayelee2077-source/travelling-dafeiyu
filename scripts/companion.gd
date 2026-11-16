class_name Companion
extends Node2D
## The pixel companion: walks the grid to an activity spot, then plays that activity
## (pose, held item, speech-bubble icon). Its position is the feet point, used for y-sorting.

const DIR := "res://assets/generated/"
const FACES := {"left": 0, "down": 1, "up": 2, "right": 3}
const WALK_CYCLE := [1, 0, 2, 0]
const STROLL_SPEED := 32.0     # idle life
const TASK_SPEED := 60.0       # called to work or chat
const URGENT_SPEED := 80.0     # waiting for the user

var world: World
var cell := Vector2i.ZERO
var face := "down"
var at_spot := ""                 # spot we are standing/sitting in, "" while walking

var _act: Dictionary = {}         # {spot, anim, bubble, urgent}
var _goal := ""
var _path: Array[Vector2i] = []
var _stepping := false
var _step_to := Vector2.ZERO
var _replan := false
var _walk_t := 0.0
var _t := 0.0

var _body := Sprite2D.new()
var _item := Sprite2D.new()
var _bubble := Node2D.new()
var _bubble_bg := Sprite2D.new()
var _glyph := Sprite2D.new()
var _rod := Line2D.new()
var _line := Line2D.new()
var _bobber := Sprite2D.new()
var _fx := Node2D.new()
var _drop_t := 0.0

var _tex: Dictionary = {}
var fs := 16                      # frame size in pixels
var k := 1.0                      # fs / 16, scales item and effect positions
var _speed_k := 1.0
var _sit_frame := false           # the sheet has a "sitting, facing us" frame (row 3, column 2)
var _tr := 1.0                    # sheet texture pixels per world pixel (finer in a style pack)
var _off := Vector2.ZERO          # body offset in world pixels
var _walk_n := 0                  # real walk frames (rows 4..), 0 = the old 3-row bob
var _idle_n := 0                  # idle loop frames after the walk rows (breathing, tail), 0 = none
const IDLE_FPS := 3.3
var _poses: Dictionary = {}       # anim -> sheet row of a drawn pose (sit, fish, crouch, water...)
var _anchors: Dictionary = {}     # anim -> [x, y] world px from the feet (rod tip, spout), for the left-facing pose
# clothes she chose (her DSH tool): "maid" is the world's own sheet, others are companion.outfits in world.json
var outfit_id := "maid"
var _wanted := ""                 # chosen, put on at the wardrobe (or after a while, if she does not get there)
var _wanted_t := 0.0
const WEAR_ANYWAY := 150.0

# going through a door to the other map: fade out, jump, fade in
const WARP_TIME := 0.8
var _warp_t := -1.0
var _warp_to := Vector2i.ZERO


func setup(w: World, start: Vector2i) -> void:
	world = w
	var look := world.companion_look()
	fs = int(look.get("frame", 16))
	k = fs / 16.0
	_speed_k = float(look.get("speed", 1.0))
	_sit_frame = bool(look.get("sit_frame", false))
	_walk_n = int(look.get("walk", 0))
	_idle_n = int(look.get("idle", 0))
	_poses = look.get("poses", {})
	_anchors = look.get("anchors", {})
	cell = start
	position = world.feet(cell)


func _ready() -> void:
	for n in ["phone", "phone_lit", "watering_can", "heart", "bubble"]:
		_tex[n] = load(DIR + n + ".png")
	for n in ["dots1", "dots2", "dots3", "alert", "think", "note", "sleep", "search", "edit", "test", "command", "tool", "error",
			"cook", "bath", "dress"]:
		_tex["g_" + n] = load(DIR + "glyph_" + n + ".png")

	var sheet: String = world.companion_look().get("texture", "companion.png")
	_body.texture = world.tex(sheet)
	_tr = float(world.companion_look().get("res", world.res_of(sheet)))
	_body.region_enabled = true
	_body.centered = false
	_body.scale = Vector2.ONE / _tr
	_body.texture_filter = world.style_filter if _tr != 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)

	_item.centered = false
	_item.visible = false
	add_child(_item)

	for l in [_rod, _line]:
		l.width = 1.0
		l.antialiased = false
		l.visible = false
		add_child(l)
	_rod.default_color = Color8(118, 59, 54)
	_line.default_color = Color(1, 1, 1, 0.7)
	var bob := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	bob.set_pixel(0, 0, Color8(230, 70, 70)); bob.set_pixel(1, 0, Color8(230, 70, 70))
	bob.set_pixel(0, 1, Color.WHITE); bob.set_pixel(1, 1, Color.WHITE)
	_bobber.texture = ImageTexture.create_from_image(bob)
	_bobber.centered = false
	_bobber.visible = false
	add_child(_bobber)

	_bubble.z_index = 20
	_bubble_bg.texture = _tex["bubble"]
	_bubble_bg.centered = false
	_bubble.add_child(_bubble_bg)
	_glyph.centered = false
	_glyph.position = Vector2(5, 3)
	_bubble.add_child(_glyph)
	_bubble.visible = false
	add_child(_bubble)

	_fx.z_index = 21
	add_child(_fx)
	_apply_frame(0)


## Sets what the companion should be doing. act: {spot, anim, bubble, urgent}
## spot "" means "right here" (stepping off furniture first).
func perform(act: Dictionary) -> void:
	if act.hash() == _act.hash():
		return
	_act = act
	var goal: String = act.get("spot", "")
	if goal == "":
		# stay here; get off the furniture first unless it is a seat facing us and sitting is fine
		goal = at_spot
		var seat := _spot(at_spot)
		var seated_facing_us: bool = seat.get("pose", "") == "sit" and seat.get("face", "") == "down"
		if _furniture_via(cell) != null and not (act.get("sit_ok", false) and seated_facing_us):
			goal = ""
	_goal = goal
	if is_busy_walking() or goal != at_spot or _furniture_via(cell) != null and goal == "":
		if _stepping or _warp_t >= 0.0:
			_replan = true
		else:
			_plan()
	elif act.get("anim", "") in ["cheer", "phone"]:
		face = "down"
	_reset_anim()


func is_busy_walking() -> bool:
	return _stepping or _warp_t >= 0.0 or not _path.is_empty()


## 0..1..0 while going through a door to the other map (1 at the moment of the jump); the screen fades with it.
func warp_fade() -> float:
	if _warp_t < 0.0:
		return 0.0
	return 1.0 - absf(_warp_t / (WARP_TIME * 0.5) - 1.0)


func pop_heart() -> void:
	var h := Sprite2D.new()
	h.texture = _tex["heart"]
	h.position = _hand_pos() + Vector2(0, -6)
	_fx.add_child(h)
	var tw := create_tween()
	tw.tween_property(h, "position", h.position + Vector2(0, -14), 1.2)
	tw.parallel().tween_property(h, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.tween_callback(h.queue_free)


func _spot(name: String) -> Dictionary:
	return world.spots.get(name, {})


func _v(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## The free cell next to a piece of furniture the companion is on, or null.
func _furniture_via(c: Vector2i):
	for s in world.spots.values():
		if s.has("via") and _v(s["cell"]) == c:
			return _v(s["via"])
	return null


func _plan() -> void:
	_replan = false
	_path.clear()
	var start := cell
	var via = _furniture_via(cell)
	if via != null and not (_goal != "" and _v(_spot(_goal)["cell"]) == cell):
		start = via
		_path.append(start)
	at_spot = ""
	var s := _spot(_goal)
	if s.is_empty():
		_goal = ""
		if _path.is_empty():
			_arrive()
		return
	if _v(s["cell"]) == cell:
		_path.clear()
		_arrive()
		return
	var dest := _v(s["via"]) if s.has("via") else _v(s["cell"])
	var route := world.find_path(start, dest)
	if route.is_empty() and start != dest:
		Settings.log_line("companion: no path %s -> %s, jumping" % [start, dest])
		cell = dest
		position = world.feet(cell)
		_path.clear()
	_path.append_array(route)
	if s.has("via"):
		_path.append(_v(s["cell"]))
	if _path.is_empty():
		_arrive()


func _arrive() -> void:
	at_spot = _goal
	if _act.get("anim", "") in ["cheer", "phone"]:
		face = "down"
	elif at_spot != "":
		face = _spot(at_spot).get("face", face)
	_reset_anim()


func _reset_anim() -> void:
	_t = 0.0
	_drop_t = 0.0
	_changed_clothes = false


var _changed_clothes := false


## The clothes she chose: put on now (starting up, nobody in sight, no wardrobe), else at the wardrobe.
func wear(id: String, now := false) -> void:
	if not world.companion_look().get("outfits", {}).has(id):
		id = "maid"
	if id == outfit_id:
		_wanted = ""
		return
	if now or not visible or not world.spots.has("dress"):
		_put_on(id)
	else:
		_wanted = id
		_wanted_t = 0.0


func _put_on(id: String) -> void:
	var look := world.companion_look()
	var o: Dictionary = look.get("outfits", {}).get(id, look)
	_body.texture = world.tex(o.get("texture", "companion.png"))
	_poses = o.get("poses", {})
	_anchors = o.get("anchors", {})
	outfit_id = id
	_wanted = ""
	Settings.log_line("companion: wearing %s" % id)


## Height on screen in world pixels (the size setting scales the whole companion; bubbles keep their size).
func height() -> float:
	return fs * scale.y


func _process(delta: float) -> void:
	_t += delta
	if _wanted != "":
		_wanted_t += delta
		if _wanted_t > WEAR_ANYWAY:
			_put_on(_wanted)
	var b := Settings.body_scale
	scale = Vector2(b, b)
	_bubble.scale = Vector2.ONE / b
	_rod.width = 1.0 / b
	_line.width = 1.0 / b
	if _warp_t >= 0.0:
		var half := WARP_TIME * 0.5
		var was := _warp_t
		_warp_t += delta
		_apply_frame(0)
		_set_offset(Vector2.ZERO)
		if was < half and _warp_t >= half:
			cell = _warp_to
			position = world.feet(cell)
			if not _path.is_empty():
				var d: Vector2i = _path[0] - cell
				face = "left" if d.x < 0 else "right" if d.x > 0 else "up" if d.y < 0 else "down"
		if _warp_t >= WARP_TIME:
			_warp_t = -1.0
			if _replan:
				_plan()
			if _path.is_empty():
				_arrive()
	elif _stepping:
		var speed := (URGENT_SPEED if _act.get("urgent", false) else STROLL_SPEED if _act.get("stroll", false) else TASK_SPEED) * _speed_k
		position = position.move_toward(_step_to, speed * delta)
		_walk_t += delta * speed / (16.0 * k) * 2.0
		_apply_frame(4 + int(_walk_t * _walk_n / 4.0) % _walk_n if _walk_n > 0 else WALK_CYCLE[int(_walk_t) % 4])
		_set_offset(Vector2.ZERO)
		_show_extras(false)
		if position == _step_to:
			_stepping = false
			cell = world.cell_of(position)
			if _replan:
				_plan()
			if _path.is_empty():
				_arrive()
	elif not _path.is_empty():
		var next: Vector2i = _path.pop_front()
		var d := next - cell
		if absi(d.x) + absi(d.y) > 1:
			# not next door: through the front door to the other map
			_warp_to = next
			_warp_t = 0.0
			_show_extras(false)
			return
		if d.x < 0: face = "left"
		elif d.x > 0: face = "right"
		elif d.y < 0: face = "up"
		elif d.y > 0: face = "down"
		_step_to = world.feet(next)
		_stepping = true
	else:
		_animate(delta)


func _set_offset(o: Vector2) -> void:
	_off = Vector2(-fs / 2.0, -fs) + o
	_body.offset = _off * _tr
	_body.position = Vector2.ZERO


func _apply_frame(row: int, col := -1) -> void:
	if col < 0:
		col = FACES.get(face, 1)
	var f := fs * _tr
	_body.region_rect = Rect2(col * f, row * f, f, f)


## Activities that have a sitting pose only when on a seat (else she would sit on air).
const SEATED_POSES := {"phone": "phone", "type": "laptop", "think": "laptop", "error": "laptop"}


## The drawn pose for an activity here, or "".
func _pose_for(anim: String, s: Dictionary) -> String:
	if SEATED_POSES.has(anim):
		var seated: bool = s.get("pose", "") == "sit" and cell == _v(s["cell"]) if not s.is_empty() else false
		var p: String = SEATED_POSES[anim]
		return p if seated and _poses.has(p) else ""
	return anim if _poses.has(anim) else ""


## A point on a drawn pose (rod tip, spout); the pose faces left in the sheet and is mirrored otherwise.
func _anchor(anim: String, o: Vector2) -> Vector2:
	var a: Array = _anchors[anim]
	return Vector2(float(a[0]) * (1.0 if face == "left" else -1.0), float(a[1])) + o


func _hand_pos() -> Vector2:
	return _off + Vector2(fs * 0.5, fs * 0.62)


func _show_extras(on: bool) -> void:
	if not on:
		_item.visible = false
		_rod.visible = false
		_line.visible = false
		_bobber.visible = false
		var urgent_bubble: bool = _act.get("urgent", false) and _act.get("bubble", "") != ""
		_bubble.visible = urgent_bubble
		if urgent_bubble:
			_place_bubble(_act.get("bubble", ""), Vector2.ZERO)
		world.monitor_on = false
		world.tv_on = false
		world.lamp_on = true
		_body.visible = true
		world.show_scene("")


func _animate(delta: float) -> void:
	var anim: String = _act.get("anim", "stand")
	var s := _spot(at_spot)
	var base := Vector2.ZERO
	if not s.is_empty() and cell == _v(s["cell"]) and s.has("offset"):
		base = Vector2(float(s["offset"][0]), float(s["offset"][1]))
	var o := base
	var row := 0
	var col := -1
	_item.visible = false
	_rod.visible = false
	_line.visible = false
	_bobber.visible = false
	world.monitor_on = false
	world.tv_on = false
	world.lamp_on = true
	_body.visible = true

	match anim:
		"type":
			world.monitor_on = true
			o.y += -1.0 if int(_t * 5.0) % 2 == 0 else 0.0
		"think":
			world.monitor_on = true
		"error":
			world.monitor_on = true
			if fmod(_t, 2.0) < 0.6:
				o.x += 1.0 if int(_t * 16.0) % 2 == 0 else -1.0
		"sleep":
			col = 1
			row = 3
			world.lamp_on = false
			o.y += 0.0 if fmod(_t, 3.0) < 1.5 else 1.0
		"phone":
			_item.texture = _tex["phone_lit"] if _act.get("bubble", "") == "dots_fast" else _tex["phone"]
			_item.visible = true
			_item.position = Vector2(-2, -7 * k) + o
			if face != "down":
				_item.position.x += 4 * k if face == "right" else -4 * k
		"water":
			var drawn := _anchors.has("water")
			_item.texture = _tex["watering_can"]
			_item.visible = not drawn
			_item.position = Vector2(3 * k, -9 * k) + o
			_drop_t -= delta
			if _drop_t <= 0.0:
				_drop_t = 0.25
				_spawn_drop(_anchor("water", o) if drawn else Vector2(11 * k, -8 * k) + o)
		"fish":
			_rod.visible = not _anchors.has("fish")
			_line.visible = true
			_bobber.visible = true
			var bobbing := 1.0 if fmod(_t, 2.4) < 1.2 else 0.0
			var hand := Vector2(4, -7) * k + o
			var tip := hand + Vector2(7, -7) * k
			var bob := Vector2(28 * k, -4 * k + bobbing)
			if face == "down":
				# casting forward into water in front of the companion
				hand = Vector2(3, -6) * k + o
				tip = hand + Vector2(4, 4) * k
				bob = Vector2(5 * k, 13 * k + bobbing)
			if _anchors.has("fish"):
				tip = _anchor("fish", o)
			_rod.points = PackedVector2Array([hand, tip])
			_line.points = PackedVector2Array([tip, bob + Vector2(1, 0)])
			_bobber.position = bob
		"crouch":
			o.y += 1.0 if fmod(_t, 1.4) < 0.7 else 2.0
		"cheer":
			var c := fmod(_t, 1.6)
			if c < 0.8:
				o.y -= absf(sin(c / 0.4 * PI)) * 4.0
		"wait":
			var w := fmod(_t, 2.2)
			if w < 0.3:
				o.y -= absf(sin(w / 0.3 * PI)) * 3.0
		"cook":
			# stirring the pot
			o.x += 1.0 if int(_t * 3.0) % 2 == 0 else 0.0
		"eat":
			o.y += -1.0 if fmod(_t, 0.9) < 0.3 else 0.0
		"bath":
			o.y += 0.0 if fmod(_t, 3.0) < 1.5 else 1.0
		"toilet":
			# inside the cubicle with the door shut: only the bubble shows
			_body.visible = false
		"dress":
			# rummage in the wardrobe, then turn round in the new clothes
			if fmod(_t, 6.0) > 3.5:
				if not _changed_clothes:
					_changed_clothes = true
					if _wanted != "":
						_put_on(_wanted)
				col = FACES["down"]
				if fmod(_t, 6.0) < 4.1:
					o.y -= 2.0
		"tv":
			world.tv_on = true
		"swing":
			o.y += sin(_t * 2.6) * 3.0
			if absf(sin(_t * 2.6)) > 0.9:
				o.y -= 1.0
		_:
			pass
	if _sit_frame and row == 0 and col < 0 and face == "down" and s.get("pose", "") == "sit" and cell == _v(s["cell"]):
		row = 3
		col = 2
	if s.get("hidden", false) and cell == _v(s["cell"]):
		# gone in through the door (the inside is not drawn yet)
		_body.visible = false
	var pose := _pose_for(anim, s)
	if pose != "" and (row == 0 or anim == "sleep"):
		# a drawn pose replaces the small code-made bobs and held items
		row = int(_poses[pose])
		if anim == "crouch":
			o = base
		if pose == "phone":
			_item.visible = false
	elif row == 0 and _idle_n > 0:
		row = 4 + _walk_n + int(_t * IDLE_FPS) % _idle_n
	# furniture redrawn with her on it: show that picture instead of the sprite (drawn in the maid dress; in
	# other clothes only the bed, where she sleeps without her coat)
	var on_spot: bool = cell == _v(s["cell"]) if not s.is_empty() else false
	var scene_ok := outfit_id == "maid" or anim == "sleep"
	if world.show_scene(at_spot if on_spot and scene_ok else ""):
		_body.visible = false
		_item.visible = false
		_rod.visible = false
		_line.visible = false
		_bobber.visible = false

	_set_offset(o)
	_apply_frame(row, col)

	var b: String = _act.get("bubble", "")
	_bubble.visible = b != ""
	if b != "":
		_place_bubble(b, base)


func _place_bubble(b: String, base: Vector2) -> void:
	var g := b
	match b:
		"dots":
			g = ["dots1", "dots2", "dots3"][int(_t / 0.45) % 3]
		"dots_fast":
			g = ["dots1", "dots2", "dots3"][int(_t / 0.2) % 3]
	if _tex.has("g_" + g):
		_glyph.texture = _tex["g_" + g]
	var bob := 0.0
	if b == "alert":
		bob = -1.0 if int(_t * 4.0) % 2 == 0 else 0.0
	elif b == "sleep":
		bob = -1.0 if fmod(_t, 2.0) < 1.0 else 0.0
	var side := 6.0 if b == "sleep" else 0.0
	_bubble.position = base + Vector2(-8.5 + side, -17.0 + bob) / scale.y + Vector2(0, -fs)
	_bubble.position = _bubble.position.round()


func _spawn_drop(at: Vector2) -> void:
	var d := Sprite2D.new()
	if not _tex.has("drop"):
		var img := Image.create(1, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color8(120, 190, 240))
		_tex["drop"] = ImageTexture.create_from_image(img)
	d.texture = _tex["drop"]
	d.centered = false
	d.position = at
	_fx.add_child(d)
	var tw := create_tween()
	tw.tween_property(d, "position", at + Vector2(1, 5), 0.4)
	tw.tween_callback(d.queue_free)
