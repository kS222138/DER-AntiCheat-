extends Node
class_name DERCloudValidator

enum ValidationMode { ON_LOAD, ON_SAVE, PERIODIC, MANUAL }

@export var mode: ValidationMode = ValidationMode.PERIODIC
@export var check_interval: float = 60.0
@export var auto_repair: bool = false
@export var strict_mode: bool = false
@export var timeout: float = 5.0
@export var max_retries: int = 3
@export var retry_delay: float = 1.0
@export var offline_mode: bool = false

var _cloud_server: String = ""
var _client_id: String = ""
var _last_check_time: float = 0.0
var _timer: Timer
var _cache: Dictionary = {}
var _pending_requests: Array = []
var _retry_count: Dictionary = {}
var _archive_manager: Node = null
var _last_online_check: float = 0.0
var _is_online: bool = true

signal validation_passed(slot: int)
signal validation_failed(slot: int, reason: String)
signal conflict_detected(local_hash: String, cloud_hash: String)
signal auto_repaired(slot: int)

func _init(server_url: String = "", client_id: String = "", archive_mgr: Node = null):
	_cloud_server = server_url
	_client_id = client_id
	_archive_manager = archive_mgr
	if mode == ValidationMode.PERIODIC:
		_setup_timer()

func set_server(server_url: String) -> void:
	_cloud_server = server_url

func set_client_id(client_id: String) -> void:
	_client_id = client_id

func set_archive_manager(archive_mgr: Node) -> void:
	_archive_manager = archive_mgr

func add_to_cache(slot: int, hash: String) -> void:
	_cache[slot] = hash

func is_online() -> bool:
	if offline_mode:
		return false
	if _cloud_server.is_empty():
		return false
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_online_check > 30.0:
		_last_online_check = now
		_check_online_status()
	return _is_online

func _check_online_status() -> void:
	var request = HTTPRequest.new()
	add_child(request)
	request.timeout = 3.0
	var url = _cloud_server + "/api/ping"
	request.request_completed.connect(_on_ping_complete.bind(request))
	request.request(url)

func _on_ping_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	_is_online = response_code == 200
	request.queue_free()

func validate(slot: int, local_data: Variant, callback: Callable = Callable()) -> bool:
	if not is_online():
		validation_passed.emit(slot)
		if callback.is_valid(): callback.call(true, "")
		return true
	
	var local_hash = _compute_hash(local_data)
	
	if _cache.get(slot) == local_hash:
		validation_passed.emit(slot)
		if callback.is_valid(): callback.call(true, "")
		return true
	
	_send_validation_request(slot, local_data, callback, local_hash)
	return true

func _send_validation_request(slot: int, local_data: Variant, callback: Callable, local_hash: String) -> void:
	var request = HTTPRequest.new()
	_pending_requests.append(request)
	add_child(request)
	request.timeout = timeout
	
	var url = _cloud_server + "/api/validate"
	var body = JSON.stringify({
		"client_id": _client_id,
		"slot": slot,
		"hash": local_hash,
		"timestamp": Time.get_unix_time_from_system()
	})
	var headers = ["Content-Type: application/json"]
	var err = request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if err != OK:
		_cleanup_request(request)
		validation_failed.emit(slot, "HTTP request failed")
		if callback.is_valid(): callback.call(false, "HTTP request failed")
		return
	
	request.request_completed.connect(_on_validation_complete.bind(slot, local_data, callback, request, local_hash))

func upload(slot: int, local_data: Variant, callback: Callable = Callable()) -> bool:
	if not is_online():
		return false
	
	var request = HTTPRequest.new()
	_pending_requests.append(request)
	add_child(request)
	request.timeout = timeout
	
	var local_hash = _compute_hash(local_data)
	var url = _cloud_server + "/api/upload"
	var body = JSON.stringify({
		"client_id": _client_id,
		"slot": slot,
		"hash": local_hash,
		"data": _serialize(local_data),
		"timestamp": Time.get_unix_time_from_system()
	})
	var headers = ["Content-Type: application/json"]
	var err = request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if err != OK:
		_cleanup_request(request)
		return false
	
	request.request_completed.connect(_on_upload_complete.bind(slot, callback, request))
	return true

