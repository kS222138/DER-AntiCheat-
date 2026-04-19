extends RefCounted
class_name DEROfflineProtector

signal violation_cached(violation_type: String, data: Dictionary)
signal cached_violations_flushed(count: int)
signal network_restored()

enum StorageFormat {
	JSON,
	ENCRYPTED_JSON
}

@export var enabled: bool = true
@export var max_cache_size: int = 1000
@export var storage_format: StorageFormat = StorageFormat.ENCRYPTED_JSON
@export var encryption_key: String = ""
@export var auto_flush_on_reconnect: bool = true
@export var flush_interval: float = 60.0
@export var max_retry_count: int = 3
@export var retry_delay: float = 5.0
@export var test_url: String = "https://www.google.com"

var _cache: Array = []
var _pending_flush: Array = []
var _is_online: bool = true
var _last_network_check: float = 0.0
var _network_check_interval: float = 5.0
var _flush_timer: Timer = null
var _logger = null
var _started: bool = false
var _main_loop: MainLoop = null
var _flush_in_progress: bool = false
var _cache_file_path: String = "user://der_offline_cache.dat"
var _network_check_http: HTTPRequest = null
var _network_check_pending: bool = false
var _pending_requests: Array = []


func _init(logger = null):
	_logger = logger
	_main_loop = Engine.get_main_loop()
	_load_cache()


func start() -> void:
	if not enabled or _started:
		return
	_started = true
	_setup_flush_timer()
	_check_network_status_async()


func stop() -> void:
	if _flush_timer:
		_flush_timer.stop()
		_flush_timer.queue_free()
		_flush_timer = null
	if _network_check_http:
		_network_check_http.queue_free()
		_network_check_http = null
	for req in _pending_requests:
		if req is HTTPRequest:
			req.queue_free()
	_pending_requests.clear()
	_started = false


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop()
	elif not _started:
		start()


func cache_violation(violation_type: String, data: Dictionary) -> bool:
	if not enabled:
		return false
	
	if _cache.size() >= max_cache_size:
		if _logger and _logger.has_method("warning"):
			_logger.warning("DEROfflineProtector", "Cache full, dropping oldest violation")
		_cache.pop_front()
	
	var cached_item = {
		"type": violation_type,
		"data": data,
		"timestamp": Time.get_unix_time_from_system(),
		"retry_count": 0
	}
	
	_cache.append(cached_item)
	_save_cache()
	violation_cached.emit(violation_type, data)
	
	if _logger and _logger.has_method("info"):
		_logger.info("DEROfflineProtector", "Cached violation: %s" % violation_type)
	
	return true


func flush_cache() -> Dictionary:
	if not enabled:
		return {"success": false, "error": "Disabled"}
	
	if _flush_in_progress:
		return {"success": false, "error": "Flush already in progress"}
	
	if _cache.is_empty():
		return {"success": true, "flushed": 0, "failed": 0}
	
	_flush_in_progress = true
	var result = {
		"success": true,
		"flushed": 0,
		"failed": 0,
		"failed_items": []
	}
	
	_pending_flush = _cache.duplicate()
	_cache.clear()
	
	for item in _pending_flush:
		var success = _send_violation_async(item["type"], item["data"])
		if success:
			result["flushed"] += 1
		else:
			item["retry_count"] += 1
			if item["retry_count"] >= max_retry_count:
				result["failed"] += 1
				result["failed_items"].append(item)
				if _logger and _logger.has_method("warning"):
					_logger.warning("DEROfflineProtector", "Failed to send violation after %d retries" % max_retry_count)
			else:
				_cache.append(item)
	
	_pending_flush.clear()
	_save_cache()
	_flush_in_progress = false
	
	if result["flushed"] > 0:
		cached_violations_flushed.emit(result["flushed"])
	
	return result


func get_cached_count() -> int:
	return _cache.size()


func get_cached_violations() -> Array:
	return _cache.duplicate()


func clear_cache() -> void:
	_cache.clear()
	_pending_flush.clear()
	_save_cache()
	
	if _logger and _logger.has_method("info"):
		_logger.info("DEROfflineProtector", "Cache cleared")


func is_online() -> bool:
	return _is_online


func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"cached_count": _cache.size(),
		"pending_flush_count": _pending_flush.size(),
		"is_online": _is_online,
		"max_cache_size": max_cache_size,
		"storage_format": storage_format
	}


func _setup_flush_timer() -> void:
	if _flush_timer:
		return
	
	_flush_timer = Timer.new()
	_flush_timer.wait_time = flush_interval
	_flush_timer.autostart = true
	_flush_timer.timeout.connect(_on_flush_timer)
	
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(_flush_timer)


func _get_main_loop() -> MainLoop:
	if not _main_loop:
		_main_loop = Engine.get_main_loop()
	return _main_loop


