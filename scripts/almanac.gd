class_name Almanac
## Calendar facts for the world: today's date, season and moon phase (tablet's local clock;
## --date / --season / --moon override them for tests).

const SYNODIC_DAYS := 29.530588853
const NEW_MOON_UNIX := 947182440.0      # 2000-01-06 18:14 UTC


static func date() -> Dictionary:
	if Settings.force_date != "":
		var p := Settings.force_date.split("-")
		if p.size() == 3:
			return {"year": p[0].to_int(), "month": p[1].to_int(), "day": p[2].to_int()}
	return Time.get_date_dict_from_system()


static func date_key() -> String:
	var d := date()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func season() -> String:
	if Settings.force_season in ["spring", "summer", "autumn", "winter"]:
		return Settings.force_season
	var m: int = date()["month"]
	if m >= 3 and m <= 5:
		return "spring"
	if m >= 6 and m <= 8:
		return "summer"
	if m >= 9 and m <= 11:
		return "autumn"
	return "winter"


## 0 = new moon, 0.5 = full, back to 1.
static func moon_phase() -> float:
	if Settings.force_moon >= 0.0:
		return fmod(Settings.force_moon, 1.0)
	var unix := Time.get_unix_time_from_system()
	if Settings.force_date != "":
		unix = Time.get_unix_time_from_datetime_string(date_key() + "T22:00:00")
	return fposmod((unix - NEW_MOON_UNIX) / 86400.0 / SYNODIC_DAYS, 1.0)


## How bright the moon is, 0 (new) .. 1 (full).
static func moon_light() -> float:
	return 0.5 * (1.0 - cos(TAU * moon_phase()))


## 1 through the night, easing in at dusk and out at dawn.
static func night_weight(h: float) -> float:
	if h >= 20.5 or h < 5.0:
		return 1.0
	if h >= 19.0:
		return (h - 19.0) / 1.5
	if h < 6.5:
		return 1.0 - (h - 5.0) / 1.5
	return 0.0
