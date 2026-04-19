extends RefCounted
class_name DERSpeedDetectorV2

signal speed_hack_detected(ratio: float, details: Dictionary)
signal detection_cleared()

enum Sensitivity {
	LOW,
	MEDIUM,
	HIGH,
	STRICT
}

@export var sensitivity: Sensitivity = Sensitivity.MEDIUM
@export var check_interval: int = 5
@export var sample_window: int = 30
@export var enabled: bool = true
@export var auto_report: bool = true
@export var min_sample_size: int = 10

var _real_timestamps: Array[float] = []
var _game_deltas: Array[float] = []
var _detection_count: int = 0
var _is_hacked: bool = false
var _last_real_time: float = 0.0
var _frame_counter: int = 0
var _logger = null


func _init(logger = null) -> void:
	_logger = logger
	_reset()


func start() -> void:
	_reset()
	enabled = true


func stop() -> void:
	enabled = false
	_reset()


func set_sensitivity(level: Sensitivity) -> void:
	sensitivity = level


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_reset()


func process_frame(delta: float) -> void:
	if not enabled:
		return
	
	if delta <= 0.0 or delta > 0.5:
		return
	
	var current_real_time: float = Time.get_ticks_msec() / 1000.0
	
	if _last_real_time > 0.0:
		var real_delta: float = current_real_time - _last_real_time
		if real_delta < 1.0:
			_real_timestamps.append(real_delta)
			_game_deltas.append(delta)
			
			if _real_timestamps.size() > sample_window * 2:
				_real_timestamps.pop_front()
				_game_deltas.pop_front()
	
	_last_real_time = current_real_time
	_frame_counter += 1
	
	if _frame_counter >= check_interval:
		_perform_check()
		_frame_counter = 0


func _perform_check() -> void:
	if _real_timestamps.size() < min_sample_size or _game_deltas.size() < min_sample_size:
		return
	
	var sum_real: float = 0.0
	var sum_game: float = 0.0
	var valid_samples: int = 0
	
	for i in range(_real_timestamps.size()):
		if _real_timestamps[i] > 0.0:
			sum_real += _real_timestamps[i]
			sum_game += _game_deltas[i]
			valid_samples += 1
	
	if valid_samples < min_sample_size or sum_real <= 0.0:
		return
	
	var ratio: float = sum_game / sum_real
	var threshold: float = _get_threshold()
	
	if ratio > threshold:
		_detection_count += 1
		var was_hacked: bool = _is_hacked
		_is_hacked = true
		
		if auto_report or not was_hacked:
			var details: Dictionary = {
				"detected_ratio": ratio,
				"threshold": threshold,
				"sensitivity": sensitivity,
				"detection_count": _detection_count,
				"sample_size": valid_samples,
				"timestamp": Time.get_unix_time_from_system()
			}
			speed_hack_detected.emit(ratio, details)
			
			if _logger and _logger.has_method("warning"):
				_logger.warning("DERSpeedDetectorV2", "Speed hack detected! Ratio: %.3f, Threshold: %.3f" % [ratio, threshold])
	else:
		if _is_hacked and _detection_count > 0:
			_detection_count -= 1
			if _detection_count <= 0:
				_is_hacked = false
				_detection_count = 0
				detection_cleared.emit()
				if _logger and _logger.has_method("info"):
					_logger.info("DERSpeedDetectorV2", "Speed hack cleared")


func _get_threshold() -> float:
	match sensitivity:
		Sensitivity.LOW:
			return 1.15
		Sensitivity.MEDIUM:
			return 1.08
		Sensitivity.HIGH:
			return 1.05
		Sensitivity.STRICT:
			return 1.03
	return 1.08


func check() -> float:
	if not enabled or _real_timestamps.size() < min_sample_size:
		return 0.0
	
	var sum_real: float = 0.0
	var sum_game: float = 0.0
	var valid_samples: int = 0
	
	for i in range(_real_timestamps.size()):
		if _real_timestamps[i] > 0.0:
			sum_real += _real_timestamps[i]
			sum_game += _game_deltas[i]
			valid_samples += 1
	
	if valid_samples < min_sample_size or sum_real <= 0.0:
		return 0.0
	
	var ratio: float = sum_game / sum_real
	var threshold: float = _get_threshold()
	
	if ratio > threshold:
		return clamp((ratio - 1.0) / (threshold - 1.0), 0.0, 1.0)
	return 0.0


func is_hacked() -> bool:
	return _is_hacked


func get_detection_count() -> int:
	return _detection_count


func get_current_ratio() -> float:
	if _real_timestamps.size() < min_sample_size:
		return -1.0
	
	var sum_real: float = 0.0
	var sum_game: float = 0.0
	var valid_samples: int = 0
	
	for i in range(_real_timestamps.size()):
		if _real_timestamps[i] > 0.0:
			sum_real += _real_timestamps[i]
			sum_game += _game_deltas[i]
			valid_samples += 1
	
	if valid_samples < min_sample_size or sum_real <= 0.0:
		return -1.0
	
	return sum_game / sum_real


func get_details() -> Dictionary:
	return {
		"enabled": enabled,
		"is_hacked": _is_hacked,
		"detection_count": _detection_count,
		"current_ratio": get_current_ratio(),
		"threshold": _get_threshold(),
		"sensitivity": sensitivity,
		"sample_size": _real_timestamps.size(),
		"min_sample_size": min_sample_size
	}


func reset() -> void:
	_reset()


func _reset() -> void:
	_real_timestamps.clear()
	_game_deltas.clear()
	_detection_count = 0
	_is_hacked = false
	_last_real_time = 0.0
	_frame_counter = 0


func shutdown() -> void:
	_reset()
	enabled = false


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERSpeedDetectorV2:
	var detector = DERSpeedDetectorV2.new()
	for key in config:
		if key in detector:
			detector.set(key, config[key])
	
	node.tree_entered.connect(detector.start.bind())
	node.tree_exiting.connect(detector.shutdown.bind())
	
	return detector