func fetch_cloud_hash(slot: int, callback: Callable) -> bool:
	if not is_online():
		if callback.is_valid(): callback.call("", false)
		return false
	
	var request = HTTPRequest.new()
	_pending_requests.append(request)
	add_child(request)
	request.timeout = timeout
	
	var url = _cloud_server + "/api/hash?client_id=%s&slot=%d" % [_client_id, slot]
	var err = request.request(url, [], HTTPClient.METHOD_GET)
	
	if err != OK:
		_cleanup_request(request)
		return false
	
	request.request_completed.connect(_on_fetch_complete.bind(slot, callback, request))
	return true

func validate_batch(slots: Array, data_map: Dictionary, callback: Callable = Callable()) -> void:
	var results = {}
	var pending = slots.size()
	
	if pending == 0:
		if callback.is_valid(): callback.call(results)
		return
	
	for slot in slots:
		validate(slot, data_map[slot], func(success, reason):
			results[slot] = success
			pending -= 1
			if pending == 0:
				if callback.is_valid(): callback.call(results)
		)

func _on_validation_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, slot: int, local_data: Variant, callback: Callable, request: HTTPRequest, local_hash: String) -> void:
	_cleanup_request(request)
	
	var retry_key = "slot_%d" % slot
	var retries = _retry_count.get(retry_key, 0)
	
	if response_code != 200:
		if retries < max_retries:
			_retry_count[retry_key] = retries + 1
			await get_tree().create_timer(retry_delay).timeout
			_send_validation_request(slot, local_data, callback, local_hash)
		else:
			_retry_count.erase(retry_key)
			validation_failed.emit(slot, "Server error: %d" % response_code)
			if callback.is_valid(): callback.call(false, "Server error")
		return
	
	_retry_count.erase(retry_key)
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		validation_failed.emit(slot, "Invalid server response")
		if callback.is_valid(): callback.call(false, "Invalid server response")
		return
	
	var cloud_hash = json.get("hash", "")
	var valid = json.get("valid", false)
	
	if not valid:
		conflict_detected.emit(local_hash, cloud_hash)
		validation_failed.emit(slot, "Hash mismatch")
		if auto_repair and strict_mode:
			var cloud_data = json.get("data", null)
			if cloud_data != null:
				_repair_local(slot, cloud_data)
		if callback.is_valid(): callback.call(false, "Hash mismatch")
		return
	
	_cache[slot] = local_hash
	validation_passed.emit(slot)
	if callback.is_valid(): callback.call(true, "")

func _on_upload_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, slot: int, callback: Callable, request: HTTPRequest) -> void:
	_cleanup_request(request)
	if callback.is_valid():
		callback.call(response_code == 200)

func _on_fetch_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, slot: int, callback: Callable, request: HTTPRequest) -> void:
	_cleanup_request(request)
	if response_code != 200:
		if callback.is_valid(): callback.call("", false)
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		if callback.is_valid(): callback.call("", false)
		return
	
	if callback.is_valid(): callback.call(json.get("hash", ""), true)

func _repair_local(slot: int, cloud_data: Variant) -> void:
	if _archive_manager and _archive_manager.has_method("save"):
		_archive_manager.save(slot, cloud_data)
		auto_repaired.emit(slot)

func _compute_hash(data: Variant) -> String:
	var json = JSON.stringify(data)
	var bytes = json.to_utf8_buffer()
	return bytes.sha256_text()

func _serialize(data: Variant) -> String:
	return JSON.stringify(data)

func _cleanup_request(request: HTTPRequest) -> void:
	if request in _pending_requests:
		_pending_requests.erase(request)
	if is_instance_valid(request):
		request.queue_free()

func _setup_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = check_interval
	_timer.autostart = true
	_timer.timeout.connect(_periodic_check)
	add_child(_timer)

func _periodic_check() -> void:
	if mode != ValidationMode.PERIODIC or not is_online():
		return
	
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_check_time >= check_interval:
		_last_check_time = now
		_trigger_periodic_validation()

func _trigger_periodic_validation() -> void:
	pass

func get_cached_hash(slot: int) -> String:
	return _cache.get(slot, "")

func clear_cache() -> void:
	_cache.clear()

func get_pending_count() -> int:
	return _pending_requests.size()

func get_stats() -> Dictionary:
	return {
		pending_requests = _pending_requests.size(),
		cached_slots = _cache.size(),
		offline_mode = offline_mode,
		online = _is_online,
		server = _cloud_server,
		client_id = _client_id
	}