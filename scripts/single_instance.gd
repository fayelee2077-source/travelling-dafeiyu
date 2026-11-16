class_name SingleInstance
extends Node
## Only one 《旅行的大肥鱼》 window at a time (11-16): the first window holds a port on this computer only
## (data port + 5, so test runs on other ports do not meet the real window); a second one opening finds it,
## asks the first to come to the front and quits. A port held by some other program (no greeting) is ignored.

const OFFSET := 5
const HELLO := "travelling-dafeiyu\n"

var _server := TCPServer.new()


## False when another window is already open (it has been asked to come to the front): quit then.
func claim() -> bool:
	if OS.has_feature("web") or OS.has_feature("android"):
		return true
	var port := Settings.data_port + OFFSET
	if _server.listen(port, "127.0.0.1") == OK:
		return true
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return true
	var until := Time.get_ticks_msec() + 800
	var got := ""
	while Time.get_ticks_msec() < until and got.length() < HELLO.length():
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0:
			got += peer.get_utf8_string(peer.get_available_bytes())
		elif peer.get_status() in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
			break
		OS.delay_msec(10)
	peer.disconnect_from_host()
	return not got.begins_with(HELLO)


func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		peer.put_data(HELLO.to_utf8_buffer())
		peer.disconnect_from_host()
		Settings.log_line("main: opened again, showing this window instead")
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_move_to_foreground()


func _exit_tree() -> void:
	_server.stop()
