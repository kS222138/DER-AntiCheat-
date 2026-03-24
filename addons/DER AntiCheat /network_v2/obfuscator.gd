class_name DERObfuscator
extends RefCounted

enum ObfuscateLevel {
	NONE,
	LIGHT,
	MEDIUM,
	HEAVY
}

var _level: int = ObfuscateLevel.MEDIUM
var _key: PackedByteArray
var _crypto = Crypto.new()
var _rng = RandomNumberGenerator.new()

func _init():
	_rng.randomize()
	_key = _crypto.generate_random_bytes(32)

func set_level(level: int) -> void:
	_level = level

func set_key(key: PackedByteArray) -> bool:
	if key.size() != 32:
		push_error("DERObfuscator: Key must be 32 bytes, got %d" % key.size())
		return false
	_key = key
	return true

func obfuscate(data: Variant) -> Variant:
	if _level == ObfuscateLevel.NONE:
		return data
	
	var json = JSON.stringify(data)
	var bytes = json.to_utf8_buffer()
	
	match _level:
		ObfuscateLevel.LIGHT:
			bytes = _light(bytes)
		ObfuscateLevel.MEDIUM:
			bytes = _medium(bytes)
		ObfuscateLevel.HEAVY:
			bytes = _heavy(bytes)
	
	return {"_d": Marshalls.raw_to_base64(bytes), "_v": 1}

func deobfuscate(data: Variant) -> Variant:
	if _level == ObfuscateLevel.NONE:
		return data
	
	if not data is Dictionary or not data.has("_d"):
		return data
	
	var bytes = Marshalls.base64_to_raw(data["_d"])
	
	match _level:
		ObfuscateLevel.LIGHT:
			bytes = _light(bytes)
		ObfuscateLevel.MEDIUM:
			bytes = _medium(bytes)
		ObfuscateLevel.HEAVY:
			bytes = _heavy(bytes)
	
	var json = bytes.get_string_from_utf8()
	return JSON.parse_string(json)

func _light(data: PackedByteArray) -> PackedByteArray:
	var out = PackedByteArray()
	out.resize(data.size())
	for i in data.size():
		out[i] = data[i] ^ _key[i % _key.size()]
	return out

func _medium(data: PackedByteArray) -> PackedByteArray:
	var out = PackedByteArray()
	out.resize(data.size() + 4)
	
	var off = _rng.randi() % 256
	out[0] = off
	out[1] = _rng.randi() % 256
	out[2] = _rng.randi() % 256
	out[3] = _rng.randi() % 256
	
	for i in data.size():
		var idx = i + 4
		var val = data[i] ^ _key[(i + off) % _key.size()]
		val = (val + off) & 0xFF
		out[idx] = val
	
	return out

func _heavy(data: PackedByteArray) -> PackedByteArray:
	var out = _medium(data)
	
	var mask = _rng.randi() % 256
	var shift = _rng.randi() % 256
	
	for i in out.size():
		if i % 2 == 0:
			out[i] = out[i] ^ mask
		else:
			out[i] = (out[i] + shift) & 0xFF
	
	out.append(mask)
	out.append(shift)
	out.append(0)
	return out