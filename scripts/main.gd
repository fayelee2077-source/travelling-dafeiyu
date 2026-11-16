extends Node2D
## P1 frame app: pixel world + companion, driven by the DSH plugin's state stream.
## Chats from other channels only show as actions (phone, typing bubble), never text.

const LONG_PRESS := 1.5
const DOUBLE_TAP := 0.35
const ZOOM_SPEED := 3.0
# states that pull the camera in close to the companion
const CLOSE_UP_STATES := ["chatting", "waiting"]

const WORK_ICONS := {"searching": "search", "editing": "edit", "testing": "test", "commanding": "command", "tool": "tool"}
const CHAT_BUBBLES := {"reading": "dots", "replying": "dots_fast", "busy": "tool"}
# spot, anim, weight
const IDLE_LIFE := [
	["window", "stand", 2], ["bookshelf", "stand", 2], ["flowers", "water", 3], ["garden", "crouch", 2],
	["pond", "fish", 3], ["bench", "sit", 2], ["sofa", "sit", 2],
]
# rain: stay in (watch the rain from the window); snow: in, or out at the door to look at it
const IDLE_RAIN := [["window", "stand", 3], ["bookshelf", "stand", 2], ["sofa", "sit", 3]]
const IDLE_SNOW := [["window", "stand", 3], ["bookshelf", "stand", 2], ["sofa", "sit", 3], ["front", "stand", 2]]

var world := World.new()
var companion := Companion.new()
var link := FrameLink.new()
var camera := Camera2D.new()

var _ui := CanvasLayer.new()
var _dot := TextureRect.new()
var _toast := Label.new()
var _toast_t := 0.0
var _debug := Label.new()
var _panel: SettingsPanel

var _state := {"state": "idle", "activity": null}
var _forced := false
var _frozen := false
var _idle_spot := ""
var _idle_until := 0.0
var _clock := 0.0
var _press_at := -1.0
var _press_pos := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _near := false               # the user's choice (double tap); chat / waiting also pull in
var _zoom := 1.0
var _last_tap := -10.0
var _last_tap_pos := Vector2.ZERO
var _shot_done := false
var _shots := 0
var _area := "?"                 # which map the camera is on
var _room := ""                  # indoors: the room the close-up frames
var _fade := ColorRect.new()     # black while going through the door
var _marker := Sprite2D.new()    # bobbing arrow over the companion in the whole-map view
var _photo := PhotoMaker.new()
var _photo_busy := false         # taking a photo: close up first, then a shot without the UI
var _photo_taken := false
var travel := Travel.new()
var keepsakes := Keepsakes.new()
var notes := Notes.new()
var _hover := Label.new()        # under the mouse: which trip a postcard / souvenir came from, the notes
var _album := AlbumPanel.new()
var _album_btn := Button.new()
var _magazines := PanelContainer.new()
var _leaving_home := false       # she decided to leave the little home: walking out of the gate
var _chosen := {}                # what she chose to do (her DSH tool): {spot, name, until (unix seconds), reason}
var _had_home := false           # this run has had the plugin's record (clothes in it change at the wardrobe)


func _ready() -> void:
	var single := SingleInstance.new()
	add_child(single)
	if not single.claim():
		Settings.log_line("main: 《旅行的大肥鱼》 is already open, showing that window instead")
		process_mode = Node.PROCESS_MODE_DISABLED
		get_tree().quit()
		return
	DisplayServer.screen_set_keep_on(true)
	_rng.randomize()
	add_child(world)

	add_child(travel)
	travel.postcard_arrived.connect(_on_postcard)
	travel.came_back.connect(_on_came_back)
	travel.set_out.connect(_on_set_out)
	travel.went_out.connect(func(): _leaving_home = companion.visible)
	travel.tell_plugin.connect(func(msg): link.send(msg))
	var start: Array = world.data.get("start", [8, 7])
	if not travel.is_inside() and world.spots.has("gate"):
		start = world.spots["gate"]["cell"]          # out or away: she will come in through the gate
	companion.setup(world, Vector2i(int(start[0]), int(start[1])))
	world.sort_root.add_child(companion)
	companion.wear(Settings.wear if Settings.wear != "" else str(travel.data.get("outfit", "maid")), true)
	notes.setup(travel)
	add_child(notes)
	keepsakes.setup(world, travel, notes)
	world.add_child(keepsakes)
	var ambient := Ambient.new()
	ambient.setup(world, companion)
	world.add_child(ambient)
	var sound := Soundscape.new()
	sound.setup(world, companion, ambient)
	world.add_child(sound)

	_near = Settings.start_near
	_zoom = _target_zoom()
	camera.zoom = Vector2.ONE * _zoom
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 2.5
	add_child(camera)
	camera.make_current()
	_follow_area()

	add_child(link)
	link.linked.connect(_on_linked)
	link.unlinked.connect(_on_unlinked)
	link.message.connect(_on_message)

	_build_ui()
	add_child(_photo)

	if Settings.force_state != "":
		var p := Settings.force_state.split(":")
		_state = {"state": p[0], "activity": p[1] if p.size() > 1 else null}
		_forced = true
	if Settings.open_settings:
		_open_panel()


