extends RefCounted
class_name DERConsistencyValidator

signal inconsistency_detected(validation_type: String, local_value: Variant, server_value: Variant)
signal validation_passed(validation_type: String)
signal throttle_triggered(validation_type: String, wait_time: float)

enum ValidationType {
	POSITION,
	VELOCITY,
	ROTATION,
	HEALTH,
	AMMO,
	SCORE,
	SPEED,
	CUSTOM
}

enum ActionOnViolation {
	LOG_ONLY,
	KICK_PLAYER,
	ROLLBACK,
	FLAG_SUSPICIOUS,
	SHADOW_BAN
}

@export var enabled: bool = true
@export var validation_interval: float = 0.5
@export var max_position_error: float = 5.0
@export var max_velocity_error: float = 10.0
@export var max_rotation_error: float = 15.0
@export var max_health_change_per_sec: float = 100.0
@export var max_ammo_change_per_sec: float = 30.0
@export var max_score_change_per_sec: float = 1000.0
@export var max_speed_multiplier: float = 1.5
@export var action_on_violation: ActionOnViolation = ActionOnViolation.LOG_ONLY
@export var violation_threshold: int = 3
@export var shadow_ban_duration: float = 300.0
@export var enable_throttle: bool = true
@export var throttle_window: float = 5.0
@export var max_validations_per_window: int = 30
@export var http_timeout: float = 5.0
@export var persist_shadow_ban: bool = true
@export var shadow_ban_persist_path: String = "user://der_shadow_ban.cfg"

var _last_server_states: Dictionary = {}
var _last_local_states: Dictionary = {}
var _violation_counts: Dictionary = {}
var _shadow_banned_until: float = 0.0
var _validation_timer: Timer = null
var _throttle_counter: Dictionary = {}
var _throttle_reset_time: float = 0.0
var _started: bool = false
var _main_loop: MainLoop = null
var _pending_http: Array = []


func _init():
	_main_loop = Engine.get_main_loop()
	if persist_shadow_ban:
		_load_shadow_ban()


func start():
	if _started:
		return
	_started = true
	_setup_timer()


func stop():
	if _validation_timer:
		_validation_timer.stop()
		_validation_timer.queue_free()
		_validation_timer = null
	_started = false
	
	for http in _pending_http:
		if is_instance_valid(http):
			http.queue_free()
	_pending_http.clear()


func _setup_timer():
	_validation_timer = Timer.new()
	_validation_timer.wait_time = validation_interval
	_validation_timer.autostart = true
	_validation_timer.timeout.connect(_validate_all)
	
	var tree = _main_loop
	if tree and tree.has_method("root"):
		tree.root.add_child(_validation_timer)
	else:
		await _main_loop.process_frame
		if _main_loop and _main_loop.has_method("root"):
			_main_loop.root.add_child(_validation_timer)


func update_server_state(player_id: String, state: Dictionary):
	if not enabled:
		return
	
	if not _last_server_states.has(player_id):
		_last_server_states[player_id] = {}
	
	for key in state:
		_last_server_states[player_id][key] = state[key]


func update_local_state(player_id: String, state: Dictionary):
	if not enabled:
		return
	
	if is_shadow_banned():
		return
	
	if not _last_local_states.has(player_id):
		_last_local_states[player_id] = {}
	
	for key in state:
		_last_local_states[player_id][key] = state[key]


func _validate_all():
	if not enabled:
		return
	
	if is_shadow_banned():
		return
	
	if not _check_throttle():
		return
	
	for player_id in _last_local_states:
		var local = _last_local_states.get(player_id, {})
		var server = _last_server_states.get(player_id, {})
		
		_validate_position(player_id, local.get("position", null), server.get("position", null))
		_validate_velocity(player_id, local.get("velocity", null), server.get("velocity", null))
		_validate_rotation(player_id, local.get("rotation", null), server.get("rotation", null))
		_validate_health(player_id, local.get("health", null), server.get("health", null))
		_validate_ammo(player_id, local.get("ammo", null), server.get("ammo", null))
		_validate_score(player_id, local.get("score", null), server.get("score", null))
		_validate_speed(player_id, local.get("speed", null), server.get("speed", null))


func _check_throttle() -> bool:
	if not enable_throttle:
		return true
	
	var now = Time.get_ticks_msec() / 1000.0
	if now - _throttle_reset_time > throttle_window:
		_throttle_counter.clear()
		_throttle_reset_time = now
	
	var total = 0
	for count in _throttle_counter.values():
		total += count
	
	if total >= max_validations_per_window:
		return false
	
	return true


func _record_validation(player_id: String):
	if enable_throttle:
		var now = Time.get_ticks_msec() / 1000.0
		if now - _throttle_reset_time > throttle_window:
			_throttle_counter.clear()
			_throttle_reset_time = now
		
		_throttle_counter[player_id] = _throttle_counter.get(player_id, 0) + 1


func _validate_position(player_id: String, local: Variant, server: Variant):
	if not local is Vector3 or not server is Vector3:
		return
	
	var distance = local.distance_to(server)
	if distance > max_position_error:
		_handle_violation(player_id, "POSITION", local, server)


func _validate_velocity(player_id: String, local: Variant, server: Variant):
	if not local is Vector3 or not server is Vector3:
		return
	
	var diff = (local - server).length()
	if diff > max_velocity_error:
		_handle_violation(player_id, "VELOCITY", local, server)


