extends Node
## Saved settings (user://settings.cfg) plus test-only launch options.
## On the tablet there is no command line: options can be put one per line in user://launch_args.txt
## (pushed with adb). Launch options win over saved settings but are not saved.

const FILE := "user://settings.cfg"
const ARGS_FILE := "user://launch_args.txt"
const LOG_FILE := "user://log.txt"

var pair_code := ""
var host_ip := ""
var zoom := 4
var on_disconnect := "freeze"   # "freeze": stop on the last frame; "loop": keep living on its own
var weather_mode := "season"    # "season": the world's own weather, by season; "clear": always fair
var sound := "on"               # ambient sound "on" / "off"
var body_scale := 1.0           # companion size: 1 (two cells, Stardew), 0.75, 0.625 — to compare on the tablet
var view := "far"               # what the screen shows normally: "far" (whole map) or "near" (follow, Stardew style)
const BODY_SCALES := [1.0, 0.75, 0.625]
var data_port := 48960
var beacon_port := 48961
var link_url := ""              # web version: the plugin's WebSocket (given in the page)

# test-only
var fixed_hour := -1.0
var time_scale := 1.0
var screenshot_path := ""
var screenshot_after := 3.0
var quit_after := 0.0
var force_state := ""           # e.g. "working:editing", "idle", "chatting:replying"
var debug := false
var force_weather := ""         # clear / cloudy / rain / snow
var force_season := ""          # spring / summer / autumn / winter
var force_date := ""            # YYYY-MM-DD (season, moon, the day's weather)
var force_moon := -1.0          # 0 new .. 0.5 full .. 1 new
var snow_cover := -1.0          # starting snow on the ground, 0..1
var camera_at := Vector2(-1, -1)  # fixed camera point in world pixels (screenshots)
var start_near := false         # start in the close-up view instead of the whole-world view
var force_spot := ""            # idle at this activity spot only (screenshots)
var wear := ""                  # start in these clothes (maid / winter / summer / rain; tests and screenshots)
var tour: PackedStringArray = []  # idle at these spots in turn (demo recordings)
var tour_every := 12.0          # seconds at each spot of the tour
var open_settings := false      # open the settings panel at start (screenshots)
var photo_after := 0.0          # take a photo after this many seconds (tests)
var minimize_after := 0.0       # tests: minimize the window after this many seconds (her photo tool still works)
var perf_every := 0.0           # log frame rate and memory every this many seconds (tablet tests)
var clean := false              # no status dot or toasts (recording videos)
var travel_now := ""            # tests: she sets off for this place at start (the real trigger is her DSH tool)
var travel_message := ""        # tests: what she writes on the postcard
var trip_minutes := 0.0         # tests: trip length in minutes (0 = the normal length)
var travel_save := true         # keep trips in user://travel.json (off for tests, so the real record is untouched)
var travel_seed := ""           # tests: start with these trips done, e.g. "hangzhou,hangzhou" (not saved)
var album_after := 0.0          # tests: open the travel album after this many seconds
var album_back := false         # tests: and turn its postcard over
var test_magazine := ""         # tests: a travel magazine on the coffee table (not saved)
var inside := ""                # tests: "on" / "off" = she is / is not in the little home (not saved)
var notes_dir := ""             # tests: another coffee-table notes folder ("" = 文档\旅行的大肥鱼\茶几纸条)
var hover_at := Vector2(-1, -1) # tests: act as if the mouse were on this world point (screenshots of the labels)

var _start_hour := 0.0
var _start_ms := 0
var _log: FileAccess