func _build_ui() -> void:
	_ui.layer = 10
	add_child(_ui)

	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 14:
			var d := Vector2(x - 6.5, y - 6.5).length()
			if d <= 6.5:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(6.5 - d, 0.0, 1.0)))
	_dot.texture = ImageTexture.create_from_image(img)
	_dot.position = Vector2(1280 - 26, 800 - 26)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.visible = not Settings.clean
	_ui.add_child(_dot)

	for l in [_toast, _debug]:
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(l)
	_toast.position = Vector2(20, 760)
	_toast.visible = false
	_hover.add_theme_font_size_override("font_size", 20)
	_hover.add_theme_color_override("font_color", Color8(80, 62, 52))
	var tag := StyleBoxFlat.new()
	tag.bg_color = Color(0.98, 0.95, 0.86, 0.96)
	tag.border_color = Color8(150, 120, 96)
	tag.set_border_width_all(1)
	tag.set_corner_radius_all(4)
	tag.set_content_margin_all(6)
	_hover.add_theme_stylebox_override("normal", tag)
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.visible = false
	_ui.add_child(_hover)
	_debug.position = Vector2(16, 10)
	_debug.visible = Settings.debug

	_marker.texture = _marker_texture()
	_marker.scale = Vector2.ONE * 4.0
	_marker.visible = false
	_ui.add_child(_marker)
	_fade.color = Color.BLACK
	_fade.size = Vector2(1280, 800)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_ui.add_child(_fade)

	_album_btn.position = Vector2(16, 16)
	_album_btn.add_theme_font_size_override("font_size", 20)
	_album_btn.focus_mode = Control.FOCUS_NONE
	_album_btn.visible = not Settings.clean
	_album_btn.pressed.connect(func(): _album.open())
	_ui.add_child(_album_btn)
	_update_album_btn()
	travel.changed.connect(_update_album_btn)
	_album.travel = travel
	_album.visible = false
	_ui.add_child(_album)
	_build_magazines()

	_panel = SettingsPanel.new()
	_panel.visible = false
	_panel.saved.connect(_on_settings_saved)
	_ui.add_child(_panel)


func _update_album_btn() -> void:
	var n: int = travel.data["unseen"]
	_album_btn.text = "旅行相册" + ("（新 %d）" % n if n > 0 else "")


## Put a travel magazine on the coffee table (or take it away). She only learns of it by looking (her DSH
## tools show what is in the house) or because the user tells her; going or not is up to her.
func _build_magazines() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_magazines.add_child(box)
	var title := Label.new()
	title.text = "在茶几上放一本旅行杂志"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	for id in travel.places:
		var b := Button.new()
		b.text = "《%s》" % travel.places[id].get("short", id)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func():
			travel.set_magazine(id)
			_magazines.visible = false
			_show_toast("《%s》放在茶几上了。可以跟她提一句哦" % travel.places[id].get("short", id), 5.0))
		box.add_child(b)
	for pair in [["收起来", true], ["算了", false]]:
		var b := Button.new()
		b.text = pair[0]
		b.add_theme_font_size_override("font_size", 22)
		var take: bool = pair[1]
		b.pressed.connect(func():
			if take:
				travel.set_magazine("")
			_magazines.visible = false)
		box.add_child(b)
	_magazines.position = Vector2(520, 220)
	_magazines.visible = false
	_ui.add_child(_magazines)


func _on_postcard(trip: Dictionary) -> void:
	var p: Dictionary = travel.places.get(trip["place"], {})
	_show_toast("收到一张从%s寄来的明信片！点左下角「旅行相册」看看" % p.get("short", ""), 8.0)


func _on_came_back(trip: Dictionary) -> void:
	var p: Dictionary = travel.places.get(trip["place"], {})
	companion.visible = true
	var got: String = ("，带回了" + trip["souvenir"]) if trip["souvenir"] != "" else ""
	_show_toast("她从%s回来了%s" % [p.get("short", ""), got], 8.0)


