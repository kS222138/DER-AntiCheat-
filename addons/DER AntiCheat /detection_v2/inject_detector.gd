class_name DERInjectDetector
extends RefCounted

enum InjectType {
	DLL_INJECT,
	CODE_HOOK,
	SCRIPT_INJECT,
	MEMORY_PATCH,
	FRAMEWORK_HOOK
}

enum DetectionLevel {
	LOW,
	MEDIUM,
	HIGH,
	CRITICAL
}

class InjectThreat:
	var type: InjectType
	var level: DetectionLevel
	var details: Dictionary
	var timestamp: int
	
	func _init(t: InjectType, l: DetectionLevel, d: Dictionary):
		type = t
		level = l
		details = d
		timestamp = Time.get_unix_time_from_system()
	
	func to_string() -> String:
		var type_str = ["DLL", "HOOK", "SCRIPT", "PATCH", "FRAME"][type]
		var level_str = ["LOW", "MEDIUM", "HIGH", "CRITICAL"][level]
		return "[%s] %s: %s" % [level_str, type_str, JSON.stringify(details)]
	
	func to_dict() -> Dictionary:
		return {
			"type": type,
			"type_name": ["DLL_INJECT", "CODE_HOOK", "SCRIPT_INJECT", "MEMORY_PATCH", "FRAMEWORK_HOOK"][type],
			"level": level,
			"level_name": ["LOW", "MEDIUM", "HIGH", "CRITICAL"][level],
			"details": details,
			"timestamp": timestamp
		}

const HEMOLOADER_PATTERNS = [
	"HemoLoader",
	"HemoHook",
	"install_script_hooks",
	"call_hook",
	"_hemo_original",
	"HemoLoaderStore",
	".script_backup"
]

const SUSPICIOUS_MODULES = [
	"cheatengine",
	"gameguardian",
	"frida",
	"xposed",
	"substrate",
	"zygisk",
	"magisk"
]

const SUSPICIOUS_PATHS = [
	"/data/local/tmp/",
	"/sdcard/Android/data/",
	"res://mods/",
	"res://addons/hemoloader/",
	"user://mods/"
]

var _logger: DERLogger
var _enabled: bool = true
var _scan_interval: float = 5.0
var _last_scan: int = 0
var _threats: Array[InjectThreat] = []
var _crypto: Crypto = Crypto.new()
var _code_hash: Dictionary = {}
var _whitelist: Array[String] = []
var _on_threat_detected: Callable
var _scan_timer: SceneTreeTimer
var _tree: SceneTree

func _init(logger: DERLogger = null):
	_logger = logger
	_calculate_code_hashes()

func set_enabled(enabled: bool) -> void:
	_enabled = enabled

func set_scan_interval(interval: float) -> void:
	_scan_interval = interval

func set_threat_callback(callback: Callable) -> void:
	_on_threat_detected = callback

func add_to_whitelist(pattern: String) -> void:
	_whitelist.append(pattern)

func start_continuous_scan(tree: SceneTree) -> void:
	_tree = tree
	_scan_continuous()

func stop_continuous_scan() -> void:
	if _scan_timer:
		_scan_timer = null

func scan() -> Array[InjectThreat]:
	if not _enabled:
		return []
	
	var threats: Array[InjectThreat] = []
	
	threats.append_array(_detect_dll_injection())
	threats.append_array(_detect_code_hooks())
	threats.append_array(_detect_script_injection())
	threats.append_array(_detect_memory_patches())
	threats.append_array(_detect_framework_hooks())
	
	for t in threats:
		if _is_whitelisted(t.details):
			continue
		_threats.append(t)
		if _logger:
			_logger.warning("inject", t.to_string())
		if _on_threat_detected:
			_on_threat_detected.call(t)
	
	return threats

func get_threats() -> Array[InjectThreat]:
	return _threats.duplicate()

func clear_threats() -> void:
	_threats.clear()

