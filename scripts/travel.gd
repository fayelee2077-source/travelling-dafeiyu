class_name Travel
extends Node
## Trips (free version): she decides to go (her DSH tool; --travel-now in tests), walks out of the gate and
## the home stays empty; halfway a postcard comes (her own words on the back, if she wrote any); she comes
## back with a photo and a souvenir. Only facts are kept (user://travel.json): where, when, what came back.
## Pictures are made beforehand (assets/travel/, tools/travel_assets.py); nothing is generated or sent anywhere.
## Since 补充条款四·修订二 the DSH plugin keeps the record and the rules (dsh-plugin/lib/home.js): once a
## plugin says it keeps it, this only shows what it sends (remote), kept here as a copy for when DSH is off;
## the rules below then only run in test runs (record not saved) and with an old plugin.

signal changed                       # anything the room or the album shows changed
signal postcard_arrived(trip: Dictionary)
signal came_back(trip: Dictionary)
signal set_out(trip: Dictionary)     # remote: she decided to go (the window walks her to the gate)
signal went_out                      # remote: she left the little home
signal tell_plugin(msg: Dictionary)  # remote: what the user did here, for the plugin to keep

const FILE := "user://travel.json"
const BEFORE_PLUGIN := "user://travel_before_plugin.json"
const DIR := "res://assets/travel/"
const HOURS := [8.0, 20.0]           # a trip lasts this long (real hours), the postcard comes halfway

var places: Dictionary = {}          # id -> {name, en, short, postcard, photos, souvenir, souvenir_tex, magazine_tex}
# trips: [{place, left, back, postcard_at, message, postcard (arrived), home (back home), photo, souvenir}]
# inside: she is in the little home (she goes in and out herself, with her DSH tools; empty house until then)
# notes_read: coffee-table note file -> its modified time when she read it; note_left: when she last left one
var data := {"trips": [], "magazine": "", "magazine_new": false, "unseen": 0, "inside": false, "notes_read": {},
	"note_left": 0.0, "outfit": "maid"}
var remote := false                  # the plugin keeps the record (data["kept_by_plugin"] in the saved copy)
var notes_state := {}                # remote: {unread, on_table} of the coffee-table notes
var leaving := ""                    # place she is walking to the gate for
var _leave_message := ""
var _leave_seconds := 0.0
var _check := 0.0
var _got_remote := false             # this run has had the plugin's record (later ones show what changed)
var quiet_next := 0                  # records from the plugin to take without showing changes (handing over)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var p = JSON.parse_string(FileAccess.get_file_as_string(DIR + "places.json")) \
		if FileAccess.file_exists(DIR + "places.json") else null
	places = p if p is Dictionary else {}
	if Settings.travel_save and FileAccess.file_exists(FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			data.merge(d, true)
			remote = bool(data.get("kept_by_plugin", false))
			notes_state = data.get("notes", {})
	for id in Settings.travel_seed.split(",", false):
		_seed_trip(id)
	if Settings.inside != "":
		data["inside"] = Settings.inside == "on"
	if Settings.test_magazine != "":
		data["magazine"] = Settings.test_magazine
	if Settings.travel_now != "":
		go(Settings.travel_now, Settings.travel_message, Settings.trip_minutes * 60.0)


## A place is ready once its postcard and photos are made (she must not come back with nothing to show).
func can_go(place: String) -> bool:
	return places.has(place) and places[place].get("postcard", "") != "" and not places[place].get("photos", []).is_empty()


func away() -> Dictionary:
	var t: Array = data["trips"]
	return t[-1] if not t.is_empty() and not t[-1]["home"] else {}


func is_away() -> bool:
	return not away().is_empty()


func is_inside() -> bool:
	return data["inside"] and not is_away()


func set_inside(on: bool) -> void:
	if remote:
		return                           # the plugin already has it
	data["inside"] = on
	Settings.log_line("home: she %s" % ("came in" if on else "went out"))
	_store()
	changed.emit()


## Remote: the record the plugin sends (on connecting and after every change). Shows what changed: the
## postcard coming, her coming home, setting out, going out of the little home.
func apply_remote(d: Dictionary) -> void:
	var first := not remote or not _got_remote or quiet_next > 0
	quiet_next = maxi(quiet_next - 1, 0)
	# the record this window kept itself, kept once more before the plugin's replaces it
	if Settings.travel_save and not data.get("kept_by_plugin", false) and FileAccess.file_exists(FILE) \
			and not FileAccess.file_exists(BEFORE_PLUGIN):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FILE), ProjectSettings.globalize_path(BEFORE_PLUGIN))
	var before: Array = data["trips"]
	var was_inside := is_inside()
	remote = true
	_got_remote = true
	for k in ["trips", "magazine", "magazine_new", "unseen", "inside", "note_left", "chosen", "outfit"]:
		if d.has(k):
			data[k] = d[k]
	notes_state = d.get("notes", {})
	data["notes"] = notes_state
	data["kept_by_plugin"] = true
	_store()
	if not first:
		var trips: Array = data["trips"]
		for i in trips.size():
			var t: Dictionary = trips[i]
			var old: Dictionary = before[i] if i < before.size() else {}
			if old.is_empty() and not t["home"]:
				Settings.log_line("travel: going to %s" % t["place"])
				set_out.emit(t)
			if t["postcard"] and not old.get("postcard", false) and not t["home"]:
				Settings.log_line("travel: postcard from %s" % t["place"])
				postcard_arrived.emit(t)
			if t["home"] and not old.get("home", false) and not old.is_empty():
				Settings.log_line("travel: back from %s with %s" % [t["place"], t["souvenir"]])
				came_back.emit(t)
		if was_inside and not is_inside() and not is_away():
			went_out.emit()
	changed.emit()


