class_name Soundscape
extends Node
## Ambient sound that follows the world: rain, wind (snow, overcast), crickets on summer and
## early-autumn nights, birds by day (more at dawn and when birds are in the yard), a splash when
## a fish jumps. Outdoor sound is muffled while the companion is inside. Sounds come from
## tools/p1_sounds.py (synthesised, original). Pauses with the world when it freezes.
## Rain comes and goes (11-16: one rain sound for hours is tiring): three kinds of rain, a new mix every
## minute or two with now and then a near-quiet lull. (Single drips from the eaves were tried and taken out,
## 11-16: they did not sound nice.)

const DIR := "res://assets/sounds/"
const BUS := "Outdoor"
# loop name -> loudness at full (dB)
const LOOPS := {"rain": -10.0, "rain_light": -9.0, "rain_roof": -10.0, "wind": -9.0, "crickets": -15.0}
const RAINS := ["rain", "rain_light", "rain_roof"]
const SPELL := [45.0, 120.0]         # seconds one rain mix lasts
const LULL := 0.25                   # chance a spell is a near-quiet lull

var world: World
var companion: Companion
var ambient: Ambient

var _loops: Dictionary = {}           # name -> {player, level}
var _birds: Array[AudioStream] = []
var _splash: AudioStream
var _shots: Array[AudioStreamPlayer] = []
var _bird_t := 4.0
var _rain_mix := {}                  # rain loop -> share of the rain now
var _spell_t := 0.0
var _lp := AudioEffectLowPassFilter.new()
var _rng := RandomNumberGenerator.new()


func setup(w: World, c: Companion, a: Ambient) -> void:
	world = w
	companion = c
	ambient = a


func _ready() -> void:
	_rng.randomize()
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, "Master")
		_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(idx, _lp)
	else:
		_lp = AudioServer.get_bus_effect(idx, 0)

	for n in LOOPS:
		var s: AudioStreamOggVorbis = load(DIR + n + ".ogg")
		s.loop = true
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = BUS
		p.volume_db = -80.0
		add_child(p)
		p.play(_rng.randf_range(0.0, s.get_length()))
		_loops[n] = {"player": p, "level": 0.0}
	for i in 4:
		_birds.append(load(DIR + "bird_%d.ogg" % i))
	_new_spell()
	_splash = load(DIR + "splash.ogg")
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_shots.append(p)
	ambient.fish_jumped.connect(func(): _shot(_splash, -13.0, _rng.randf_range(0.9, 1.1)))


func _process(delta: float) -> void:
	var on := Settings.sound == "on"
	var w := world.weather
	var h := Settings.hour_now()
	var night := Almanac.night_weight(h)
	var fair := w.rain < 0.2 and w.snow < 0.4
	var cricket_season := {"summer": 1.0, "autumn": 0.5}.get(world.season, 0.0) as float
	_spell_t -= delta
	if _spell_t <= 0.0:
		_new_spell()
	var want := {
		"wind": maxf(w.snow * 0.8, w.cloud * 0.3) * (1.0 - w.rain * 0.6),
		"crickets": night * cricket_season * (1.0 if fair else 0.0),
	}
	for n in RAINS:
		want[n] = w.rain * float(_rain_mix[n])
	for n in _loops:
		var l: Dictionary = _loops[n]
		var target: float = want[n] if on else 0.0
		# rain changes slowly, so a new spell fades in over ten seconds or so
		l["level"] = move_toward(l["level"], target, delta * (0.08 if n in RAINS else 0.5))
		var p: AudioStreamPlayer = l["player"]
		p.volume_db = LOOPS[n] + linear_to_db(maxf(l["level"], 0.0001))

	# inside the house the outdoors sounds muffled
	var inside := world.indoor.has_point(companion.position)
	var cutoff := 900.0 if inside else 20000.0
	_lp.cutoff_hz = lerpf(_lp.cutoff_hz, cutoff, minf(delta * 2.0, 1.0))

	_bird_t -= delta
	var day := 1.0 - night
	if _bird_t <= 0.0:
		var dawn := h >= 5.0 and h < 7.5
		var busy := ambient.birds_in_yard() > 0
		_bird_t = _rng.randf_range(1.5, 4.0) if dawn or busy else _rng.randf_range(4.0, 11.0)
		if on and day > 0.5 and fair and world.season != "winter":
			_shot(_birds[_rng.randi() % _birds.size()], _rng.randf_range(-16.0, -10.0), _rng.randf_range(0.9, 1.15))


## The next stretch of rain: mostly one kind with a little of the others, or now and then a near-quiet lull.
func _new_spell() -> void:
	_spell_t = _rng.randf_range(SPELL[0], SPELL[1])
	var lull := _rng.randf() < LULL
	var lead: String = RAINS[_rng.randi() % RAINS.size()]
	for n in RAINS:
		if lull:
			_rain_mix[n] = _rng.randf_range(0.15, 0.3) if n == "rain_light" else 0.0
		else:
			_rain_mix[n] = _rng.randf_range(0.6, 1.0) if n == lead else _rng.randf_range(0.0, 0.3)


func _shot(stream: AudioStream, db: float, pitch: float) -> void:
	if Settings.sound != "on":
		return
	for p in _shots:
		if not p.playing:
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return
