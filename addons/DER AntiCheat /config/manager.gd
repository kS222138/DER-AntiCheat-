class_name DERConfigManager
extends RefCounted

signal config_loaded(path: String)
signal config_saved(path: String)
signal config_changed(key: String, old_val: Variant, new_val: Variant)

enum ConfigFormat { JSON }
enum ResetMode { REPLACE, MERGE }

const MAX_FILE_SIZE := 10 * 1024 * 1024

var _config: Dictionary = {}
var _path: String = ""
var _format: ConfigFormat = ConfigFormat.JSON
var _auto_save: bool = false
var _validator: Callable
var _diff: DERConfigDiff
var _listeners: Dictionary = {}


func _init():
	_diff = DERConfigDiff.new()


func load_config(path: String, format: ConfigFormat = ConfigFormat.JSON) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("DERConfigManager: Cannot open %s" % path)
		return false
	
	var size = file.get_length()
	if size > MAX_FILE_SIZE:
		push_error("DERConfigManager: File too large: %s (%.2f MB)" % [path, size / 1048576.0])
		return false
	
	var content = file.get_as_text()
	var data = _parse(content, format, path)
	if data.is_empty():
		return false
	
	_config = data
	_path = path
	_format = format
	config_loaded.emit(path)
	return true


func save_config(path: String = "") -> bool:
	var target = path if path != "" else _path
	if target == "":
		push_error("DERConfigManager: No path specified")
		return false
	
	var content = _serialize(_config, _format)
	if content == "":
		return false
	
	var file = FileAccess.open(target, FileAccess.WRITE)
	if not file:
		push_error("DERConfigManager: Cannot write %s" % target)
		return false
	
	file.store_string(content)
	config_saved.emit(target)
	return true


func get_value(key: String, default_val: Variant = null) -> Variant:
	return _config.get(key, default_val)


func set_value(key: String, value: Variant) -> void:
	var old = _config.get(key)
	if old == value:
		return
	_config[key] = value
	config_changed.emit(key, old, value)
	_notify_listeners(key, old, value)
	if _auto_save:
		save_config()


func has_key(key: String) -> bool:
	return _config.has(key)


func remove_key(key: String) -> void:
	if not _config.has(key):
		return
	var old = _config[key]
	_config.erase(key)
	config_changed.emit(key, old, null)
	_notify_listeners(key, old, null)
	if _auto_save:
		save_config()


func get_all(deep: bool = false) -> Dictionary:
	return _config.duplicate(deep)


func set_all(new_config: Dictionary) -> void:
	var diffs = _diff.compare(_config, new_config, true)
	_config = new_config.duplicate(true)
	for d in diffs:
		config_changed.emit(d.key, d.old_val, d.new_val)
		_notify_listeners(d.key, d.old_val, d.new_val)
	if _auto_save:
		save_config()


func reset_to_default(default_config: Dictionary, mode: ResetMode = ResetMode.REPLACE) -> void:
	match mode:
		ResetMode.REPLACE:
			set_all(default_config)
		ResetMode.MERGE:
			var merged = _config.duplicate(true)
			for key in default_config:
				merged[key] = default_config[key]
			set_all(merged)


func merge(other: Dictionary, overwrite: bool = true) -> void:
	var new_config = _config.duplicate(true)
	for key in other:
		if overwrite or not new_config.has(key):
			new_config[key] = other[key]
	set_all(new_config)


func backup(path: String) -> bool:
	return save_config(path)


func restore(path: String) -> bool:
	return load_config(path)


func validate() -> bool:
	if not _validator:
		return true
	return _validator.call(_config)


func set_validator(callback: Callable) -> void:
	_validator = callback


func add_listener(key: String, callback: Callable) -> void:
	if not _listeners.has(key):
		_listeners[key] = []
	_listeners[key].append(callback)


func remove_listener(key: String, callback: Callable) -> void:
	if not _listeners.has(key):
		return
	var idx = _listeners[key].find(callback)
	if idx != -1:
		_listeners[key].remove_at(idx)
	if _listeners[key].is_empty():
		_listeners.erase(key)


func set_auto_save(enabled: bool) -> void:
	_auto_save = enabled


func get_path() -> String:
	return _path


func get_format() -> ConfigFormat:
	return _format


func get_diff(old_config: Dictionary, new_config: Dictionary, deep: bool = true) -> Array:
	return _diff.compare(old_config, new_config, deep)


func get_diff_files(path_a: String, path_b: String, deep: bool = true) -> Array:
	return _diff.compare_files(path_a, path_b, deep)


func export_diff(diffs: Array, path: String) -> int:
	return _diff.export_json(diffs, path)


func diff_report(diffs: Array) -> String:
	return _diff.report(diffs)


func diff_stats(diffs: Array) -> Dictionary:
	return _diff.stats(diffs)


func _notify_listeners(key: String, old_val: Variant, new_val: Variant) -> void:
	if not _listeners.has(key):
		return
	for cb in _listeners[key]:
		cb.call(key, old_val, new_val)


func _parse(content: String, format: ConfigFormat, path: String = "") -> Dictionary:
	match format:
		ConfigFormat.JSON:
			var j = JSON.new()
			var err = j.parse(content)
			if err != OK:
				var msg = "JSON parse error"
				if path != "":
					msg += " in %s" % path
				push_error("DERConfigManager: %s: %s" % [msg, j.get_error_message()])
				return {}
			var data = j.get_data()
			if data is Dictionary:
				return data
			push_error("DERConfigManager: JSON root is not a dictionary%s" % (" in " + path if path != "" else ""))
			return {}
	return {}


func _serialize(data: Dictionary, format: ConfigFormat) -> String:
	match format:
		ConfigFormat.JSON:
			var json = JSON.new()
			var result = json.stringify(data, "\t", true)
			if result == "":
				push_error("DERConfigManager: Failed to serialize config")
			return result
	return ""


func clear() -> void:
	set_all({})


func reload() -> bool:
	if _path == "":
		return false
	return load_config(_path, _format)


func exists() -> bool:
	return FileAccess.file_exists(_path)


func size() -> int:
	return _config.size()