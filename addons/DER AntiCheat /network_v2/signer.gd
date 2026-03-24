class_name DERSigner
extends RefCounted

signal signature_failed(request_id, reason)

enum Algorithm {
	HMAC_SHA256,
	HMAC_SHA1
}

var _key: PackedByteArray
var _algo: int = Algorithm.HMAC_SHA256
var _crypto = Crypto.new()
var _nonce_length: int = 16
var _timestamp_window: float = 300.0
var _used_nonces: Dictionary = {}
var _stats = {"signed": 0, "verified": 0, "failed": 0}

func _init(key: PackedByteArray = PackedByteArray()):
	if key.is_empty():
		key = _crypto.generate_random_bytes(32)
	set_key(key)

func set_key(key: PackedByteArray) -> bool:
	if key.size() < 16:
		push_error("DERSigner: Key must be at least 16 bytes")
		return false
	_key = key
	return true

func sign(path: String, data: Variant, timestamp: int = 0, nonce: String = "") -> Dictionary:
	if timestamp == 0:
		timestamp = Time.get_unix_time_from_system()
	if nonce.is_empty():
		nonce = _generate_nonce()
	
	var body = JSON.stringify(data)
	var message = "%s:%d:%s:%s" % [path, timestamp, nonce, body]
	var signature = _sign_message(message)
	
	_stats.signed += 1
	
	return {
		"timestamp": timestamp,
		"nonce": nonce,
		"signature": signature
	}

func verify(request_id: int, path: String, data: Variant, timestamp: int, nonce: String, signature: String) -> bool:
	var now = Time.get_unix_time_from_system()
	if abs(now - timestamp) > _timestamp_window:
		_stats.failed += 1
		signature_failed.emit(request_id, "timestamp_out_of_window")
		return false
	
	if _is_nonce_reused(nonce, timestamp):
		_stats.failed += 1
		signature_failed.emit(request_id, "nonce_reused")
		return false
	
	var body = JSON.stringify(data)
	var message = "%s:%d:%s:%s" % [path, timestamp, nonce, body]
	var expected = _sign_message(message)
	
	var result = expected == signature
	if result:
		_stats.verified += 1
	else:
		_stats.failed += 1
		signature_failed.emit(request_id, "signature_mismatch")
	
	return result

func get_stats() -> Dictionary:
	return _stats.duplicate()

func _generate_nonce() -> String:
	var bytes = _crypto.generate_random_bytes(_nonce_length)
	return Marshalls.raw_to_base64(bytes)

func _sign_message(msg: String) -> String:
	var bytes = msg.to_utf8_buffer()
	match _algo:
		Algorithm.HMAC_SHA256:
			var hmac = _crypto.hmac_sha256(_key, bytes)
			return Marshalls.raw_to_base64(hmac)
		Algorithm.HMAC_SHA1:
			var hmac = _crypto.hmac_sha1(_key, bytes)
			return Marshalls.raw_to_base64(hmac)
	return ""

func _is_nonce_reused(nonce: String, timestamp: int) -> bool:
	if _used_nonces.has(nonce):
		return true
	var now = Time.get_unix_time_from_system()
	for n in _used_nonces.keys():
		if now - _used_nonces[n] > _timestamp_window:
			_used_nonces.erase(n)
	_used_nonces[nonce] = timestamp
	return false