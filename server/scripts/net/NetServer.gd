class_name NetServer
extends RefCounted
## WebSocket 服务端：TCPServer 监听 + 每连接一个 WebSocketPeer 状态机。
##
## 只做「连接生命周期 + 文本帧收发」，**不含任何玩法规则**，也不认识命令名。
## 由 ServerMain 在 `_process` 中驱动 `poll()`（headless 下不依赖节点树）。

signal client_connected(peer: WebSocketPeer)
signal client_disconnected(peer: WebSocketPeer, code: int, reason: String)
signal text_received(peer: WebSocketPeer, text: String)

var _tcp: TCPServer = null
var _peers: Array[WebSocketPeer] = []
var _announced: Dictionary = {}
var _port: int = 0


## 开始监听；返回 Error（非 OK 时调用方应以非零码退出）。
func listen(port: int, bind_address: String = Msg.DEFAULT_HOST) -> Error:
	_tcp = TCPServer.new()
	var error: Error = _tcp.listen(port, bind_address)
	if error != OK:
		_tcp = null
		return error
	_port = port
	return OK


func is_listening() -> bool:
	return _tcp != null and _tcp.is_listening()


func get_port() -> int:
	return _port


func get_peer_count() -> int:
	return _peers.size()


## 每帧调用一次：接受新连接 + 推进所有连接的状态机与收包。
func poll() -> void:
	if _tcp == null:
		return
	_accept_new_connections()
	_poll_peers()


## 关闭全部连接并停止监听。
func stop() -> void:
	for peer: WebSocketPeer in _peers:
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.close(1001, "server shutting down")
	_peers.clear()
	_announced.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null


## 发送一条 JSON 文本帧。JSON.stringify 产出紧凑 JSON，帧内不会出现裸换行。
func send_json(peer: WebSocketPeer, payload: Dictionary) -> void:
	send_text(peer, JSON.stringify(payload))


func send_text(peer: WebSocketPeer, text: String) -> void:
	if peer == null:
		return
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(text)


func _accept_new_connections() -> void:
	while _tcp.is_connection_available():
		var stream: StreamPeerTCP = _tcp.take_connection()
		if stream == null:
			continue
		var peer: WebSocketPeer = WebSocketPeer.new()
		# 缓冲上限必须在 accept_stream 之前设置，否则 view 快照帧会被静默丢弃。
		peer.inbound_buffer_size = Msg.FRAME_BUFFER_BYTES
		peer.outbound_buffer_size = Msg.FRAME_BUFFER_BYTES
		var error: Error = peer.accept_stream(stream)
		if error != OK:
			push_warning("[Server] websocket accept_stream failed: %s" % error_string(error))
			stream.disconnect_from_host()
			continue
		_peers.append(peer)


func _poll_peers() -> void:
	var alive: Array[WebSocketPeer] = []
	for peer: WebSocketPeer in _peers:
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				# 握手真正完成后才广播「已连接」，调用方据此发送 hello 首帧。
				if not _announced.has(peer):
					_announced[peer] = true
					client_connected.emit(peer)
				while peer.get_available_packet_count() > 0:
					var packet: PackedByteArray = peer.get_packet()
					if peer.was_string_packet():
						text_received.emit(peer, packet.get_string_from_utf8())
				alive.append(peer)
			WebSocketPeer.STATE_CLOSED:
				if _announced.has(peer):
					_announced.erase(peer)
				client_disconnected.emit(peer, peer.get_close_code(), peer.get_close_reason())
			_:
				# STATE_CONNECTING / STATE_CLOSING：继续等待
				alive.append(peer)
	_peers = alive
