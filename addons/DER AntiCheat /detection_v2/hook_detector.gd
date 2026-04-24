extends RefCounted
class_name DERHookDetector

signal hook_detected(target: String, hook_type: String)
signal scan_completed(risk_score: float)
signal baseline_captured(success: bool)

enum HookType {
	SCRIPT_METHOD,
	NATIVE_METHOD,
	VIRTUAL_TABLE,
	HEMOLOADER,
	UNKNOWN
}

enum ProtectionLevel { LIGHT, MEDIUM, HEAVY, EXTREME }

@export var protection_level: ProtectionLevel = ProtectionLevel.HEAVY
@export var scan_interval: float = 8.0
@export var auto_repair: bool = false
@export var kill_on_hook: bool = false
@export var enable_hemoloader_detection: bool = true
@export var async_scan: bool = true
@export var enable_vtable_repair: bool = false

var _scan_timer: Timer
var _detected_hooks: Dictionary
var _method_hashes: Dictionary
var _vt_hashes: Dictionary
var _method_source_cache: Dictionary
var _hemoloader_patterns: Array[String]
var _started: bool
var _pending_start: bool
var _main_loop: MainLoop
var _baseline_captured: bool
var _scan_thread: Thread


func _init():
	_scan_timer = null
	_detected_hooks = {}
	_method_hashes = {}
	_vt_hashes = {}
	_method_source_cache = {}
	_hemoloader_patterns = [
		"HemoLoader", "HemoHook", "install_script_hooks", "call_hook",
		"_hemo_original", "HemoLoaderStore", ".script_backup", "hook_method"
	]
	_started = false
	_pending_start = false
	_main_loop = Engine.get_main_loop()
	_baseline_captured = false
	_scan_thread = null


func start():
	if _started:
		return
	_started = true
	
	if not _baseline_captured:
		if async_scan:
			_capture_baseline_async()
		else:
			_capture_method_hashes()
			_capture_vtable_hashes()
			_baseline_captured = true
			baseline_captured.emit(true)
	
	if protection_level >= ProtectionLevel.MEDIUM:
		_start_scanning()


func stop():
	if _scan_timer:
		_scan_timer.stop()
		_scan_timer.queue_free()
		_scan_timer = null
	if _scan_thread and _scan_thread.is_alive():
		_scan_thread.wait_to_finish()
	_started = false
	_pending_start = false


func _get_main_loop():
	if not _main_loop:
		_main_loop = Engine.get_main_loop()
	return _main_loop


func _capture_baseline_async():
	_scan_thread = Thread.new()
	_scan_thread.start(_capture_baseline_thread.bind())


func _capture_baseline_thread():
	_capture_method_hashes()
	_capture_vtable_hashes()
	_baseline_captured = true
	call_deferred("emit_signal", "baseline_captured", true)


func _start_scanning():
	if _scan_timer or _pending_start:
		return
	_pending_start = true
	
	_scan_timer = Timer.new()
	_scan_timer.wait_time = scan_interval
	_scan_timer.autostart = true
	_scan_timer.timeout.connect(_scan)
	
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(_scan_timer)
		_pending_start = false
	else:
		await Engine.get_main_loop().process_frame
		if _started:
			var t = _get_main_loop()
			if t and t.has_method("root"):
				t.root.add_child(_scan_timer)
		_pending_start = false


func _capture_method_hashes():
	var scripts = _get_all_scripts()
	for script_path in scripts:
		var script = load(script_path)
		if not script:
			continue
		var methods = script.get_script_method_list()
		var script_hash = script_path.hash()
		for method in methods:
			var key = str(script_hash, ":", method.name)
			var source = _get_method_source(script_path, method.name)
			_method_hashes[key] = source.hash()


func _capture_vtable_hashes():
	var objects = _get_all_objects()
	var count = 0
	var max_objects = 200
	_vt_hashes.clear()
	for obj in objects:
		if count >= max_objects:
			break
		if obj.has_method("get_class"):
			var obj_class_name = obj.get_class()
			var methods: Array = []
			if obj.has_method("get_method_list"):
				methods = obj.get_method_list()
			var hash_str = obj_class_name
			for m in methods:
				if m.has("name"):
					hash_str += m.name
			_vt_hashes[obj_class_name] = hash_str.hash()
			count += 1


func _get_all_scripts() -> Array:
	var scripts: Array = []
	var dir = DirAccess.open("res://")
	_scan_scripts(dir, "", scripts)
	return scripts


