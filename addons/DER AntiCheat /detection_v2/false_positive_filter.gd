extends RefCounted
class_name DERFalsePositiveFilter

signal false_positive_detected(metric: String, value: float, threshold: float)
signal filter_calibrated()

enum FilterLevel { OFF, LIGHT, MEDIUM, HEAVY }
enum DeviceTier { LOW, MEDIUM, HIGH, ULTRA }

@export var filter_level: FilterLevel = FilterLevel.MEDIUM
@export var auto_calibrate: bool = true
@export var calibration_samples: int = 30
@export var persist_calibration: bool = true
@export var calibration_path: String = "user://der_filter_cache.cfg"
@export var outlier_trim_ratio: float = 0.1

var _device_profile: Dictionary = {}
var _calibrated: bool = false
var _frame_times: Array = []
var _touch_samples: Array = []
var _memory_samples: Array = []
var _device_tier: DeviceTier = DeviceTier.MEDIUM


func _init():
	if auto_calibrate:
		_calibrate()


func start():
	if not _calibrated and auto_calibrate:
		_calibrate()


func _calibrate():
	if persist_calibration and _load_calibration():
		return
	
	_frame_times.clear()
	_touch_samples.clear()
	_memory_samples.clear()
	_calibrated = false
	_detect_device_tier()


func _detect_device_tier():
	var mem = OS.get_memory_info()
	var physical_bytes = mem.get("physical", 0)
	
	if physical_bytes == 0:
		physical_bytes = mem.get("heap", 0)
	
	var total_mem_mb = physical_bytes / (1024 * 1024)
	var cpu_count = OS.get_processor_count()
	
	if total_mem_mb < 2048 and cpu_count < 4:
		_device_tier = DeviceTier.LOW
	elif total_mem_mb < 4096 and cpu_count < 6:
		_device_tier = DeviceTier.MEDIUM
	elif total_mem_mb < 8192 and cpu_count < 8:
		_device_tier = DeviceTier.HIGH
	else:
		_device_tier = DeviceTier.ULTRA


func record_frame_time(frame_time_ms: float):
	_frame_times.append(frame_time_ms)
	if _frame_times.size() > calibration_samples:
		_frame_times.pop_front()
	
	if _frame_times.size() >= calibration_samples and not _calibrated:
		_complete_calibration()


func record_touch_delta(delta_x: float, delta_y: float):
	_touch_samples.append(sqrt(delta_x * delta_x + delta_y * delta_y))
	if _touch_samples.size() > calibration_samples:
		_touch_samples.pop_front()


func record_memory_usage(memory_mb: float):
	_memory_samples.append(memory_mb)
	if _memory_samples.size() > calibration_samples:
		_memory_samples.pop_front()


func _trim_outliers(values: Array) -> Array:
	if values.size() < 5:
		return values
	
	var sorted = values.duplicate()
	sorted.sort()
	
	var trim_count = max(1, int(values.size() * outlier_trim_ratio))
	
	return sorted.slice(trim_count, -trim_count)


func _calculate_trimmed_mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	
	var trimmed = _trim_outliers(values)
	if trimmed.is_empty():
		return 0.0
	
	var sum = 0.0
	for v in trimmed:
		sum += v
	return sum / trimmed.size()


func _complete_calibration():
	var samples = _frame_times.size()
	if samples < calibration_samples:
		return
	
	var avg_frame = _calculate_trimmed_mean(_frame_times)
	var avg_fps = 1000.0 / avg_frame if avg_frame > 0 else 60.0
	
	var trimmed_frame_times = _trim_outliers(_frame_times)
	var frame_std = 0.0
	for ft in trimmed_frame_times:
		frame_std += (ft - avg_frame) * (ft - avg_frame)
	frame_std = sqrt(frame_std / trimmed_frame_times.size()) if trimmed_frame_times.size() > 0 else 5.0
	
	var avg_touch = _calculate_trimmed_mean(_touch_samples)
	var avg_memory = _calculate_trimmed_mean(_memory_samples)
	
	_device_profile = {
		"avg_fps": avg_fps,
		"avg_frame_ms": avg_frame,
		"frame_std_ms": frame_std,
		"avg_touch_delta": avg_touch,
		"avg_memory_mb": avg_memory,
		"device_tier": _device_tier,
		"calibrated": true
	}
	
	_calibrated = true
	filter_calibrated.emit()
	
	if persist_calibration:
		_save_calibration()


func _save_calibration():
	var cfg = ConfigFile.new()
	for key in _device_profile:
		cfg.set_value("profile", key, _device_profile[key])
	cfg.save(calibration_path)


func _load_calibration() -> bool:
	var cfg = ConfigFile.new()
	if cfg.load(calibration_path) != OK:
		return false
	
	_device_profile.clear()
	for key in cfg.get_section_keys("profile"):
		_device_profile[key] = cfg.get_value("profile", key)
	
	if _device_profile.has("calibrated") and _device_profile["calibrated"]:
		_calibrated = true
		_device_tier = _device_profile.get("device_tier", DeviceTier.MEDIUM)
		return true
	
	return false


