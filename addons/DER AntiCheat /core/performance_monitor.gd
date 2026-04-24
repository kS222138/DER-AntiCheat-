extends Node
class_name PerformanceMonitor

signal frame_updated(fps: float, frame_time_ms: float)
signal module_timed(module_name: String, elapsed_ms: float)
signal memory_updated(memory_mb: float)
signal threshold_exceeded(metric: String, value: float, threshold: float)

enum MetricType {
	FPS,
	FRAME_TIME,
	MEMORY,
	CPU_USAGE,
	MODULE_TIME
}

@export var enable_monitoring: bool = true
@export var update_interval: float = 0.5
@export var log_thresholds: bool = true
@export var auto_report: bool = false
@export var report_interval: float = 60.0

@export var fps_warning_threshold: int = 30
@export var frame_time_warning_threshold: float = 33.3
@export var memory_warning_threshold_mb: float = 1024.0
@export var module_time_warning_threshold_ms: float = 50.0

var _current_fps: float = 0.0
var _current_frame_time: float = 0.0
var _current_memory_mb: float = 0.0
var _module_times: Dictionary = {}
var _history: Array = []
var _max_history: int = 300
var _update_timer: Timer = null
var _report_timer: Timer = null
var _frame_times: Array = []
var _frame_count: int = 0
var _last_frame_time: int = 0


func _ready():
	if enable_monitoring:
		_start_monitoring()


func _start_monitoring() -> void:
	_setup_update_timer()
	_setup_report_timer()
	_last_frame_time = Time.get_ticks_msec()


func _process(delta: float):
	if not enable_monitoring:
		return
	
	_frame_count += 1
	
	var now = Time.get_ticks_msec()
	var frame_delta = now - _last_frame_time
	_last_frame_time = now
	
	if frame_delta > 0:
		_current_fps = 1000.0 / frame_delta
		_current_frame_time = frame_delta
		
		_frame_times.append(frame_delta)
		if _frame_times.size() > 60:
			_frame_times.pop_front()
		
		# 修复：第二个参数应该是帧时间，不是 fps
		frame_updated.emit(_current_fps, _current_frame_time)
		
		if _current_fps < fps_warning_threshold:
			threshold_exceeded.emit("FPS", _current_fps, fps_warning_threshold)


func _update_memory() -> void:
	var memory = OS.get_static_memory_usage()
	_current_memory_mb = memory / (1024.0 * 1024.0)
	memory_updated.emit(_current_memory_mb)
	
	if _current_memory_mb > memory_warning_threshold_mb:
		threshold_exceeded.emit("MEMORY", _current_memory_mb, memory_warning_threshold_mb)


func _setup_update_timer() -> void:
	_update_timer = Timer.new()
	_update_timer.wait_time = update_interval
	_update_timer.autostart = true
	_update_timer.timeout.connect(_on_update_timer)
	add_child(_update_timer)


func _setup_report_timer() -> void:
	if not auto_report:
		return
	
	_report_timer = Timer.new()
	_report_timer.wait_time = report_interval
	_report_timer.autostart = true
	_report_timer.timeout.connect(_on_report_timer)
	add_child(_report_timer)


func _on_update_timer() -> void:
	if not enable_monitoring:
		return
	
	_update_memory()
	_update_history()


func _on_report_timer() -> void:
	if not enable_monitoring:
		return
	
	var report = generate_report()
	print("PerformanceMonitor Report: ", JSON.stringify(report, "\t"))


func start_module_timing(module_name: String) -> int:
	return Time.get_ticks_usec()


func end_module_timing(module_name: String, start_time: int) -> void:
	var elapsed_us = Time.get_ticks_usec() - start_time
	var elapsed_ms = elapsed_us / 1000.0
	
	_module_times[module_name] = elapsed_ms
	module_timed.emit(module_name, elapsed_ms)
	
	if elapsed_ms > module_time_warning_threshold_ms and log_thresholds:
		threshold_exceeded.emit("MODULE_TIME", elapsed_ms, module_time_warning_threshold_ms)


func get_module_time(module_name: String) -> float:
	return _module_times.get(module_name, 0.0)


func get_all_module_times() -> Dictionary:
	return _module_times.duplicate()


func get_current_fps() -> float:
	return _current_fps


func get_average_fps() -> float:
	if _frame_times.is_empty():
		return 0.0
	
	var total = 0.0
	for ft in _frame_times:
		total += ft
	
	var avg_frame_time = total / _frame_times.size()
	return 1000.0 / avg_frame_time if avg_frame_time > 0 else 0.0