## Remote: she decided to go (her tool, kept by the plugin); if she is in sight she walks out of the gate first.
func _on_set_out(trip: Dictionary) -> void:
	_chosen = {}
	if companion.visible:
		travel.leaving = trip["place"]

func _show_toast(text: String, seconds := 3.0) -> void:
	if Settings.clean:
		return
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = seconds


# ------------------------------------------------------------------ link

func _on_linked(host_name: String) -> void:
	_set_frozen(false)
	_show_toast("已连上电脑 %s" % host_name)
	if link.welcome.get("keeper", false):
		# what can be done here and how many postcards the wall holds, for the plugin that keeps the home
		link.send({"t": "world", "activities": _activities().map(_activity_name),
			"wall_slots": keepsakes.info().get("wall_slots", []).size()})
		# a plugin with no record yet gets the one this window kept (once; a copy stays here)
		if link.welcome.get("fresh", false) and Settings.travel_save and not travel.remote \
				and not OS.has_feature("web") and not travel.data["trips"].is_empty():
			Settings.log_line("travel: handing the record over to the plugin (%d trips)" % travel.data["trips"].size())
			travel.quiet_next = 2
			link.send({"t": "seed", "data": travel.data})


func _on_unlinked(graceful: bool, reason: String) -> void:
	if _forced:
		return
	if Settings.on_disconnect == "freeze":
		_set_frozen(true)
	else:
		_state = {"state": "idle", "activity": null}
	_show_toast("和电脑断开了（%s）" % ("电脑退出" if graceful else "连接中断"))
	Settings.log_line("main: unlinked %s, %s" % [reason, "frozen" if _frozen else "living on"])


func _on_message(msg: Dictionary) -> void:
	if _forced:
		return
	match msg.get("t"):
		"state":
			_state = {"state": str(msg.get("state", "idle")), "activity": msg.get("activity")}
			if Settings.debug:
				Settings.log_line("main: state %s %s" % [_state["state"], _state["activity"]])
		"chat":
			if msg.get("dir") == "out" and not _frozen:
				companion.pop_heart()
		"photo":
			take_photo()
		"home":
			if msg.get("data") is Dictionary:
				var first := not _had_home
				_had_home = true
				travel.apply_remote(msg["data"])
				_apply_chosen(msg["data"].get("chosen"))
				companion.wear(str(travel.data.get("outfit", "maid")), first)
		"cmd":
			if msg.get("op") == "photo":
				_reply_photo(msg)
				return
			if msg.get("op") == "facts":
				link.send({"t": "reply", "id": msg.get("id"), "ok": true, "facts": _facts()})
				return
			var why := _do_cmd(str(msg.get("op", "")), msg)
			link.send({"t": "reply", "id": msg.get("id"), "ok": why == "", "why": why, "world": _world_report()})


## Her photo tool: the window as it is now (without the buttons and notes), for her to see herself. Away on a
## trip nobody is home, so she gets the postcard she sent instead, once it has arrived.
func _reply_photo(msg: Dictionary) -> void:
	var why := ""
	var image := ""
	var kind := "window"
	var a := travel.away()
	if not a.is_empty():
		var card: String = travel.places.get(a["place"], {}).get("postcard", "")
		why = "no_postcard_yet" if not a["postcard"] or card == "" else ""
		if why == "":
			kind = "postcard"
			image = Marshalls.raw_to_base64((load(Travel.DIR + card) as Texture2D).get_image().save_jpg_to_buffer(0.85))
	else:
		_ui.visible = false
		# a minimized window is not drawn: draw this one frame anyway, just for the photo
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
			RenderingServer.force_draw(false)
		else:
			await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		_ui.visible = true
		if shot == null or shot.is_empty() or shot.get_width() < 64:
			why = "minimized"
		else:
			if shot.get_width() > 1280:
				shot.resize(1280, roundi(shot.get_height() * 1280.0 / shot.get_width()), Image.INTERPOLATE_LANCZOS)
			image = Marshalls.raw_to_base64(shot.save_jpg_to_buffer(0.85))
	var reply := {"t": "reply", "id": msg.get("id"), "ok": why == "", "why": why, "image": image, "mime": "image/jpeg",
		"kind": kind, "facts": _facts()}
	if not travel.remote:
		reply["world"] = _world_report()          # an old plugin words the window's own report
	link.send(reply)


## Remote: what she chose to do, from the plugin ({name, until, reason} or null).
func _apply_chosen(c) -> void:
	if not (c is Dictionary):
		_chosen = {}
		return
	var spot := _find_activity(str(c.get("name", "")))
	_chosen = {} if spot == "" else {"spot": spot, "name": c["name"], "until": float(c.get("until", 0)),
		"reason": str(c.get("reason", ""))}


