extends RefCounted
class_name DEREncryptedLogger

signal log_written(level: String, message: String)
signal log_uploaded(success: bool, count: int)
signal encryption_key_rotated

enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR,
	CRITICAL
}

enum UploadMode {
	MANUAL,
	INTERVAL,
	ON_CRITICAL,
	BATCH
}

@export var enabled: bool = true
@export var log_level: LogLevel = LogLevel.INFO
@export var max_log_entries: int = 10000
@export var enable_encryption: bool = true
@export var enable_compression: bool = true
@export var log_storage_path: String = "user://der_logs.enc"
@export var upload_mode: UploadMode = UploadMode.INTERVAL
@export var upload_interval: float = 300.0
@export var upload_url: String = ""
@export var api_key: String = ""
@export var batch_size: int = 100
@export var max_retries: int = 3
@export var retry_delay: float = 5.0
@export var enable_device_fingerprint: bool = true
@export var enable_timestamp_encryption: bool = true
@export var auto_rotate_key: bool = true
@export var key_rotation_interval: float = 86400.0

var _logs: Array = []
var _pending_upload: Array = []
var _encryption_key: PackedByteArray = []
var _device_id: String = ""
var _session_id: String = ""
var _upload_timer: Timer = null
var _rotation_timer: Timer = null
var _crypto: Crypto = null
var _aes: AESContext = null
var _started: bool = false
var _main_loop: MainLoop = null
var _pending_uploads: Dictionary = {}


func _init():
	_main_loop = Engine.get_main_loop()
	_crypto = Crypto.new()
	_aes = AESContext.new()
	_generate_device_id()
	_generate_session_id()
	
	if enable_encryption:
		_generate_encryption_key()
	
	if enabled:
		_load_logs()


func start():
	if _started:
		return
	_started = true
	
	if upload_mode == UploadMode.INTERVAL and not upload_url.is_empty():
		_setup_upload_timer()
	
	if auto_rotate_key:
		_setup_rotation_timer()


func stop():
	if _upload_timer:
		_upload_timer.stop()
		_upload_timer.queue_free()
		_upload_timer = null
	if _rotation_timer:
		_rotation_timer.stop()
		_rotation_timer.queue_free()
		_rotation_timer = null
	_started = false


func _setup_upload_timer():
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	_upload_timer = Timer.new()
	_upload_timer.wait_time = upload_interval
	_upload_timer.autostart = true
	_upload_timer.timeout.connect(_upload_logs)
	tree.root.add_child(_upload_timer)


func _setup_rotation_timer():
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	_rotation_timer = Timer.new()
	_rotation_timer.wait_time = key_rotation_interval
	_rotation_timer.autostart = true
	_rotation_timer.timeout.connect(_rotate_encryption_key)
	tree.root.add_child(_rotation_timer)


func _generate_device_id():
	if not enable_device_fingerprint:
		_device_id = "unknown"
		return
	
	var fingerprint_data = {
		"os": OS.get_name(),
		"processor": OS.get_processor_count(),
		"screen": DisplayServer.screen_get_size(),
		"language": OS.get_locale()
	}
	
	var json = JSON.stringify(fingerprint_data)
	_device_id = json.sha256_text()


func _generate_session_id():
	_session_id = str(Time.get_unix_time_from_system()) + "_" + str(randi())


func _generate_encryption_key():
	_encryption_key = _crypto.generate_random_bytes(32)


func _rotate_encryption_key():
	_generate_encryption_key()
	encryption_key_rotated.emit()
	
	if auto_rotate_key:
		_save_logs()


func _get_timestamp() -> int:
	if enable_timestamp_encryption:
		var offset = randi() % 1000
		return Time.get_unix_time_from_system() ^ offset
	return Time.get_unix_time_from_system()


func debug(module: String, message: String, data: Dictionary = {}):
	if log_level <= LogLevel.DEBUG:
		_log(LogLevel.DEBUG, module, message, data)


func info(module: String, message: String, data: Dictionary = {}):
	if log_level <= LogLevel.INFO:
		_log(LogLevel.INFO, module, message, data)


