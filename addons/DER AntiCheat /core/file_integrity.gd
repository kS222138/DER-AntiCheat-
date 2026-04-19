extends RefCounted
class_name DERFileIntegrity

signal file_tampered(file_path: String, expected_hash: String, current_hash: String)
signal scan_completed(total_files: int, tampered_count: int)
signal scan_failed(error: String)

enum ScanMode {
	QUICK,
	NORMAL,
	DEEP,
	FULL
}

enum HashAlgorithm {
	MD5,
	SHA1,
	SHA256
}

@export var scan_mode: ScanMode = ScanMode.NORMAL
@export var hash_algorithm: HashAlgorithm = HashAlgorithm.SHA256
@export var scan_interval: float = 60.0
@export var enabled: bool = true
@export var auto_repair: bool = false
@export var auto_report: bool = true
@export var exclude_patterns: Array[String] = [".import", ".godot", "*.tmp", "*.backup"]
@export var include_extensions: Array[String] = [".gd", ".tscn", ".res", ".tres", ".gdshader"]

var _file_manifest: Dictionary = {}
var _tampered_files: Dictionary = {}
var _scan_timer: Timer = null
var _logger = null
var _started: bool = false
var _main_loop: MainLoop = null
var _is_scanning: bool = false


func _init(logger = null):
	_logger = logger
	_main_loop = Engine.get_main_loop()


func start() -> void:
	if not enabled or _started:
		return
	_started = true
	_load_manifest()
	_setup_timer()


func stop() -> void:
	if _scan_timer:
		_scan_timer.stop()
		_scan_timer.queue_free()
		_scan_timer = null
	_started = false


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop()
	elif not _started:
		start()


func set_scan_mode(mode: int) -> void:
	scan_mode = mode


func set_scan_interval(interval: float) -> void:
	scan_interval = interval
	if _started:
		stop()
		start()


func _get_main_loop() -> MainLoop:
	if not _main_loop:
		_main_loop = Engine.get_main_loop()
	return _main_loop


func _setup_timer() -> void:
	if _scan_timer:
		return
	
	_scan_timer = Timer.new()
	_scan_timer.wait_time = scan_interval
	_scan_timer.autostart = true
	_scan_timer.timeout.connect(_perform_scan)
	
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(_scan_timer)


func _perform_scan() -> void:
	if not enabled or _is_scanning:
		return
	
	_is_scanning = true
	var result = scan()
	_is_scanning = false
	
	if result.has("error"):
		scan_failed.emit(result["error"])
	elif result.has("tampered_count"):
		scan_completed.emit(result["total_files"], result["tampered_count"])
	
	if auto_repair and _tampered_files.size() > 0:
		_repair_files()


func scan() -> Dictionary:
	if not enabled:
		return {"error": "Scanner disabled"}
	
	var result = {
		"total_files": 0,
		"tampered_count": 0,
		"tampered_files": [],
		"timestamp": Time.get_unix_time_from_system()
	}
	
	_tampered_files.clear()
	
	var files_to_scan = _get_files_to_scan()
	result["total_files"] = files_to_scan.size()
	
	for file_path in files_to_scan:
		var expected_hash = _file_manifest.get(file_path, "")
		if expected_hash == "":
			continue
		
		var current_hash = _calculate_file_hash(file_path)
		if current_hash == "":
			continue
		
		if current_hash != expected_hash:
			result["tampered_count"] += 1
			result["tampered_files"].append(file_path)
			_tampered_files[file_path] = {
				"expected": expected_hash,
				"current": current_hash,
				"timestamp": Time.get_unix_time_from_system()
			}
			file_tampered.emit(file_path, expected_hash, current_hash)
			
			if auto_report and _logger and _logger.has_method("warning"):
				_logger.warning("DERFileIntegrity", "File tampered: %s" % file_path)
	
	return result


func generate_manifest(directory: String = "res://", recursive: bool = true) -> Dictionary:
	var manifest = {}
	var files = _get_files_in_directory(directory, recursive)
	
	for file_path in files:
		var should_include = _should_include_file(file_path)
		if not should_include:
			continue
		
		var file_hash = _calculate_file_hash(file_path)
		if file_hash != "":
			manifest[file_path] = file_hash
	
	return manifest


func save_manifest(path: String = "user://file_manifest.json") -> bool:
	var manifest = generate_manifest()
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	
	var json_string = JSON.stringify(manifest, "\t")
	file.store_string(json_string)
	file.close()
	
	_file_manifest = manifest
	return true


func load_manifest(path: String = "user://file_manifest.json") -> bool:
	if not FileAccess.file_exists(path):
		return false
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		return false
	
	_file_manifest = json.data
	return true


func _load_manifest() -> void:
	if _file_manifest.is_empty():
		load_manifest()