func _validate_rotation(player_id: String, local: Variant, server: Variant):
	if not local is Vector3 or not server is Vector3:
		return
	
	if local.length_squared() == 0 or server.length_squared() == 0:
		return
	
	var local_dir = local.normalized()
	var server_dir = server.normalized()
	var dot = clamp(local_dir.dot(server_dir), -1.0, 1.0)
	var angle_diff = rad_to_deg(acos(dot))
	
	if angle_diff > max_rotation_error:
		_handle_violation(player_id, "ROTATION", local, server)


func _validate_health(player_id: String, local: Variant, server: Variant):
	if not local is float and not local is int:
		return
	if not server is float and not server is int:
		return
	
	local = float(local)
	server = float(server)
	var diff = abs(local - server)
	if diff > max_health_change_per_sec * validation_interval:
		_handle_violation(player_id, "HEALTH", local, server)


func _validate_ammo(player_id: String, local: Variant, server: Variant):
	if not local is int:
		return
	if not server is int:
		return
	
	var diff = abs(local - server)
	if diff > max_ammo_change_per_sec * validation_interval:
		_handle_violation(player_id, "AMMO", local, server)


func _validate_score(player_id: String, local: Variant, server: Variant):
	if not local is int:
		return
	if not server is int:
		return
	
	var diff = abs(local - server)
	if diff > max_score_change_per_sec * validation_interval:
		_handle_violation(player_id, "SCORE", local, server)


func _validate_speed(player_id: String, local: Variant, server: Variant):
	if not local is float and not local is int:
		return
	if not server is float and not server is int:
		return
	
	local = float(local)
	server = float(server)
	var ratio = local / server if server > 0 else 1.0
	if ratio > max_speed_multiplier:
		_handle_violation(player_id, "SPEED", local, server)


func _handle_violation(player_id: String, vtype: String, local: Variant, server: Variant):
	_record_validation(player_id)
	
	_violation_counts[player_id] = _violation_counts.get(player_id, 0) + 1
	inconsistency_detected.emit(vtype, local, server)
	
	var count = _violation_counts[player_id]
	
	match action_on_violation:
		ActionOnViolation.LOG_ONLY:
			pass
		
		ActionOnViolation.KICK_PLAYER:
			if count >= violation_threshold:
				_kick_player(player_id)
		
		ActionOnViolation.ROLLBACK:
			_rollback_state(player_id, vtype.to_lower())
		
		ActionOnViolation.FLAG_SUSPICIOUS:
			if count >= violation_threshold:
				_flag_suspicious(player_id)
		
		ActionOnViolation.SHADOW_BAN:
			if count >= violation_threshold:
				_shadow_ban()


func _kick_player(player_id: String):
	if _main_loop and _main_loop is SceneTree:
		if not OS.has_feature("editor"):
			_main_loop.quit()


func _rollback_state(player_id: String, field: String):
	var server_state = _last_server_states.get(player_id, {})
	if server_state.has(field):
		if not _last_local_states.has(player_id):
			_last_local_states[player_id] = {}
		_last_local_states[player_id][field] = server_state[field]


func _flag_suspicious(player_id: String):
	var data = {
		"player_id": player_id,
		"violations": _violation_counts.get(player_id, 0),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	var http = HTTPRequest.new()
	http.timeout = http_timeout
	tree.root.add_child(http)
	_pending_http.append(http)
	
	var body = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	http.request_completed.connect(_on_http_complete.bind(http), CONNECT_ONE_SHOT)
	http.request("https://your-server.com/api/anticheat/suspicious", headers, HTTPClient.METHOD_POST, body)


func _on_http_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest):
	if http in _pending_http:
		_pending_http.erase(http)
	if is_instance_valid(http):
		http.queue_free()


func _shadow_ban():
	_shadow_banned_until = Time.get_unix_time_from_system() + shadow_ban_duration
	if persist_shadow_ban:
		_save_shadow_ban()


func _save_shadow_ban():
	var cfg = ConfigFile.new()
	cfg.set_value("shadow_ban", "until", _shadow_banned_until)
	cfg.save(shadow_ban_persist_path)


func _load_shadow_ban():
	var cfg = ConfigFile.new()
	if cfg.load(shadow_ban_persist_path) == OK:
		_shadow_banned_until = cfg.get_value("shadow_ban", "until", 0.0)


func is_shadow_banned() -> bool:
	var now = Time.get_unix_time_from_system()
	if now >= _shadow_banned_until:
		if persist_shadow_ban and _shadow_banned_until > 0:
			_clear_shadow_ban_file()
		return false
	return true


func _clear_shadow_ban_file():
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove(shadow_ban_persist_path)


func get_violation_count(player_id: String) -> int:
	return _violation_counts.get(player_id, 0)


func reset_violations(player_id: String):
	_violation_counts.erase(player_id)


func clear_all_data():
	_last_server_states.clear()
	_last_local_states.clear()
	_violation_counts.clear()
	_shadow_banned_until = 0.0
	_throttle_counter.clear()
	
	if persist_shadow_ban:
		_clear_shadow_ban_file()


func get_stats() -> Dictionary:
	var total_violations = 0
	for count in _violation_counts.values():
		total_violations += count
	
	return {
		"active_players": _last_local_states.size(),
		"total_violations": total_violations,
		"shadow_banned": is_shadow_banned(),
		"enabled": enabled
	}


func set_custom_validator(validator_name: String, validator_func: Callable):
	var key = "CUSTOM_" + validator_name
	self["_validate_" + key.to_lower()] = validator_func


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERConsistencyValidator:
	var validator = DERConsistencyValidator.new()
	for key in config:
		if key in validator:
			validator.set(key, config[key])
	
	node.tree_entered.connect(validator.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(validator.stop.bind())
	return validator