func warning(module: String, message: String, data: Dictionary = {}):
	if log_level <= LogLevel.WARNING:
		_log(LogLevel.WARNING, module, message, data)


func error(module: String, message: String, data: Dictionary = {}):
	if log_level <= LogLevel.ERROR:
		_log(LogLevel.ERROR, module, message, data)


func critical(module: String, message: String, data: Dictionary = {}):
	if log_level <= LogLevel.CRITICAL:
		_log(LogLevel.CRITICAL, module, message, data)
		
		if upload_mode == UploadMode.ON_CRITICAL and not upload_url.is_empty():
			_upload_logs()


func _log(level: LogLevel, module: String, message: String, data: Dictionary):
	var entry = {
		"timestamp": _get_timestamp(),
		"level": level,
		"level_name": _get_level_name(level),
		"module": module,
		"message": message,
		"data": data,
		"session_id": _session_id,
		"device_id": _device_id
	}
	
	_logs.append(entry)
	log_written.emit(_get_level_name(level), message)
	
	while _logs.size() > max_log_entries:
		_logs.pop_front()
	
	if _logs.size() >= batch_size and upload_mode == UploadMode.BATCH:
		_upload_logs()
	
	_save_logs()


func _get_level_name(level: LogLevel) -> String:
	match level:
		LogLevel.DEBUG:
			return "DEBUG"
		LogLevel.INFO:
			return "INFO"
		LogLevel.WARNING:
			return "WARNING"
		LogLevel.ERROR:
			return "ERROR"
		LogLevel.CRITICAL:
			return "CRITICAL"
	return "UNKNOWN"


func _save_logs():
	if not enabled:
		return
	
	var data_to_save = _logs.duplicate()
	var processed_data = data_to_save
	
	if enable_compression:
		processed_data = _compress_data(processed_data)
	
	if enable_encryption:
		processed_data = _encrypt_data(processed_data)
	
	var file = FileAccess.open(log_storage_path, FileAccess.WRITE)
	if file:
		if processed_data is String:
			file.store_string(processed_data)
		elif processed_data is PackedByteArray:
			file.store_buffer(processed_data)
		file.close()


func _load_logs():
	if not FileAccess.file_exists(log_storage_path):
		return
	
	var file = FileAccess.open(log_storage_path, FileAccess.READ)
	if not file:
		return
	
	var raw_data = file.get_as_text() if file.get_length() < 1024 * 1024 else file.get_buffer(file.get_length())
	file.close()
	
	var processed_data = raw_data
	
	if enable_encryption:
		processed_data = _decrypt_data(processed_data)
	
	if enable_compression:
		processed_data = _decompress_data(processed_data)
	
	if processed_data is Array:
		_logs = processed_data


func _compress_data(data: Variant) -> Variant:
	var json = JSON.stringify(data)
	var bytes = json.to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(compressed)


func _decompress_data(data: Variant) -> Variant:
	var bytes = Marshalls.base64_to_raw(data)
	var decompressed = bytes.decompress(FileAccess.COMPRESSION_DEFLATE)
	var json = decompressed.get_string_from_utf8()
	return JSON.parse_string(json)


func _encrypt_data(data: Variant) -> Variant:
	var json = JSON.stringify(data)
	var bytes = json.to_utf8_buffer()
	
	_aes.start(AESContext.MODE_CBC_ENCRYPT, _encryption_key)
	var encrypted = _aes.update(bytes)
	_aes.finish()
	_aes.reset()
	
	return Marshalls.raw_to_base64(encrypted)


func _decrypt_data(data: Variant) -> Variant:
	var bytes = Marshalls.base64_to_raw(data)
	
	_aes.start(AESContext.MODE_CBC_DECRYPT, _encryption_key)
	var decrypted = _aes.update(bytes)
	_aes.finish()
	_aes.reset()
	
	var json = decrypted.get_string_from_utf8()
	return JSON.parse_string(json)


func _upload_logs():
	if _logs.is_empty():
		return
	
	if upload_url.is_empty():
		return
	
	_pending_upload = _logs.duplicate()
	_do_upload()


