extends RefCounted
class_name VanguardValue

signal value_changed(old_value: Variant, new_value: Variant)
signal access_detected(access_type: String)

enum AccessType { READ, WRITE }

enum ValueType { NULL, BOOL, INT, FLOAT, STRING, ARRAY, DICT }

@export var scan_threshold_read: int = 50
@export var scan_threshold_alternating_ratio: float = 0.7

var _encrypted: PackedByteArray = []
var _key: PackedByteArray = []
var _access_history: Array = []
var _honeypot: Variant = null
var _observer: Callable = Callable()
var _checksum: int = 0

var _read_count: int = 0
var _write_count: int = 0
var _last_access: int = 0
var _is_destroyed: bool = false

static var _pool: Array = []
static var _pool_max: int = 1000


func _init(initial_value: Variant = null):
	_generate_key()
	if initial_value != null:
		set_value(initial_value)


static func pool_get(initial_value: Variant = null) -> VanguardValue:
	if _pool.size() > 0:
		var inst = _pool.pop_back()
		inst._is_destroyed = false
		inst._generate_key()
		if initial_value != null:
			inst.set_value(initial_value)
		return inst
	return VanguardValue.new(initial_value)


func pool_release() -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	_encrypted = []
	_access_history.clear()
	_honeypot = null
	_observer = Callable()
	_checksum = 0
	_read_count = 0
	_write_count = 0
	_last_access = 0
	
	if _pool.size() < _pool_max:
		_pool.append(self)


func _generate_key() -> void:
	_key.resize(32)
	for i in range(32):
		_key[i] = randi() % 256


func set_value(new_value: Variant) -> void:
	if _is_destroyed:
		return
	
	_record_access(AccessType.WRITE)
	var old_value = get_value()
	_encrypted = _encrypt_value(new_value)
	_checksum = _calculate_checksum(_encrypted)
	
	if _observer.is_valid():
		_observer.call(old_value, new_value)
	value_changed.emit(old_value, new_value)


func get_value() -> Variant:
	if _is_destroyed:
		return null
	
	_record_access(AccessType.READ)
	
	if not _verify_checksum(_encrypted, _checksum):
		access_detected.emit("TAMPER_DETECTED")
		return _honeypot if _honeypot != null else null
	
	return _decrypt_value(_encrypted)


func _encrypt_value(value: Variant) -> PackedByteArray:
	var data = _serialize(value)
	if data.is_empty():
		return PackedByteArray()
	
	var encrypted = PackedByteArray()
	encrypted.resize(data.size())
	
	var shift = (_key[0] & 0x7F) % 7 + 1
	
	for i in range(data.size()):
		var b = data[i] ^ _key[i % _key.size()]
		b = ((b << shift) | (b >> (8 - shift))) & 0xFF
		encrypted[i] = b
	
	return encrypted


func _decrypt_value(encrypted: PackedByteArray) -> Variant:
	if encrypted.is_empty():
		return null
	
	var shift = (_key[0] & 0x7F) % 7 + 1
	var data = PackedByteArray()
	data.resize(encrypted.size())
	
	for i in range(encrypted.size()):
		var b = encrypted[i]
		b = ((b >> shift) | (b << (8 - shift))) & 0xFF
		data[i] = b ^ _key[i % _key.size()]
	
	return _deserialize(data)


func _serialize(value: Variant) -> PackedByteArray:
	var type_tag = _get_type_tag(value)
	var out = PackedByteArray()
	out.append(type_tag)
	
	match type_tag:
		ValueType.NULL:
			return out
		ValueType.BOOL:
			out.append(1 if value else 0)
		ValueType.INT:
			var bytes = var_to_bytes(value)
			out.append_array(bytes)
		ValueType.FLOAT:
			var bytes = var_to_bytes(value)
			out.append_array(bytes)
		ValueType.STRING:
			var str_bytes = value.to_utf8_buffer()
			var len_bytes = _int_to_bytes(str_bytes.size())
			out.append_array(len_bytes)
			out.append_array(str_bytes)
		ValueType.ARRAY:
			var json = JSON.stringify(value)
			var json_bytes = json.to_utf8_buffer()
			var len_bytes = _int_to_bytes(json_bytes.size())
			out.append_array(len_bytes)
			out.append_array(json_bytes)
		ValueType.DICT:
			var json = JSON.stringify(value)
			var json_bytes = json.to_utf8_buffer()
			var len_bytes = _int_to_bytes(json_bytes.size())
			out.append_array(len_bytes)
			out.append_array(json_bytes)
		_:
			var json = JSON.stringify(value)
			var json_bytes = json.to_utf8_buffer()
			var len_bytes = _int_to_bytes(json_bytes.size())
			out.append_array(len_bytes)
			out.append_array(json_bytes)
	
	return out


