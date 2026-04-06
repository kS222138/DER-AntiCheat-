class_name VanguardCore
extends RefCounted

static var _instance: VanguardCore
static var _values: Dictionary = {}
static var _config: Dictionary = {}
static var _report_system
static var _initialized: bool = false
static var _threat_log: Array = []

static var _hemoloader_detected: bool = false
static var _hemoloader_check_done: bool = false
static var _is_editor: bool = false

const HEMOLOADER_MARKERS = [
	"HemoLoader Hook",
	"var _hemo_loader",
	"_hemo_original_",
	"call_hook",
	".script_backup/",
	"HemoHookGenerator",
    "HemoLoaderStore"
]

signal cheat_detected(value_id: String, cheat_type: int, confidence: float)
signal value_registered(value_id: String)
signal value_unregistered(value_id: String)
signal threat_reported(threat_type: String, data: Dictionary)

func _init():
	if _instance == null:
		_instance = self
		_initialize()

static func _initialize():
	if _initialized:
		return
	
	_is_editor = Engine.is_editor_hint() or OS.has_feature("editor")
	
	_report_system = preload("../report/logger.gd").new()
	_initialized = true
	
	_check_hemoloader()
	
	_report_system.info("core", "VanguardCore initialized")

static func _check_hemoloader() -> void:
	if _hemoloader_check_done:
		return
	
	var detected = false
	var details = {}
	
	if Engine.has_singleton("HemoLoader"):
		detected = true
		details["singleton"] = true
	
	if DirAccess.dir_exists_absolute("res://addons/hemoloader/"):
		detected = true
		details["addon_folder"] = "res://addons/hemoloader/"
	
	if DirAccess.dir_exists_absolute("res://mods/"):
		var dir = DirAccess.open("res://mods/")
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			var mod_count = 0
			while file_name != "":
				if dir.current_is_dir() and not file_name.begins_with("."):
					mod_count += 1
				file_name = dir.get_next()
			dir.list_dir_end()
			if mod_count > 0:
				detected = true
				details["mods_present"] = mod_count
	
	var hooked_scripts = _scan_for_hooked_scripts()
	if not hooked_scripts.is_empty():
		detected = true
		details["hooked_scripts"] = hooked_scripts
	
	_hemoloader_detected = detected
	_hemoloader_check_done = true
	
	if detected:
		var message = "HemoLoader detected"
		if _is_editor:
			_report_system.warning("core", message + " (editor mode - monitoring only)")
		else:
			_report_system.warning("core", message + " - enabling runtime protection")
			report("HIGH", "HEMOLOADER_DETECTED", details)

static func _scan_for_hooked_scripts() -> Array:
	var hooked = []
	var paths_to_check = [
		"res://addons/DER_Protection_System/core/",
        "res://addons/DER_Protection_System/detection/"
	]
	
	for base_path in paths_to_check:
		if not DirAccess.dir_exists_absolute(base_path):
			continue
		
		var dir = DirAccess.open(base_path)
		if not dir:
			continue
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".gd"):
				var full_path = base_path + file_name
				if _check_script_for_hooks(full_path):
					hooked.append(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	return hooked

static func _check_script_for_hooks(script_path: String) -> bool:
	if not FileAccess.file_exists(script_path):
		return false
	
	var file = FileAccess.open(script_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	for marker in HEMOLOADER_MARKERS:
		if content.contains(marker):
			return true
	
	return false

static func register(value_id: String, value: VanguardValue) -> void:
	if not _initialized:
		_initialize()
	_values[value_id] = {
		"value": value,
		"created": Time.get_ticks_usec(),
		"last_check": Time.get_ticks_usec(),
		"alerts": 0
	}
	_instance.value_registered.emit(value_id)

static func unregister(value_id: String) -> void:
	if _values.has(value_id):
		_values.erase(value_id)
		_instance.value_unregistered.emit(value_id)

static func report(level: String, threat_type: String, data: Dictionary) -> void:
	var report_entry = {
		"time": Time.get_datetime_string_from_system(),
		"timestamp": Time.get_unix_time_from_system(),
		"level": level,
		"type": threat_type,
		"data": data
	}
	
	_threat_log.append(report_entry)
	if _threat_log.size() > 1000:
		_threat_log.pop_front()
	
	_report_system.log(level, "core", threat_type, data)
	_instance.threat_reported.emit(threat_type, data)
	
	if (level == "CRITICAL" or level == "HIGH") and not _is_editor:
		_instance.cheat_detected.emit("SYSTEM", 5, 1.0)

static func scan_for_cheats() -> Dictionary:
	var results = {}
	
	if not _hemoloader_check_done:
		_check_hemoloader()
	
	if _hemoloader_detected and not _is_editor:
		results["hemoloader"] = {
			"type": 5,
			"stats": {"detected": true}
		}
		report("HIGH", "HEMOLOADER_ACTIVE", {})
	
	for id in _values:
		var v = _values[id].value
		var cheat_type = v.get_detected_cheat_type()
		if cheat_type != value.CheatType.NONE:
			results[id] = {
				"type": cheat_type,
				"stats": v.get_stats()
			}
			_values[id].alerts += 1
			_instance.cheat_detected.emit(id, cheat_type, 1.0)
			_report_system.warning("core", "Cheat detected in " + id)
	
	return results

static func get_threat_log() -> Array:
	return _threat_log.duplicate()

static func get_stats() -> Dictionary:
	var stats = {
		"values_protected": _values.size(),
		"total_threats": _threat_log.size(),
		"critical_threats": _threat_log.filter(func(t): return t.level == "CRITICAL").size()
	}
	
	if _hemoloader_detected:
		stats["hemoloader_detected"] = true
	
	return stats
