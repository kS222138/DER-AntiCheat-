class_name DERRequestQueue
extends RefCounted

signal request_queued(id)
signal request_sent(id)
signal request_failed(id, error)

enum Priority { LOW, NORMAL, HIGH, CRITICAL }

class Request:
	var id: int
	var path: String
	var data: Variant
	var callback: Callable
	var priority: int
	var retry: int
	var max_retry: int
	var timestamp: int
	var timeout_timer: SceneTreeTimer
	
	func _init(i: int, p: String, d, cb: Callable, pri: int, retry_max: int = 3):
		id = i
		path = p
		data = d
		callback = cb
		priority = pri
		retry = 0
		max_retry = retry_max
		timestamp = Time.get_ticks_msec()

var _client
var _tree: SceneTree
var _queue: Array = []
var _pending: Dictionary = {}
var _next_id: int = 0
var _sending: int = 0
var _max_concurrent: int = 3
var _timeout: float = 10.0
var _deduplicate: bool = false
var _stats = {"queued": 0, "sent": 0, "failed": 0, "retried": 0}

func _init(client, tree: SceneTree):
	_client = client
	_tree = tree

func set_max_concurrent(max: int) -> void:
	_max_concurrent = max

func set_timeout(sec: float) -> void:
	_timeout = sec

func set_deduplicate(enabled: bool) -> void:
	_deduplicate = enabled

func add(path: String, data, callback: Callable = Callable(), priority: int = Priority.NORMAL, max_retry: int = 3) -> int:
	if _deduplicate:
		for req in _queue:
			if req.path == path and req.data == data:
				return req.id
		for req in _pending.values():
			if req.path == path and req.data == data:
				return req.id
	
	_next_id += 1
	var req = Request.new(_next_id, path, data, callback, priority, max_retry)
	_queue.append(req)
	_queue.sort_custom(func(a, b): return a.priority > b.priority)
	_stats.queued += 1
	request_queued.emit(_next_id)
	_process()
	return _next_id

func cancel(id: int) -> bool:
	for i in range(_queue.size()):
		if _queue[i].id == id:
			_queue.remove_at(i)
			return true
	if _pending.has(id):
		if _pending[id].timeout_timer:
			_pending[id].timeout_timer = null
		_pending.erase(id)
		return true
	return false

func cancel_all() -> void:
	_queue.clear()
	for id in _pending:
		if _pending[id].timeout_timer:
			_pending[id].timeout_timer = null
	_pending.clear()

func flush() -> void:
	_process()

func get_stats() -> Dictionary:
	return _stats.duplicate()

func get_pending_count() -> int:
	return _queue.size() + _pending.size()

func wait_for_empty(timeout: float = 5.0) -> bool:
	var start = Time.get_ticks_msec()
	while get_pending_count() > 0:
		if Time.get_ticks_msec() - start > timeout * 1000:
			return false
		await _tree.process_frame
	return true

func _process() -> void:
	while _sending < _max_concurrent and not _queue.is_empty():
		_send_one()

func _send_one() -> void:
	var req = _queue.pop_front()
	_sending += 1
	_pending[req.id] = req
	
	req.timeout_timer = _tree.create_timer(_timeout, false)
	req.timeout_timer.timeout.connect(_on_timeout.bind(req.id))
	
	_client.send(req.path, req.data, func(success, response):
		req.timeout_timer = null
		_sending -= 1
		_on_response(success, response, req)
	)
	request_sent.emit(req.id)

func _on_timeout(id: int) -> void:
	if _pending.has(id):
		var req = _pending[id]
		_pending.erase(id)
		_sending -= 1
		_on_response(false, {"error": "timeout"}, req)

func _on_response(success, response, req: Request) -> void:
	_pending.erase(req.id)
	
	if success:
		_stats.sent += 1
		if req.callback.is_valid():
			req.callback.call(true, response)
	else:
		if req.retry < req.max_retry:
			req.retry += 1
			_stats.retried += 1
			_queue.append(req)
			_queue.sort_custom(func(a, b): return a.priority > b.priority)
		else:
			_stats.failed += 1
			request_failed.emit(req.id, str(response))
			if req.callback.is_valid():
				req.callback.call(false, response)
	
	_process()