extends RefCounted
class_name DERVirtualPosDetector

signal location_fake_detected(details: Dictionary)
signal gps_spoof_detected(details: Dictionary)
signal detection_cleared()

enum DetectionLevel {
	BASIC,
	STANDARD,
	ADVANCED,
	AGGRESSIVE
}

enum LocationSource {
	GPS,
	NETWORK,
	UNKNOWN
}

@export var detection_level: DetectionLevel = DetectionLevel.STANDARD
@export var check_interval: float = 5.0
@export var enabled: bool = true
@export var auto_report: bool = true
@export var require_gps: bool = true
@export var max_speed_kmh: float = 300.0
@export var min_accuracy_meters: float = 100.0

var _last_location: Dictionary = {}
var _location_history: Array = []
var _history_size: int = 10
var _detection_count: int = 0
var _is_fake: bool = false
var _check_timer: Timer = null
var _location_source: LocationSource = LocationSource.UNKNOWN
var _logger = null
var _started: bool = false
var _main_loop: MainLoop = null
var _mock_location_apps: Array[String] = [
	"com.lexa.fakegps",
	"com.incorporateapps.fakegps.free",
	"com.robertour.fakegps",
	"com.fakegps.android",
	"com.blueox.fakegps",
	"com.gpsjoystick",
	"com.theappninjas.gpsjoystick",
	"com.sermobile.fakelocation",
	"com.fakelocation.free",
	"com.gpsfake",
	"com.xiaomi.gps",
	"com.lbe.security"
]
var _gms_packages: Array[String] = [
	"com.google.android.gms",
	"com.google.android.gsf",
	"com.android.vending"
]


func _init(logger = null) -> void:
	_logger = logger
	_main_loop = Engine.get_main_loop()


func start() -> void:
	if not enabled or _started:
		return
	_started = true
	_location_history.clear()
	_last_location.clear()
	_detection_count = 0
	_is_fake = false
	_setup_timer()


func stop() -> void:
	if _check_timer:
		_check_timer.stop()
		_check_timer.queue_free()
		_check_timer = null
	_started = false


func _get_main_loop() -> MainLoop:
	if not _main_loop:
		_main_loop = Engine.get_main_loop()
	return _main_loop


func _setup_timer() -> void:
	if _check_timer:
		return
	
	_check_timer = Timer.new()
	_check_timer.wait_time = check_interval
	_check_timer.autostart = true
	_check_timer.timeout.connect(_perform_check)
	
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(_check_timer)
	else:
		_check_timer.queue_free()
		_check_timer = null


func update_location(latitude: float, longitude: float, accuracy: float = -1.0, source: int = 0) -> void:
	if not enabled:
		return
	
	var current_time: float = Time.get_unix_time_from_system()
	var location: Dictionary = {
		"lat": latitude,
		"lon": longitude,
		"accuracy": accuracy,
		"timestamp": current_time,
		"source": source
	}
	
	if _last_location.is_empty():
		_last_location = location
		_location_history.append(location)
		return
	
	var distance: float = _calculate_distance(
		_last_location["lat"], _last_location["lon"],
		location["lat"], location["lon"]
	)
	var time_diff: float = location["timestamp"] - _last_location["timestamp"]
	
	if time_diff > 0.0:
		var speed: float = (distance / 1000.0) / (time_diff / 3600.0)
		location["speed_kmh"] = speed
		location["distance_m"] = distance
	
	_last_location = location
	_location_history.append(location)
	
	if _location_history.size() > _history_size:
		_location_history.pop_front()