## What only this window knows, for the plugin's report: the weather, where she is standing, whether she got
## to what she chose.
func _facts() -> Dictionary:
	var label: String = world.spots.get(companion.at_spot, {}).get("label", "")
	return {"hour": snappedf(Settings.hour_now(), 0.01), "weather": world.weather.name_now(), "season": world.season,
		"at": label.get_slice("：", label.get_slice_count("：") - 1) if travel.is_inside() and companion.visible else "",
		"arrived": not _chosen.is_empty() and companion.at_spot == _chosen["spot"] and not companion.is_busy_walking()}


## Her own decisions through her DSH tools (supplement 4): nothing here happens unless she calls one.
## Returns "" when done, else why not.
func _do_cmd(op: String, msg: Dictionary) -> String:
	var busy := "away" if travel.is_away() else ("leaving" if travel.leaving != "" or _leaving_home else "")
	match op:
		"look":
			return ""
		"do":
			if busy != "":
				return busy
			if not travel.is_inside():
				return "outside"
			var spot := _find_activity(str(msg.get("activity", "")))
			if spot == "":
				return "unknown_activity"
			var minutes := clampf(float(msg.get("minutes", 20)), 1.0, 240.0)
			_chosen = {"spot": spot, "name": _activity_name(spot), "until": Time.get_unix_time_from_system() + minutes * 60.0,
				"reason": str(msg.get("reason", "")).left(100)}
			Settings.log_line("home: she chose %s for %d min" % [spot, int(minutes)])
			return ""
		"enter":
			if busy != "":
				return busy
			if travel.is_inside():
				return "already_inside"
			travel.set_inside(true)
			return ""
		"leave":
			if busy != "":
				return busy
			if not travel.is_inside():
				return "not_inside"
			_leaving_home = true
			_chosen = {}
			return ""
		"travel":
			if busy != "":
				return busy
			if not travel.can_go(str(msg.get("place", ""))):
				return "unknown_place"
			travel.go(str(msg.get("place", "")), str(msg.get("message", "")))
			_chosen = {}
			return ""
		"come_back":
			if not travel.is_away():
				return "not_away"
			travel.come_back_early(str(msg.get("keep", "photo")))
			return ""
		"postcard":
			if not travel.is_away():
				return "not_away"
			if travel.away()["postcard"]:
				return "postcard_sent"
			travel.write_postcard(str(msg.get("text", "")))
			return ""
		"note":
			if busy != "":
				return busy
			if not travel.is_inside():
				return "outside"
			var words := str(msg.get("text", "")).strip_edges().left(Notes.MAX_CHARS)
			if words == "":
				return "empty_note"
			return "" if notes.write(words) else "note_failed"
	return "unknown_op"


## Spots she can choose to spend time at (not doors and gates).
func _activities() -> Array:
	return world.spots.keys().filter(func(k):
		var s: Dictionary = world.spots[k]
		return not s.get("hidden", false) and not k in ["door", "gate", "door_in"] and s.has("label"))


func _activity_name(spot: String) -> String:
	var s: Dictionary = world.spots.get(spot, {})
	var label: String = s.get("label", spot)
	return s.get("do", label.get_slice("：", label.get_slice_count("：") - 1))


func _find_activity(text: String) -> String:
	text = text.strip_edges()
	if text == "":
		return ""
	for k in _activities():
		if _activity_name(k) == text:
			return k
	for k in _activities():
		var n := _activity_name(k)
		if n.contains(text) or text.contains(n):
			return k
	return ""


func _chosen_active() -> bool:
	if _chosen.is_empty():
		return false
	if Time.get_unix_time_from_system() < float(_chosen["until"]) and world.spots.has(_chosen["spot"]):
		return true
	_chosen = {}
	return false