func verify_integrity() -> Dictionary:
	return {
		"current_hash": _hash_code_section(),
		"expected_hash": _code_hash.get("code_section", ""),
		"is_clean": _hash_code_section() == _code_hash.get("code_section", ""),
		"threat_count": _threats.size()
	}

func generate_report() -> String:
	var report = "Inject Detection Report\n"
	report += "========================================\n"
	report += "Total threats: " + str(_threats.size()) + "\n"
	
	var by_type = _count_by_type()
	if not by_type.is_empty():
		report += "\nBy type:\n"
		for t in by_type:
			report += "  " + t + ": " + str(by_type[t]) + "\n"
	
	var by_level = _count_by_level()
	if not by_level.is_empty():
		report += "\nBy level:\n"
		for l in by_level:
			report += "  " + l + ": " + str(by_level[l]) + "\n"
	
	return report

func get_stats() -> Dictionary:
	return {
		"total_threats": _threats.size(),
		"by_type": _count_by_type(),
		"by_level": _count_by_level(),
		"enabled": _enabled,
		"integrity": verify_integrity()
	}

func _scan_continuous() -> void:
	if not _enabled or not _tree:
		return
	scan()
	_scan_timer = _tree.create_timer(_scan_interval)
	await _scan_timer.timeout
	_scan_continuous()

func _detect_dll_injection() -> Array[InjectThreat]:
	var threats: Array[InjectThreat] = []
	
	if OS.has_feature("windows"):
		for module in SUSPICIOUS_MODULES:
			if _is_module_loaded(module):
				threats.append(InjectThreat.new(
					InjectType.DLL_INJECT,
					DetectionLevel.HIGH,
					{"module": module, "platform": "windows"}
				))
	
	if OS.has_feature("android"):
		var maps = _read_file("/proc/self/maps")
		if maps != "":
			for path in SUSPICIOUS_PATHS:
				if maps.find(path) != -1:
					threats.append(InjectThreat.new(
						InjectType.DLL_INJECT,
						DetectionLevel.HIGH,
						{"path": path, "platform": "android"}
					))
		else:
			threats.append(InjectThreat.new(
				InjectType.DLL_INJECT,
				DetectionLevel.MEDIUM,
				{"error": "Cannot read /proc/self/maps", "possible_hook": true}
			))
	
	return threats

func _detect_code_hooks() -> Array[InjectThreat]:
	var threats: Array[InjectThreat] = []
	
	var current_hash = _hash_code_section()
	var expected = _code_hash.get("code_section", "")
	if current_hash != expected and expected != "":
		threats.append(InjectThreat.new(
			InjectType.CODE_HOOK,
			DetectionLevel.CRITICAL,
			{"hash": current_hash, "expected": expected}
		))
	
	return threats

func _detect_script_injection() -> Array[InjectThreat]:
	var threats: Array[InjectThreat] = []
	
	var script_paths = _get_all_scripts_in_project()
	for path in script_paths:
		var content = _read_file(path)
		if content == "":
			continue
		for pattern in HEMOLOADER_PATTERNS:
			if content.find(pattern) != -1:
				threats.append(InjectThreat.new(
					InjectType.SCRIPT_INJECT,
					DetectionLevel.CRITICAL,
					{"pattern": pattern, "file": path, "tool": "HemoLoader"}
				))
	
	if Engine.has_singleton("HemoLoader"):
		threats.append(InjectThreat.new(
			InjectType.SCRIPT_INJECT,
			DetectionLevel.CRITICAL,
			{"singleton": "HemoLoader"}
		))
	
	return threats

func _detect_memory_patches() -> Array[InjectThreat]:
	var threats: Array[InjectThreat] = []
	
	var memory_info = OS.get_memory_info()
	if memory_info.has("dynamic") and memory_info.has("static"):
		if memory_info.dynamic > memory_info.static * 2:
			threats.append(InjectThreat.new(
				InjectType.MEMORY_PATCH,
				DetectionLevel.MEDIUM,
				{"dynamic": memory_info.dynamic, "static": memory_info.static}
			))
	
	return threats

