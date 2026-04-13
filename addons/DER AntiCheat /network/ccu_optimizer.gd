extends RefCounted
class_name DERCCUOptimizer

signal optimization_applied(metric: String, old_value: float, new_value: float)
signal player_limit_reached(current: int, max: int)
signal quality_scaled(level: int)

enum OptimizationMode {
	AUTO,
	MANUAL,
	HYBRID
}

enum QualityLevel {
	LOWEST,
	LOW,
	MEDIUM,
	HIGH,
	ULTRA
}

@export var enabled: bool = true
@export var mode: OptimizationMode = OptimizationMode.AUTO
@export var target_fps: int = 60
@export var min_fps: int = 30
@export var max_players: int = 50
@export var quality_scale_interval: float = 5.0
@export var player_check_interval: float = 2.0
@export var enable_dynamic_quality: bool = true
@export var enable_player_limiting: bool = true
@export var enable_lod_scaling: bool = true
@export var enable_shadow_scaling: bool = true
@export var enable_particle_scaling: bool = true
@export var enable_network_throttling: bool = true
@export var quality_base_level: QualityLevel = QualityLevel.HIGH

var _current_quality: QualityLevel = QualityLevel.HIGH
var _current_player_count: int = 0
var _current_fps: float = 60.0
var _quality_timer: Timer = null
var _player_timer: Timer = null
var _optimization_history: Array = []
var _started: bool = false
var _main_loop: MainLoop = null
var _quality_levels: Dictionary = {}


func _init():
	_main_loop = Engine.get_main_loop()
	_init_quality_levels()


func _init_quality_levels():
	_quality_levels = {
		QualityLevel.ULTRA: {
			"lod_distance": 1.0,
			"shadow_quality": 1.0,
			"particle_ratio": 1.0,
			"network_throttle": 0,
			"update_rate": 1.0
		},
		QualityLevel.HIGH: {
			"lod_distance": 0.8,
			"shadow_quality": 0.8,
			"particle_ratio": 0.7,
			"network_throttle": 0,
			"update_rate": 0.9
		},
		QualityLevel.MEDIUM: {
			"lod_distance": 0.6,
			"shadow_quality": 0.5,
			"particle_ratio": 0.5,
			"network_throttle": 0,
			"update_rate": 0.75
		},
		QualityLevel.LOW: {
			"lod_distance": 0.4,
			"shadow_quality": 0.3,
			"particle_ratio": 0.3,
			"network_throttle": 1,
			"update_rate": 0.6
		},
		QualityLevel.LOWEST: {
			"lod_distance": 0.25,
			"shadow_quality": 0.15,
			"particle_ratio": 0.15,
			"network_throttle": 2,
			"update_rate": 0.4
		}
	}


func start():
	if _started:
		return
	_started = true
	_current_quality = quality_base_level
	_setup_timers()


func stop():
	if _quality_timer:
		_quality_timer.stop()
		_quality_timer.queue_free()
		_quality_timer = null
	if _player_timer:
		_player_timer.stop()
		_player_timer.queue_free()
		_player_timer = null
	_started = false


func _setup_timers():
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	if enable_dynamic_quality:
		_quality_timer = Timer.new()
		_quality_timer.wait_time = quality_scale_interval
		_quality_timer.autostart = true
		_quality_timer.timeout.connect(_adjust_quality)
		tree.root.add_child(_quality_timer)
	
	if enable_player_limiting:
		_player_timer = Timer.new()
		_player_timer.wait_time = player_check_interval
		_player_timer.autostart = true
		_player_timer.timeout.connect(_check_player_limit)
		tree.root.add_child(_player_timer)


func update_fps(fps: float):
	_current_fps = fps


func update_player_count(count: int):
	_current_player_count = count
	_check_player_limit()


func _adjust_quality():
	if mode == OptimizationMode.MANUAL:
		return
	
	var target_quality = _calculate_target_quality()
	
	if target_quality != _current_quality:
		var old_quality = _current_quality
		_current_quality = target_quality
		_apply_quality_settings()
		optimization_applied.emit("quality", float(old_quality), float(target_quality))
		quality_scaled.emit(target_quality)


