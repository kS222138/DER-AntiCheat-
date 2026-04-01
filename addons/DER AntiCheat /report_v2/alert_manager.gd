extends Node
class_name DERAlertManager

enum AlertLevel {
	INFO = 0,
	WARNING = 1,
	HIGH = 2,
	CRITICAL = 3
}

@export var enable_console: bool = true
@export var enable_file_log: bool = true
@export var enable_callback: bool = true
@export var enable_http: bool = false
@export var http_url: String = ""
@export var alert_cooldown: float = 5.0
@export var log_path: String = "user://anticheat_alerts.log"
@export var max_log_size_mb: float = 10.0

var _last_alert_time: Dictionary = {}
var _callback: Callable = Callable()
var _stats_cache: Dictionary = {
	"info": 0,
	"warning": 0,
	"high": 0,
	"critical": 0,
	"total": 0
}

signal alert_triggered(level: AlertLevel, message: String, data: Dictionary)

func set_callback(callback: Callable) -> void:
	_callback = callback

func alert(level: AlertLevel, message: String, data: Dictionary = {}) -> bool:
	var key = str(level) + message
	if _last_alert_time.has(key):
		if Time.get_unix_time_from_system() - _last_alert_time[key] < alert_cooldown:
			return false
	
	_last_alert_time[key] = Time.get_unix_time_from_system()
	_update_stats_cache(level)
	alert_triggered.emit(level, message, data)
	
	if enable_console:
		_console_alert(level, message, data)
	
	if enable_file_log:
		_file_alert(level, message, data)
	
	if enable_callback and _callback.is_valid():
		_callback.call(level, message, data)
	
	if enable_http and not http_url.is_empty():
		_http_alert(level, message, data)
	
	return true

func _console_alert(level: AlertLevel, message: String, data: Dictionary) -> void:
	var prefix = _get_prefix(level)
	print(prefix, message)
	if not data.is_empty():
		print("  Data: ", data)

func _file_alert(level: AlertLevel, message: String, data: Dictionary) -> void:
	var file = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	
	if file:
		if file.get_length() > max_log_size_mb * 1024 * 1024:
			_rotate_log()
			file = FileAccess.open(log_path, FileAccess.WRITE)
		
		file.seek_end()
		var timestamp = Time.get_datetime_string_from_system()
		var prefix = _get_prefix(level)
		file.store_line("%s [%s] %s" % [timestamp, prefix, message])
		if not data.is_empty():
			file.store_line("  Data: %s" % JSON.stringify(data))
		file.close()

func _rotate_log() -> void:
	var old_path = log_path + ".old"
	if FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(old_path)
	DirAccess.rename_absolute(log_path, old_path)

func _http_alert(level: AlertLevel, message: String, data: Dictionary) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	var body = JSON.stringify({
		"level": level,
		"level_name": _get_level_name(level),
		"message": message,
		"data": data,
		"timestamp": Time.get_unix_time_from_system()
	})
	var headers = ["Content-Type: application/json"]
	http.request(http_url, headers, HTTPClient.METHOD_POST, body)
	http.request_completed.connect(_on_http_complete.bind(http))

func _on_http_complete(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if result != OK or code != 200:
		push_warning("DERAlertManager: HTTP alert failed, code: %d" % code)
	http.queue_free()

func _get_prefix(level: AlertLevel) -> String:
	match level:
		AlertLevel.INFO:
			return "[INFO]"
		AlertLevel.WARNING:
			return "[WARNING]"
		AlertLevel.HIGH:
			return "[HIGH]"
		AlertLevel.CRITICAL:
			return "[CRITICAL]"
	return "[UNKNOWN]"

func _get_level_name(level: AlertLevel) -> String:
	match level:
		AlertLevel.INFO:
			return "INFO"
		AlertLevel.WARNING:
			return "WARNING"
		AlertLevel.HIGH:
			return "HIGH"
		AlertLevel.CRITICAL:
			return "CRITICAL"
	return "UNKNOWN"

func _update_stats_cache(level: AlertLevel) -> void:
	match level:
		AlertLevel.INFO:
			_stats_cache.info += 1
		AlertLevel.WARNING:
			_stats_cache.warning += 1
		AlertLevel.HIGH:
			_stats_cache.high += 1
		AlertLevel.CRITICAL:
			_stats_cache.critical += 1
	_stats_cache.total += 1

func get_logs() -> Array:
	var logs = []
	if not FileAccess.file_exists(log_path):
		return logs
	
	var file = FileAccess.open(log_path, FileAccess.READ)
	while not file.eof_reached():
		var line = file.get_line()
		if not line.is_empty():
			logs.append(line)
	file.close()
	return logs

func clear_logs() -> void:
	var file = FileAccess.open(log_path, FileAccess.WRITE)
	if file:
		file.store_string("")
		file.close()
	
	_stats_cache = {
		"info": 0,
		"warning": 0,
		"high": 0,
		"critical": 0,
		"total": 0
	}

func get_stats() -> Dictionary:
	return _stats_cache.duplicate()

func get_summary() -> Dictionary:
	return {
		"last_alerts": _last_alert_time,
		"stats": _stats_cache.duplicate(),
		"active_alert_types": _last_alert_time.size()
	}