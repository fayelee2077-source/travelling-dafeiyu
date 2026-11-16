class_name FrameLink
extends Node
## Finds the computer on the LAN, connects over TCP, pairs with the code, and passes on the JSON-line messages.
## Finding: the DSH plugin broadcasts a beacon, and we also broadcast a "where are you" probe that it answers
## by unicast (many tablets drop incoming broadcasts while their Wi-Fi saves power).
## Web version: the page comes from the plugin itself, so it connects back to where it came from over a
## WebSocket (the link the page was given, e.g. ws://<page host>/living-dock/link inside DSH), with the same
## pairing and messages; no finding.

signal linked(host_name: String)
signal unlinked(graceful: bool, reason: String)
signal message(msg: Dictionary)

const CONNECT_TIMEOUT := 4.0
const WELCOME_TIMEOUT := 5.0
const RX_TIMEOUT := 12.0       # the plugin pings every 5 s
const RETRY := 2.0
const DENIED_RETRY := 20.0
const PROBE_EVERY := 3.0
const FIND_PORT_OFFSET := 1     # plugin listens for probes on beacon port + 1

enum Status { NO_CODE, SEARCHING, CONNECTING, PAIRING, LINKED, DENIED }

var status := Status.SEARCHING
var host := ""
var host_name := ""
var welcome := {}               # the plugin's welcome (keeper: it keeps the home record; fresh: it has none yet)

var _udp := PacketPeerUDP.new()
var _peer: StreamPeerTCP
var _web := OS.has_feature("web")
var _ws: WebSocketPeer
var _port := 48960
var _buf := PackedByteArray()
var _clock := 0.0
var _since := 0.0
var _last_rx := 0.0
var _retry_at := 0.0
var _hello_sent := false
var _probe_at := 0.0


func _ready() -> void:
	_port = Settings.data_port
	if _web:
		restart()
		return
	var err := _udp.bind(Settings.beacon_port, "0.0.0.0")
	if err != OK:
		Settings.log_line("link: beacon bind failed (%d)" % err)
	# on Android this also takes the Wi-Fi multicast lock, without which most broadcasts are dropped
	_udp.set_broadcast_enabled(true)
	restart()


## Call after the pair code or host address changed.
func restart() -> void:
	_close(false, "restart", true)
	host = Settings.host_ip
	_retry_at = 0.0
	status = Status.NO_CODE if Settings.pair_code == "" else Status.SEARCHING


func status_text() -> String:
	match status:
		Status.NO_CODE: return "还没有配对码"
		Status.SEARCHING: return "正在找电脑…"
		Status.CONNECTING: return "正在连接 %s…" % host
		Status.PAIRING: return "正在配对…"
		Status.LINKED: return "已连接：%s" % (host_name if host_name != "" else host)
		Status.DENIED: return "配对码不对（%s）" % host
	return ""


func _process(delta: float) -> void:
	_clock += delta
	if _web:
		_process_web()
		return
	_read_beacons()
	if Settings.pair_code == "":
		return
	if status != Status.LINKED and Settings.host_ip == "" and _clock >= _probe_at:
		_probe_at = _clock + PROBE_EVERY
		_udp.set_dest_address("255.255.255.255", Settings.beacon_port + FIND_PORT_OFFSET)
		_udp.put_packet(JSON.stringify({"t": "living-dock-find"}).to_utf8_buffer())

	if _peer == null:
		if host != "" and _clock >= _retry_at:
			_peer = StreamPeerTCP.new()
			if _peer.connect_to_host(host, _port) != OK:
				_peer = null
				_retry_at = _clock + RETRY
				return
			status = Status.CONNECTING
			_since = _clock
			_hello_sent = false
			_buf.clear()
		return

	_peer.poll()
	var st := _peer.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING:
		if _clock - _since > CONNECT_TIMEOUT:
			_close(false, "connect timeout")
		return
	if st != StreamPeerTCP.STATUS_CONNECTED:
		_close(false, "socket closed")
		return

	if not _hello_sent:
		_hello_sent = true
		_peer.set_no_delay(true)
		status = Status.PAIRING
		_since = _clock
		_last_rx = _clock
		_send({"t": "hello", "code": Settings.pair_code})

	_read()
	if _peer == null:
		return
	if status == Status.PAIRING and _clock - _since > WELCOME_TIMEOUT:
		_close(false, "no welcome")
	elif status == Status.LINKED and _clock - _last_rx > RX_TIMEOUT:
		_close(false, "heartbeat timeout")