func _perform_check() -> void:
	if not enabled or not _started:
		return
	
	var risk_score: float = 0.0
	var details: Dictionary = {
		"timestamp": Time.get_unix_time_from_system(),
		"checks": []
	}
	
	risk_score += _check_location_consistency(details)
	risk_score += _check_mock_location_apps(details)
	risk_score += _check_gps_accuracy(details)
	
	if detection_level >= DetectionLevel.STANDARD:
		risk_score += _check_movement_physics(details)
	
	if detection_level >= DetectionLevel.ADVANCED:
		risk_score += _check_gms_integrity(details)
	
	if detection_level >= DetectionLevel.AGGRESSIVE:
		risk_score += _check_location_jumps(details)
		risk_score += _check_teleportation(details)
	
	var was_fake: bool = _is_fake
	_is_fake = risk_score >= 3.0
	
	if risk_score >= 2.0 and detection_level >= DetectionLevel.AGGRESSIVE:
		_is_fake = true
	
	if _is_fake and not was_fake:
		_detection_count += 1
		details["risk_score"] = risk_score
		details["detection_count"] = _detection_count
		location_fake_detected.emit(details)
		
		if auto_report and _logger and _logger.has_method("warning"):
			_logger.warning("DERVirtualPosDetector", "Location fake detected! Risk: %.2f" % risk_score)
	elif not _is_fake and was_fake and _detection_count > 0:
		_detection_count -= 1
		if _detection_count <= 0:
			_is_fake = false
			_detection_count = 0
			detection_cleared.emit()


func _check_location_consistency(details: Dictionary) -> float:
	if _location_history.size() < 3:
		return 0.0
	
	var inconsistent_count: int = 0
	
	for i in range(1, _location_history.size()):
		var prev = _location_history[i - 1]
		var curr = _location_history[i]
		
		if prev.has("speed_kmh") and curr.has("speed_kmh"):
			var speed_change: float = abs(curr["speed_kmh"] - prev["speed_kmh"])
			if speed_change > 100.0:
				inconsistent_count += 1
	
	if inconsistent_count > _location_history.size() / 2:
		details["checks"].append({"name": "location_consistency", "passed": false, "score": 1.5})
		return 1.5
	
	details["checks"].append({"name": "location_consistency", "passed": true, "score": 0.0})
	return 0.0


func _check_mock_location_apps(details: Dictionary) -> float:
	if OS.get_name() != "Android":
		return 0.0
	
	var found_mock: Array = []
	
	for app in _mock_location_apps:
		if _is_package_installed(app):
			found_mock.append(app)
	
	if found_mock.size() > 0:
		details["checks"].append({"name": "mock_location_apps", "passed": false, "score": 2.0, "found": found_mock})
		gps_spoof_detected.emit({"mock_apps": found_mock})
		return 2.0
	
	details["checks"].append({"name": "mock_location_apps", "passed": true, "score": 0.0})
	return 0.0


func _check_gps_accuracy(details: Dictionary) -> float:
	if not require_gps or _location_history.is_empty():
		return 0.0
	
	var poor_accuracy_count: int = 0
	
	for loc in _location_history:
		if loc.has("accuracy") and loc["accuracy"] > min_accuracy_meters:
			poor_accuracy_count += 1
	
	if poor_accuracy_count > _location_history.size() / 2:
		details["checks"].append({"name": "gps_accuracy", "passed": false, "score": 1.0})
		return 1.0
	
	details["checks"].append({"name": "gps_accuracy", "passed": true, "score": 0.0})
	return 0.0


func _check_movement_physics(details: Dictionary) -> float:
	if _location_history.size() < 3:
		return 0.0
	
	var max_speed: float = 0.0
	
	for loc in _location_history:
		if loc.has("speed_kmh") and loc["speed_kmh"] > max_speed:
			max_speed = loc["speed_kmh"]
	
	if max_speed > max_speed_kmh:
		details["checks"].append({"name": "movement_physics", "passed": false, "score": 2.0, "max_speed": max_speed})
		return 2.0
	
	details["checks"].append({"name": "movement_physics", "passed": true, "score": 0.0})
	return 0.0


