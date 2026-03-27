extends Node
class_name DERMemoryValidator

enum ScanMode { QUICK, FULL, CRITICAL }

@export var scan_mode: ScanMode = ScanMode.QUICK
@export var auto_scan: bool = true
@export var scan_interval: float = 5.0
@export var corrupted_threshold: int = 3
@export var auto_restore: bool = false

var _values: Dictionary = {}
var _pool: DERPool = null
var _timer: Timer
var _scanning: bool = false
var _last_results: Dictionary = {}

signal value_corrupted(key: String, expected: Variant, actual: Variant)
signal value_ok(key: String)
signal value_restored(key: String)
signal scan_complete(total: int, passed: int, failed: int)
signal scan_progress(current: int, total: int, key: String)
signal threshold_exceeded(count: int, threshold: int)

func _init(pool: DERPool = null):
	if pool:
		_pool = pool
	if auto_scan:
		_setup_timer()

func set_pool(pool: DERPool) -> void:
	_pool = pool

func add_value(key: String, expected_value: Variant) -> void:
	_values[key] = expected_value

func add_values(values: Dictionary) -> void:
	for key in values:
		_values[key] = values[key]

func remove_value(key: String) -> void:
	_values.erase(key)
	_last_results.erase(key)

func clear_values() -> void:
	_values.clear()
	_last_results.clear()

func set_baseline(key: String, value: Variant) -> void:
	_values[key] = value

func set_all_baselines() -> Dictionary:
	var results = {}
	for key in _values:
		var val = null
		if _pool and _pool.has(key):
			val = _pool.get_value(key).value
		if val != null:
			_values[key] = val
			results[key] = true
		else:
			results[key] = false
	return results

func verify_value(key: String, use_cache: bool = false) -> bool:
	if use_cache and _last_results.has(key):
		return _last_results[key]
	var ok = _verify_value_impl(key)
	_last_results[key] = ok
	return ok

func _verify_value_impl(key: String) -> bool:
	if not _values.has(key):
		return true
	
	var expected = _values[key]
	var actual = null
	
	if _pool and _pool.has(key):
		actual = _pool.get_value(key).value
	else:
		actual = _values.get(key + "_current", null)
	
	if actual == null:
		return false
	
	if actual == expected:
		value_ok.emit(key)
		return true
	else:
		value_corrupted.emit(key, expected, actual)
		if auto_restore:
			restore_value(key)
		return false

func verify_all(use_cache: bool = false) -> Dictionary:
	_scanning = true
	var results = {}
	var passed = 0
	var failed = 0
	var total = _values.size()
	var current = 0
	
	for key in _values:
		scan_progress.emit(current, total, key)
		var ok = verify_value(key, use_cache)
		results[key] = ok
		if ok:
			passed += 1
		else:
			failed += 1
		current += 1
	
	if failed >= corrupted_threshold:
		threshold_exceeded.emit(failed, corrupted_threshold)
	
	scan_complete.emit(total, passed, failed)
	_scanning = false
	return results

func verify_critical() -> bool:
	for key in _values:
		if not verify_value(key):
			return false
	return true

func restore_value(key: String) -> bool:
	if not _values.has(key):
		return false
	var expected = _values[key]
	if _pool and _pool.has(key):
		_pool.get_value(key).set_value(expected)
		value_restored.emit(key)
		_last_results[key] = true
		return true
	return false

func restore_all() -> Dictionary:
	var results = {}
	for key in _values:
		results[key] = restore_value(key)
	return results

func get_corrupted() -> Array:
	var corrupted = []
	for key in _values:
		if not verify_value(key, true):
			corrupted.append(key)
	return corrupted

func get_stats() -> Dictionary:
	var total = _values.size()
	var protected = total
	var corrupted = 0
	
	for key in _values:
		if not verify_value(key, true):
			corrupted += 1
	
	return {
		total = total,
		protected = protected,
		corrupted = corrupted,
		threshold = corrupted_threshold,
		auto_restore = auto_restore,
		scan_mode = scan_mode,
		auto_scan = auto_scan,
		interval = scan_interval,
		cached_results = _last_results.size()
	}

func clear_cache() -> void:
	_last_results.clear()

func _setup_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = scan_interval
	_timer.autostart = true
	_timer.timeout.connect(_auto_scan)
	add_child(_timer)

func _auto_scan() -> void:
	if not auto_scan or _scanning:
		return
	match scan_mode:
		ScanMode.QUICK:
			verify_critical()
		ScanMode.FULL:
			verify_all(true)
		ScanMode.CRITICAL:
			verify_critical()