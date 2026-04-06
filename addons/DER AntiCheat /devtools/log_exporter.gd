extends Node
class_name DERLogExporter

enum ExportFormat { JSON, CSV, TXT }

@export var default_path: String = "user://anticheat_logs"
@export var use_timestamp: bool = true
@export var auto_export: bool = false
@export var auto_export_interval: float = 3600.0

var _logger = null
var _timer = null

signal export_completed(path, format)
signal export_failed(format, reason)

func _ready():
	if auto_export:
		_setup_timer()

func setup(logger):
	_logger = logger

func _setup_timer():
	_timer = Timer.new()
	_timer.wait_time = auto_export_interval
	_timer.autostart = true
	_timer.timeout.connect(_auto_export)
	add_child(_timer)

func _auto_export():
	export_logs(ExportFormat.JSON)

func export_logs(format = ExportFormat.JSON, path = ""):
	if _logger == null:
		export_failed.emit(format, "No logger set")
		return false
	
	var export_path = path
	if export_path.is_empty():
		export_path = default_path
	if use_timestamp:
		export_path = _get_timestamped_path(export_path)
	
	var logs = _get_logs()
	
	match format:
		ExportFormat.JSON:
			return _export_json(logs, export_path)
		ExportFormat.CSV:
			return _export_csv(logs, export_path)
		ExportFormat.TXT:
			return _export_txt(logs, export_path)
	return false

func _get_timestamped_path(base):
	return base + "_" + Time.get_datetime_string_from_system().replace(":", "-")

func _get_logs():
	if _logger.has_method("get_logs"):
		return _logger.get_logs()
	elif _logger.has_method("export"):
		var exported = _logger.export()
		return exported.get("logs", [])
	return []

func _csv_escape(str):
	if str.find(",") != -1 or str.find("\"") != -1 or str.find("\n") != -1:
		return "\"" + str.replace("\"", "\"\"") + "\""
	return str

func _export_json(logs, path):
	var data = {
		"timestamp": Time.get_datetime_string_from_system(),
		"total": logs.size(),
		"logs": logs
	}
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(path + ".json", FileAccess.WRITE)
	if not file:
		export_failed.emit(ExportFormat.JSON, "Cannot open file")
		return false
	file.store_string(json_str)
	file.close()
	export_completed.emit(path + ".json", ExportFormat.JSON)
	return true

func _export_csv(logs, path):
	var file = FileAccess.open(path + ".csv", FileAccess.WRITE)
	if not file:
		export_failed.emit(ExportFormat.CSV, "Cannot open file")
		return false
	
	file.store_line("Timestamp,Level,Type,Message")
	for log in logs:
		var timestamp = _csv_escape(log.get("timestamp", ""))
		var level = _csv_escape(log.get("level", "INFO"))
		var type = _csv_escape(log.get("type", ""))
		var message = _csv_escape(log.get("message", ""))
		file.store_line("%s,%s,%s,%s" % [timestamp, level, type, message])
	
	file.close()
	export_completed.emit(path + ".csv", ExportFormat.CSV)
	return true

func _export_txt(logs, path):
	var file = FileAccess.open(path + ".txt", FileAccess.WRITE)
	if not file:
		export_failed.emit(ExportFormat.TXT, "Cannot open file")
		return false
	
	var sep = "".lpad(60, "=")
	file.store_line(sep)
	file.store_line("DER AntiCheat Log Export")
	file.store_line("Generated: " + Time.get_datetime_string_from_system())
	file.store_line("Total Logs: " + str(logs.size()))
	file.store_line(sep)
	file.store_line("")
	
	for log in logs:
		var ts = log.get("timestamp", "Unknown")
		var lv = log.get("level", "INFO")
		var tp = log.get("type", "")
		var msg = log.get("message", "")
		file.store_line("[%s] [%s] %s: %s" % [ts, lv, tp, msg])
	
	file.store_line("")
	file.store_line(sep)
	file.store_line("End of Export")
	
	file.close()
	export_completed.emit(path + ".txt", ExportFormat.TXT)
	return true

func export_filtered(level = "", type = "", format = ExportFormat.JSON, path = ""):
	if _logger == null:
		export_failed.emit(format, "No logger set")
		return false
	
	var logs = _get_logs()
	var filtered = []
	for log in logs:
		if level != "" and log.get("level", "") != level:
			continue
		if type != "" and log.get("type", "") != type:
			continue
		filtered.append(log)
	
	var export_path = path
	if export_path.is_empty():
		export_path = default_path + "_filtered"
	if use_timestamp:
		export_path = _get_timestamped_path(export_path)
	
	match format:
		ExportFormat.JSON:
			return _export_json(filtered, export_path)
		ExportFormat.CSV:
			return _export_csv(filtered, export_path)
		ExportFormat.TXT:
			return _export_txt(filtered, export_path)
	return false

func export_recent(count = 100, format = ExportFormat.JSON, path = ""):
	if _logger == null:
		export_failed.emit(format, "No logger set")
		return false
	
	var logs = _get_logs()
	var recent = logs.slice(-count)
	
	var export_path = path
	if export_path.is_empty():
		export_path = default_path + "_recent"
	if use_timestamp:
		export_path = _get_timestamped_path(export_path)
	
	match format:
		ExportFormat.JSON:
			return _export_json(recent, export_path)
		ExportFormat.CSV:
			return _export_csv(recent, export_path)
		ExportFormat.TXT:
			return _export_txt(recent, export_path)
	return false

func get_log_stats():
	var logs = _get_logs()
	var stats = {"total": logs.size(), "by_level": {}, "by_type": {}}
	for log in logs:
		var lv = log.get("level", "UNKNOWN")
		var tp = log.get("type", "UNKNOWN")
		stats.by_level[lv] = stats.by_level.get(lv, 0) + 1
		stats.by_type[tp] = stats.by_type.get(tp, 0) + 1
	return stats