func _deserialize(data: PackedByteArray) -> Variant:
	if data.is_empty():
		return null
	
	var type_tag = data[0]
	var offset = 1
	
	match type_tag:
		ValueType.NULL:
			return null
		ValueType.BOOL:
			return data[offset] == 1
		ValueType.INT:
			var bytes = data.slice(offset, offset + 8)
			return bytes_to_var(bytes)
		ValueType.FLOAT:
			var bytes = data.slice(offset, offset + 4)
			return bytes_to_var(bytes)
		ValueType.STRING:
			var len = _bytes_to_int(data.slice(offset, offset + 4))
			offset += 4
			return data.slice(offset, offset + len).get_string_from_utf8()
		ValueType.ARRAY:
			var len = _bytes_to_int(data.slice(offset, offset + 4))
			offset += 4
			var json_str = data.slice(offset, offset + len).get_string_from_utf8()
			var result = JSON.parse_string(json_str)
			return result if result != null else []
		ValueType.DICT:
			var len = _bytes_to_int(data.slice(offset, offset + 4))
			offset += 4
			var json_str = data.slice(offset, offset + len).get_string_from_utf8()
			var result = JSON.parse_string(json_str)
			return result if result != null else {}
		_:
			var len = _bytes_to_int(data.slice(offset, offset + 4))
			offset += 4
			var json_str = data.slice(offset, offset + len).get_string_from_utf8()
			var result = JSON.parse_string(json_str)
			return result if result != null else json_str


func _int_to_bytes(value: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.resize(4)
	bytes[0] = (value >> 24) & 0xFF
	bytes[1] = (value >> 16) & 0xFF
	bytes[2] = (value >> 8) & 0xFF
	bytes[3] = value & 0xFF
	return bytes


func _bytes_to_int(bytes: PackedByteArray) -> int:
	if bytes.size() < 4:
		return 0
	return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]


func _get_type_tag(value: Variant) -> int:
	match typeof(value):
		TYPE_NIL:
			return ValueType.NULL
		TYPE_BOOL:
			return ValueType.BOOL
		TYPE_INT:
			return ValueType.INT
		TYPE_FLOAT:
			return ValueType.FLOAT
		TYPE_STRING:
			return ValueType.STRING
		TYPE_ARRAY:
			return ValueType.ARRAY
		TYPE_DICTIONARY:
			return ValueType.DICT
		_:
			return ValueType.STRING


func _calculate_checksum(data: PackedByteArray) -> int:
	var sum = 0
	for b in data:
		sum = (sum * 31 + b) & 0xFFFFFFFF
	return sum


func _verify_checksum(data: PackedByteArray, checksum: int) -> bool:
	return _calculate_checksum(data) == checksum


func _record_access(access_type: AccessType) -> void:
	var now = Time.get_ticks_msec()
	_access_history.append({
		"time": now,
		"type": access_type
	})
	
	while _access_history.size() > 100:
		_access_history.pop_front()
	
	match access_type:
		AccessType.READ:
			_read_count += 1
		AccessType.WRITE:
			_write_count += 1
	
	_last_access = now
	_detect_anomaly()


func _detect_anomaly() -> void:
	if _access_history.size() < 10:
		return
	
	var reads = 0
	var writes = 0
	
	for record in _access_history:
		if record["type"] == AccessType.READ:
			reads += 1
		else:
			writes += 1
	
	if reads > scan_threshold_read and writes == 0:
		access_detected.emit("MEMORY_SCAN")
	
	if reads > 0 and writes > 0:
		var alternating = 0
		var last_type = _access_history[0]["type"]
		for i in range(1, _access_history.size()):
			if _access_history[i]["type"] != last_type:
				alternating += 1
			last_type = _access_history[i]["type"]
		
		var ratio = alternating / float(_access_history.size())
		if ratio > scan_threshold_alternating_ratio:
			access_detected.emit("PATTERN_SCAN")


func enable_honeypot(fake_value: Variant) -> void:
	_honeypot = fake_value


func get_honeypot() -> Variant:
	return _honeypot


func set_observer(callback: Callable) -> void:
	_observer = callback


func get_stats() -> Dictionary:
	return {
		"read_count": _read_count,
		"write_count": _write_count,
		"last_access": _last_access,
		"history_size": _access_history.size(),
		"has_honeypot": _honeypot != null,
		"is_destroyed": _is_destroyed
	}


func reset_stats() -> void:
	_read_count = 0
	_write_count = 0
	_access_history.clear()


func is_suspicious() -> bool:
	return _read_count > 1000 or _write_count > 500


func destroy() -> void:
	pool_release()


func _to_string() -> String:
	var val = get_value()
	return "VanguardValue(%s)" % str(val)