func _detect_framework_hooks() -> Array[InjectThreat]:
	var threats: Array[InjectThreat] = []
	
	if OS.has_feature("android"):
		var props = _read_file("/system/build.prop")
		if props.find("ro.debuggable=1") != -1:
			threats.append(InjectThreat.new(
				InjectType.FRAMEWORK_HOOK,
				DetectionLevel.MEDIUM,
				{"prop": "ro.debuggable=1"}
			))
		
		if _check_xposed():
			threats.append(InjectThreat.new(
				InjectType.FRAMEWORK_HOOK,
				DetectionLevel.HIGH,
				{"framework": "Xposed"}
			))
		
		if _check_magisk():
			threats.append(InjectThreat.new(
				InjectType.FRAMEWORK_HOOK,
				DetectionLevel.MEDIUM,
				{"framework": "Magisk"}
			))
	
	return threats

func _is_module_loaded(module: String) -> bool:
	if not OS.has_feature("windows"):
		return false
	
	var output = []
	var exit_code = OS.execute("tasklist", ["/m", module], output)
	if exit_code == 0:
		for line in output:
			if line.to_lower().find(module.to_lower()) != -1:
				return true
	return false

func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	return file.get_as_text()

func _hash_code_section() -> String:
	var main_loop = Engine.get_main_loop()
	if main_loop:
		var script = main_loop.get_script()
		if script and script.resource_path != "":
			var file = FileAccess.open(script.resource_path, FileAccess.READ)
			if file:
				return file.get_as_text().sha256_text()
	
	var memory = OS.get_memory_info()
	var hash_str = str(memory.get("static", 0)) + str(memory.get("dynamic", 0))
	return hash_str.sha256_text()

func _calculate_code_hashes() -> void:
	_code_hash["code_section"] = _hash_code_section()
	_code_hash["timestamp"] = Time.get_unix_time_from_system()

func _get_all_scripts_in_project() -> Array:
	var scripts = []
	var dir = DirAccess.open("res://")
	_scan_scripts_recursive(dir, "", scripts)
	return scripts

func _scan_scripts_recursive(dir: DirAccess, path: String, result: Array) -> void:
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path = path + "/" + file_name
		if dir.current_is_dir():
			var sub_dir = DirAccess.open("res://" + full_path)
			if sub_dir:
				_scan_scripts_recursive(sub_dir, full_path, result)
		elif file_name.ends_with(".gd"):
			result.append("res://" + full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

func _check_xposed() -> bool:
	var paths = [
		"/data/data/de.robv.android.xposed.installer/",
		"/data/data/io.va.exposed/",
		"/system/framework/XposedBridge.jar"
	]
	for p in paths:
		if DirAccess.dir_exists_absolute(p) or FileAccess.file_exists(p):
			return true
	return false

func _check_magisk() -> bool:
	var paths = [
		"/data/adb/magisk/",
		"/sbin/.magisk/",
		"/data/adb/modules/"
	]
	for p in paths:
		if DirAccess.dir_exists_absolute(p):
			return true
	return false

func _is_whitelisted(details: Dictionary) -> bool:
	for pattern in _whitelist:
		if JSON.stringify(details).find(pattern) != -1:
			return true
	return false

func _count_by_type() -> Dictionary:
	var counts = {}
	for t in _threats:
		var name = ["DLL", "HOOK", "SCRIPT", "PATCH", "FRAME"][t.type]
		counts[name] = counts.get(name, 0) + 1
	return counts

func _count_by_level() -> Dictionary:
	var counts = {}
	for t in _threats:
		var name = ["LOW", "MEDIUM", "HIGH", "CRITICAL"][t.level]
		counts[name] = counts.get(name, 0) + 1
	return counts