extends Node
class_name DERFileValidator

enum HashType { MD5, SHA1, SHA256 }

@export var hash_type: HashType = HashType.SHA256
@export var auto_verify: bool = true
@export var verify_interval: float = 10.0
@export var max_file_size: int = 100 * 1024 * 1024
@export var chunk_size: int = 65536

var _files: Dictionary = {}
var _cache: Dictionary = {}
var _ignore: Array[String] = []
var _timer: Timer
var _verifying: bool = false

signal file_ok(file: String)
signal file_corrupted(file: String, expected: String, actual: String)
signal verification_complete(total: int, passed: int, failed: int)
signal verification_progress(current: int, total: int, file: String)

func _init():
	if auto_verify:
		_setup_timer()

func add_file(path: String, expected_hash: String) -> void:
	_files[path] = expected_hash

func add_files(files: Dictionary) -> void:
	for path in files:
		_files[path] = files[path]

func remove_file(path: String) -> void:
	_files.erase(path)

func clear_files() -> void:
	_files.clear()
	_cache.clear()

func ignore_file(path: String) -> void:
	if path not in _ignore:
		_ignore.append(path)

func unignore_file(path: String) -> void:
	_ignore.erase(path)

func is_ignored(path: String) -> bool:
	return path in _ignore

func verify_file(path: String) -> bool:
	if is_ignored(path):
		return true
	
	if not FileAccess.file_exists(path):
		push_error("File not found: ", path)
		return false
	
	var actual = _compute_hash(path)
	var expected = _files.get(path, "")
	
	if expected.is_empty():
		return true
	
	if actual == expected:
		file_ok.emit(path)
		return true
	else:
		file_corrupted.emit(path, expected, actual)
		return false

func verify_all() -> Dictionary:
	_verifying = true
	var total = _files.size()
	var passed = 0
	var failed = 0
	var results = {}
	var current = 0
	
	for path in _files:
		if is_ignored(path):
			current += 1
			continue
		
		verification_progress.emit(current, total, path)
		var ok = verify_file(path)
		results[path] = ok
		if ok:
			passed += 1
		else:
			failed += 1
		current += 1
	
	verification_complete.emit(total, passed, failed)
	_verifying = false
	return results

func verify_critical() -> bool:
	for path in _files:
		if is_ignored(path):
			continue
		if not verify_file(path):
			return false
	return true

func get_hash(path: String, force: bool = false) -> String:
	if not force and _cache.has(path):
		return _cache[path]
	var h = _compute_hash(path)
	if not h.is_empty():
		_cache[path] = h
	return h

func is_corrupted(path: String, force: bool = false) -> bool:
	if not _files.has(path) or is_ignored(path):
		return false
	var actual = get_hash(path, force)
	return actual != _files[path]

func _compute_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	
	var size = f.get_length()
	if size > max_file_size:
		push_error("File too large: ", path)
		return ""
	
	var ctx = HashingContext.new()
	match hash_type:
		HashType.MD5:
			ctx.start(HashingContext.HASH_MD5)
		HashType.SHA1:
			ctx.start(HashingContext.HASH_SHA1)
		HashType.SHA256:
			ctx.start(HashingContext.HASH_SHA256)
	
	while not f.eof_reached():
		var bytes = f.get_buffer(chunk_size)
		if bytes.size() > 0:
			ctx.update(bytes)
	
	f.close()
	var hash_bytes = ctx.finish()
	
	match hash_type:
		HashType.MD5:
			return hash_bytes.hex_encode()
		HashType.SHA1:
			return hash_bytes.hex_encode()
		HashType.SHA256:
			return hash_bytes.hex_encode()
	return ""

func _setup_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = verify_interval
	_timer.autostart = true
	_timer.timeout.connect(_auto_verify)
	add_child(_timer)

func _auto_verify() -> void:
	if not auto_verify or _verifying:
		return
	verify_all()

func get_stats() -> Dictionary:
	var total = 0
	var verified = 0
	var corrupted = 0
	
	for path in _files:
		if is_ignored(path):
			continue
		total += 1
		if is_corrupted(path):
			corrupted += 1
		else:
			verified += 1
	
	return {
		total = total,
		verified = verified,
		corrupted = corrupted,
		ignored = _ignore.size(),
		hash_type = hash_type,
		auto_verify = auto_verify,
		interval = verify_interval,
		max_file_size = max_file_size,
		chunk_size = chunk_size
	}

func export_manifest(path: String) -> bool:
	var manifest = {}
	for file in _files:
		if is_ignored(file):
			continue
		manifest[file] = _files[file]
	
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(manifest))
	f.close()
	return true

func import_manifest(path: String, clear_existing: bool = false) -> bool:
	if not FileAccess.file_exists(path):
		return false
	
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	var json = f.get_as_text()
	f.close()
	
	var data = JSON.parse_string(json)
	if data == null:
		return false
	
	if clear_existing:
		_files.clear()
	
	for file in data:
		_files[file] = data[file]
	return true