## What she sees when she looks at the little home (facts only; the plugin words them).
func _world_report() -> Dictionary:
	var a := travel.away()
	var places := []
	for id in travel.places:
		if travel.can_go(id):
			places.append({"id": id, "name": travel.places[id].get("name", id)})
	var label: String = world.spots.get(companion.at_spot, {}).get("label", "")
	var r := {
		"inside": travel.is_inside(), "leaving": travel.leaving != "" or _leaving_home,
		"hour": snappedf(Settings.hour_now(), 0.01), "weather": world.weather.name_now(), "season": world.season,
		"at": label.get_slice("：", label.get_slice_count("：") - 1) if travel.is_inside() and companion.visible else "",
		"places": places, "trips": travel.data["trips"].filter(func(t): return t["home"]).size(),
		"postcards": travel.trips_with_postcards().size(),
		"souvenirs": travel.souvenirs().map(func(p): return travel.places.get(p, {}).get("souvenir", p)),
		"wall": travel.wall_labels(keepsakes.info().get("wall_slots", []).size()), "shelf": travel.shelf_labels(),
		"away": null, "magazine": null, "doing": null, "activities": _activities().map(_activity_name),
	}
	if _chosen_active() and travel.is_inside():
		r["doing"] = {"name": _chosen["name"], "reason": _chosen["reason"],
			"arrived": companion.at_spot == _chosen["spot"] and not companion.is_busy_walking(),
			"minutes_left": ceili((float(_chosen["until"]) - Time.get_unix_time_from_system()) / 60.0)}
	if not a.is_empty():
		r["away"] = {"place": a["place"], "name": travel.places.get(a["place"], {}).get("name", a["place"]),
			"left": a["left"], "back": a["back"], "postcard": a["postcard"], "wrote": a["message"] != ""}
	var mag: String = travel.data["magazine"]
	if mag != "":
		r["magazine"] = {"id": mag, "name": travel.places.get(mag, {}).get("short", mag), "new": travel.take_magazine_news()}
	# notes on the coffee table: read to her only when she is in the little home
	r["notes"] = notes.take() if travel.is_inside() else []
	r["notes_waiting"] = notes.unread_count()
	return r


func _set_frozen(on: bool) -> void:
	_frozen = on
	world.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT


# ------------------------------------------------------------------ what to do

func _decide() -> Dictionary:
	var a = _state.get("activity")
	var st: String = _state.get("state", "idle")
	var at: String = world.data.get("state_spots", {}).get(st, "front" if st == "waiting" else "desk")
	match st:
		"waiting":
			return {"spot": at, "anim": "wait", "bubble": "alert", "urgent": true}
		"error":
			return {"spot": at, "anim": "error", "bubble": "error"}
		"chatting":
			# a world may name a seat to chat on (state_spots.chatting); otherwise right here. Doing something
			# she chose, she looks at her phone right there (on the swing, by the pond), not in bed though.
			var seat: String = world.data.get("state_spots", {}).get("chatting", "")
			if _chosen_active() and world.spots[_chosen["spot"]].get("anim", "") != "sleep":
				seat = _chosen["spot"]
			return {"spot": seat, "anim": "phone", "bubble": CHAT_BUBBLES.get(a, "dots"), "sit_ok": true}
		"working":
			return {"spot": at, "anim": "type", "bubble": WORK_ICONS.get(a, "tool")}
		"thinking":
			return {"spot": at, "anim": "think", "bubble": "think"}
		"done":
			return {"spot": "", "anim": "cheer", "bubble": "note"}
	if _chosen_active():
		_idle_spot = ""
		return _activity(_chosen["spot"])
	if Settings.force_spot != "" and world.spots.has(Settings.force_spot):
		return _activity(Settings.force_spot)
	if not Settings.tour.is_empty():
		return _activity(Settings.tour[int(_clock / Settings.tour_every) % Settings.tour.size()])
	if Settings.is_night():
		_idle_spot = ""
		return {"spot": "sleep" if world.spots.has("sleep") else "bed", "anim": "sleep", "bubble": "sleep"}
	# the day's routine (meals, bath) from the world data; not in a calm world, where she picks meals herself
	var h := Settings.hour_now()
	for r in (world.data.get("routine", []) if not world.data.has("calm_life") else []):
		if h >= float(r[0]) and h < float(r[1]) and world.spots.has(r[2]):
			_idle_spot = ""
			return _activity(r[2])
	return _idle_life()


## An activity at a spot, with the animation and bubble the spot asks for.
func _activity(spot: String) -> Dictionary:
	var s: Dictionary = world.spots.get(spot, {})
	return {"spot": spot, "anim": s.get("anim", "stand"), "bubble": s.get("bubble", ""), "stroll": true}


## [spot, anim, weight] lists: from the world data when it has them ([spot, weight]), else the built-in ones.
func _life(key: String, fallback: Array) -> Array:
	if not world.data.has(key):
		return fallback
	var out := []
	for e in world.data[key]:
		if world.spots.has(e[0]):
			out.append([e[0], world.spots[e[0]].get("anim", "stand"), int(e[1])])
	return out