func _process_web() -> void:
	if Settings.pair_code == "" or host == "":
		return
	if _ws == null:
		if _clock < _retry_at:
			return
		_ws = WebSocketPeer.new()
		_ws.inbound_buffer_size = 8 << 20
		_ws.outbound_buffer_size = 8 << 20
		if _ws.connect_to_url(Settings.link_url if Settings.link_url != "" else "ws://%s/link" % host) != OK:
			_ws = null
			_retry_at = _clock + RETRY
			return
		status = Status.CONNECTING
		_since = _clock
		_hello_sent = false
		return

	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if _clock - _since > CONNECT_TIMEOUT:
				_close(false, "connect timeout")
			return
		WebSocketPeer.STATE_CLOSING:
			return
		WebSocketPeer.STATE_CLOSED:
			_close(false, "socket closed")
			return
	if not _hello_sent:
		_hello_sent = true
		status = Status.PAIRING
		_since = _clock
		_last_rx = _clock
		_send({"t": "hello", "code": Settings.pair_code})
	while _ws != null and _ws.get_available_packet_count() > 0:
		for line in _ws.get_packet().get_string_from_utf8().split("\n", false):
			_handle_line(line)
			if _ws == null:
				return
	if _ws == null:
		return
	if status == Status.PAIRING and _clock - _since > WELCOME_TIMEOUT:
		_close(false, "no welcome")
	elif status == Status.LINKED and _clock - _last_rx > RX_TIMEOUT:
		_close(false, "heartbeat timeout")


func _read_beacons() -> void:
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if not (d is Dictionary) or d.get("t") != "living-dock":
			continue
		if Settings.host_ip != "":
			continue
		var port := int(d.get("port", Settings.data_port))
		if ip != host or port != _port:
			if _peer == null or status != Status.LINKED:
				Settings.log_line("link: found computer %s (%s:%d)" % [d.get("name", "?"), ip, port])
				host = ip
				_port = port
				if status == Status.DENIED:
					_retry_at = 0.0


func _read() -> void:
	var n := _peer.get_available_bytes()
	if n <= 0:
		return
	var res: Array = _peer.get_data(n)
	if res[0] != OK:
		return
	_buf.append_array(res[1])
	if _buf.size() > 65536:
		_close(false, "line too long")
		return
	while true:
		var i := _buf.find(10)
		if i < 0:
			break
		var line := _buf.slice(0, i).get_string_from_utf8()
		_buf = _buf.slice(i + 1)
		_handle_line(line)
		if _peer == null:
			return


func _handle_line(line: String) -> void:
	line = line.strip_edges()
	if line == "":
		return
	var msg = JSON.parse_string(line)
	if not (msg is Dictionary):
		return
	_last_rx = _clock
	match msg.get("t"):
		"welcome":
			status = Status.LINKED
			welcome = msg
			host_name = str(msg.get("name", ""))
			Settings.log_line("link: linked to %s (%s)" % [host_name, host])
			linked.emit(host_name)
		"denied":
			Settings.log_line("link: pair code denied by %s" % host)
			_close(false, "denied")
			status = Status.DENIED
			_retry_at = _clock + DENIED_RETRY
		"bye":
			_close(true, "computer said bye")
		"ping":
			pass
		_:
			if status == Status.LINKED:
				message.emit(msg)


## A message to the plugin (answers to her DSH tools); dropped when not linked.
func send(msg: Dictionary) -> void:
	if (_peer or _ws) and status == Status.LINKED:
		_send(msg)


func _send(msg: Dictionary) -> void:
	if _ws:
		_ws.send_text(JSON.stringify(msg))
	else:
		_peer.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())


func _close(graceful: bool, reason: String, quiet := false) -> void:
	var was_linked := status == Status.LINKED
	if _peer:
		_peer.disconnect_from_host()
	_peer = null
	if _ws:
		_ws.close()
	_ws = null
	_buf.clear()
	_retry_at = _clock + RETRY
	if Settings.pair_code == "":
		status = Status.NO_CODE
	else:
		status = Status.SEARCHING if host == "" else Status.CONNECTING
	if was_linked and not quiet:
		Settings.log_line("link: lost (%s, %s)" % ["graceful" if graceful else "sudden", reason])
		unlinked.emit(graceful, reason)
	elif was_linked:
		unlinked.emit(graceful, reason)
