extends RefCounted
class_name DERDetector

signal threat_detected(threat_type: String, confidence: float, data: Dictionary)
signal scan_completed(results: Dictionary)
signal detector_registered(detector_name: String)

enum ScanPriority {
	LOW,
	NORMAL,
	HIGH,
	CRITICAL
}

var _detectors: Array = []
var _detector_names: Dictionary = {}
var _logger = null
var _thread_pool = null
var _performance_monitor = null
var _last_scan_time: int = 0
var _scan_interval: int = 5000
var _started: bool = false
var _scan_timer: Timer = null
var _main_loop: MainLoop = null

var process_monitor = null
var integrity_check = null
var memory_guard = null
var speed_detector = null
var debugger_detector = null
var packet_protector = null
var process_scanner_v2 = null
var hook_detector = null
var memory_obfuscator = null


func _init(logger_obj = null):
	_logger = logger_obj if logger_obj else preload("../report/logger.gd").new()
	_main_loop = Engine.get_main_loop()
	_logger.info("detector", "DER Detector initialized")


func setup(thread_pool = null, performance_monitor = null):
	_thread_pool = thread_pool
	_performance_monitor = performance_monitor
	_init_detectors()


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
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	_scan_timer = Timer.new()
	_scan_timer.wait_time = _scan_interval / 1000.0
	_scan_timer.autostart = true
	_scan_timer.timeout.connect(_async_scan_all)
	tree.root.add_child(_scan_timer)


func _init_detectors():
	_detectors.clear()
	_detector_names.clear()
	
	var monitor_script = preload("process_monitor.gd")
	if monitor_script:
		process_monitor = monitor_script.new()
		if process_monitor:
			_detectors.append(process_monitor)
			_detector_names[process_monitor] = "ProcessMonitor"
	
	var integrity_script = preload("integrity_check.gd")
	if integrity_script:
		integrity_check = integrity_script.new()
		if integrity_check:
			_detectors.append(integrity_check)
			_detector_names[integrity_check] = "IntegrityCheck"
	
	var memory_script = preload("memory_guard.gd")
	if memory_script:
		memory_guard = memory_script.new()
		if memory_guard:
			_detectors.append(memory_guard)
			_detector_names[memory_guard] = "MemoryGuard"
	
	var speed_script = preload("speed_detector.gd")
	if speed_script:
		speed_detector = speed_script.new()
		if speed_detector:
			_detectors.append(speed_detector)
			_detector_names[speed_detector] = "SpeedDetector"
	
	var debugger_script = preload("debugger_detector.gd")
	if debugger_script:
		debugger_detector = debugger_script.new()
		if debugger_detector:
			_detectors.append(debugger_detector)
			_detector_names[debugger_detector] = "DebuggerDetector"
	
	var packet_script = preload("packet_protector.gd")
	if packet_script:
		packet_protector = packet_script.new()
	
	var scanner_v2_script = preload("../detection_v2/process_scanner_v2.gd")
	if scanner_v2_script:
		process_scanner_v2 = scanner_v2_script.new()
		if process_scanner_v2:
			_detectors.append(process_scanner_v2)
			_detector_names[process_scanner_v2] = "ProcessScannerV2"
	
	var hook_script = preload("../detection_v2/hook_detector.gd")
	if hook_script:
		hook_detector = hook_script.new()
		if hook_detector:
			_detectors.append(hook_detector)
			_detector_names[hook_detector] = "HookDetector"
	
	var obfuscator_script = preload("../core/memory_obfuscator.gd")
	if obfuscator_script:
		memory_obfuscator = obfuscator_script.new()
		if memory_obfuscator:
			_detectors.append(memory_obfuscator)
			_detector_names[memory_obfuscator] = "MemoryObfuscator"
	
	for d in _detectors:
		if d.has_method("set_logger"):
			d.set_logger(_logger)
		detector_registered.emit(_detector_names[d])
	
	_logger.info("detector", "Detectors ready: " + str(_detectors.size()))


func _async_scan_all():
	if not _thread_pool:
		_sync_scan_all()
		return
	
	_thread_pool.submit(_do_scan.bind(), [], 1, "detector_scan", 30.0, 2)


