class_name DERMultiInstance
extends RefCounted

enum DetectionLevel {
	LOW,
	MEDIUM,
	HIGH,
	CRITICAL
}

enum DetectionMethod {
	PROCESS_LIST,
	FILE_LOCK,
	SOCKET,
	MUTEX,
	SHARED_MEMORY
}

class InstanceThreat:
	var method: DetectionMethod
	var level: DetectionLevel
	var details: Dictionary
	var timestamp: int
	
	func _init(m: DetectionMethod, l: DetectionLevel, d: Dictionary):
		method = m
		level = l
		details = d
		timestamp = Time.get_unix_time_from_system()
	
	func to_string() -> String:
		var method_str = ["PROCESS", "FILE", "SOCKET", "MUTEX", "MEMORY"][method]
		var level_str = ["LOW", "MEDIUM", "HIGH", "CRITICAL"][level]
		return "[%s] %s: %s" % [level_str, method_str, JSON.stringify(details)]
	
	func to_dict() -> Dictionary:
		return {
			"method": method,
			"method_name": ["PROCESS_LIST", "FILE_LOCK", "SOCKET", "MUTEX", "SHARED_MEMORY"][method],
			"level": level,
			"level_name": ["LOW", "MEDIUM", "HIGH", "CRITICAL"][level],
			"details": details,
			"timestamp": timestamp
		}

const LOCK_FILE_NAME = "der_anticheat.lock"
const DETECTION_PORT = 45123

var _logger: DERLogger
var _enabled: bool = true
var _scan_interval: float = 5.0
var _threats: Array[InstanceThreat] = []
var _instance_id: String
var _lock_file: FileAccess
var _allow_multi_instance: bool = false
var _on_threat_detected: Callable
var _scan_timer: SceneTreeTimer
var _tree: SceneTree
var _port_in_use_cache: bool = false
var _last_port_check: int = 0

func _init(logger: DERLogger = null):
	_logger = logger
	_instance_id = _generate_instance_id()
	_create_lock_file()

func _generate_instance_id() -> String:
	var timestamp = Time.get_unix_time_from_system()
	var pid = OS.get_process_id()
	var random = randi()
	return "%d_%d_%d" % [timestamp, pid, random]

func _create_lock_file() -> bool:
	var path = "user://" + LOCK_FILE_NAME
	
	if FileAccess.file_exists(path):
		var existing = _read_lock_file()
		if existing != "" and existing != _instance_id:
			return false
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(_instance_id)
	_lock_file = file
	return true

func _read_lock_file() -> String:
	var path = "user://" + LOCK_FILE_NAME
	if not FileAccess.file_exists(path):
		return ""
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	
	var content = file.get_as_text().strip_edges()
	file.close()
	return content

func set_enabled(enabled: bool) -> void:
	_enabled = enabled

func set_scan_interval(interval: float) -> void:
	_scan_interval = interval

func set_allow_multi_instance(allow: bool) -> void:
	_allow_multi_instance = allow

func set_threat_callback(callback: Callable) -> void:
	_on_threat_detected = callback

func start_continuous_scan(tree: SceneTree) -> void:
	_tree = tree
	_scan_continuous()

func stop_continuous_scan() -> void:
	_scan_timer = null

func is_single_instance() -> bool:
	if _allow_multi_instance:
		return true
	return not _has_other_instances()

func scan() -> Array[InstanceThreat]:
	if not _enabled or _allow_multi_instance:
		return []
	
	var threats: Array[InstanceThreat] = []
	
	threats.append_array(_detect_by_file_lock())
	threats.append_array(_detect_by_process_list())
	threats.append_array(_detect_by_socket())
	
	for t in threats:
		_threats.append(t)
		if _logger:
			_logger.warning("multi_instance", t.to_string())
		if _on_threat_detected:
			_on_threat_detected.call(t)
	
	return threats

func get_threats() -> Array[InstanceThreat]:
	return _threats.duplicate()

func clear_threats() -> void:
	_threats.clear()