## Whether the magazine on the table is one she has not been told about yet; telling her once clears it.
func take_magazine_news() -> bool:
	if not data["magazine_new"]:
		return false
	data["magazine_new"] = false
	_store()
	return true


## She decided to go. She walks to the gate first (main calls set_off there). False if she cannot now.
func go(place: String, message := "", seconds := 0.0) -> bool:
	if is_away() or leaving != "" or not can_go(place):
		return false
	leaving = place
	_leave_message = message
	_leave_seconds = seconds
	Settings.log_line("travel: going to %s" % place)
	return true


func set_off() -> void:
	if remote:
		leaving = ""                     # only the walk to the gate was shown; the trip is the plugin's
		changed.emit()
		return
	var now := _now()
	var length := _leave_seconds if _leave_seconds > 0.0 else _rng.randf_range(HOURS[0], HOURS[1]) * 3600.0
	data["trips"].append({"place": leaving, "left": now, "back": now + length, "postcard_at": now + length * 0.5,
		"message": _leave_message, "postcard": false, "home": false, "photo": "", "souvenir": ""})
	if data["magazine"] == leaving:
		data["magazine"] = ""
	leaving = ""
	_store()
	changed.emit()


## Her words for the postcard while she is away (her DSH tool); before it has come they go on its back.
func write_postcard(text: String) -> bool:
	var a := away()
	if a.is_empty() or a["postcard"]:
		return false
	a["message"] = text
	_store()
	return true


## She decided to come home early (her DSH tool): she brings back only one of the photo and the souvenir
## (keep: "photo" or "souvenir"); a postcard not mailed yet comes home with her. False if she is not away.
func come_back_early(keep: String) -> bool:
	var a := away()
	if a.is_empty():
		return false
	a["early"] = "souvenir" if keep == "souvenir" else "photo"
	a["back"] = minf(a["back"], _now())
	a["postcard_at"] = minf(a["postcard_at"], a["back"])
	Settings.log_line("travel: coming home early from %s, keeping the %s" % [a["place"], a["early"]])
	_store()
	return true