func _do_scan() -> Dictionary:
	var start_time = Time.get_ticks_usec() if _performance_monitor else 0
	var results = {}
	var current_time = Time.get_ticks_msec()
	
	if current_time - _last_scan_time < _scan_interval:
		return results
	
	for detector in _detectors:
		if detector and detector.has_method("check"):
			var risk = detector.check()
			if risk != null and typeof(risk) == TYPE_FLOAT and risk > 0.0:
				var name = _detector_names.get(detector, "unknown")
				results[name] = {
					"risk": risk,
					"time": current_time,
					"details": detector.get_details() if detector.has_method("get_details") else {}
				}
				
				if risk > 0.5:
					threat_detected.emit(name, risk, results[name])
					if _logger:
						_logger.warning("detector", "Threat: " + name + " risk: " + str(risk))
	
	_last_scan_time = current_time
	
	if _performance_monitor and start_time > 0:
		var elapsed_us = Time.get_ticks_usec() - start_time
		_performance_monitor.module_timed.emit("detector_scan", elapsed_us / 1000.0)
	
	return results


func _sync_scan_all():
	var results = _do_scan()
	scan_completed.emit(results)


func scan_all() -> Dictionary:
	if _thread_pool:
		_thread_pool.submit(_do_scan.bind(), [], 1, "detector_scan_sync", 10.0, 1)
		return {}
	return _do_scan()


func scan_all_async(callback: Callable = Callable()):
	if not _thread_pool:
		var results = _do_scan()
		if callback.is_valid():
			callback.call(results)
		scan_completed.emit(results)
		return
	
	_thread_pool.submit(_do_scan.bind(), [], 1, "detector_scan_async", 30.0, 2, callback)


func register_object(obj, name_str = ""):
	if memory_guard and memory_guard.has_method("track_allocation"):
		memory_guard.track_allocation(obj, name_str)


func unregister_object(obj):
	if memory_guard and memory_guard.has_method("track_free"):
		memory_guard.track_free(obj)


func verify_object(obj) -> bool:
	if memory_guard and memory_guard.has_method("verify_access"):
		return memory_guard.verify_access(obj)
	return true


func add_critical_file(file_path: String):
	if integrity_check and integrity_check.has_method("add_file_to_monitor"):
		integrity_check.add_file_to_monitor(file_path)


func encrypt_data(data):
	if packet_protector and packet_protector.has_method("encrypt_packet"):
		return packet_protector.encrypt_packet(data)
	return data


func decrypt_data(data):
	if packet_protector and packet_protector.has_method("decrypt_packet"):
		return packet_protector.decrypt_packet(data)
	return data


func get_report() -> Dictionary:
	var threats = []
	var last_results = _do_scan()
	for name in last_results:
		threats.append({
			"detector": name,
			"risk": last_results[name]["risk"],
			"time": last_results[name]["time"]
		})
	
	return {
		"last_scan": _last_scan_time,
		"active": _detectors.size(),
		"threats": threats,
		"thread_pool_enabled": _thread_pool != null
	}


func get_detector(name: String):
	match name.to_lower():
		"process_monitor":
			return process_monitor
		"integrity_check":
			return integrity_check
		"memory_guard":
			return memory_guard
		"speed_detector":
			return speed_detector
		"debugger_detector":
			return debugger_detector
		"packet_protector":
			return packet_protector
		"process_scanner_v2":
			return process_scanner_v2
		"hook_detector":
			return hook_detector
		"memory_obfuscator":
			return memory_obfuscator
	return null


func get_process_monitor(): return process_monitor
func get_integrity_check(): return integrity_check
func get_memory_guard(): return memory_guard
func get_speed_detector(): return speed_detector
func get_debugger_detector(): return debugger_detector
func get_packet_protector(): return packet_protector
func get_process_scanner_v2(): return process_scanner_v2
func get_hook_detector(): return hook_detector
func get_memory_obfuscator(): return memory_obfuscator


func set_scan_interval(interval_ms: int):
	_scan_interval = interval_ms
	if _scan_timer:
		_scan_timer.wait_time = interval_ms / 1000.0


func shutdown():
	stop()
	for detector in _detectors:
		if detector and detector.has_method("shutdown"):
			detector.shutdown()
	_detectors.clear()
	_logger.info("detector", "DER Detector shutdown")


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERDetector:
	var detector = DERDetector.new()
	for key in config:
		if key in detector:
			detector.set(key, config[key])
	
	node.tree_entered.connect(detector.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(detector.shutdown.bind())
	return detector