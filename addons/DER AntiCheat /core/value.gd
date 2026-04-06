class_name value
extends RefCounted

enum CheatType {
	NONE,
	MEMORY_EDITOR,
	SPEED_HACK,
	DEBUGGER,
	HOOK,
	HEMOLOADER,
	UNKNOWN
}

enum ViolationLevel {
	SUSPICIOUS,
	CONFIRMED,
	IMMEDIATE,
	ANNIHILATE
}

var _encrypted_segments: Dictionary = {}
var _xor_key: int
var _obfuscation_pattern: PackedByteArray
var _segment_locations: Array = []
var _validator_chain: Array[Callable] = []
var _last_verify_time: int = 0
var _verify_interval: int = 500
var _last_read: int = 0
var _read_count: int = 0
var _access_timestamps: Array = []
var _access_pattern_hash: int = 0
var _integrity_token: int = 0
var _checksum: int = 0
var _bait_system
var _bait_values: Array = []
var _detected_cheat_type: CheatType = CheatType.NONE
var _honeypot_active: bool = false
var _memory_fingerprint: Dictionary = {}
var _rng = RandomNumberGenerator.new()
var _value_type: int = 0
var _creation_time: int = 0
var _last_value: Variant = null
var _validator = null

const HEMOLOADER_MARKERS = [
	"HemoLoader Hook",
	"var _hemo_loader",
	"_hemo_original_",
	"call_hook",
	".script_backup/",
	"HemoHookGenerator",
	"HemoLoaderStore",
	"install_script_hooks",
    "add_hook"
]

const HEMOLOADER_SCRIPT_PATHS = [
	"res://addons/hemoloader/",
    "res://mods/"
]

static var _hemoloader_global_detected: bool = false
static var _hemoloader_detection_time: int = 0
static var _hemoloader_attack_count: int = 0
static var _hemoloader_scripts_cached: Array = []
var _self_script_path: String = ""
var _hemoloader_hook_check_timer: int = 0

func _init(initial_value: Variant, validator_obj = null):
	if not _hemoloader_global_detected:
		_detect_global_hemoloader()
		if _hemoloader_global_detected:
			_hemoloader_detection_time = Time.get_ticks_usec()
			_trigger_protocol(ViolationLevel.IMMEDIATE)
	
	_self_script_path = get_script().resource_path
	if _check_script_for_hooks(_self_script_path):
		_detected_cheat_type = CheatType.HEMOLOADER
		_hemoloader_attack_count += 1
		_trigger_protocol(ViolationLevel.ANNIHILATE)
	
	_rng.randomize()
	_creation_time = Time.get_ticks_usec()
	_value_type = typeof(initial_value)
	_last_value = initial_value
	_validator = validator_obj
	
	var time_seed = Time.get_ticks_usec()
	var pid_seed = _get_process_id()
	var stack_seed = _get_stack_hash()
	_xor_key = _rng.randi() ^ time_seed ^ pid_seed ^ stack_seed
	
	_encrypted_segments = _segment_and_encrypt(initial_value)
	_obfuscation_pattern = _generate_obfuscation_pattern()
	_setup_verification_chain()
	_bait_system = self
	_generate_baits()
	_memory_fingerprint = _generate_fingerprint()
	_update_checksum()
	_last_read = Time.get_ticks_usec()
	
	_hemoloader_hook_check_timer = _creation_time

func get_value() -> Variant:
	var current_time = Time.get_ticks_usec()
	var time_since_last = current_time - _last_read
	_last_read = current_time
	_read_count += 1
	
	if current_time - _hemoloader_hook_check_timer > 10000:
		_hemoloader_hook_check_timer = current_time
		if Engine.has_singleton("HemoLoader"):
			var loader = Engine.get_singleton("HemoLoader")
			if loader and loader.has_method("call_hook"):
				var result = loader.call_hook(self, "get_value", [])
				if result.should_return:
					_detected_cheat_type = CheatType.HEMOLOADER
					_hemoloader_attack_count += 1
					_trigger_protocol(ViolationLevel.CONFIRMED)
					return _generate_honeypot_value()
	
	_access_timestamps.append(current_time)
	if _access_timestamps.size() > 100:
		_access_timestamps.pop_front()
	
	var behavior_risk = _analyze_behavior(time_since_last)
	if behavior_risk > 0.7:
		_detected_cheat_type = CheatType.SPEED_HACK
		_trigger_protocol(ViolationLevel.CONFIRMED)
		return _generate_honeypot_value()
	
	if not _quick_verify():
		_detected_cheat_type = CheatType.MEMORY_EDITOR
		_trigger_protocol(ViolationLevel.IMMEDIATE)
		return _generate_honeypot_value()
	
	if current_time - _last_verify_time > _verify_interval:
		if not _full_verify():
			_detected_cheat_type = CheatType.HOOK
			_trigger_protocol(ViolationLevel.CONFIRMED)
		_last_verify_time = current_time
	
	var value = _decrypt_and_assemble()
	value = _mix_with_baits(value)
	_update_access_pattern()
	_last_value = value
	return value