func _do_upload(retry_count: int = 0):
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	var http = HTTPRequest.new()
	http.timeout = 30.0
	tree.root.add_child(http)
	
	var upload_id = str(Time.get_ticks_msec()) + "_" + str(randi())
	_pending_uploads[upload_id] = {
		"http": http,
		"retry_count": retry_count,
		"data": _pending_upload
	}
	
	var payload = {
		"logs": _pending_upload,
		"device_id": _device_id,
		"session_id": _session_id,
		"timestamp": Time.get_unix_time_from_system(),
		"count": _pending_upload.size()
	}
	
	var body = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	if not api_key.is_empty():
		headers.append("X-API-Key: " + api_key)
	
	http.request_completed.connect(_on_upload_complete.bind(upload_id), CONNECT_ONE_SHOT)
	http.request(upload_url, headers, HTTPClient.METHOD_POST, body)


func _on_upload_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, upload_id: String):
	if not _pending_uploads.has(upload_id):
		return
	
	var upload_info = _pending_uploads[upload_id]
	var http = upload_info["http"]
	
	_pending_uploads.erase(upload_id)
	
	if is_instance_valid(http):
		http.queue_free()
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_clear_uploaded_logs(upload_info["data"])
		log_uploaded.emit(true, upload_info["data"].size())
	else:
		if upload_info["retry_count"] < max_retries:
			var tree = _main_loop
			if tree and tree.has_method("create_timer"):
				await tree.create_timer(retry_delay).timeout
				_do_upload(upload_info["retry_count"] + 1)
		else:
			log_uploaded.emit(false, 0)


func _clear_uploaded_logs(uploaded_logs: Array):
	var uploaded_hashes = []
	for log in uploaded_logs:
		var log_str = JSON.stringify(log)
		uploaded_hashes.append(log_str.sha256_text())
	
	var remaining_logs = []
	for log in _logs:
		var log_str = JSON.stringify(log)
		var hash = log_str.sha256_text()
		if hash not in uploaded_hashes:
			remaining_logs.append(log)
	
	_logs = remaining_logs
	_save_logs()


func get_logs(level: int = -1, module: String = "") -> Array:
	if level == -1 and module.is_empty():
		return _logs.duplicate()
	
	var filtered = []
	for log in _logs:
		if level != -1 and log["level"] != level:
			continue
		if not module.is_empty() and log["module"] != module:
			continue
		filtered.append(log)
	
	return filtered


func get_logs_by_time_range(start_time: int, end_time: int) -> Array:
	var filtered = []
	for log in _logs:
		var timestamp = log["timestamp"]
		if timestamp >= start_time and timestamp <= end_time:
			filtered.append(log)
	return filtered


func get_recent_logs(count: int) -> Array:
	return _logs.slice(-count)


func get_log_stats() -> Dictionary:
	var stats = {
		"total": _logs.size(),
		"by_level": {},
		"by_module": {},
		"oldest": null,
		"newest": null
	}
	
	for log in _logs:
		var level_name = log["level_name"]
		stats["by_level"][level_name] = stats["by_level"].get(level_name, 0) + 1
		
		var module = log["module"]
		stats["by_module"][module] = stats["by_module"].get(module, 0) + 1
	
	if not _logs.is_empty():
		stats["oldest"] = _logs[0]["timestamp"]
		stats["newest"] = _logs[-1]["timestamp"]
	
	return stats


func clear_logs():
	_logs.clear()
	_save_logs()


func force_upload():
	_upload_logs()


func rotate_key():
	_rotate_encryption_key()


func get_device_id() -> String:
	return _device_id


func get_session_id() -> String:
	return _session_id


func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"log_count": _logs.size(),
		"pending_upload": _pending_upload.size(),
		"encryption": enable_encryption,
		"compression": enable_compression,
		"upload_mode": upload_mode,
		"log_level": _get_level_name(log_level),
		"device_id": _device_id,
		"session_id": _session_id
	}


static func attach_to_node(node: Node, config: Dictionary = {}) -> DEREncryptedLogger:
	var logger = DEREncryptedLogger.new()
	for key in config:
		if key in logger:
			logger.set(key, config[key])
	
	node.tree_entered.connect(logger.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(logger.stop.bind())
	return logger