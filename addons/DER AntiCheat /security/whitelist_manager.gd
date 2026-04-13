extends RefCounted
class_name DERWhitelistManager

signal whitelist_updated
signal key_rotated
signal unauthorized_access_attempted(reason: String, details: Dictionary)

enum WhitelistType {
	DEVELOPMENT,
	STAGING,
	PRODUCTION,
	DEBUG,
	RELEASE
}

enum KeyRotationMode {
	MANUAL,
	TIME_BASED,
	USAGE_BASED,
	HYBRID
}

@export var enabled: bool = true
@export var whitelist_type: WhitelistType = WhitelistType.PRODUCTION
@export var key_rotation_mode: KeyRotationMode = KeyRotationMode.TIME_BASED
@export var key_validity_duration: float = 86400.0
@export var max_uses_per_key: int = 1000
@export var auto_rotate_on_invalid: bool = true
@export var enable_device_fingerprint: bool = true
@export var enable_hardware_id_check: bool = true
@export var enable_ip_check: bool = false
@export var allowed_ips: Array[String] = []
@export var persist_keys: bool = true
@export var key_storage_path: String = "user://der_whitelist.cfg"

var _current_key: String = ""
var _key_created_at: float = 0.0
var _key_uses: int = 0
var _device_fingerprint: String = ""
var _hardware_id: String = ""
var _whitelisted_devices: Dictionary = {}
var _temp_whitelist: Dictionary = {}
var _rotation_timer: Timer = null
var _started: bool = false
var _main_loop: MainLoop = null


func _init():
	_main_loop = Engine.get_main_loop()
	_generate_device_fingerprint()
	_generate_hardware_id()
	
	if persist_keys:
		_load_keys()


func start():
	if _started:
		return
	_started = true
	
	if _current_key.is_empty():
		_rotate_key()
	
	if key_rotation_mode == KeyRotationMode.TIME_BASED:
		_setup_rotation_timer()
	
	if whitelist_type == WhitelistType.DEVELOPMENT:
		_add_development_whitelist()


func stop():
	if _rotation_timer:
		_rotation_timer.stop()
		_rotation_timer.queue_free()
		_rotation_timer = null
	_started = false


func _setup_rotation_timer():
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	_rotation_timer = Timer.new()
	_rotation_timer.wait_time = key_validity_duration
	_rotation_timer.autostart = true
	_rotation_timer.timeout.connect(_rotate_key)
	tree.root.add_child(_rotation_timer)


func _generate_device_fingerprint():
	var timezone_offset = Time.get_time_zone_from_system() if Time.has_method("get_time_zone_from_system") else 0
	var timezone_name = str(timezone_offset / 60) + ":" + str(abs(timezone_offset) % 60)
	
	var fingerprint_data = {
		"os": OS.get_name(),
		"processor": OS.get_processor_count(),
		"screen": DisplayServer.screen_get_size(),
		"language": OS.get_locale(),
		"timezone": timezone_name
	}
	
	if OS.has_feature("windows"):
		fingerprint_data["computer_name"] = OS.get_environment("COMPUTERNAME")
	elif OS.has_feature("linux") or OS.has_feature("macos"):
		fingerprint_data["hostname"] = OS.get_environment("HOSTNAME")
	
	var json = JSON.stringify(fingerprint_data)
	_device_fingerprint = json.sha256_text()


func _generate_hardware_id():
	if not enable_hardware_id_check:
		return
	
	var hw_data = []
	
	if OS.has_feature("windows"):
		var output = []
		OS.execute("wmic", ["csproduct", "get", "uuid"], output)
		if output.size() > 1:
			hw_data.append(output[1].strip_edges())
	
	elif OS.has_feature("linux"):
		var paths = ["/etc/machine-id", "/var/lib/dbus/machine-id", "/proc/sys/kernel/random/boot_id"]
		for path in paths:
			var f = FileAccess.open(path, FileAccess.READ)
			if f:
				hw_data.append(f.get_as_text().strip_edges())
				f.close()
	
	elif OS.has_feature("macos"):
		var output = []
		OS.execute("ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"], output)
		for line in output:
			if "IOPlatformUUID" in line:
				var parts = line.split("=")
				if parts.size() > 1:
					hw_data.append(parts[1].strip_edges())
					break
	
	var combined = ",".join(hw_data)
	_hardware_id = combined.sha256_text() if not combined.is_empty() else _device_fingerprint


