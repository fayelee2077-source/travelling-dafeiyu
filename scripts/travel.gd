class_name Travel
extends Node
## Trips (free version): she decides to go (her DSH tool; --travel-now in tests), walks out of the gate and
## the home stays empty; halfway a postcard comes (her own words on the back, if she wrote any, and a seasonal
## scenic footer); she comes back with a photo and a souvenir.

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
const SEASONS := ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"]

const SCENIC_NOTES := {
	"hangzhou": {"spring": "苏堤的柳丝刚蘸到水，风里都是软的", "summer": "荷叶挨着荷叶，风过时翻起一片白背", "autumn": "晚风里有桂花味，雷峰塔的影子拉得很长", "winter": "断桥边的残荷立在冷水里，湖面格外安静"},
	"suzhou": {"spring": "月洞门外的细雨，把青石板洗得发亮", "summer": "芭蕉叶大得能遮阴，池里的锦鲤躲在石影下", "autumn": "白墙角落下几片黄叶，水面上一点风也没有", "winter": "花窗格子里漏进一点冬阳，茶气散得很慢"},
	"huangshan": {"spring": "山缝里开了小野花，云海从脚底下漫上来", "summer": "松针上挂着雾珠，山顶的风比山下凉快得多", "autumn": "日出把云海染成橘红色，松影落在石头上", "winter": "迎客松的针叶裹着白霜，踩雪声传得很远"},
	"xiamen": {"spring": "海风潮乎乎的，老院子墙头垂下一串花", "summer": "白浪一层层拍在礁石上，阳光晒得石头暖洋洋", "autumn": "傍晚的海风不燥了，巷子里飘来一段钢琴声", "winter": "南方的冬天海还是蓝的，浪花漫过脚边的沙"},
	"xuexiang": {"spring": "屋檐的厚雪化出冰溜子，滴答滴答落在木阶上", "summer": "林子里的木屋收起了厚雪，夜里风还是很凉", "autumn": "松林先黄了一层，木屋烟囱早早升起了白烟", "winter": "屋顶的雪厚得像白蘑菇，红灯笼把雪照成暖橙色"},
	"shanghai": {"spring": "江风吹过来带点凉意，对岸的灯一盏接一盏亮了", "summer": "夏夜的江面晃着粉紫色的灯影，汽笛声慢悠悠的", "autumn": "梧桐叶落了满街，傍晚江上的晚霞像橘子汽水", "winter": "江边的风有点冻耳朵，亮灯的塔在夜空里特别清楚"},
	"suichang": {"spring": "山谷的晨雾还没散，竹林里全是新笋和泥土味", "summer": "蓄满水的梯田像一块块亮镜子，把天光接住了", "autumn": "一层层稻田黄透了，山腰小村飘着做长粽的香气", "winter": "清晨梯田结了一层薄霜，山里安静得只听见竹叶响"},
	"xianghu": {"spring": "湖面像没擦干的玻璃，远山淡淡地洇在水里", "summer": "木栈道边的芦苇绿得发亮，小木舟轻轻晃着水波", "autumn": "芦苇荡全变成金黄色了，夕阳把湖水染得暖融融", "winter": "起雾的早晨，湖面像没擦干的玻璃"},
	"beijing": {"spring": "灰瓦屋檐上掠过鸽哨声，胡同口的槐花刚开", "summer": "老槐树把青石板遮出大片凉阴，蝉声一声接一声", "autumn": "金黄的银杏叶铺在灰瓦上，风里有糖炒栗子香", "winter": "细雪静静落在青砖灰瓦上，枝头还挂着几个冻红柿"},
	"xian": {"spring": "古老的城砖缝里冒出小草，春风顺着城墙跑得很远", "summer": "太阳落下去以后，青砖还留着白天的余温", "autumn": "天色刚暗成群青蓝，城墙上的一排红灯笼全亮了", "winter": "城墙上的红灯笼在冷风里轻轻晃，暖光映着旧砖"},
	"guilin": {"spring": "细雨像烟一样拢着青峰，竹筏划开绿绸子似的水", "summer": "江水清得能数见水底鹅卵石，把脚伸进去凉丝丝的", "autumn": "秋天的江面平得像块碧玉，一层层山影倒映在水里", "winter": "薄雾贴着江面慢慢走，远处的青山像淡墨画出来的"},
	"dali": {"spring": "苍山腰上系着一条白云带，洱海蓝得晃眼睛", "summer": "午后的风穿过水边大树，湖面上碎银似地闪着光", "autumn": "天高得没有一丝杂色，晒在院里的蓝白染布随风鼓起来", "winter": "冬天的阳光还是暖的，水鸟贴着蓝盈盈的湖面飞"},
	"chengdu": {"spring": "竹叶间漏下碎阳光，盖碗茶的盖子轻轻磕出清脆响声", "summer": "高高的翠竹挡住了暑气，竹椅坐上去凉快又踏实", "autumn": "细雨打在竹叶上沙沙响，铜茶壶嘴冒着一缕白热气", "winter": "捧着热乎乎的盖碗茶窝在竹椅里，半天都不想起来"},
	"dunhuang": {"spring": "风吹过沙脊留下一道道细波纹，沙粒簌簌地轻响", "summer": "傍晚的沙山还带着日头的暖意，月牙泉绿得像块宝石", "autumn": "夕阳把连绵的沙丘染成金橙色，风里有远远的驼铃声", "winter": "清冷的夕光落在金色沙脊上，一弯泉水安安静静映着天"},
}