func _calculate_target_quality() -> QualityLevel:
	var fps_ratio = _current_fps / float(target_fps)
	
	if fps_ratio >= 1.0:
		return quality_base_level
	
	var fps_factor = fps_ratio
	
	var player_factor = 1.0
	if _current_player_count > max_players * 0.8:
		player_factor = max(0.5, 1.0 - (_current_player_count - max_players * 0.8) / (max_players * 0.2))
	
	var total_factor = fps_factor * player_factor
	
	if total_factor >= 0.9:
		return quality_base_level
	elif total_factor >= 0.7:
		return _clamp_quality(quality_base_level - 1)
	elif total_factor >= 0.5:
		return _clamp_quality(quality_base_level - 2)
	elif total_factor >= 0.3:
		return _clamp_quality(quality_base_level - 3)
	else:
		return QualityLevel.LOWEST


func _clamp_quality(level: int) -> QualityLevel:
	return clamp(level, QualityLevel.LOWEST, QualityLevel.ULTRA)


func _apply_quality_settings():
	var settings = _quality_levels.get(_current_quality, _quality_levels[QualityLevel.MEDIUM])
	
	if enable_lod_scaling:
		_set_lod_distance(settings["lod_distance"])
	
	if enable_shadow_scaling:
		_set_shadow_quality(settings["shadow_quality"])
	
	if enable_particle_scaling:
		_set_particle_ratio(settings["particle_ratio"])
	
	if enable_network_throttling:
		_set_network_throttle(settings["network_throttle"])
	
	_set_update_rate(settings["update_rate"])


func _set_lod_distance(scale: float):
	var tree = _main_loop
	if tree and tree.has_method("root"):
		var root = tree.root
		if root:
			root.set("lod_distance_scale", scale)


func _set_shadow_quality(scale: float):
	var settings = ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/size")
	if settings:
		var new_size = max(512, int(4096 * scale))
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", new_size)


func _set_particle_ratio(ratio: float):
	var tree = _main_loop
	if tree and tree.has_method("root"):
		var root = tree.root
		if root:
			root.set("particle_amount_ratio", ratio)


func _set_network_throttle(level: int):
	var tree = _main_loop
	if tree and tree.has_method("root"):
		var root = tree.root
		if root and root.has_method("set_network_throttle"):
			root.set_network_throttle(level)


func _set_update_rate(rate: float):
	var tree = _main_loop
	if tree and tree.has_method("root"):
		var root = tree.root
		if root:
			root.set("physics_update_rate", rate)


func _check_player_limit():
	if not enable_player_limiting:
		return
	
	if _current_player_count > max_players:
		player_limit_reached.emit(_current_player_count, max_players)
		
		if mode != OptimizationMode.MANUAL:
			var excess = _current_player_count - max_players
			var reduction_ratio = max(0.7, 1.0 - (excess / float(max_players)))
			_current_quality = _clamp_quality(_current_quality - 1)
			_apply_quality_settings()
			optimization_applied.emit("player_limit", float(_current_player_count), float(max_players))


func get_current_quality() -> int:
	return _current_quality


func get_quality_level_name(level: int) -> String:
	match level:
		QualityLevel.ULTRA:
			return "Ultra"
		QualityLevel.HIGH:
			return "High"
		QualityLevel.MEDIUM:
			return "Medium"
		QualityLevel.LOW:
			return "Low"
		QualityLevel.LOWEST:
			return "Lowest"
	return "Unknown"


func get_quality_settings(level: int) -> Dictionary:
	return _quality_levels.get(level, {}).duplicate()


func get_current_settings() -> Dictionary:
	return get_quality_settings(_current_quality)


func record_optimization_event(metric: String, old_value: float, new_value: float):
	_optimization_history.append({
		"timestamp": Time.get_unix_time_from_system(),
		"metric": metric,
		"old_value": old_value,
		"new_value": new_value
	})
	
	while _optimization_history.size() > 100:
		_optimization_history.pop_front()


func get_optimization_history() -> Array:
	return _optimization_history.duplicate()


func set_quality_manually(level: int):
	if mode == OptimizationMode.AUTO:
		return
	
	_current_quality = _clamp_quality(level)
	_apply_quality_settings()
	quality_scaled.emit(_current_quality)


func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"mode": mode,
		"current_quality": _current_quality,
		"current_quality_name": get_quality_level_name(_current_quality),
		"current_fps": _current_fps,
		"current_players": _current_player_count,
		"max_players": max_players,
		"target_fps": target_fps,
		"min_fps": min_fps,
		"optimization_events": _optimization_history.size()
	}


func reset_stats():
	_optimization_history.clear()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERCCUOptimizer:
	var optimizer = DERCCUOptimizer.new()
	for key in config:
		if key in optimizer:
			optimizer.set(key, config[key])
	
	node.tree_entered.connect(optimizer.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(optimizer.stop.bind())
	return optimizer