func get_instance_count() -> int:
	var count = 0
	var process_name = OS.get_executable_path().get_file()
	
	if OS.has_feature("windows"):
		var output = []
		var exit_code = OS.execute("tasklist", ["/fi", "IMAGENAME eq " + process_name], output)
		if exit_code == 0:
			for line in output:
				if line.find(process_name) != -1:
					count += 1
			count -= 1
	
	elif OS.has_feature("linux") or OS.has_feature("macos"):
		var output = []
		var exit_code = OS.execute("pgrep", [process_name], output)
		if exit_code == 0:
			count = output.size()
	
	elif OS.has_feature("android"):
		var output = []
		var exit_code = OS.execute("ps", [], output)
		if exit_code == 0:
			for line in output:
				if line.find(process_name) != -1:
					count += 1
			count -= 1
	
	return max(0, count)

func get_stats() -> Dictionary:
	return {
		"total_threats": _threats.size(),
		"is_single_instance": is_single_instance(),
		"instance_count": get_instance_count(),
		"instance_id": _instance_id,
		"enabled": _enabled,
		"allow_multi_instance": _allow_multi_instance
	}

func generate_report() -> String:
	var report = "Multi Instance Detection Report\n"
	report += "========================================\n"
	report += "Total threats: " + str(_threats.size()) + "\n"
	report += "Single instance: " + str(is_single_instance()) + "\n"
	report += "Instance count: " + str(get_instance_count()) + "\n"
	report += "Instance ID: " + _instance_id + "\n"
	
	var by_method = _count_by_method()
	if not by_method.is_empty():
		report += "\nBy method:\n"
		for m in by_method:
			report += "  " + m + ": " + str(by_method[m]) + "\n"
	
	var by_level = _count_by_level()
	if not by_level.is_empty():
		report += "\nBy level:\n"
		for l in by_level:
			report += "  " + l + ": " + str(by_level[l]) + "\n"
	
	return report

func _scan_continuous() -> void:
	if not _enabled or not _tree or _allow_multi_instance:
		return
	scan()
	_scan_timer = _tree.create_timer(_scan_interval)
	await _scan_timer.timeout
	_scan_continuous()

func _has_other_instances() -> bool:
	return get_instance_count() > 1

func _detect_by_file_lock() -> Array[InstanceThreat]:
	var threats: Array[InstanceThreat] = []
	
	var existing_id = _read_lock_file()
	if existing_id != "" and existing_id != _instance_id:
		threats.append(InstanceThreat.new(
			DetectionMethod.FILE_LOCK,
			DetectionLevel.HIGH,
			{"existing_id": existing_id, "current_id": _instance_id}
		))
	
	return threats

func _detect_by_process_list() -> Array[InstanceThreat]:
	var threats: Array[InstanceThreat] = []
	
	var count = get_instance_count()
	if count > 1:
		threats.append(InstanceThreat.new(
			DetectionMethod.PROCESS_LIST,
			DetectionLevel.CRITICAL,
			{"count": count}
		))
	
	return threats

func _detect_by_socket() -> Array[InstanceThreat]:
	var threats: Array[InstanceThreat] = []
	
	if _is_port_in_use(DETECTION_PORT):
		threats.append(InstanceThreat.new(
			DetectionMethod.SOCKET,
			DetectionLevel.MEDIUM,
			{"port": DETECTION_PORT}
		))
	
	return threats

func _is_port_in_use(port: int) -> bool:
	var now = Time.get_ticks_msec()
	if now - _last_port_check < 5000:
		return _port_in_use_cache
	_last_port_check = now
	
	var in_use = false
	
	if OS.has_feature("windows"):
		var output = []
		var exit_code = OS.execute("netstat", ["-an"], output)
		if exit_code == 0:
			for line in output:
				if line.find(":" + str(port)) != -1 and line.find("LISTENING") != -1:
					in_use = true
					break
	
	elif OS.has_feature("linux") or OS.has_feature("macos"):
		var output = []
		var exit_code = OS.execute("lsof", ["-i", ":" + str(port)], output)
		if exit_code == 0:
			in_use = output.size() > 1
	
	_port_in_use_cache = in_use
	return in_use

func _count_by_method() -> Dictionary:
	var counts = {}
	for t in _threats:
		var name = ["PROCESS", "FILE", "SOCKET", "MUTEX", "MEMORY"][t.method]
		counts[name] = counts.get(name, 0) + 1
	return counts

func _count_by_level() -> Dictionary:
	var counts = {}
	for t in _threats:
		var name = ["LOW", "MEDIUM", "HIGH", "CRITICAL"][t.level]
		counts[name] = counts.get(name, 0) + 1
	return counts