const SOUVENIR_DO := {
	"hangzhou": "泡龙井茶", "suzhou": "摇丝绸团扇", "huangshan": "打理迎客松盆景", "xiamen": "听钢琴音乐盒",
	"xuexiang": "点亮雪屋小摆件", "shanghai": "摇东方明珠水晶球", "suichang": "尝遂昌长粽", "xianghu": "尝萧山萝卜干",
	"beijing": "看兔儿爷", "xian": "看小陶马", "guilin": "摸漓江鹅卵石", "dali": "看扎染挂布",
	"chengdu": "抱熊猫玩偶", "dunhuang": "摇驼铃",
}

var places: Dictionary = {}          # id -> {name, en, short, postcard, photos, souvenir, souvenir_tex, magazine_tex}
var data := {"trips": [], "magazine": "", "magazine_new": false, "unseen": 0, "inside": false, "notes_read": {},
	"note_left": 0.0, "outfit": "maid"}
var remote := false                  # the plugin keeps the record (data["kept_by_plugin"] in the saved copy)
var notes_state := {}                # remote: {unread, on_table} of the coffee-table notes
var leaving := ""                    # place she is walking to the gate for
var _leave_message := ""
var _leave_to := ""
var _leave_seconds := 0.0
var _check := 0.0
var _got_remote := false
var quiet_next := 0
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
	for spec in Settings.travel_seed.split(",", false):
		var parts := spec.split(":", true, 1)
		_seed_trip(parts[0], parts[1] if parts.size() > 1 else Settings.travel_to)
	if Settings.inside != "":
		data["inside"] = Settings.inside == "on"
	if Settings.test_magazine != "":
		data["magazine"] = Settings.test_magazine
	if Settings.travel_now != "":
		go(Settings.travel_now, Settings.travel_message, Settings.trip_minutes * 60.0, Settings.travel_to)


static func clean_to(raw: String) -> String:
	var s := raw.strip_edges()
	if s.begins_with("寄给：") or s.begins_with("寄给:"):
		s = s.substr(3).strip_edges()
	elif s.begins_with("给"):
		s = s.substr(1).strip_edges()
	s = s.left(20)
	return "" if s in ["家里", "家里的你", "小家", "自己"] else s


static func season_of(t: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(t + Time.get_time_zone_from_system()["bias"] * 60))
	var m := clampi(int(d.get("month", 1)) - 1, 0, 11)
	return SEASONS[m]


func scenic_note(t: Dictionary) -> String:
	var pid := str(t.get("place", ""))
	var s := str(t.get("season", ""))
	if s == "":
		s = Settings.force_season if Settings.force_season != "" else season_of(float(t.get("left", _now())))
	var p: Dictionary = places.get(pid, {})
	var notes: Dictionary = p.get("notes", {}) if p.get("notes") is Dictionary else {}
	if notes.has(s):
		return str(notes[s])
	return str(SCENIC_NOTES.get(pid, {}).get(s, ""))


func souvenir_action(pid: String) -> String:
	var p: Dictionary = places.get(pid, {})
	var act := str(p.get("souvenir_do", ""))
	return act if act != "" else str(SOUVENIR_DO.get(pid, ""))


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
		return
	data["inside"] = on
	Settings.log_line("home: she %s" % ("came in" if on else "went out"))
	_store()
	changed.emit()


func apply_remote(d: Dictionary) -> void:
	var first := not remote or not _got_remote or quiet_next > 0
	quiet_next = maxi(quiet_next - 1, 0)
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


func take_magazine_news() -> bool:
	if not data["magazine_new"]:
		return false
	data["magazine_new"] = false
	_store()
	return true


func go(place: String, message := "", seconds := 0.0, to := "") -> bool:
	if is_away() or leaving != "" or not can_go(place):
		return false
	leaving = place
	_leave_message = message
	_leave_to = clean_to(to)
	_leave_seconds = seconds
	Settings.log_line("travel: going to %s" % place)
	return true