func _check_gms_integrity(details: Dictionary) -> float:
	if OS.get_name() != "Android":
		return 0.0
	
	for pkg in _gms_packages:
		if not _is_package_installed(pkg):
			details["checks"].append({"name": "gms_integrity", "passed": false, "score": 1.5, "missing": pkg})
			return 1.5
	
	details["checks"].append({"name": "gms_integrity", "passed": true, "score": 0.0})
	return 0.0


func _check_location_jumps(details: Dictionary) -> float:
	if _location_history.size() < 5:
		return 0.0
	
	var jump_count: int = 0
	
	for i in range(1, _location_history.size()):
		var prev = _location_history[i - 1]
		var curr = _location_history[i]
		
		if prev.has("distance_m") and curr.has("distance_m"):
			if curr["distance_m"] > 50000 and curr["timestamp"] - prev["timestamp"] < 10:
				jump_count += 1
	
	if jump_count >= 2:
		details["checks"].append({"name": "location_jumps", "passed": false, "score": 2.5})
		return 2.5
	
	details["checks"].append({"name": "location_jumps", "passed": true, "score": 0.0})
	return 0.0


func _check_teleportation(details: Dictionary) -> float:
	if _location_history.size() < 2:
		return 0.0
	
	var last = _location_history[-1]
	var prev = _location_history[-2]
	
	if last.has("distance_m") and prev.has("distance_m"):
		if last["distance_m"] > 100000 and last["timestamp"] - prev["timestamp"] < 5:
			details["checks"].append({"name": "teleportation", "passed": false, "score": 3.0})
			return 3.0
	
	details["checks"].append({"name": "teleportation", "passed": true, "score": 0.0})
	return 0.0


func _is_package_installed(package: String) -> bool:
	if OS.get_name() != "Android":
		return false
	
	var output: Array = []
	var exit_code: int = OS.execute("pm", ["list", "packages", package], output, true)
	
	if exit_code != 0:
		return false
	
	for line in output:
		if line.find(package) != -1:
			return true
	
	return false


func _calculate_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var R: float = 6371000.0
	var lat1_rad: float = deg_to_rad(lat1)
	var lat2_rad: float = deg_to_rad(lat2)
	var delta_lat: float = deg_to_rad(lat2 - lat1)
	var delta_lon: float = deg_to_rad(lon2 - lon1)
	
	var a: float = sin(delta_lat / 2.0) * sin(delta_lat / 2.0) + cos(lat1_rad) * cos(lat2_rad) * sin(delta_lon / 2.0) * sin(delta_lon / 2.0)
	var c: float = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
	
	return R * c


func is_fake() -> bool:
	return _is_fake


func get_detection_count() -> int:
	return _detection_count


func get_risk_score() -> float:
	if not _started or _location_history.size() < 3:
		return 0.0
	
	var risk: float = 0.0
	risk += _check_location_consistency({})
	risk += _check_mock_location_apps({})
	risk += _check_gps_accuracy({})
	
	if detection_level >= DetectionLevel.STANDARD:
		risk += _check_movement_physics({})
	
	if detection_level >= DetectionLevel.ADVANCED:
		risk += _check_gms_integrity({})
	
	if detection_level >= DetectionLevel.AGGRESSIVE:
		risk += _check_location_jumps({})
		risk += _check_teleportation({})
	
	return risk


func get_last_location() -> Dictionary:
	return _last_location.duplicate()


func get_location_history() -> Array:
	return _location_history.duplicate()


func reset() -> void:
	_location_history.clear()
	_last_location.clear()
	_detection_count = 0
	_is_fake = false


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop()
	elif not _started:
		start()


func set_detection_level(level: int) -> void:
	detection_level = level


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERVirtualPosDetector:
	var detector = DERVirtualPosDetector.new()
	for key in config:
		if key in detector:
			detector.set(key, config[key])
	
	node.tree_entered.connect(detector.start.bind())
	node.tree_exiting.connect(detector.stop.bind())
	
	return detector