func _add_development_whitelist():
	add_device(_hardware_id, "development", 86400 * 30)
	add_device(_device_fingerprint, "development_fingerprint", 86400 * 30)


func _rotate_key():
	var old_key = _current_key
	_current_key = _generate_key()
	_key_created_at = Time.get_unix_time_from_system()
	_key_uses = 0
	
	if persist_keys:
		_save_keys()
	
	key_rotated.emit()
	
	if not old_key.is_empty():
		whitelist_updated.emit()


func _generate_key() -> String:
	var timestamp = Time.get_unix_time_from_system()
	var random = randi() % 1000000
	var data = "%d_%d_%s_%s" % [timestamp, random, _device_fingerprint, _hardware_id]
	return data.sha256_text()


func get_current_key() -> String:
	return _current_key


func is_key_valid(key: String) -> bool:
	if not enabled:
		return true
	
	if key == _current_key:
		return true
	
	if whitelist_type == WhitelistType.DEVELOPMENT:
		return true
	
	return false


func use_key(key: String) -> bool:
	if not enabled:
		return true
	
	if key != _current_key:
		unauthorized_access_attempted.emit("Invalid key", {"provided_key": key})
		return false
	
	if key_rotation_mode == KeyRotationMode.USAGE_BASED or key_rotation_mode == KeyRotationMode.HYBRID:
		_key_uses += 1
		if _key_uses >= max_uses_per_key:
			_rotate_key()
	
	return true


func is_device_whitelisted(device_id: String = "") -> bool:
	if not enabled:
		return true
	
	var id = device_id if not device_id.is_empty() else _hardware_id
	
	if _whitelisted_devices.has(id):
		var entry = _whitelisted_devices[id]
		if entry["expires"] > Time.get_unix_time_from_system():
			return true
		else:
			_whitelisted_devices.erase(id)
			whitelist_updated.emit()
	
	if _temp_whitelist.has(id):
		var entry = _temp_whitelist[id]
		if entry["expires"] > Time.get_unix_time_from_system():
			return true
		else:
			_temp_whitelist.erase(id)
			whitelist_updated.emit()
	
	return false


func add_device(device_id: String, reason: String = "", duration: float = 0.0):
	var expires = Time.get_unix_time_from_system() + duration if duration > 0 else 0.0
	
	if duration > 0 and duration <= 86400 * 7:
		_temp_whitelist[device_id] = {
			"reason": reason,
			"expires": expires,
			"added": Time.get_unix_time_from_system()
		}
	else:
		_whitelisted_devices[device_id] = {
			"reason": reason,
			"expires": expires,
			"added": Time.get_unix_time_from_system()
		}
	
	whitelist_updated.emit()


func remove_device(device_id: String):
	if _whitelisted_devices.has(device_id):
		_whitelisted_devices.erase(device_id)
		whitelist_updated.emit()
	
	if _temp_whitelist.has(device_id):
		_temp_whitelist.erase(device_id)
		whitelist_updated.emit()


func is_ip_allowed(ip: String) -> bool:
	if not enable_ip_check:
		return true
	
	if allowed_ips.is_empty():
		return true
	
	for allowed in allowed_ips:
		if ip == allowed or ip.begins_with(allowed.replace("*", "")):
			return true
	
	return false


func get_device_fingerprint() -> String:
	return _device_fingerprint


func get_hardware_id() -> String:
	return _hardware_id


