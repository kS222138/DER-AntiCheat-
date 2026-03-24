class_name DERHeartbeat
extends RefCounted

signal sent()
signal failed(err)
signal lost()
signal restored()

enum State { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, OFFLINE }

var _client
var _tree
var _interval: float = 30.0
var _timeout: float = 10.0
var _max_retry: int = 5
var _retry: int = 0
var _state: int = State.DISCONNECTED
var _timer: SceneTreeTimer
var _pending: bool = false
var _offline: bool = false
var _queue: Array = []
var _stats = {"sent": 0, "fail": 0, "lost": 0, "restore": 0}

func _init(client, tree):
	_client = client
	_tree = tree

func start() -> void:
	_state = State.CONNECTING
	_send()

func stop() -> void:
	if _timer: _timer = null
	_state = State.DISCONNECTED

func is_online() -> bool:
	return _state == State.CONNECTED

func set_offline(e: bool) -> void:
	_offline = e
	if not e and not _queue.is_empty():
		for r in _queue:
			_client.send(r.path, r.data, r.cb)
		_queue.clear()

func add(path: String, data, cb: Callable = Callable()) -> void:
	if _queue.size() < 1000:
		_queue.append({"path": path, "data": data, "cb": cb})

func _send() -> void:
	if _pending or _offline:
		return
	_pending = true
	
	_client.send("/heartbeat", {"ts": Time.get_unix_time_from_system()}, func(s, r):
		_pending = false
		_on_resp(s, r)
	)
	
	var t = _tree.create_timer(_timeout, false)
	t.timeout.connect(func(): if _pending: _pending = false; _on_resp(false, "timeout"))

func _on_resp(success, resp) -> void:
	if success:
		_stats.sent += 1
		_retry = 0
		if _state == State.CONNECTING or _state == State.RECONNECTING:
			_state = State.CONNECTED
			if _state == State.RECONNECTING:
				_stats.restore += 1
				restored.emit()
		_schedule()
	else:
		_stats.fail += 1
		_retry += 1
		if _state == State.CONNECTED:
			_state = State.RECONNECTING
			_stats.lost += 1
			lost.emit()
		
		if _retry <= _max_retry:
			var delay = min(_interval, 5.0) * (1 + _retry * 0.5)
			var t = _tree.create_timer(delay, false)
			t.timeout.connect(_send)
		else:
			_state = State.DISCONNECTED
			failed.emit(str(resp))

func _schedule() -> void:
	if _timer: _timer = null
	_timer = _tree.create_timer(_interval, false)
	_timer.timeout.connect(_on_timer)

func _on_timer() -> void:
	if _offline or _pending:
		return
	_send()