func _idle_life() -> Dictionary:
	var life: Array = _life("idle_life", IDLE_LIFE)
	match world.weather.kind:
		Weather.Kind.RAIN: life = _life("idle_rain", IDLE_RAIN)
		Weather.Kind.SNOW: life = _life("idle_snow", IDLE_SNOW)
	var calm := world.data.has("calm_life")
	if calm:
		# free version: on her own only small things (sitting, standing at the door), long stays; in rain or
		# snow indoors when there is an inside
		life = _life("calm_life", [])
		if world.weather.keeps_indoors() and world.indoor.size.x > 0.0:
			var inside := life.filter(func(e):
				var c: Array = world.spots[e[0]]["cell"]
				return world.indoor.has_point(world.feet(Vector2i(int(c[0]), int(c[1])))))
			life = inside if not inside.is_empty() else life
	var allowed := life.any(func(e): return e[0] == _idle_spot)
	if _idle_spot == "" or _clock > _idle_until or not allowed:
		var total := 0
		for e in life:
			if e[0] != _idle_spot:
				total += e[2]
		var pick := _rng.randi_range(1, total)
		for e in life:
			if e[0] == _idle_spot:
				continue
			pick -= e[2]
			if pick <= 0:
				_idle_spot = e[0]
				break
		_idle_until = _clock + (_rng.randf_range(300.0, 600.0) if calm else _rng.randf_range(30.0, 60.0))
	for e in life:
		if e[0] == _idle_spot:
			return {"spot": e[0], "anim": e[1], "bubble": world.spots[e[0]].get("bubble", ""), "stroll": true}
	return {"spot": "", "anim": "stand", "bubble": "", "stroll": true}


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	_clock += delta
	if not _frozen:
		if travel.leaving != "" or _leaving_home:
			# off on a trip or just out: through the gate, then the home is empty until she comes back in
			companion.perform({"spot": "gate", "anim": "stand"})
			if companion.at_spot == "gate" and not companion.is_busy_walking():
				if travel.leaving != "":
					travel.set_off()
				else:
					_leaving_home = false
					travel.set_inside(false)
				companion.visible = false
		elif not travel.is_inside():
			companion.visible = false
		else:
			companion.visible = true
			companion.perform(_decide())
		world.nobody_home = not companion.visible
		world.occupied_room = world.room_at(companion.position)
		# she fades out passing through the door
		var p := companion.position
		var in_door := world.doorway.has_point(p) and p.y > world.indoor.end.y and p.y < world.doorway.end.y - 4.0
		companion.modulate.a = move_toward(companion.modulate.a, 0.0 if in_door else 1.0, delta * 6.0)
		_fade.modulate.a = companion.warp_fade()
		_follow_area()
		var target := _target_zoom()
		_zoom = lerpf(_zoom, target, minf(delta * ZOOM_SPEED, 1.0))
		if absf(_zoom - target) < 0.01:
			_zoom = target
		camera.zoom = Vector2.ONE * _zoom
		var near_t := clampf((_zoom - _far_zoom()) / maxf(_near_zoom() - _far_zoom(), 0.01), 0.0, 1.0)
		if Settings.camera_at.x >= 0.0:
			camera.position = Settings.camera_at
		else:
			# far view looks at the whole map; close up follows the companion (indoors: frames its room)
			camera.position = world.area_rect(companion.position).get_center().lerp(_near_point(), near_t)
		_update_marker(1.0 - near_t)

	match link.status:
		FrameLink.Status.LINKED:
			_dot.modulate = Color(0.4, 0.9, 0.5, maxf(_dot.modulate.a - delta * 0.25, 0.0))
		FrameLink.Status.DENIED:
			_dot.modulate = Color(0.95, 0.35, 0.3, 0.8)
		FrameLink.Status.NO_CODE:
			_dot.modulate = Color(0.95, 0.75, 0.3, 0.6)
		_:
			_dot.modulate = Color(0.7, 0.7, 0.75, 0.45)

	_update_hover()

	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 1.0:
			_toast.modulate.a = maxf(_toast_t, 0.0)
		if _toast_t <= 0.0:
			_toast.visible = false

	if _debug.visible:
		_debug.text = "%s %s | %s %s | %s | %s | %02d:%02d | %s %s 月%.2f 雪%.2f | %d fps 贴图%dMB 内存%dMB%s" % [
			_state["state"], _state["activity"] if _state["activity"] != null else "", _area, _room,
			world.spots.get(companion.at_spot, {}).get("label", companion.at_spot), link.status_text(), int(Settings.hour_now()), int(fmod(Settings.hour_now(), 1.0) * 60.0),
			world.season, world.weather.name_now(), Almanac.moon_phase(), world.weather.cover,
			Engine.get_frames_per_second(), _mb(Performance.RENDER_TEXTURE_MEM_USED), _mb(Performance.MEMORY_STATIC),
			" | 定格" if _frozen else ""]
	if Settings.perf_every > 0.0:
		_perf_log(delta)

	if _press_at >= 0.0 and _clock - _press_at > LONG_PRESS and not _panel.visible:
		_press_at = -1.0
		_open_panel()
	if _panel.visible:
		_panel.set_status(link.status_text())

	if Settings.screenshot_path != "" and not _shot_done and _clock > Settings.screenshot_after * (_shots + 1):
		# a path containing %d keeps taking numbered shots every screenshot_after seconds
		var many := Settings.screenshot_path.contains("%")
		var path := Settings.screenshot_path % _shots if many else Settings.screenshot_path
		get_viewport().get_texture().get_image().save_png(path)
		_shots += 1
		_shot_done = not many
		Settings.log_line("screenshot: %s" % path)
	if Settings.album_after > 0.0 and _clock > Settings.album_after:
		Settings.album_after = 0.0
		_album.open()
		if Settings.album_back:
			_album.turn_card()
	if Settings.photo_after > 0.0 and _clock > Settings.photo_after and not _photo_taken:
		_photo_taken = true
		take_photo()
	if Settings.minimize_after > 0.0 and _clock > Settings.minimize_after:
		Settings.minimize_after = 0.0
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		Settings.log_line("test: window minimized")
	if Settings.quit_after > 0.0 and _clock > Settings.quit_after:
		get_tree().quit()


