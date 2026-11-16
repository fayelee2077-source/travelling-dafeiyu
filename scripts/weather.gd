class_name Weather
extends Node2D
## The world's own weather (no network): each day's weather is drawn from the season, seeded by
## the date so a restart gives the same day. Fades between kinds, draws rain and snow, and builds
## up / melts the snow cover. Nothing falls under the (cut-away) roof.

enum Kind { CLEAR, CLOUDY, RAIN, SNOW }
const NAMES := ["clear", "cloudy", "rain", "snow"]
const ODDS := {                        # clear, cloudy, rain, snow
	"spring": [45, 25, 30, 0],
	"summer": [55, 15, 30, 0],
	"autumn": [50, 30, 20, 0],
	"winter": [40, 25, 5, 30],
}
const FADE_SECONDS := 40.0
const COVER_UP_SECONDS := 480.0        # snowing -> fully white
const MELT_SECONDS := 1800.0
const RAIN_MELT_SECONDS := 300.0
const RAIN_DROPS := 220
const SNOW_FLAKES := 90
const SLANT := 0.3

const SNOW_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, (c.a > 0.0 && c.a <= amount) ? 1.0 : 0.0);
}
"""

var world: World
var kind := Kind.CLEAR
var cloud := 0.0
var rain := 0.0
var snow := 0.0
var cover := 0.0
var snow_mat := ShaderMaterial.new()

var _plan: Array = []                  # [[start_hour, kind]]
var _day := ""
var _rng := RandomNumberGenerator.new()
var _drops: Array = []                 # [land_x, land_y, fall_left, speed]
var _flakes: Array = []                # [land_x, land_y, fall_left, speed, phase, sway]
var _splashes: Array = []              # [x, y, age, on_water]
var _was_drawing := false


func setup(w: World) -> void:
	world = w
	var sh := Shader.new()
	sh.code = SNOW_SHADER
	snow_mat.shader = sh
	z_index = 15


func _ready() -> void:
	_rng.randomize()
	_plan_day()
	kind = _wanted()
	_snap_to(kind)
	if Settings.snow_cover >= 0.0:
		cover = clampf(Settings.snow_cover, 0.0, 1.0)
	elif Settings.force_weather == "" and kind == Kind.SNOW and Settings.hour_now() - _segment_start() > 0.15:
		cover = 1.0
	snow_mat.set_shader_parameter("amount", cover)
	for i in RAIN_DROPS:
		_drops.append(_new_drop(true))
	for i in SNOW_FLAKES:
		_flakes.append(_new_flake(true))
	Settings.log_line("weather: %s %s, today %s" % [Almanac.season(), NAMES[kind], _plan_text()])


## The world's colour multiplier for the current weather.
func tint() -> Color:
	var c := Color.WHITE.lerp(Color(0.84, 0.86, 0.92), cloud)
	c = c * Color.WHITE.lerp(Color(0.82, 0.86, 0.95), rain)
	c = c.lerp(Color(0.92, 0.94, 1.0), snow * 0.5)
	return c


## Rain or heavy snow keeps the companion's idle life indoors.
func keeps_indoors() -> bool:
	return kind == Kind.RAIN or kind == Kind.SNOW


func name_now() -> String:
	return NAMES[kind]


func _wanted() -> int:
	var f := NAMES.find(Settings.force_weather)
	if f >= 0:
		return f
	if Settings.weather_mode == "clear":
		return Kind.CLEAR
	var h := Settings.hour_now()
	var k: int = _plan[0][1]
	for seg in _plan:
		if h >= seg[0]:
			k = seg[1]
	return k


func _segment_start() -> float:
	var h := Settings.hour_now()
	var start := 0.0
	for seg in _plan:
		if h >= seg[0]:
			start = seg[0]
	return start


func _plan_day() -> void:
	_day = Almanac.date_key()
	var r := RandomNumberGenerator.new()
	r.seed = hash("living-dock-weather-" + _day)
	var odds: Array = ODDS[Almanac.season()]
	var first := _pick(r, odds, -1)
	_plan = [[0.0, first]]
	var hours: Array = []
	for i in r.randi_range(0, 2):
		hours.append(r.randf_range(6.0, 21.0))
	hours.sort()
	for h in hours:
		_plan.append([h, _pick(r, odds, _plan[-1][1])])


func _pick(r: RandomNumberGenerator, odds: Array, not_this: int) -> int:
	var total := 0
	for i in odds.size():
		if i != not_this:
			total += odds[i]
	var n := r.randi_range(1, total)
	for i in odds.size():
		if i == not_this:
			continue
		n -= odds[i]
		if n <= 0:
			return i
	return Kind.CLEAR


func _plan_text() -> String:
	var parts: Array[String] = []
	for seg in _plan:
		parts.append("%02d:%02d %s" % [int(seg[0]), int(fmod(seg[0], 1.0) * 60.0), NAMES[seg[1]]])
	return ", ".join(parts)


func _targets(k: int) -> Vector3:
	match k:
		Kind.CLOUDY: return Vector3(1.0, 0.0, 0.0)
		Kind.RAIN: return Vector3(1.0, 1.0, 0.0)
		Kind.SNOW: return Vector3(0.7, 0.0, 1.0)
	return Vector3.ZERO


func _snap_to(k: int) -> void:
	var t := _targets(k)
	cloud = t.x
	rain = t.y
	snow = t.z


func _process(delta: float) -> void:
	if Almanac.date_key() != _day:
		_plan_day()
	var k := _wanted()
	if k != kind:
		Settings.log_line("weather: %s -> %s" % [NAMES[kind], NAMES[k]])
		kind = k
	var scaled := delta * clampf(Settings.time_scale, 1.0, 60.0)
	var step := scaled / FADE_SECONDS
	var t := _targets(kind)
	cloud = move_toward(cloud, t.x, step)
	rain = move_toward(rain, t.y, step)
	snow = move_toward(snow, t.z, step)
	if snow > 0.5:
		cover += scaled / COVER_UP_SECONDS
	elif rain > 0.3:
		cover -= scaled / RAIN_MELT_SECONDS
	else:
		cover -= scaled / MELT_SECONDS
	cover = clampf(cover, 0.0, 1.0)
	snow_mat.set_shader_parameter("amount", cover)

	var active_drops := int(RAIN_DROPS * rain)
	for i in active_drops:
		var d: Array = _drops[i]
		d[2] -= d[3] * delta
		if d[2] <= 0.0:
			_splashes.append([d[0], d[1], 0.0, world.water.has_point(Vector2(d[0], d[1]))])
			_drops[i] = _new_drop(false)
	var active_flakes := int(SNOW_FLAKES * snow)
	for i in active_flakes:
		var f: Array = _flakes[i]
		f[2] -= f[3] * delta
		if f[2] <= 0.0:
			_flakes[i] = _new_flake(false)
	for s in _splashes:
		s[2] += delta
	_splashes = _splashes.filter(func(s): return s[2] < (0.6 if s[3] else 0.2))
	var drawing := active_drops > 0 or active_flakes > 0 or not _splashes.is_empty()
	if drawing or _was_drawing:
		queue_redraw()
	_was_drawing = drawing


func _outdoor_point() -> Vector2:
	var o := world.outdoor
	for i in 6:
		var p := Vector2(_rng.randf_range(o.position.x, o.end.x), _rng.randf_range(o.position.y, o.end.y))
		if not world.under_roof(p):
			return p
	return o.end - Vector2(8.0, 8.0)


func _new_drop(scatter: bool) -> Array:
	var p := _outdoor_point()
	var fall := _rng.randf_range(30.0, 90.0)
	return [p.x, p.y, _rng.randf_range(0.0, fall) if scatter else fall, _rng.randf_range(190.0, 240.0)]


func _new_flake(scatter: bool) -> Array:
	var p := _outdoor_point()
	var fall := _rng.randf_range(50.0, 160.0)
	return [p.x, p.y, _rng.randf_range(0.0, fall) if scatter else fall, _rng.randf_range(12.0, 22.0),
		_rng.randf_range(0.0, TAU), _rng.randf_range(1.0, 3.0)]


func _dot(p: Vector2, c: Color) -> void:
	p = p.round()
	if world.under_roof(p):
		return
	draw_rect(Rect2(p, Vector2.ONE), c)


func _draw() -> void:
	var drop_c := Color(0.86, 0.93, 1.0, 0.8)
	for i in int(RAIN_DROPS * rain):
		var d: Array = _drops[i]
		var head := Vector2(d[0] + d[2] * SLANT, d[1] - d[2])
		for j in 6:
			_dot(head + Vector2(j * SLANT, -j), Color(drop_c, drop_c.a * (1.0 - j * 0.14)))
	for s in _splashes:
		var at := Vector2(s[0], s[1])
		var age: float = s[2]
		if s[3]:
			var r := 1.0 + age * 4.0
			var a := 0.6 * (1.0 - age / 0.6)
			for v in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r * 0.6), Vector2(0, -r * 0.6),
					Vector2(r * 0.7, r * 0.42), Vector2(-r * 0.7, r * 0.42), Vector2(r * 0.7, -r * 0.42), Vector2(-r * 0.7, -r * 0.42)]:
				_dot(at + v, Color(0.85, 0.93, 1.0, a))
		elif age < 0.08:
			_dot(at, drop_c)
		else:
			_dot(at + Vector2(-1, -1), Color(drop_c, 0.45))
			_dot(at + Vector2(1, -1), Color(drop_c, 0.45))
	for i in int(SNOW_FLAKES * snow):
		var f: Array = _flakes[i]
		var x: float = f[0] + sin(f[4] + f[2] * 0.08) * f[5]
		var a: float = 1.0 if f[2] > 4.0 else f[2] / 4.0
		var p := Vector2(x, f[1] - f[2])
		# a blue-grey shadow pixel keeps the flake readable over white snow
		_dot(p + Vector2(1, 1), Color(0.55, 0.62, 0.78, 0.6 * a))
		_dot(p, Color(1, 1, 1, a))
		if f[5] > 2.2:
			_dot(p + Vector2(1, 0), Color(1, 1, 1, a))