func set_value(new_value: Variant) -> void:
	_encrypted_segments = _segment_and_encrypt(new_value)
	_generate_baits()
	_update_checksum()
	_last_value = new_value

func verify() -> bool:
	if not _full_verify():
		return false
	if _check_script_for_hooks(_self_script_path):
		_detected_cheat_type = CheatType.HEMOLOADER
		_trigger_protocol(ViolationLevel.CONFIRMED)
		return false
	return true

func get_detected_cheat_type() -> CheatType:
	return _detected_cheat_type

func reset_detection() -> void:
	_detected_cheat_type = CheatType.NONE
	_honeypot_active = false

func _segment_and_encrypt(value: Variant) -> Dictionary:
	var bytes = var_to_bytes(value)
	var segments = {}
	var segment_count = maxi(3, bytes.size() / 4 + 2)
	
	_segment_locations.clear()
	
	for i in range(segment_count):
		var segment_data = PackedByteArray()
		
		if i < bytes.size() / 4:
			var start = i * 4
			var end = mini(start + 4, bytes.size())
			segment_data = bytes.slice(start, end)
			
			segment_data = _xor_encrypt(segment_data, _xor_key + i)
			segment_data = _shift_encrypt(segment_data, (i % 8))
		else:
			segment_data = _generate_garbage_segment()
		
		var storage_id = _get_scattered_storage_id(i)
		segments[storage_id] = segment_data
		_segment_locations.append(storage_id)
	
	for i in range(2):
		var garbage_id = _get_scattered_storage_id(-i - 1)
		segments[garbage_id] = _generate_garbage_segment()
	
	return segments