func _scan_scripts(dir: DirAccess, path: String, result: Array):
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
				_scan_scripts(sub_dir, full_path, result)
		elif file_name.ends_with(".gd"):
			result.append("res://" + full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _get_method_source(script_path: String, method_name: String) -> String:
	var cache_key = script_path + ":" + method_name
	if _method_source_cache.has(cache_key):
		return _method_source_cache[cache_key]
	
	var f = FileAccess.open(script_path, FileAccess.READ)
	if not f:
		return ""
	var content = f.get_as_text()
	f.close()
	
	var lines = content.split("\n")
	var in_method = false
	var method_source = ""
	var base_indent = -1
	
	for line in lines:
		var stripped = line.strip_edges()
		if not in_method and stripped.begins_with("func " + method_name):
			in_method = true
			base_indent = line.length() - line.lstrip(" ").length()
			method_source += line + "\n"
		elif in_method:
			var current_indent = line.length() - line.lstrip(" ").length()
			if stripped == "" or current_indent > base_indent:
				method_source += line + "\n"
			else:
				break
	
	_method_source_cache[cache_key] = method_source
	return method_source


func _get_all_objects() -> Array:
	var objects: Array = []
	var root = _get_main_loop()
	if root and root.has_method("root"):
		_collect_objects(root.root, objects)
	return objects


func _collect_objects(node: Node, result: Array):
	if result.size() >= 1000:
		return
	result.append(node)
	for child in node.get_children():
		_collect_objects(child, result)


func _scan():
	var total_weight = _get_total_weight()
	var risk = 0.0
	
	risk += _check_script_hooks()
	risk += _check_vtable_hooks()
	
	if enable_hemoloader_detection:
		risk += _check_hemoloader()
	
	if protection_level >= ProtectionLevel.EXTREME:
		risk += _check_native_method_hooks()
	
	risk = min(risk, total_weight)
	var score = (1.0 - risk / total_weight) * 100.0 if total_weight > 0 else 100.0
	scan_completed.emit(score)
	
	if risk > total_weight * 0.6 and kill_on_hook:
		_trigger_response()
	
	_cleanup_old_entries()


func _get_total_weight() -> float:
	match protection_level:
		ProtectionLevel.LIGHT:
			return 20.0
		ProtectionLevel.MEDIUM:
			return 40.0
		ProtectionLevel.HEAVY:
			return 60.0
		ProtectionLevel.EXTREME:
			return 100.0
		_:
			return 60.0


func _check_script_hooks() -> float:
	var risk = 0.0
	var scripts = _get_all_scripts()
	
	for script_path in scripts:
		var f = FileAccess.open(script_path, FileAccess.READ)
		if not f:
			continue
		var content = f.get_as_text()
		f.close()
		
		var lines = content.split("\n")
		for i in range(lines.size()):
			var line = lines[i]
			var lower = line.to_lower()
			var matched = false
			
			for pattern in _hemoloader_patterns:
				if lower.find(pattern.to_lower()) != -1:
					matched = true
					break
			
			if matched:
				var key = str(script_path, ":", i)
				if not _detected_hooks.has(key):
					var hook_info = {
						"time": Time.get_ticks_msec(),
						"type": HookType.HEMOLOADER,
						"target": script_path
					}
					_detected_hooks[key] = hook_info
					hook_detected.emit(script_path, "HEMOLOADER")
				risk += 2.0
				continue
			
			if line.find("call_deferred(\"set_script\"") != -1:
				var key = str(script_path, ":", i)
				if not _detected_hooks.has(key):
					var hook_info = {
						"time": Time.get_ticks_msec(),
						"type": HookType.SCRIPT_METHOD,
						"target": script_path
					}
					_detected_hooks[key] = hook_info
					hook_detected.emit(script_path, "SCRIPT_METHOD")
				risk += 1.5
	
	var now = Time.get_ticks_msec()
	var keys_to_remove: Array = []
	for key in _detected_hooks.keys():
		if now - _detected_hooks[key]["time"] > 60000:
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_detected_hooks.erase(key)
	
	return min(risk, 30.0)


func _check_vtable_hooks() -> float:
	var risk = 0.0
	var objects = _get_all_objects()
	var count = 0
	var max_objects = 200
	
	for obj in objects:
		if count >= max_objects:
			break
		if obj.has_method("get_class"):
			var obj_class_name = obj.get_class()
			var current_hash = _get_object_vtable_hash(obj)
			var expected_hash = _vt_hashes.get(obj_class_name, 0)
			if expected_hash != 0 and current_hash != expected_hash:
				var key = str(obj_class_name, ":", obj.get_instance_id())
				if not _detected_hooks.has(key):
					var hook_info = {
						"time": Time.get_ticks_msec(),
						"type": HookType.VIRTUAL_TABLE,
						"target": obj_class_name
					}
					_detected_hooks[key] = hook_info
					hook_detected.emit(obj_class_name, "VIRTUAL_TABLE")
				risk += 2.0
				
				if auto_repair and enable_vtable_repair:
					_repair_vtable(obj)
		count += 1
	
	return min(risk, 40.0)


func _get_object_vtable_hash(obj: Object) -> int:
	var methods: Array = []
	if obj.has_method("get_method_list"):
		methods = obj.get_method_list()
	var hash_str = ""
	for m in methods:
		if m.has("name"):
			hash_str += m.name
	return hash_str.hash()


func _repair_vtable(obj: Object):
	if obj.has_method("notify_property_list_changed"):
		obj.notify_property_list_changed()


func _check_native_method_hooks() -> float:
	var risk = 0.0
	
	var main_loop = _get_main_loop()
	if main_loop:
		var main_hash = main_loop.get_method_list().hash()
		var expected = _method_hashes.get("main_loop", 0)
		if expected != 0 and main_hash != expected:
			risk += 5.0
			hook_detected.emit("MainLoop", "NATIVE_METHOD")
	
	return min(risk, 20.0)


func _check_hemoloader() -> float:
	var risk = 0.0
	
	if Engine.has_singleton("HemoLoader"):
		risk += 10.0
		hook_detected.emit("HemoLoader", "HEMOLOADER")
	
	var dirs = ["res://addons/hemoloader/", "res://mods/", "user://mods/"]
	for dir_path in dirs:
		if DirAccess.dir_exists_absolute(dir_path):
			risk += 5.0
			hook_detected.emit(dir_path, "HEMOLOADER")
	
	var files = ["res://hemoloader.gd", "res://mod_loader.gd", "res://hook.gd"]
	for file_path in files:
		if FileAccess.file_exists(file_path):
			risk += 3.0
			hook_detected.emit(file_path, "HEMOLOADER")
	
	return min(risk, 20.0)


func _trigger_response():
	if auto_repair:
		_reload_hooked_scripts()
	
	if kill_on_hook:
		var loop = Engine.get_main_loop()
		if loop and loop.has_method("create_timer"):
			await loop.create_timer(randf_range(3.0, 15.0)).timeout
			if Engine.get_main_loop():
				Engine.get_main_loop().quit()


func _reload_hooked_scripts():
	var hooked_scripts: Array = []
	for key in _detected_hooks:
		var hook_type = _detected_hooks[key]["type"]
		if hook_type == HookType.SCRIPT_METHOD or hook_type == HookType.HEMOLOADER:
			var target = _detected_hooks[key]["target"]
			if target.ends_with(".gd") and target not in hooked_scripts:
				hooked_scripts.append(target)
	
	for script_path in hooked_scripts:
		if FileAccess.file_exists(script_path):
			ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_REPLACE)


func _cleanup_old_entries():
	var now = Time.get_ticks_msec()
	var keys_to_remove: Array = []
	for key in _detected_hooks:
		if now - _detected_hooks[key]["time"] > 60000:
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_detected_hooks.erase(key)


func refresh_baseline():
	_method_source_cache.clear()
	if async_scan:
		_capture_baseline_async()
	else:
		_capture_method_hashes()
		_capture_vtable_hashes()
		_baseline_captured = true
		baseline_captured.emit(true)


func get_detected_hooks() -> Dictionary:
	return _detected_hooks.duplicate()


func is_hooked() -> bool:
	return not _detected_hooks.is_empty()


func reset():
	_detected_hooks.clear()
	_method_source_cache.clear()
	refresh_baseline()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERHookDetector:
	var detector = DERHookDetector.new()
	for k in config:
		if detector.has_method("set_" + k):
			detector.call("set_" + k, config[k])
		elif k in detector:
			detector.set(k, config[k])
	node.tree_entered.connect(detector.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(detector.stop.bind())
	return detector