func _on_flush_timer() -> void:
	if not enabled:
		return
	
	_check_network_status_async()
	
	if _is_online and auto_flush_on_reconnect and _cache.size() > 0:
		flush_cache()


func _check_network_status_async() -> void:
	if _network_check_pending:
		return
	
	var now = Time.get_ticks_msec()
	if now - _last_network_check < _network_check_interval * 1000:
		return
	
	_last_network_check = now
	
	var tree = _get_main_loop()
	if not tree or not tree.has_method("root"):
		_is_online = true
		return
	
	if _network_check_http:
		_network_check_http.queue_free()
	
	_network_check_http = HTTPRequest.new()
	tree.root.add_child(_network_check_http)
	_network_check_http.request_completed.connect(_on_network_check_completed)
	_network_check_pending = true
	
	var error = _network_check_http.request(test_url)
	if error != OK:
		_network_check_pending = false
		_is_online = false


func _on_network_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_network_check_pending = false
	var was_online = _is_online
	_is_online = (result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 400)
	
	if _network_check_http:
		_network_check_http.queue_free()
		_network_check_http = null
	
	if not was_online and _is_online:
		network_restored.emit()
		if auto_flush_on_reconnect:
			flush_cache()


func _send_violation_async(violation_type: String, data: Dictionary) -> bool:
	var tree = _get_main_loop()
	if not tree or not tree.has_method("root"):
		return false
	
	var http = HTTPRequest.new()
	tree.root.add_child(http)
	_pending_requests.append(http)
	
	var payload = {
		"type": violation_type,
		"data": data,
		"timestamp": Time.get_unix_time_from_system(),
		"client_id": OS.get_unique_id(),
		"game_version": ProjectSettings.get_setting("application/config/version", "1.0")
	}
	
	var body = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	
	var error = http.request("https://your-server.com/api/anticheat/violation", headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		_pending_requests.erase(http)
		http.queue_free()
		return false
	
	var success = false
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		success = (result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 400)
		_pending_requests.erase(http)
		http.queue_free()
	)
	
	return success


func _save_cache() -> void:
	if _cache.is_empty():
		if FileAccess.file_exists(_cache_file_path):
			DirAccess.remove_absolute(_cache_file_path)
		return
	
	var data = JSON.stringify(_cache)
	
	match storage_format:
		StorageFormat.ENCRYPTED_JSON:
			data = _encrypt_data(data)
	
	var file = FileAccess.open(_cache_file_path, FileAccess.WRITE)
	if file:
		file.store_string(data)
		file.close()


func _load_cache() -> void:
	if not FileAccess.file_exists(_cache_file_path):
		return
	
	var file = FileAccess.open(_cache_file_path, FileAccess.READ)
	if not file:
		return
	
	var data = file.get_as_text()
	file.close()
	
	match storage_format:
		StorageFormat.ENCRYPTED_JSON:
			data = _decrypt_data(data)
	
	var json = JSON.new()
	var error = json.parse(data)
	if error == OK and json.data is Array:
		_cache = json.data
		
		var valid_items = []
		for item in _cache:
			if item.has("type") and item.has("data") and item.has("timestamp"):
				valid_items.append(item)
		_cache = valid_items


func _encrypt_data(data: String) -> String:
	if encryption_key.is_empty():
		return data
	
	var key = encryption_key.md5_buffer()
	var iv = "DEROfflineProtector".md5_buffer()
	
	var encrypted = data.to_utf8_buffer()
	
	for i in range(encrypted.size()):
		encrypted[i] = encrypted[i] ^ key[i % key.size()] ^ iv[i % iv.size()]
	
	return Marshalls.raw_to_base64(encrypted)


func _decrypt_data(encrypted_base64: String) -> String:
	if encryption_key.is_empty():
		return encrypted_base64
	
	var encrypted = Marshalls.base64_to_raw(encrypted_base64)
	var key = encryption_key.md5_buffer()
	var iv = "DEROfflineProtector".md5_buffer()
	
	for i in range(encrypted.size()):
		encrypted[i] = encrypted[i] ^ key[i % key.size()] ^ iv[i % iv.size()]
	
	return encrypted.get_string_from_utf8()


func reset() -> void:
	clear_cache()


func cleanup() -> void:
	stop()
	if _flush_in_progress:
		var tree = _get_main_loop()
		if tree and tree.has_method("process_frame"):
			await tree.process_frame
	_save_cache()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DEROfflineProtector:
	var protector = DEROfflineProtector.new()
	for key in config:
		if key in protector:
			protector.set(key, config[key])
	
	node.tree_entered.connect(protector.start.bind())
	node.tree_exiting.connect(protector.cleanup.bind())
	
	return protector