func _xor_encrypt(data: PackedByteArray, key: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(data.size())
	
	for i in range(data.size()):
		result[i] = data[i] ^ ((key >> (i % 4)) & 0xFF)
	
	return result

func _shift_encrypt(data: PackedByteArray, bits: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(data.size())
	
	for i in range(data.size()):
		result[i] = ((data[i] << bits) | (data[i] >> (8 - bits))) & 0xFF
	
	return result

func _generate_obfuscation_pattern() -> PackedByteArray:
	var pattern = PackedByteArray()
	pattern.resize(32)
	
	for i in range(32):
		pattern[i] = _rng.randi() % 256
	
	return pattern

func _generate_garbage_segment() -> PackedByteArray:
	var size = _rng.randi_range(2, 8)
	var garbage = PackedByteArray()
	garbage.resize(size)
	
	for i in range(size):
		garbage[i] = _rng.randi() % 256
	
	return garbage

func _get_scattered_storage_id(seed: int) -> int:
	var hash_val = hash(str(seed) + str(_xor_key) + str(Time.get_ticks_usec()))
	return abs(hash_val) % 1000000

func _decrypt_and_assemble() -> Variant:
	var all_bytes = PackedByteArray()
	
	for loc in _segment_locations:
		if _encrypted_segments.has(loc):
			var encrypted = _encrypted_segments[loc]
			var index = _segment_locations.find(loc)
			var decrypted = _shift_decrypt(encrypted, (index % 8))
			decrypted = _xor_decrypt(decrypted, _xor_key + index)
			all_bytes.append_array(decrypted)
	
	if all_bytes.size() == 0:
		return null
	
	return bytes_to_var(all_bytes)

func _shift_decrypt(data: PackedByteArray, bits: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(data.size())
	
	for i in range(data.size()):
		result[i] = ((data[i] >> bits) | (data[i] << (8 - bits))) & 0xFF
	
	return result

func _xor_decrypt(data: PackedByteArray, key: int) -> PackedByteArray:
	return _xor_encrypt(data, key)

func _setup_verification_chain():
	_validator_chain = [
		func() -> bool: return _check_temporal_consistency(),
		func() -> bool: return _check_memory_pattern(),
		func() -> bool: return _check_callstack_integrity(),
		func() -> bool: return _check_antidebug(),
		func() -> bool: return _verify_checksum(),
		func() -> bool: return _verify_baits(),
		func() -> bool: return _check_hemoloader_hooks()
	]
	
	_validator_chain.shuffle()

func _quick_verify() -> bool:
	for loc in _segment_locations:
		if not _encrypted_segments.has(loc):
			return false
	
	var quick_sum = 0
	for loc in _segment_locations:
		if _encrypted_segments.has(loc):
			for byte in _encrypted_segments[loc]:
				quick_sum += byte
	
	return quick_sum == (_checksum & 0xFFFF)

func _full_verify() -> bool:
	_validator_chain.shuffle()
	
	for validator in _validator_chain:
		if not validator.call():
			return false
	
	return true

func _check_temporal_consistency() -> bool:
	if _access_timestamps.size() < 5:
		return true
	
	var intervals = []
	for i in range(1, _access_timestamps.size()):
		intervals.append(_access_timestamps[i] - _access_timestamps[i-1])
	
	var avg = 0.0
	for interval in intervals:
		avg += interval
	avg /= intervals.size()
	
	for interval in intervals:
		if interval < avg * 0.3:
			return false
	
	return true

func _check_memory_pattern() -> bool:
	var current_pattern = _calculate_pattern_hash()
	return current_pattern == _access_pattern_hash

func _check_callstack_integrity() -> bool:
	var stack = get_stack()
	for frame in stack:
		var source = frame.get("source", "")
		for path in HEMOLOADER_SCRIPT_PATHS:
			if source.begins_with(path):
				return false
	return true

func _check_antidebug() -> bool:
	var debug_detected = false
	
	if OS.has_feature("editor"):
		debug_detected = true
	
	var start = Time.get_ticks_usec()
	for i in range(10000):
		var temp = i * i
	var elapsed = Time.get_ticks_usec() - start
	
	if elapsed > 5000:
		debug_detected = true
	
	return not debug_detected

func _verify_checksum() -> bool:
	var current_checksum = _calculate_checksum()
	return current_checksum == _integrity_token

func _calculate_checksum() -> int:
	var checksum = _xor_key
	
	for loc in _encrypted_segments:
		for byte in _encrypted_segments[loc]:
			checksum = ((checksum << 5) + checksum) + byte
	
	return checksum

func _update_checksum() -> void:
	_checksum = _calculate_checksum()
	_integrity_token = _checksum

func _generate_baits():
	_bait_values.clear()
	var real_value = _decrypt_and_assemble()
	var bait_count = _rng.randi_range(5, 10)
	
	for i in range(bait_count):
		match _value_type:
			TYPE_INT:
				var offset = _rng.randi_range(-20, 20)
				if offset == 0:
					offset = 1
				_bait_values.append(real_value + offset)
			TYPE_FLOAT:
				var offset = _rng.randf_range(-2.0, 2.0)
				if abs(offset) < 0.1:
					offset = 0.5
				_bait_values.append(real_value + offset)
			TYPE_STRING:
				_bait_values.append(str(real_value) + "_" + str(_rng.randi_range(100, 999)))
			_:
				_bait_values.append(real_value)

func _mix_with_baits(value: Variant) -> Variant:
	if _rng.randf() < 0.3 and _bait_values.size() > 0:
		return _bait_values[_rng.randi() % _bait_values.size()]
	return value

func _verify_baits() -> bool:
	if _bait_values.size() < 3:
		return false
	
	if _hemoloader_global_detected and _bait_values.size() > 10:
		return false
	
	return true

func _check_hemoloader_hooks() -> bool:
	if _check_script_for_hooks(_self_script_path):
		return false
	return true

func _generate_honeypot_value() -> Variant:
	_honeypot_active = true
	var real_value = _decrypt_and_assemble()
	
	if _detected_cheat_type == CheatType.HEMOLOADER:
		printerr("DER: HemoLoader detected - triggering anti-cheat")
		assert(false, "HemoLoader detected")
	
	match _detected_cheat_type:
		CheatType.MEMORY_EDITOR:
			match _value_type:
				TYPE_INT:
					return real_value + _rng.randi_range(50, 200)
				TYPE_FLOAT:
					return real_value + _rng.randf_range(5.0, 20.0)
				_:
					return real_value
		CheatType.SPEED_HACK:
			return real_value
		CheatType.DEBUGGER:
			return null
		CheatType.HOOK:
			return _rng.randi()
		CheatType.HEMOLOADER:
			return _rng.randi()
		_:
			return real_value

func _analyze_behavior(time_since_last: int) -> float:
	var risk = 0.0
	var elapsed = max(1, Time.get_ticks_usec() - _creation_time)
	var reads_per_second = _read_count / (elapsed / 1000000.0)
	
	if reads_per_second > 1000:
		risk += 0.5
	
	if time_since_last < 100 and _read_count > 100:
		risk += 0.4
	
	if _hemoloader_attack_count > 0:
		risk += 0.3
	
	return mini(risk, 1.0)

func _update_access_pattern():
	_access_pattern_hash = _calculate_pattern_hash()

func _calculate_pattern_hash() -> int:
	var pattern = 0
	var size = mini(10, _access_timestamps.size())
	
	for i in range(size):
		pattern ^= _access_timestamps[-i - 1] & 0xFF
	
	return pattern

func _generate_fingerprint() -> Dictionary:
	return {
		"instance_id": self.get_instance_id(),
		"xor_key_hash": hash(_xor_key),
		"segment_count": _encrypted_segments.size(),
		"creation_time": _creation_time,
		"value_type": _value_type,
		"hemoloader_detected": _hemoloader_global_detected,
		"hemoloader_attacks": _hemoloader_attack_count
	}

func _trigger_protocol(level: ViolationLevel):
	match level:
		ViolationLevel.SUSPICIOUS:
			pass
		ViolationLevel.CONFIRMED:
			_honeypot_active = true
		ViolationLevel.IMMEDIATE:
			_honeypot_active = true
			_detected_cheat_type = CheatType.HEMOLOADER
		ViolationLevel.ANNIHILATE:
			_honeypot_active = true
			_detected_cheat_type = CheatType.HEMOLOADER
			printerr("DER CRITICAL: HemoLoader injection detected - shutting down")
			assert(false, "HemoLoader injection detected")

func _get_process_id() -> int:
	if OS.has_feature("editor"):
		return OS.get_process_id()
	return randi()

func _get_stack_hash() -> int:
	return hash(get_stack())

func get_random_bait() -> Variant:
	if _bait_values.size() > 0:
		return _bait_values[_rng.randi() % _bait_values.size()]
	return null

func get_stats() -> Dictionary:
	return {
		"reads": _read_count,
		"verifies": _read_count,
		"tampers": 1 if _detected_cheat_type != CheatType.NONE else 0,
		"baits": _bait_values.size(),
		"segments": _encrypted_segments.size(),
		"type": _value_type,
		"last_value": _last_value,
		"hemoloader_detected": _hemoloader_global_detected,
		"hemoloader_attacks": _hemoloader_attack_count
	}

func _detect_global_hemoloader() -> void:
	if Engine.has_singleton("HemoLoader"):
		_hemoloader_global_detected = true
		return
	
	if DirAccess.dir_exists_absolute("res://addons/hemoloader/"):
		_hemoloader_global_detected = true
		return
	
	if _hemoloader_scripts_cached.is_empty():
		_scan_for_hemoloader_scripts()
	
	if not _hemoloader_scripts_cached.is_empty():
		_hemoloader_global_detected = true
		return

func _scan_for_hemoloader_scripts() -> void:
	var dirs_to_check = ["res://addons/", "res://mods/"]
	for base_dir in dirs_to_check:
		if DirAccess.dir_exists_absolute(base_dir):
			var dir = DirAccess.open(base_dir)
			if dir:
				dir.list_dir_begin()
				var file_name = dir.get_next()
				while file_name != "":
					if file_name.contains("hemo") or file_name.contains("Hemo"):
						_hemoloader_scripts_cached.append(base_dir + file_name)
					file_name = dir.get_next()
				dir.list_dir_end()

func _check_script_for_hooks(script_path: String) -> bool:
	if not FileAccess.file_exists(script_path):
		return false
	
	var file = FileAccess.open(script_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	for marker in HEMOLOADER_MARKERS:
		if content.contains(marker):
			return true
	
	return false