func set_magazine(place: String) -> void:
	data["magazine"] = place
	data["magazine_new"] = place != ""
	if remote:
		tell_plugin.emit({"t": "user", "op": "magazine", "place": place})
	_store()
	changed.emit()


func trips_with_postcards() -> Array:
	return data["trips"].filter(func(t): return t["postcard"])


func souvenirs() -> Array:
	var out := []
	for t in data["trips"]:
		if t["home"] and t["souvenir"] != "" and not out.has(t["place"]):
			out.append(t["place"])
	return out


## "11月12日·杭州": which trip a postcard or souvenir came from.
func trip_label(t: Dictionary, when: String) -> String:
	return "%s·%s" % [day_text(float(t[when])), places.get(t["place"], {}).get("short", t["place"])]


## The postcards on the wall (newest first, as many as it has slots), labelled by trip.
func wall_labels(slots: int) -> Array:
	var cards := trips_with_postcards()
	cards.reverse()
	return cards.slice(0, slots).map(func(t): return trip_label(t, "postcard_at"))


## The souvenirs on the shelf, each with the trip that first brought it home.
func shelf_labels() -> Array:
	var out := []
	for place in souvenirs():
		var t: Dictionary = data["trips"].filter(func(x): return x["home"] and x["place"] == place and x["souvenir"] != "")[0]
		out.append("%s（%s）" % [places.get(place, {}).get("souvenir", place), trip_label(t, "back")])
	return out


func mark_seen() -> void:
	if remote and int(data["unseen"]) > 0:
		tell_plugin.emit({"t": "user", "op": "seen"})
	data["unseen"] = 0
	_store()
	changed.emit()


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 or remote:
		return
	_check = 1.0
	var a := away()
	if a.is_empty():
		return
	var now := _now()
	if not a["postcard"] and now >= a["postcard_at"]:
		a["postcard"] = true
		data["unseen"] += 1
		_store()
		Settings.log_line("travel: postcard from %s" % a["place"])
		postcard_arrived.emit(a)
		changed.emit()
	if now >= a["back"]:
		_come_home(a)
		_store()
		Settings.log_line("travel: back from %s with %s" % [a["place"], a["souvenir"]])
		came_back.emit(a)
		changed.emit()


func _come_home(a: Dictionary) -> void:
	a["postcard"] = true
	a["home"] = true
	data["inside"] = true                # back from a trip into the little home
	var place: Dictionary = places.get(a["place"], {})
	# a photo she has not brought home before, if there is one left
	var had := []
	for t in data["trips"]:
		if t != a and t["place"] == a["place"]:
			had.append(t["photo"])
	var photos: Array = place.get("photos", [])
	var fresh := photos.filter(func(p): return not had.has(p))
	var pool := fresh if not fresh.is_empty() else photos
	a["photo"] = pool[_rng.randi() % pool.size()] if not pool.is_empty() else ""
	a["souvenir"] = place.get("souvenir", "")
	# home early: only the one she chose to keep
	match a.get("early", ""):
		"photo": a["souvenir"] = ""
		"souvenir": a["photo"] = ""
	data["unseen"] += 1


func _seed_trip(place: String) -> void:
	if not places.has(place):
		return
	var now: float = _now() - 86400.0 * (3 - data["trips"].size())
	var t := {"place": place, "left": now, "back": now + 36000.0, "postcard_at": now + 18000.0,
		"message": Settings.travel_message, "postcard": true, "home": false, "photo": "", "souvenir": ""}
	data["trips"].append(t)
	_come_home(t)


func _now() -> float:
	return Time.get_unix_time_from_system()


func store() -> void:
	_store()


func _store() -> void:
	if not Settings.travel_save:
		return
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))


## "11月9日" from a unix time (local).
static func day_text(t: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(t + Time.get_time_zone_from_system()["bias"] * 60))
	return "%d月%d日" % [d["month"], d["day"]]