func _init() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		pair_code = str(cfg.get_value("link", "pair_code", ""))
		host_ip = str(cfg.get_value("link", "host_ip", ""))
		zoom = int(cfg.get_value("view", "zoom", 4))
		on_disconnect = str(cfg.get_value("view", "on_disconnect", "freeze"))
		weather_mode = str(cfg.get_value("view", "weather", "season"))
		sound = str(cfg.get_value("view", "sound", "on"))
		body_scale = float(cfg.get_value("view", "body", 1.0))
		view = str(cfg.get_value("view", "view", "far"))
	if OS.has_feature("web"):
		# the page comes from the DSH plugin, which puts the pair code in it; it connects back to where it came from
		host_ip = str(JavaScriptBridge.eval("location.host", true))
		var code := str(JavaScriptBridge.eval("(window.LIVING_DOCK || {}).pair || ''", true))
		if code != "":
			pair_code = code
		# the link the page was given, on the page's own host; inside the DSH desktop window the page may come
		# through DSH's own scheme, then the link goes to DSH's real web address (the parent window knows it)
		link_url = str(JavaScriptBridge.eval("""(function () {
			var b = window.LIVING_DOCK || {}, base = location.href;
			if (!b.link) return '';
			if (!/^https?:$/.test(location.protocol)) {
				try { base = (parent.__DSH_TRANSPORT__ || {}).streamBaseUrl || base } catch (e) {}
			}
			var u = new URL(b.link, base);
			u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
			return u.href;
		})()""", true))

	var args: Array[String] = []
	if FileAccess.file_exists(ARGS_FILE):
		for line in FileAccess.get_file_as_string(ARGS_FILE).split("\n", false):
			line = line.strip_edges()
			if line != "" and not line.begins_with("#"):
				args.append(line)
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		var kv := arg.trim_prefix("--").split("=", true, 1)
		var val := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"pair": pair_code = val
			"host-ip": host_ip = val
			"zoom": zoom = val.to_int()
			"on-disconnect": on_disconnect = val
			"port": data_port = val.to_int()
			"beacon-port": beacon_port = val.to_int()
			"hour": fixed_hour = val.to_float()
			"time-scale": time_scale = maxf(val.to_float(), 0.0)
			"screenshot": screenshot_path = val
			"screenshot-after": screenshot_after = val.to_float()
			"quit-after": quit_after = val.to_float()
			"state": force_state = val
			"debug": debug = true
			"weather": force_weather = val
			"sound": sound = val
			"near": start_near = true
			"view": view = val
			"open-settings": open_settings = true
			"photo-after": photo_after = val.to_float()
			"minimize-after": minimize_after = val.to_float()
			"spot": force_spot = val
			"wear": wear = val
			"tour": tour = val.split(",", false)
			"tour-every": tour_every = maxf(val.to_float(), 1.0)
			"perf": perf_every = val.to_float()
			"clean": clean = true
			"travel-now": travel_now = val
			"travel-message": travel_message = val
			"trip-minutes": trip_minutes = val.to_float()
			"travel-save": travel_save = val != "off"
			"travel-seed": travel_seed = val
			"album-after": album_after = val.to_float()
			"album-back": album_back = true
			"magazine": test_magazine = val
			"inside": inside = val
			"notes-dir": notes_dir = val
			"hover":
				var hxy := val.split(",")
				if hxy.size() == 2:
					hover_at = Vector2(hxy[0].to_float(), hxy[1].to_float())
			"body": body_scale = val.to_float()
			"season": force_season = val
			"date": force_date = val
			"moon": force_moon = val.to_float()
			"snow-cover": snow_cover = val.to_float()
			"camera":
				var xy := val.split(",")
				if xy.size() == 2:
					camera_at = Vector2(xy[0].to_float(), xy[1].to_float())
	# test runs that show her doing something have her in the little home (she decides that herself otherwise)
	if inside == "" and (travel_now != "" or travel_seed != "" or test_magazine != "" or force_state != ""
			or force_spot != "" or not tour.is_empty()):
		inside = "on"
	if travel_now != "" or travel_seed != "" or test_magazine != "" or inside != "":
		travel_save = false
	zoom = clampi(zoom, 3, 5)
	if not BODY_SCALES.has(body_scale):
		body_scale = 1.0
	if view != "near":
		view = "far"
	start_near = start_near or view == "near"
	if on_disconnect != "loop":
		on_disconnect = "freeze"
	if weather_mode != "clear":
		weather_mode = "season"
	if sound != "off":
		sound = "on"

	_start_ms = Time.get_ticks_msec()
	if fixed_hour >= 0.0:
		_start_hour = fixed_hour
	else:
		var t := Time.get_time_dict_from_system()
		_start_hour = t["hour"] + t["minute"] / 60.0 + t["second"] / 3600.0

	_log = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	log_line("start: zoom=%d on_disconnect=%s paired=%s host=%s" % [zoom, on_disconnect, pair_code != "", host_ip])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("link", "pair_code", pair_code)
	cfg.set_value("link", "host_ip", host_ip)
	cfg.set_value("view", "zoom", zoom)
	cfg.set_value("view", "on_disconnect", on_disconnect)
	cfg.set_value("view", "weather", weather_mode)
	cfg.set_value("view", "sound", sound)
	cfg.set_value("view", "body", body_scale)
	cfg.set_value("view", "view", view)
	cfg.save(FILE)
	log_line("settings saved: zoom=%d on_disconnect=%s weather=%s sound=%s paired=%s host=%s" % [zoom, on_disconnect, weather_mode, sound, pair_code != "", host_ip])


## Local hour of day, 0.0–24.0.
func hour_now() -> float:
	var elapsed_h := (Time.get_ticks_msec() - _start_ms) / 3600000.0
	return fmod(_start_hour + elapsed_h * time_scale, 24.0)


func is_night() -> bool:
	var h := hour_now()
	return h >= 23.0 or h < 7.0


func log_line(text: String) -> void:
	var line := "%s %s" % [Time.get_time_string_from_system(), text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()
