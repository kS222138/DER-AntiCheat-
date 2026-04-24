extends RefCounted
class_name DERDeviceFingerprint

signal fingerprint_changed(new_fingerprint: String)
signal tamper_detected(reason: String, details: Dictionary)

enum FingerprintStability {
	HIGH,
	MEDIUM,
	LOW,
	VOLATILE
}

enum FingerprintComponent {
	HARDWARE_UUID,
	CPU_SERIAL,
	MAC_ADDRESS,
	DISK_SERIAL,
	BOARD_SERIAL,
	OS_VERSION,
	SCREEN_RESOLUTION,
	GPU_NAME,
	RAM_SIZE,
	STORAGE_SIZE,
	INSTALLATION_PATH
}

@export var enabled: bool = true
@export var stability_level: FingerprintStability = FingerprintStability.HIGH
@export var include_mac: bool = false
@export var include_disk_serial: bool = true
@export var include_os_version: bool = true
@export var include_screen_resolution: bool = true
@export var include_gpu: bool = true
@export var include_ram: bool = true
@export var include_storage: bool = true
@export var include_installation_path: bool = false
@export var salt: String = ""
@export var persist_fingerprint: bool = true
@export var persist_path: String = "user://der_fingerprint.cfg"
@export var enable_anti_tamper: bool = true

var _fingerprint: String = ""
var _fingerprint_hash: String = ""
var _component_hashes: Dictionary = {}
var _tamper_count: int = 0
var _cached_storage_size: int = -1
var _started: bool = false


func _init():
	if not salt.is_empty():
		_apply_salt()
	
	if persist_fingerprint:
		_load_fingerprint()


func start():
	if _started:
		return
	_started = true
	
	if _fingerprint.is_empty():
		_generate_fingerprint()


func _apply_salt():
	pass


func _generate_fingerprint():
	var components = _collect_components()
	
	_component_hashes = {}
	for key in components:
		_component_hashes[key] = components[key].sha256_text()
	
	var combined = ""
	for key in components:
		combined += components[key]
	
	_fingerprint = combined.sha256_text()
	
	if not salt.is_empty():
		_fingerprint = (_fingerprint + salt).sha256_text()
	
	if persist_fingerprint:
		_save_fingerprint()
	
	fingerprint_changed.emit(_fingerprint)


func _collect_components() -> Dictionary:
	var components = {}
	
	if stability_level <= FingerprintStability.HIGH:
		components["hardware_uuid"] = _get_hardware_uuid()
		components["cpu_serial"] = _get_cpu_serial()
		components["board_serial"] = _get_board_serial()
		
		if include_disk_serial:
			components["disk_serial"] = _get_disk_serial()
		
		if include_mac:
			components["mac"] = _get_mac_address()
	
	if stability_level <= FingerprintStability.MEDIUM:
		if include_os_version:
			components["os_version"] = _get_os_version()
		if include_gpu:
			components["gpu"] = _get_gpu_name()
		if include_ram:
			components["ram"] = str(_get_ram_size())
		if include_storage:
			components["storage"] = str(_get_storage_size())
	
	if stability_level <= FingerprintStability.LOW:
		if include_screen_resolution:
			components["screen"] = _get_screen_resolution()
		if include_installation_path:
			components["install_path"] = _get_installation_path()
	
	if stability_level <= FingerprintStability.VOLATILE:
		components["session_id"] = str(Time.get_unix_time_from_system()) + "_" + str(randi())
	
	return components


func _calculate_fingerprint() -> String:
	var components = _collect_components()
	
	var combined = ""
	for key in components:
		combined += components[key]
	
	var result = combined.sha256_text()
	if not salt.is_empty():
		result = (result + salt).sha256_text()
	
	return result


func verify_integrity() -> bool:
	if not enable_anti_tamper:
		return true
	
	var old_fingerprint = _fingerprint
	var current_fingerprint = _calculate_fingerprint()
	
	if old_fingerprint != current_fingerprint:
		_tamper_count += 1
		tamper_detected.emit("fingerprint_mismatch", {
			"old": old_fingerprint,
			"new": current_fingerprint,
			"tamper_count": _tamper_count
		})
		
		if persist_fingerprint:
			_save_fingerprint()
		
		return false
	
	return true