func is_calibrated() -> bool:
	return _calibrated


func should_filter_fps(fps: float) -> bool:
	if not _calibrated or filter_level == FilterLevel.OFF:
		return false
	
	var baseline = _device_profile.get("avg_fps", 60.0)
	var should_filter = false
	var threshold = 0.0
	
	match filter_level:
		FilterLevel.LIGHT:
			threshold = baseline * 0.5
			should_filter = fps < threshold
		FilterLevel.MEDIUM:
			threshold = baseline * 0.35
			should_filter = fps < threshold
		FilterLevel.HEAVY:
			threshold = baseline * 0.2
			should_filter = fps < threshold
	
	if should_filter:
		false_positive_detected.emit("fps", fps, threshold)
	
	return should_filter


func should_filter_frame_time(frame_time_ms: float) -> bool:
	if not _calibrated or filter_level == FilterLevel.OFF:
		return false
	
	var baseline = _device_profile.get("avg_frame_ms", 16.67)
	var std = _device_profile.get("frame_std_ms", 5.0)
	var threshold = baseline + std * 2.0
	var should_filter = false
	
	match filter_level:
		FilterLevel.LIGHT:
			threshold = baseline + std * 3.0
			should_filter = frame_time_ms > threshold
		FilterLevel.MEDIUM:
			threshold = baseline + std * 2.0
			should_filter = frame_time_ms > threshold
		FilterLevel.HEAVY:
			threshold = baseline + std * 1.5
			should_filter = frame_time_ms > threshold
	
	if should_filter:
		false_positive_detected.emit("frame_time", frame_time_ms, threshold)
	
	return should_filter


func should_filter_memory(memory_mb: float) -> bool:
	if not _calibrated or filter_level == FilterLevel.OFF:
		return false
	
	var mem = OS.get_memory_info()
	var physical_bytes = mem.get("physical", 0)
	if physical_bytes == 0:
		physical_bytes = mem.get("heap", 0)
	
	var total_mem = physical_bytes / (1024 * 1024)
	var memory_ratio = memory_mb / total_mem if total_mem > 0 else 0.5
	var threshold = 0.0
	var should_filter = false
	
	match filter_level:
		FilterLevel.LIGHT:
			threshold = 0.7
			should_filter = memory_ratio > threshold
		FilterLevel.MEDIUM:
			threshold = 0.8
			should_filter = memory_ratio > threshold
		FilterLevel.HEAVY:
			threshold = 0.85
			should_filter = memory_ratio > threshold
	
	if should_filter:
		false_positive_detected.emit("memory", memory_mb, threshold * total_mem)
	
	return should_filter


func should_filter_touch(delta: float) -> bool:
	if not _calibrated or filter_level == FilterLevel.OFF:
		return false
	
	var baseline = _device_profile.get("avg_touch_delta", 10.0)
	var threshold = baseline * 3.0
	var should_filter = delta > threshold
	
	if should_filter:
		false_positive_detected.emit("touch", delta, threshold)
	
	return should_filter


func get_adjusted_threshold(base_threshold: float, metric: String = "fps") -> float:
	if not _calibrated:
		return base_threshold
	
	match metric:
		"fps":
			var baseline = _device_profile.get("avg_fps", 60.0)
			var factor = baseline / 60.0
			return base_threshold * clamp(factor, 0.5, 1.5)
		
		"frame_time":
			var baseline = _device_profile.get("avg_frame_ms", 16.67)
			var factor = baseline / 16.67
			return base_threshold * clamp(factor, 0.5, 2.0)
		
		"touch":
			var baseline = _device_profile.get("avg_touch_delta", 10.0)
			if baseline < 5.0:
				return base_threshold * 0.7
			elif baseline > 20.0:
				return base_threshold * 1.3
			return base_threshold
	
	return base_threshold


func get_device_profile() -> Dictionary:
	return _device_profile.duplicate()


func get_device_tier() -> DeviceTier:
	return _device_tier


func get_device_tier_name() -> String:
	match _device_tier:
		DeviceTier.LOW:
			return "Low"
		DeviceTier.MEDIUM:
			return "Medium"
		DeviceTier.HIGH:
			return "High"
		DeviceTier.ULTRA:
			return "Ultra"
	return "Unknown"


func reset_calibration():
	_calibrated = false
	_frame_times.clear()
	_touch_samples.clear()
	_memory_samples.clear()
	_device_profile.clear()
	_calibrate()


func set_filter_level(level: int):
	filter_level = level


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERFalsePositiveFilter:
	var filter = DERFalsePositiveFilter.new()
	for key in config:
		if key in filter:
			filter.set(key, config[key])
	
	node.tree_entered.connect(filter.start.bind(), CONNECT_ONE_SHOT)
	return filter