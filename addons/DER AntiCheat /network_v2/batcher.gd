class_name DERBatchRequest
extends RefCounted

signal batch_sent(batch_id, count, saved)
signal batch_failed(batch_id, error)

enum BatchMode { IMMEDIATE, TIMER, COUNT, ADAPTIVE }

class BatchEntry:
	var id: int
	var path: String
	var data: Variant
	var cb: Callable
	var prio: int
	
	func _init(i: int, p: String, d, c: Callable, pri: int):
		id = i
		path = p
		data = d
		cb = c
		prio = pri

var _queue: Array = []
var _next_req: int = 0
var _next_batch: int = 0
var _mode: BatchMode = BatchMode.ADAPTIVE
var _max_size: int = 20
var _max_wait: int = 100
var _max_retry: int = 3
var _timeout: int = 5000
var _timer: SceneTreeTimer
var _tree: SceneTree
var _client
var _pending: Dictionary = {}
var _stats = {"sent": 0, "total": 0, "avg": 0.0, "saved": 0}

func _init(client, tree):
	_client = client
	_tree = tree

func set_mode(m: int) -> void:
	_mode = m

func add(path: String, data, cb: Callable = Callable(), prio: int = 0) -> int:
	_next_req += 1
	var entry = BatchEntry.new(_next_req, path, data, cb, prio)
	if _mode == BatchMode.IMMEDIATE:
		_client.send(path, data, cb)
	else:
		_queue.append(entry)
		_queue.sort_custom(func(a, b): return a.prio > b.prio)
		_flush_schedule()
	return _next_req

func flush() -> void:
	if _queue.is_empty(): return
	_send()

func _flush_schedule() -> void:
	if _mode == BatchMode.COUNT and _queue.size() >= _max_size:
		_send()
	elif _mode in [BatchMode.TIMER, BatchMode.ADAPTIVE] and not _timer:
		_timer = _tree.create_timer(_max_wait / 1000.0, false)
		_timer.timeout.connect(_send)

func _send() -> void:
	if _queue.is_empty(): return
	var batch = _queue.duplicate()
	_queue.clear()
	
	var data = []
	for e in batch:
		data.append({"id": e.id, "path": e.path, "data": e.data})
	
	var comp = _compress(data)
	var bid = _next_batch + 1
	_next_batch = bid
	
	_pending[bid] = {"batch": batch, "retry": 0, "time": Time.get_ticks_msec()}
	
	_client.send("/batch", {"batch_id": bid, "requests": comp.data, "compressed": comp.comp}, 
		func(succ, res): _on_response(succ, res, bid))
	
	var t = _tree.create_timer(_timeout / 1000.0, false)
	t.timeout.connect(func(): if _pending.has(bid): _on_response(false, {"error": "timeout"}, bid))

func _on_response(succ, res, bid) -> void:
	if not _pending.has(bid): return
	var p = _pending[bid]
	var batch = p.batch
	var retry = p.retry
	
	if not succ and retry < _max_retry:
		p.retry += 1
		for e in batch:
			_queue.append(e)
		_flush_schedule()
		return
	
	_pending.erase(bid)
	
	if not succ:
		batch_failed.emit(bid, str(res))
		for e in batch:
			if e.cb.is_valid(): e.cb.call(false, res)
		return
	
	var results = res.results if res is Dictionary and res.has("results") else {}
	var saved = res.bytes_saved if res is Dictionary else 0
	
	_stats.sent += 1
	_stats.total += batch.size()
	_stats.avg = (_stats.avg * (_stats.sent - 1) + batch.size()) / _stats.sent
	_stats.saved += saved
	
	batch_sent.emit(bid, batch.size(), saved)
	
	for e in batch:
		if e.cb.is_valid(): e.cb.call(true, results.get(e.id))

func _compress(data) -> Dictionary:
	var json = JSON.stringify(data)
	var raw = json.length()
	
	var bytes = json.to_utf8_buffer()
	var comp = bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	var csize = comp.size()
	
	if csize < raw * 0.7:
		return {"data": Marshalls.raw_to_base64(comp), "comp": true}
	return {"data": json, "comp": false}