func _get_hardware_uuid() -> String:
	var os_name = OS.get_name()
	
	if os_name == "Windows":
		var output = []
		OS.execute("wmic", ["csproduct", "get", "uuid"], output)
		if output.size() > 1:
			return output[1].strip_edges()
	
	elif os_name == "Linux":
		var paths = ["/sys/class/dmi/id/product_uuid", "/var/lib/dbus/machine-id"]
		for path in paths:
			if FileAccess.file_exists(path):
				var f = FileAccess.open(path, FileAccess.READ)
				if f:
					var content = f.get_as_text().strip_edges()
					f.close()
					if not content.is_empty():
						return content
	
	elif os_name == "macOS":
		var output = []
		OS.execute("ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"], output)
		for line in output:
			if "IOPlatformUUID" in line:
				var parts = line.split("=")
				if parts.size() > 1:
					return parts[1].strip_edges().replace("\"", "")
	
	return "unknown_" + str(randi())


func _get_cpu_serial() -> String:
	var os_name = OS.get_name()
	
	if os_name == "Windows":
		var output = []
		OS.execute("wmic", ["cpu", "get", "processorid"], output)
		if output.size() > 1:
			var serial = output[1].strip_edges()
			if not serial.is_empty() and serial != "ProcessorId":
				return serial
	
	elif os_name == "Linux":
		if FileAccess.file_exists("/proc/cpuinfo"):
			var f = FileAccess.open("/proc/cpuinfo", FileAccess.READ)
			if f:
				var content = f.get_as_text()
				f.close()
				var lines = content.split("\n")
				for line in lines:
					if line.begins_with("Serial"):
						var parts = line.split(":")
						if parts.size() > 1:
							return parts[1].strip_edges()
	
	return "unknown_" + str(randi())


func _get_board_serial() -> String:
	var os_name = OS.get_name()
	
	if os_name == "Windows":
		var output = []
		OS.execute("wmic", ["baseboard", "get", "serialnumber"], output)
		if output.size() > 1:
			var serial = output[1].strip_edges()
			if not serial.is_empty() and serial != "BaseBoard":
				return serial
	
	elif os_name == "Linux":
		var paths = ["/sys/class/dmi/id/board_serial", "/sys/class/dmi/id/product_serial"]
		for path in paths:
			if FileAccess.file_exists(path):
				var f = FileAccess.open(path, FileAccess.READ)
				if f:
					var content = f.get_as_text().strip_edges()
					f.close()
					if not content.is_empty():
						return content
	
	return "unknown_" + str(randi())


func _get_disk_serial() -> String:
	var os_name = OS.get_name()
	
	if os_name == "Windows":
		var output = []
		OS.execute("wmic", ["diskdrive", "get", "serialnumber"], output)
		if output.size() > 1:
			for i in range(1, output.size()):
				var serial = output[i].strip_edges()
				if not serial.is_empty() and serial != "SerialNumber":
					return serial
	
	elif os_name == "Linux":
		var output = []
		OS.execute("lsblk", ["-o", "SERIAL", "-n"], output)
		for line in output:
			var serial = line.strip_edges()
			if not serial.is_empty():
				return serial
	
	return "unknown_" + str(randi())


func _get_mac_address() -> String:
	var interfaces = []
	
	if OS.has_feature("windows"):
		var output = []
		OS.execute("getmac", [], output)
		for line in output:
			if line.find("-") != -1:
				var parts = line.split(" ")
				for part in parts:
					if part.find("-") != -1:
						return part
	else:
		var output = []
		OS.execute("ifconfig", [], output)
		for line in output:
			if line.find("ether") != -1:
				var parts = line.split(" ")
				for part in parts:
					if part.find(":") != -1:
						return part
	
	return "unknown_" + str(randi())