func set_off() -> void:
	if remote:
		leaving = ""
		changed.emit()
		return
	var now := _now()
	var length := _leave_seconds if _leave_seconds > 0.0 else _rng.randf_range(HOURS[0], HOURS[1]) * 3600.0
	var season := Settings.force_season if Settings.force_season != "" else season_of(now)
	var rec := {"place": leaving, "left": now, "back": now + length, "postcard_at": now + length * 0.5,
		"message": _leave_message, "season": season, "postcard": false, "home": false, "photo": "", "souvenir": ""}
	if _leave_to != "":
		rec["to"] = _leave_to
	data["trips"].append(rec)
	if data["magazine"] == leaving:
		data["magazine"] = ""
	leaving = ""
	_leave_to = ""
	_store()
	changed.emit()


func write_postcard(text: String, to = null) -> bool:
	var a := away()
	if a.is_empty() or a["postcard"]:
		return false
	a["message"] = text
	if to != null:
		var cleaned := clean_to(str(to))
		if cleaned != "":
			a["to"] = cleaned
		else:
			a.erase("to")
	_store()
	return true


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


## Postcards kept on her own wall (unaddressed / for home). Postcards addressed to 妈妈 / 姐姐 stay in the album.
func wall_trips() -> Array:
	return trips_with_postcards().filter(func(t): return str(t.get("to", "")).strip_edges() == "")


func souvenirs() -> Array:
	var out := []
	for t in data["trips"]:
		if t["home"] and t["souvenir"] != "" and not out.has(t["place"]):
			out.append(t["place"])
	return out


func trip_label(t: Dictionary, when: String) -> String:
	return "%s·%s" % [day_text(float(t[when])), places.get(t["place"], {}).get("short", t["place"])]


func wall_labels(slots: int) -> Array:
	var cards := wall_trips()
	cards.reverse()
	return cards.slice(0, slots).map(func(t): return trip_label(t, "postcard_at"))


func sent_to_labels() -> Array:
	var cards := trips_with_postcards().filter(func(t): return str(t.get("to", "")).strip_edges() != "")
	cards.reverse()
	return cards.map(func(t): return "%s（%s）" % [str(t["to"]), trip_label(t, "postcard_at")])


func shelf_labels() -> Array:
	var out := []
	for place in souvenirs():
		var t: Dictionary = data["trips"].filter(func(x): return x["home"] and x["place"] == place and x["souvenir"] != "")[0]
		var prefix := "挂在墙上·" if str(place) == "dali" else ""
		out.append("%s（%s%s）" % [places.get(place, {}).get("souvenir", place), prefix, trip_label(t, "back")])
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
	data["inside"] = true
	var place: Dictionary = places.get(a["place"], {})
	var had := []
	for t in data["trips"]:
		if t != a and t["place"] == a["place"]:
			had.append(t["photo"])
	var photos: Array = place.get("photos", [])
	var fresh := photos.filter(func(p): return not had.has(p))
	var pool := fresh if not fresh.is_empty() else photos
	a["photo"] = pool[_rng.randi() % pool.size()] if not pool.is_empty() else ""
	a["souvenir"] = place.get("souvenir", "")
	match a.get("early", ""):
		"photo": a["souvenir"] = ""
		"souvenir": a["photo"] = ""
	data["unseen"] += 1


const SEED_FALLBACK := {
	"beijing": {"name": "北京·胡同", "short": "北京", "souvenir": "兔儿爷"},
	"xian": {"name": "陕西·西安城墙", "short": "西安", "souvenir": "小陶马"},
	"guilin": {"name": "广西·桂林漓江", "short": "桂林", "souvenir": "漓江鹅卵石"},
	"dali": {"name": "云南·大理洱海", "short": "大理", "souvenir": "蓝白扎染布"},
	"chengdu": {"name": "四川·成都竹林茶铺", "short": "成都", "souvenir": "熊猫玩偶"},
	"dunhuang": {"name": "甘肃·敦煌鸣沙山", "short": "敦煌", "souvenir": "沙子小瓶与驼铃"},
}

func _seed_trip(place: String, to_raw := "") -> void:
	if not places.has(place):
		if not SEED_FALLBACK.has(place):
			return
		places[place] = SEED_FALLBACK[place].duplicate()
	var now: float = _now() - 86400.0 * maxf(1.0, float(6 - data["trips"].size()))
	var season := Settings.force_season if Settings.force_season != "" else season_of(now)
	var t := {"place": place, "left": now, "back": now + 36000.0, "postcard_at": now + 18000.0,
		"message": Settings.travel_message, "season": season, "postcard": true, "home": false, "photo": "", "souvenir": ""}
	var cleaned := clean_to(to_raw)
	if cleaned != "":
		t["to"] = cleaned
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


static func day_text(t: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(t + Time.get_time_zone_from_system()["bias"] * 60))
	return "%d月%d日" % [d["month"], d["day"]]