## Zoom that shows the whole map the companion is on.
func _far_zoom() -> float:
	var s := world.area_rect(companion.position).size
	return maxf(1280.0 / s.x, 800.0 / s.y)


## Close-up zoom: indoors the largest whole zoom that still shows the companion's room with its walls;
## outdoors the zoom from the settings.
func _near_zoom() -> float:
	var r := _room_frame()
	if r.size.x <= 0.0:
		return float(Settings.zoom)
	return clampf(minf(floorf(minf(1280.0 / r.size.x, 800.0 / r.size.y)), Settings.zoom), _far_zoom(), 6.0)


func _near_point() -> Vector2:
	var r := _room_frame()
	if r.size.x > 0.0:
		return r.get_center()
	return companion.position + Vector2(0, -companion.height() * 0.5)


func _room_frame() -> Rect2:
	if _room == "" or not world.rooms.has(_room):
		return Rect2()
	return (world.rooms[_room] as Rect2).grow(world.tile)


## Keeps the camera on the companion's map, and notes which room it is in (kept while in a doorway).
func _follow_area() -> void:
	var p := companion.position
	var a := world.area_at(p)
	if a != _area:
		_area = a
		_room = ""
		var r := world.area_rect(p)
		camera.limit_left = int(r.position.x)
		camera.limit_top = int(r.position.y)
		camera.limit_right = int(r.end.x)
		camera.limit_bottom = int(r.end.y)
		_room = world.room_at(p)
		_zoom = _target_zoom()
		camera.zoom = Vector2.ONE * _zoom
		camera.position = _near_point() if _zoom > _far_zoom() else r.get_center()
		camera.reset_smoothing()
	var room := world.room_at(p)
	if room != "":
		_room = room


## A photo of what the companion is doing (way A: no AI), saved under user://photos/.
func take_photo() -> void:
	if _photo_busy or _frozen:
		return
	_photo_busy = true
	var t := 0.0
	while t < 4.0 and (t < 1.6 or absf(_zoom - _target_zoom()) > 0.02 or companion.warp_fade() > 0.0):
		await get_tree().process_frame
		t += get_process_delta_time()
	_ui.visible = false
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	_ui.visible = true
	var focus := get_viewport().get_canvas_transform() * (companion.position + Vector2(0, -companion.height() * 0.5))
	var label: String = world.spots.get(companion.at_spot, {}).get("label", "")
	var when := Time.get_datetime_dict_from_system()
	var caption := "%d.%02d.%02d  %02d:%02d   %s" % [when["year"], when["month"], when["day"], int(Settings.hour_now()),
		int(fmod(Settings.hour_now(), 1.0) * 60.0), label.get_slice("：", label.get_slice_count("：") - 1)]
	var k := shot.get_width() / get_viewport().get_visible_rect().size.x     # window may be bigger than 1280 x 800
	await _photo.make(shot, focus * k, _zoom * k, caption)
	_show_toast("拍了一张照片")
	_photo_busy = false