func get_min_fps() -> float:
	if _frame_times.is_empty():
		return 0.0
	
	var max_frame_time = 0.0
	for ft in _frame_times:
		if ft > max_frame_time:
			max_frame_time = ft
	
	return 1000.0 / max_frame_time if max_frame_time > 0 else 0.0


func get_max_fps() -> float:
	if _frame_times.is_empty():
		return 0.0
	
	var min_frame_time = 999999.0
	for ft in _frame_times:
		if ft < min_frame_time:
			min_frame_time = ft
	
	return 1000.0 / min_frame_time if min_frame_time > 0 else 0.0


func get_frame_time_stats() -> Dictionary:
	if _frame_times.is_empty():
		return {"avg": 0.0, "min": 0.0, "max": 0.0, "std": 0.0}
	
	var avg = 0.0
	for ft in _frame_times:
		avg += ft
	avg /= _frame_times.size()
	
	var min_ft = _frame_times[0]
	var max_ft = _frame_times[0]
	for ft in _frame_times:
		if ft < min_ft:
			min_ft = ft
		if ft > max_ft:
			max_ft = ft
	
	var variance = 0.0
	for ft in _frame_times:
		variance += (ft - avg) * (ft - avg)
	variance /= _frame_times.size()
	var std = sqrt(variance)
	
	return {
		"avg": avg,
		"min": min_ft,
		"max": max_ft,
		"std": std
	}


func get_current_memory_mb() -> float:
	return _current_memory_mb


func get_peak_memory_mb() -> float:
	var peak = 0.0
	for entry in _history:
		var mem = entry.get("memory_mb", 0)
		if mem > peak:
			peak = mem
	return peak


func get_current_cpu_usage() -> float:
	return 0.0


func get_stability_score() -> float:
	var stats = get_frame_time_stats()
	if stats.avg == 0:
		return 100.0
	var cv = stats.std / stats.avg
	return clamp(100.0 * (1.0 - cv), 0.0, 100.0)


func _update_history() -> void:
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"fps": _current_fps,
		"frame_time": _current_frame_time,
		"memory_mb": _current_memory_mb,
		"module_times": _module_times.duplicate()
	}
	
	_history.append(entry)
	
	while _history.size() > _max_history:
		_history.pop_front()


func get_history() -> Array:
	return _history.duplicate()


func get_history_range(start_index: int, end_index: int) -> Array:
	if start_index < 0:
		start_index = 0
	if end_index >= _history.size():
		end_index = _history.size() - 1
	
	if start_index > end_index:
		return []
	
	return _history.slice(start_index, end_index + 1)


func get_recent_history(seconds: float) -> Array:
	var cutoff = Time.get_unix_time_from_system() - seconds
	var result = []
	
	for entry in _history:
		if entry.timestamp >= cutoff:
			result.append(entry)
	
	return result


func generate_report() -> Dictionary:
	var frame_stats = get_frame_time_stats()
	
	return {
		"timestamp": Time.get_datetime_string_from_system(),
		"fps": {
			"current": _current_fps,
			"avg": get_average_fps(),
			"min": get_min_fps(),
			"max": get_max_fps(),
			"stability": get_stability_score()
		},
		"frame_time": {
			"avg_ms": frame_stats.avg,
			"min_ms": frame_stats.min,
			"max_ms": frame_stats.max,
			"std_ms": frame_stats.std
		},
		"memory": {
			"current_mb": _current_memory_mb,
			"peak_mb": get_peak_memory_mb()
		},
		"module_times": _module_times,
		"history_size": _history.size()
	}


func export_report_to_file(path: String) -> bool:
	var report = generate_report()
	var json_str = JSON.stringify(report, "\t")
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(json_str)
	file.close()
	return true


func reset_history() -> void:
	_history.clear()
	_frame_times.clear()
	_module_times.clear()
	_frame_count = 0


func get_bottleneck_modules(threshold_ms: float = -1.0) -> Array:
	var threshold = threshold_ms if threshold_ms > 0 else module_time_warning_threshold_ms
	var bottlenecks = []
	
	for module_name in _module_times:
		var elapsed = _module_times[module_name]
		if elapsed > threshold:
			bottlenecks.append({
				"module": module_name,
				"time_ms": elapsed
			})
	
	bottlenecks.sort_custom(func(a, b): return a.time_ms > b.time_ms)
	return bottlenecks


func shutdown() -> void:
	enable_monitoring = false
	
	if _update_timer:
		_update_timer.stop()
		_update_timer.queue_free()
		_update_timer = null
	
	if _report_timer:
		_report_timer.stop()
		_report_timer.queue_free()
		_report_timer = null
	
	_history.clear()
	_frame_times.clear()
	_module_times.clear()
