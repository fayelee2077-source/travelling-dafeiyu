class_name PostcardView
extends Control
## A postcard drawn by the program around a picture: front = the picture, the place, a stamp of our own
## (not a real one) and a postmark with the date; back = her own words (only if she wrote some), a printed
## seasonal scenic footer at the bottom, and who it is addressed to on the right. Click to turn it over.

signal flipped

var picture: Texture2D
var place := {}                      # {name, en, short}
var trip := {}                       # {postcard_at, message, to?}
var scenic := ""
var back := false

const PAPER := Color(0.98, 0.96, 0.9)
const INK := Color(0.25, 0.3, 0.45)
const MARK := Color(0.35, 0.45, 0.62, 0.75)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_trip(p: Dictionary, t: Dictionary, tex: Texture2D, scenic_line := "") -> void:
	place = p
	trip = t
	picture = tex
	scenic = scenic_line
	back = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		back = not back
		queue_redraw()
		flipped.emit()
		accept_event()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.25))
	draw_rect(r, PAPER)
	var stamp := Rect2(size.x - 104, 18, 78, 96)
	if not back:
		var inner := r.grow(-14)
		if picture:
			draw_texture_rect(picture, inner, false)
		var name: String = place.get("name", "")
		var strip := Rect2(inner.position.x, inner.end.y - 66, 30 + 30 * name.length(), 54)
		draw_rect(strip, Color(PAPER, 0.82))
		draw_string(font, strip.position + Vector2(14, 32), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
		draw_string(font, strip.position + Vector2(15, 48), place.get("en", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
		_stamp(stamp, font)
		_postmark(stamp.position + Vector2(-22, 70), font)
		return
	# back: her words on the left, printed seasonal scenic note below, recipient / sender / stamp on the right
	var mid := size.x * 0.58
	draw_line(Vector2(mid, 30), Vector2(mid, size.y - 30), Color(INK, 0.35), 2.0)
	var words: String = str(trip.get("message", ""))
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var max_h := size.y - (168.0 if scenic != "" else 130.0)
	if words != "":
		var fs := 24
		while fs > 14 and font.get_multiline_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, mid - 64, fs, -1, brk).y > max_h:
			fs -= 2
		draw_multiline_string(font, Vector2(34, 42 + fs), words, HORIZONTAL_ALIGNMENT_LEFT, mid - 64, fs, -1, INK, brk)
	else:
		draw_multiline_string(font, Vector2(34, 68), "（她没有写字，只寄来了风景）", HORIZONTAL_ALIGNMENT_LEFT, mid - 64, 16, -1,
			Color(INK, 0.55), brk)
	if scenic != "":
		draw_line(Vector2(34, size.y - 98), Vector2(mid - 26, size.y - 98), Color(INK, 0.18), 1.0)
		draw_multiline_string(font, Vector2(34, size.y - 78), "风物小注：" + scenic, HORIZONTAL_ALIGNMENT_LEFT,
			mid - 52, 12, 2, Color(0.42, 0.36, 0.32, 0.75), brk)
	draw_string(font, Vector2(34, size.y - 26), Travel.day_text(float(trip.get("postcard_at", 0))) + " · " + str(place.get("short", "")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(INK, 0.8))
	for i in 3:
		var y := 200.0 + i * 52.0
		draw_line(Vector2(mid + 24, y), Vector2(size.x - 30, y), Color(INK, 0.3), 1.5)
	var to_who := str(trip.get("to", "")).strip_edges()
	draw_string(font, Vector2(mid + 28, 192), "寄给：" + (to_who if to_who != "" else "家里的你"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	draw_string(font, Vector2(mid + 28, 244), "寄自：" + str(place.get("short", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	draw_string(font, Vector2(mid + 28, 296), "大肥鱼", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	_stamp(stamp, font)
	_postmark(stamp.position + Vector2(-22, 70), font)


func _stamp(s: Rect2, font: Font) -> void:
	draw_rect(s, Color.WHITE)
	var step := 8.0
	var x := s.position.x
	while x <= s.end.x:
		draw_circle(Vector2(x, s.position.y), 2.6, PAPER)
		draw_circle(Vector2(x, s.end.y), 2.6, PAPER)
		x += step
	var y := s.position.y
	while y <= s.end.y:
		draw_circle(Vector2(s.position.x, y), 2.6, PAPER)
		draw_circle(Vector2(s.end.x, y), 2.6, PAPER)
		y += step
	var inner := s.grow(-7)
	inner.size.y -= 16
	if picture:
		var ts := picture.get_size()
		var src := Rect2(ts.x * 0.55, ts.y * 0.15, ts.x * 0.3, ts.y * 0.45)
		draw_texture_rect_region(picture, inner, src)
	draw_string(font, Vector2(inner.position.x, s.end.y - 7), "大肥鱼邮政", HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 11, INK)
	draw_string(font, inner.position + Vector2(3, 14), "一份想念", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _postmark(c: Vector2, font: Font) -> void:
	draw_arc(c, 34, 0, TAU, 48, MARK, 2.0)
	draw_arc(c, 27, 0, TAU, 48, MARK, 1.0)
	draw_string(font, c + Vector2(-26, -8), str(place.get("short", "")), HORIZONTAL_ALIGNMENT_CENTER, 52, 13, MARK)
	draw_string(font, c + Vector2(-26, 12), Travel.day_text(float(trip.get("postcard_at", 0))), HORIZONTAL_ALIGNMENT_CENTER, 52, 12, MARK)
	for i in 3:
		var pts := PackedVector2Array()
		for k in 9:
			pts.append(c + Vector2(-44 - k * 9, -12 + i * 12 + sin(k * 1.3) * 3))
		draw_polyline(pts, MARK, 1.5)