func _target_zoom() -> float:
	var close: bool = _near or _photo_busy or (not _forced_far() and _state.get("state", "") in CLOSE_UP_STATES)
	return _near_zoom() if close else _far_zoom()


func _marker_texture() -> Texture2D:
	var rows := ["#######", "#yyyyy#", "##yyy##", " ##y## ", "  ###  ", "   #   "]
	var img := Image.create(7, 6, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in 7:
			match rows[y][x]:
				"#": img.set_pixel(x, y, Color8(63, 38, 49))
				"y": img.set_pixel(x, y, Color8(255, 214, 90))
	return ImageTexture.create_from_image(img)


## The arrow over the companion's head in the whole-map view: same size on screen at any zoom.
func _update_marker(far_t: float) -> void:
	# no arrow while she is drawn into the furniture (it would sit on her face)
	_marker.visible = far_t > 0.05 and companion.warp_fade() < 0.05 and not world.scene_on and companion.visible
	if not _marker.visible:
		return
	var head := companion.position + Vector2(0, -companion.height() - 22.0)
	var at := get_viewport().get_canvas_transform() * head
	_marker.position = (at + Vector2(0, -absf(sin(_clock * 3.0)) * 10.0)).round()
	_marker.modulate.a = clampf(far_t * 1.5, 0.0, 1.0)


## The mouse on a postcard, souvenir or note: a little tag with its words ("11月12日·杭州").
func _update_hover() -> void:
	var screen := get_viewport().get_mouse_position()
	var p := get_viewport().get_canvas_transform().affine_inverse() * screen
	if Settings.hover_at.x >= 0.0:
		p = Settings.hover_at
		screen = get_viewport().get_canvas_transform() * p
	var text := "" if _panel.visible or _album.visible or _magazines.visible else keepsakes.label_at(p)
	_hover.visible = text != ""
	if text != "":
		_hover.text = text
		_hover.reset_size()
		_hover.position = (screen + Vector2(-_hover.size.x * 0.5, -_hover.size.y - 14.0)).clamp(
			Vector2(4, 4), Vector2(1276, 796) - _hover.size)


func _mb(monitor: Performance.Monitor) -> int:
	return int(Performance.get_monitor(monitor) / 1048576.0)


## Tablet tests: every perf_every seconds, the slowest / average frame rate since the last line and memory.
var _perf_t := 0.0
var _perf_frames := 0
var _perf_worst := 0.0
func _perf_log(delta: float) -> void:
	if _clock < 3.0:
		return    # skip loading
	_perf_t += delta
	_perf_frames += 1
	_perf_worst = maxf(_perf_worst, delta)
	if _perf_t >= Settings.perf_every:
		Settings.log_line("perf: %s %s avg %.1f fps, slowest frame %.1f ms, textures %d MB, video %d MB, static %d MB" % [
			_area, "near" if _zoom > _far_zoom() + 0.01 else "far",
			_perf_frames / _perf_t, _perf_worst * 1000.0, _mb(Performance.RENDER_TEXTURE_MEM_USED),
			_mb(Performance.RENDER_VIDEO_MEM_USED), _mb(Performance.MEMORY_STATIC)])
		_perf_t = 0.0
		_perf_frames = 0
		_perf_worst = 0.0


func _forced_far() -> bool:
	return Settings.camera_at.x >= 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible or _album.visible or _magazines.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _press_at >= 0.0 and _clock - _press_at < 0.4:
			# a click on the postcard wall / shelf opens the album, on the coffee table the magazines
			var hit := keepsakes.hit(get_viewport().get_canvas_transform().affine_inverse() * event.position)
			if hit == "table":
				_magazines.visible = true
			elif hit != "":
				_album.open()
		if event.pressed:
			_press_at = _clock
			_press_pos = event.position
			if _clock - _last_tap < DOUBLE_TAP and event.position.distance_to(_last_tap_pos) < 80.0:
				_near = not _near
				_last_tap = -10.0
			else:
				_last_tap = _clock
				_last_tap_pos = event.position
		else:
			_press_at = -1.0
	elif event is InputEventMouseMotion and _press_at >= 0.0:
		if event.position.distance_to(_press_pos) > 40.0:
			_press_at = -1.0
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_open_panel()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		take_photo()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_album.open()


func _open_panel() -> void:
	_panel.open(link.status_text())


func _on_settings_saved(link_changed: bool) -> void:
	_near = Settings.view == "near"
	if link_changed:
		link.restart()
	if _frozen and Settings.on_disconnect == "loop":
		_set_frozen(false)
		_state = {"state": "idle", "activity": null}
