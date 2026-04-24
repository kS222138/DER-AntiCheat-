extends RefCounted
class_name DERPool

signal value_registered(key: String)
signal value_unregistered(key: String)
signal cheat_detected(key: String, cheat_type: int)
signal scan_completed(results: Dictionary)

var _values: Dictionary = {}
var _detector = null
var _logger = null
var _auto_protect: bool = true
var _scan_timer: Timer = null
var _thread_pool = null
var _performance_monitor = null
var _started: bool = false
var _main_loop: MainLoop = null


func _init(logger = null):
	_logger = logger if logger else preload("../report/logger.gd").new()
	_logger.info("pool", "DER Pool initialized")
	_main_loop = Engine.get_main_loop()


func setup(detector = null, thread_pool = null, performance_monitor = null):
	_detector = detector
	_thread_pool = thread_pool
	_performance_monitor = performance_monitor
	
	if _thread_pool and not _started:
		_start_auto_scan()


func start():
	if _started:
		return
	_started = true
	_start_auto_scan()


func stop():
	if _scan_timer:
		_scan_timer.stop()
		_scan_timer.queue_free()
		_scan_timer = null
	_started = false


func _start_auto_scan():
	if not _thread_pool:
		return
	
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	_scan_timer = Timer.new()
	_scan_timer.wait_time = 5.0
	_scan_timer.autostart = true
	_scan_timer.timeout.connect(_async_scan)
	tree.root.add_child(_scan_timer)


func set_detector(detector) -> void:
	_detector = detector


func set_value(key: String, value: VanguardValue) -> void:
	_values[key] = value
	if _detector:
		_detector.register_object(value, key)
	VanguardCore.register(key, value)
	_logger.debug("pool", "Value protected: " + key)
	value_registered.emit(key)


func get_value(key: String) -> VanguardValue:
	if not _values.has(key):
		return null
	
	var value = _values[key]
	
	if _auto_protect and _detector:
		if not _detector.verify_object(value):
			_logger.warning("pool", "Suspicious access to: " + key)
			return null
	
	return value


func remove_value(key: String) -> void:
	if not _values.has(key):
		return
	
	var value = _values[key]
	
	if _detector:
		_detector.unregister_object(value)
	
	VanguardCore.unregister(key)
	_values.erase(key)
	
	if value and value.has_method("pool_release"):
		value.pool_release()
	
	_logger.debug("pool", "Value removed: " + key)
	value_unregistered.emit(key)


func _async_scan():
	if not _thread_pool:
		_sync_scan()
		return
	
	_thread_pool.submit(_do_scan.bind(), [], 1, "pool_scan", 30.0, 2)


func _do_scan() -> Dictionary:
	var start_time = Time.get_ticks_usec() if _performance_monitor else 0
	var results = {}
	
	if _detector:
		results = _detector.scan_all()
	
	for key in _values:
		var value = _values[key]
		if value and value.get_detected_cheat_type() != 0:
			results[key] = {
				"cheat_type": value.get_detected_cheat_type(),
				"stats": value.get_stats()
			}
			_logger.warning("pool", "Cheat detected in " + key)
	
	if _performance_monitor and start_time > 0:
		var elapsed_us = Time.get_ticks_usec() - start_time
		_performance_monitor.module_timed.emit("pool_scan", elapsed_us / 1000.0)
	
	return results


func _sync_scan():
	var results = _do_scan()
	scan_completed.emit(results)
	
	for key in results:
		cheat_detected.emit(key, results[key]["cheat_type"])


func scan_for_threats() -> Dictionary:
	if _thread_pool:
		_thread_pool.submit(_do_scan.bind(), [], 1, "pool_scan_sync", 10.0, 1)
		return {}
	
	return _do_scan()


func scan_for_threats_async(callback: Callable = Callable()):
	if not _thread_pool:
		var results = _do_scan()
		if callback.is_valid():
			callback.call(results)
		scan_completed.emit(results)
		return
	
	_thread_pool.submit(_do_scan.bind(), [], 1, "pool_scan_async", 30.0, 2, callback)


func add_critical_file(path: String) -> void:
	if _detector and _detector.has_method("add_critical_file"):
		_detector.add_critical_file(path)


func get_protection_status() -> Dictionary:
	var threat_report = {}
	if _detector and _detector.has_method("get_threat_report"):
		threat_report = _detector.get_threat_report()
	
	return {
		"values_protected": _values.size(),
		"detectors_active": _detector != null,
		"auto_scan": _auto_protect,
		"thread_pool_enabled": _thread_pool != null,
		"threat_report": threat_report
	}


func get_all_keys() -> Array:
	return _values.keys()


func get_value_count() -> int:
	return _values.size()


func clear():
	for key in _values.keys():
		remove_value(key)
	_values.clear()


func shutdown():
	stop()
	clear()
	_logger.info("pool", "DER Pool shutdown")


func set_auto_protect(enabled: bool):
	_auto_protect = enabled


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERPool:
	var pool = DERPool.new()
	for key in config:
		if key in pool:
			pool.set(key, config[key])
	
	node.tree_entered.connect(pool.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(pool.shutdown.bind())
	return pool
