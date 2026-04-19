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

var _logger = null
var _enabled: bool = true
var _scan_interval: float = 5.0
var _threats: Array[InstanceThreat] = []
var _instance_id: String
var _lock_file: FileAccess = null
var _allow_multi_instance: bool = false
var _on_threat_detected: Callable
var _scan_timer: Timer = null
var _tree: SceneTree = null
var _port_in_use_cache: bool = false
var _last_port_check: int = 0
var _is_scanning: bool = false


func _init(logger = null):
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
	file.close()
	_lock_file = null
	return true


func _release_lock_file() -> void:
	if _lock_file:
		_lock_file.close()
		_lock_file = null


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
	if _is_scanning:
		return
	_tree = tree
	_is_scanning = true
	_scan_continuous()


func stop_continuous_scan() -> void:
	_is_scanning = false
	if _scan_timer:
		_scan_timer.stop()
		_scan_timer.queue_free()
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
		if _logger and _logger.has_method("warning"):
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
	var process_path = OS.get_executable_path()
	var process_name = process_path.get_file()
	var process_full_name = process_name
	var process_base_name = process_name.replace(".exe", "").replace(".x86_64", "").replace(".x86", "")
	
	if OS.has_feature("windows"):
		var output = []
		var exit_code = OS.execute("tasklist", ["/fo", "csv", "/nh"], output)
		if exit_code == 0:
			for line in output:
				var lower_line = line.to_lower()
				var lower_name = process_name.to_lower()
				if lower_line.find(lower_name) != -1:
					var parts = line.split(",")
					if parts.size() > 0:
						var task_name = parts[0].replace('"', "").strip_edges()
						if task_name.to_lower() == lower_name:
							count += 1
	
	elif OS.has_feature("linux") or OS.has_feature("macos"):
		var output = []
		var exit_code = OS.execute("pgrep", ["-x", process_name], output)
		if exit_code == 0:
			for line in output:
				var pid = line.strip_edges()
				if pid != "" and pid != str(OS.get_process_id()):
					count += 1
	
	elif OS.has_feature("android"):
		var output = []
		var package_name = OS.get_environment("PACKAGE_NAME")
		if package_name == "":
			package_name = OS.get_executable_path().get_file()
		var exit_code = OS.execute("ps", [], output)
		if exit_code == 0:
			for line in output:
				if line.find(package_name) != -1 and line.find(":") == -1:
					var parts = line.strip_edges().split(" ")
					var pid = parts[0] if parts.size() > 0 else ""
					if pid != "" and pid != str(OS.get_process_id()):
						count += 1
	
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
	if not _is_scanning or not _enabled or not _tree or _allow_multi_instance:
		_is_scanning = false
		return
	
	scan()
	
	_scan_timer = Timer.new()
	_scan_timer.wait_time = _scan_interval
	_scan_timer.one_shot = true
	_scan_timer.timeout.connect(_on_scan_timeout)
	
	if _tree.root:
		_tree.root.add_child(_scan_timer)
		_scan_timer.start()


func _on_scan_timeout() -> void:
	if _scan_timer:
		_scan_timer.queue_free()
		_scan_timer = null
	_scan_continuous()


func _has_other_instances() -> bool:
	return get_instance_count() > 0


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
	if count > 0:
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
		var exit_code = OS.execute("ss", ["-l", "-n", "-t"], output)
		if exit_code != 0:
			exit_code = OS.execute("netstat", ["-l", "-n", "-t"], output)
		if exit_code == 0:
			for line in output:
				if line.find(":" + str(port)) != -1:
					in_use = true
					break
	
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


func cleanup() -> void:
	stop_continuous_scan()
	_release_lock_file()
	var path = "user://" + LOCK_FILE_NAME
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERMultiInstance:
	var detector = DERMultiInstance.new()
	for key in config:
		if key in detector:
			detector.set(key, config[key])
	
	node.tree_entered.connect(func():
		if node.get_tree():
			detector.start_continuous_scan(node.get_tree())
	)
	node.tree_exiting.connect(detector.cleanup.bind())
	
	return detector