func _get_os_version() -> String:
	var os_name = OS.get_name()
	
	if os_name == "Windows":
		var output = []
		OS.execute("ver", [], output)
		for line in output:
			if line.find("Microsoft") != -1:
				return line
	elif os_name == "Linux":
		if FileAccess.file_exists("/etc/os-release"):
			var f = FileAccess.open("/etc/os-release", FileAccess.READ)
			if f:
				var content = f.get_as_text()
				f.close()
				var lines = content.split("\n")
				for line in lines:
					if line.begins_with("PRETTY_NAME="):
						return line.split("=")[1].strip_edges().replace("\"", "")
	elif os_name == "macOS":
		var output = []
		OS.execute("sw_vers", ["-productVersion"], output)
		if output.size() > 0:
			return output[0].strip_edges()
	
	return os_name + "_" + Engine.get_version_info().get("string", "unknown")


func _get_gpu_name() -> String:
	var output = []
	
	if OS.has_feature("windows"):
		OS.execute("wmic", ["path", "win32_VideoController", "get", "name"], output)
		for line in output:
			var name = line.strip_edges()
			if not name.is_empty() and name != "Name" and name != "win32_VideoController":
				return name
	elif OS.has_feature("linux"):
		OS.execute("lspci", [], output)
		for line in output:
			if line.find("VGA") != -1 or line.find("3D") != -1:
				var parts = line.split(":")
				if parts.size() > 1:
					return parts[1].strip_edges()
	
	return RenderingServer.get_video_adapter_name()


func _get_ram_size() -> int:
	var memory = OS.get_memory_info()
	return memory.get("physical", 0) / (1024 * 1024 * 1024)


func _get_storage_size() -> int:
	if _cached_storage_size > 0:
		return _cached_storage_size
	
	var os_name = OS.get_name()
	
	if os_name == "Windows":
		var output = []
		OS.execute("wmic", ["logicaldisk", "where", "DeviceID='C:'", "get", "Size"], output)
		if output.size() > 1:
			_cached_storage_size = int(output[1].strip_edges()) / (1024 * 1024 * 1024)
			return _cached_storage_size
	
	elif os_name == "Linux":
		var f = FileAccess.open("/sys/block/sda/size", FileAccess.READ)
		if f:
			var sectors = int(f.get_as_text().strip_edges())
			f.close()
			_cached_storage_size = (sectors * 512) / (1024 * 1024 * 1024)
			return _cached_storage_size
	
	_cached_storage_size = 256
	return _cached_storage_size


func _get_screen_resolution() -> String:
	var size = DisplayServer.screen_get_size()
	return str(size.x) + "x" + str(size.y)


func _get_installation_path() -> String:
	return ProjectSettings.globalize_path("res://")


func _save_fingerprint():
	var cfg = ConfigFile.new()
	cfg.set_value("fingerprint", "value", _fingerprint)
	cfg.set_value("fingerprint", "hash", _fingerprint_hash)
	cfg.set_value("fingerprint", "components", _component_hashes)
	cfg.set_value("fingerprint", "tamper_count", _tamper_count)
	cfg.save(persist_path)


func _load_fingerprint():
	var cfg = ConfigFile.new()
	if cfg.load(persist_path) != OK:
		return
	
	_fingerprint = cfg.get_value("fingerprint", "value", "")
	_fingerprint_hash = cfg.get_value("fingerprint", "hash", "")
	_component_hashes = cfg.get_value("fingerprint", "components", {})
	_tamper_count = cfg.get_value("fingerprint", "tamper_count", 0)


func get_fingerprint() -> String:
	return _fingerprint


func get_fingerprint_hash() -> String:
	return _fingerprint_hash


func get_component_hash(component: String) -> String:
	return _component_hashes.get(component, "")


func get_tamper_count() -> int:
	return _tamper_count


func is_trusted() -> bool:
	return _tamper_count == 0


func reset():
	_fingerprint = ""
	_fingerprint_hash = ""
	_component_hashes.clear()
	_tamper_count = 0
	_generate_fingerprint()


func get_components() -> Dictionary:
	return _component_hashes.duplicate()


func get_stability_level() -> int:
	return stability_level


func set_stability_level(level: int):
	stability_level = level
	_generate_fingerprint()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERDeviceFingerprint:
	var fingerprint = DERDeviceFingerprint.new()
	for key in config:
		if key in fingerprint:
			fingerprint.set(key, config[key])
	
	node.tree_entered.connect(fingerprint.start.bind(), CONNECT_ONE_SHOT)
	return fingerprint
