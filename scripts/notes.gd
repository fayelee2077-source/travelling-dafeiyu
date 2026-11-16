class_name Notes
extends Node
## Notes on the coffee table (补充条款四·修订一): a folder anyone at home can drop .txt notes into, who left it
## first in the file name (妈妈_11月13日.txt). Only this folder is read, only its .txt files; files are never
## changed or deleted. She hears the ones she has not read when she uses her tools in the little home, and can
## leave one herself (大肥鱼_11月13日_0930.txt). What she has read is kept in the travel record.
## Since 修订二 the plugin reads and writes the folder (dsh-plugin/lib/notes.js): when it keeps the record
## (travel.remote) this window never touches the folder and only shows what the plugin says is on the table.

signal changed                       # whether there is a note on the table changed

const MAX_CHARS := 300
const PER_LOOK := 5
const MINE := "大肥鱼"
const SHOW_MINE := 86400.0           # her own note stays on the table this long

var travel: Travel
var dir := ""
var on_table := false
var _check := 0.0


## Test runs (travel record not saved) only use a test folder (--notes-dir), never the real notes.
func setup(t: Travel) -> void:
	travel = t
	if Settings.notes_dir != "":
		dir = Settings.notes_dir
	elif Settings.travel_save and not OS.has_feature("web"):   # a web page cannot reach the Documents folder
		dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("旅行的大肥鱼").path_join("茶几纸条")
	travel.changed.connect(_refresh)
	on_table = _on_table()


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 5.0
	var now := _on_table()
	if now != on_table:
		on_table = now
		changed.emit()


## Notes she has not read, oldest first: [{file, time}]. A note edited after she read it counts as new.
func unread() -> Array:
	var read: Dictionary = travel.data["notes_read"]
	var out := []
	if dir == "" or travel.remote or not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() != "txt":
			continue
		var t := FileAccess.get_modified_time(dir.path_join(f))
		if int(read.get(f, -1)) != t:
			out.append({"file": f, "time": t})
	out.sort_custom(func(a, b): return a["time"] < b["time"])
	return out


## Up to PER_LOOK unread notes for her to read now ({from, day, text}); they count as read from here on.
func take() -> Array:
	var out := []
	for n in unread().slice(0, PER_LOOK):
		var text := _text(dir.path_join(n["file"]))
		var name: String = n["file"].get_basename()
		out.append({"from": name.get_slice("_", 0) if name.get_slice("_", 0) != "" else name,
			"day": Travel.day_text(float(n["time"])), "text": text})
		travel.data["notes_read"][n["file"]] = n["time"]
	if not out.is_empty():
		Settings.log_line("notes: she read %d" % out.size())
		travel.store()
		_refresh()
	return out


## She leaves a note on the table. False if it could not be written.
func write(text: String) -> bool:
	if dir == "" or travel.remote:
		return false
	DirAccess.make_dir_recursive_absolute(dir)
	var d := Time.get_datetime_dict_from_system()
	var base := "%s_%d月%d日_%02d%02d" % [MINE, d["month"], d["day"], d["hour"], d["minute"]]
	var file := base + ".txt"
	var i := 2
	while FileAccess.file_exists(dir.path_join(file)):
		file = "%s_%d.txt" % [base, i]
		i += 1
	var f := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	travel.data["notes_read"][file] = FileAccess.get_modified_time(dir.path_join(file))
	travel.data["note_left"] = Time.get_unix_time_from_system()
	Settings.log_line("notes: she left %s" % file)
	travel.store()
	_refresh()
	return true


## "茶几上有 2 张她还没看的纸条" when the mouse is on the note (or "" when there is none).
func caption() -> String:
	var n := unread_count()
	if n > 0:
		return "茶几上有 %d 张她还没看的纸条" % n
	return "她留了一张纸条（在「茶几纸条」文件夹里）" if on_table else ""


func unread_count() -> int:
	return int(travel.notes_state.get("unread", 0)) if travel.remote else unread().size()


func _on_table() -> bool:
	if travel.remote:
		return bool(travel.notes_state.get("on_table", false))
	return not unread().is_empty() or \
		Time.get_unix_time_from_system() - float(travel.data.get("note_left", 0.0)) < SHOW_MINE


func _refresh() -> void:
	var now := _on_table()
	if now != on_table:
		on_table = now
		changed.emit()


## The note's words: UTF-8, on one line, at most MAX_CHARS.
static func _text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_buffer(mini(f.get_length(), 65536)).get_string_from_utf8()
	var one := ""
	for l in s.trim_prefix("\ufeff").replace("\r", "").split("\n", false):
		l = l.strip_edges()
		if l != "":
			# Chinese lines join straight on; a space only between Latin words
			one += (" " if one != "" and one.unicode_at(one.length() - 1) < 0x2E80 else "") + l
	s = one
	return s.left(MAX_CHARS) + ("……" if s.length() > MAX_CHARS else "")