func _get_files_to_scan() -> Array:
	match scan_mode:
		ScanMode.QUICK:
			return _get_quick_files()
		ScanMode.NORMAL:
			return _get_normal_files()
		ScanMode.DEEP:
			return _get_deep_files()
		ScanMode.FULL:
			return _get_full_files()
	return _get_normal_files()


func _get_quick_files() -> Array:
	var files = []
	var critical_paths = [
		"res://game.gd",
		"res://main.tscn",
		"res://project.godot"
	]
	
	for path in critical_paths:
		if FileAccess.file_exists(path):
			files.append(path)
	
	return files


func _get_normal_files() -> Array:
	var files = []
	var directories = ["res://scripts", "res://scenes", "res://addons/DER AntiCheat"]
	
	for dir_path in directories:
		if DirAccess.dir_exists_absolute(dir_path):
			files.append_array(_get_files_in_directory(dir_path, true))
	
	return files


func _get_deep_files() -> Array:
	var files = []
	var directories = ["res://scripts", "res://scenes", "res://addons", "res://src"]
	
	for dir_path in directories:
		if DirAccess.dir_exists_absolute(dir_path):
			files.append_array(_get_files_in_directory(dir_path, true))
	
	files.append_array(_get_quick_files())
	
	return files


func _get_full_files() -> Array:
	return _get_files_in_directory("res://", true)


func _get_files_in_directory(directory: String, recursive: bool) -> Array:
	var files = []
	var dir = DirAccess.open(directory)
	if not dir:
		return files
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		
		var full_path = directory.path_join(file_name)
		
		if dir.current_is_dir() and recursive:
			files.append_array(_get_files_in_directory(full_path, true))
		elif not dir.current_is_dir():
			if _should_include_file(full_path):
				files.append(full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return files


func _should_include_file(file_path: String) -> bool:
	for pattern in exclude_patterns:
		if pattern.ends_with("*"):
			var base = pattern.trim_suffix("*")
			if file_path.find(base) != -1:
				return false
		elif file_path.find(pattern) != -1:
			return false
	
	if include_extensions.is_empty():
		return true
	
	for ext in include_extensions:
		if file_path.ends_with(ext):
			return true
	
	return false


func _calculate_file_hash(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""
	
	var content = file.get_buffer(file.get_length())
	file.close()
	
	match hash_algorithm:
		HashAlgorithm.MD5:
			return _md5(content)
		HashAlgorithm.SHA1:
			return _sha1(content)
		HashAlgorithm.SHA256:
			return _sha256(content)
	
	return ""


func _md5(data: PackedByteArray) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(data)
	var hash = ctx.finish()
	return _bytes_to_hex(hash)


func _sha1(data: PackedByteArray) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(data)
	var hash = ctx.finish()
	return _bytes_to_hex(hash)


func _sha256(data: PackedByteArray) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	var hash = ctx.finish()
	return _bytes_to_hex(hash)


func _bytes_to_hex(bytes: PackedByteArray) -> String:
	var hex = ""
	for b in bytes:
		hex += "%02x" % b
	return hex


func _repair_files() -> void:
	for file_path in _tampered_files:
		_repair_file(file_path)


func _repair_file(file_path: String) -> void:
	var backup_path = file_path + ".backup"
	if FileAccess.file_exists(backup_path):
		var dir = DirAccess.open("res://")
		if dir:
			dir.copy(backup_path, file_path)
			if _logger and _logger.has_method("info"):
				_logger.info("DERFileIntegrity", "Repaired: %s" % file_path)


func verify_single_file(file_path: String) -> bool:
	var expected_hash = _file_manifest.get(file_path, "")
	if expected_hash == "":
		return true
	
	var current_hash = _calculate_file_hash(file_path)
	return current_hash == expected_hash


func add_to_manifest(file_path: String, file_hash: String = "") -> void:
	if file_hash == "":
		file_hash = _calculate_file_hash(file_path)
	if file_hash != "":
		_file_manifest[file_path] = file_hash


func remove_from_manifest(file_path: String) -> void:
	_file_manifest.erase(file_path)


func get_manifest() -> Dictionary:
	return _file_manifest.duplicate()


func get_tampered_files() -> Dictionary:
	return _tampered_files.duplicate()


func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"scan_mode": scan_mode,
		"hash_algorithm": hash_algorithm,
		"total_manifest_entries": _file_manifest.size(),
		"tampered_count": _tampered_files.size(),
		"is_scanning": _is_scanning
	}


func reset() -> void:
	_tampered_files.clear()
	_file_manifest.clear()


func cleanup() -> void:
	stop()
	reset()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERFileIntegrity:
	var detector = DERFileIntegrity.new()
	for key in config:
		if key in detector:
			detector.set(key, config[key])
	
	node.tree_entered.connect(detector.start.bind())
	node.tree_exiting.connect(detector.cleanup.bind())
	
	return detector