func verify_access(device_id: String = "", ip: String = "") -> Dictionary:
	var result = {
		"allowed": true,
		"reason": "",
		"key_valid": true,
		"device_whitelisted": true,
		"ip_allowed": true
	}
	
	if not enabled:
		return result
	
	if not _current_key.is_empty():
		result.key_valid = true
	else:
		result.allowed = false
		result.reason = "No valid key"
	
	var device_id_to_check = device_id if not device_id.is_empty() else _hardware_id
	result.device_whitelisted = is_device_whitelisted(device_id_to_check)
	
	if not result.device_whitelisted:
		result.allowed = false
		result.reason = "Device not whitelisted"
	
	if enable_ip_check and not ip.is_empty():
		result.ip_allowed = is_ip_allowed(ip)
		if not result.ip_allowed:
			result.allowed = false
			result.reason = "IP not allowed"
	
	if not result.allowed:
		unauthorized_access_attempted.emit(result.reason, {
			"device_id": device_id_to_check,
			"ip": ip,
			"key_valid": result.key_valid
		})
	
	return result


func _save_keys():
	var cfg = ConfigFile.new()
	cfg.set_value("whitelist", "current_key", _current_key)
	cfg.set_value("whitelist", "key_created_at", _key_created_at)
	cfg.set_value("whitelist", "key_uses", _key_uses)
	
	var devices = []
	for device_id in _whitelisted_devices:
		devices.append({
			"id": device_id,
			"reason": _whitelisted_devices[device_id]["reason"],
			"expires": _whitelisted_devices[device_id]["expires"],
			"added": _whitelisted_devices[device_id]["added"]
		})
	cfg.set_value("whitelist", "devices", devices)
	
	var temp_devices = []
	for device_id in _temp_whitelist:
		temp_devices.append({
			"id": device_id,
			"reason": _temp_whitelist[device_id]["reason"],
			"expires": _temp_whitelist[device_id]["expires"],
			"added": _temp_whitelist[device_id]["added"]
		})
	cfg.set_value("whitelist", "temp_devices", temp_devices)
	
	cfg.save(key_storage_path)


func _load_keys():
	var cfg = ConfigFile.new()
	if cfg.load(key_storage_path) != OK:
		return
	
	_current_key = cfg.get_value("whitelist", "current_key", "")
	_key_created_at = cfg.get_value("whitelist", "key_created_at", 0.0)
	_key_uses = cfg.get_value("whitelist", "key_uses", 0)
	
	var devices = cfg.get_value("whitelist", "devices", [])
	for device in devices:
		_whitelisted_devices[device["id"]] = {
			"reason": device["reason"],
			"expires": device["expires"],
			"added": device["added"]
		}
	
	var temp_devices = cfg.get_value("whitelist", "temp_devices", [])
	for device in temp_devices:
		_temp_whitelist[device["id"]] = {
			"reason": device["reason"],
			"expires": device["expires"],
			"added": device["added"]
		}


func add_allowed_ip(ip: String):
	if ip not in allowed_ips:
		allowed_ips.append(ip)
		whitelist_updated.emit()


func remove_allowed_ip(ip: String):
	if ip in allowed_ips:
		allowed_ips.erase(ip)
		whitelist_updated.emit()


func get_whitelisted_devices() -> Dictionary:
	return _whitelisted_devices.duplicate()


func get_temp_whitelist() -> Dictionary:
	return _temp_whitelist.duplicate()


func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"whitelist_type": whitelist_type,
		"key_rotation_mode": key_rotation_mode,
		"key_valid": not _current_key.is_empty(),
		"key_age": Time.get_unix_time_from_system() - _key_created_at if _key_created_at > 0 else 0,
		"key_uses": _key_uses,
		"permanent_devices": _whitelisted_devices.size(),
		"temporary_devices": _temp_whitelist.size(),
		"allowed_ips": allowed_ips.size(),
		"device_fingerprint": _device_fingerprint
	}


func reset():
	_whitelisted_devices.clear()
	_temp_whitelist.clear()
	allowed_ips.clear()
	_rotate_key()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERWhitelistManager:
	var manager = DERWhitelistManager.new()
	for key in config:
		if key in manager:
			manager.set(key, config[key])
	
	node.tree_entered.connect(manager.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(manager.stop.bind())
	return manager