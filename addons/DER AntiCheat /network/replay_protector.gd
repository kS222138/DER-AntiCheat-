class_name DERReplayProtector
extends RefCounted

const DEFAULT_TIME_WINDOW: int = 60000
const MAX_NONCE_AGE: int = 300000
const CLEANUP_INTERVAL: int = 60000
const MAX_NONCE_COUNT: int = 1000

class NonceEntry:
    var timestamp: int
    var request_id: String
    var path: String
    var fingerprint: String
    var signature: String
    
    func _init(p_timestamp: int, p_request_id: String, p_path: String, p_fingerprint: String, p_signature: String = ""):
        timestamp = p_timestamp
        request_id = p_request_id
        path = p_path
        fingerprint = p_fingerprint
        signature = p_signature
    
    func is_expired(current_time: int) -> bool:
        return current_time - timestamp > MAX_NONCE_AGE

var _used_nonces: Dictionary = {}
var _request_ids: Dictionary = {}
var _time_window: int = DEFAULT_TIME_WINDOW
var _last_cleanup: int = 0
var _mutex = Mutex.new()
var _crypto = Crypto.new()
var _secret_key: String = ""
var _stats = {
    "total_generated": 0,
    "total_validated": 0,
    "replay_detected": 0,
    "time_window_rejected": 0,
    "expired_cleaned": 0,
    "invalid_signature": 0
}

func _init(p_time_window: int = DEFAULT_TIME_WINDOW, p_secret_key: String = ""):
    _time_window = p_time_window
    _secret_key = p_secret_key
    _last_cleanup = Time.get_ticks_msec()

func _cleanup():
    var now = Time.get_ticks_msec()
    if now - _last_cleanup < CLEANUP_INTERVAL:
        return
    
    _last_cleanup = now
    
    var expired = []
    for nonce in _used_nonces:
        if _used_nonces[nonce].is_expired(now):
            expired.append(nonce)
    
    for nonce in expired:
        _used_nonces.erase(nonce)
        _stats.expired_cleaned += 1
    
    if _used_nonces.size() > MAX_NONCE_COUNT:
        var entries = []
        for n in _used_nonces:
            entries.append({
                "nonce": n,
                "time": _used_nonces[n].timestamp
            })
        entries.sort_custom(func(a, b): return a.time > b.time)
        for i in range(MAX_NONCE_COUNT, entries.size()):
            _used_nonces.erase(entries[i].nonce)
            _stats.expired_cleaned += 1

func generate_nonce() -> String:
    var bytes = _crypto.generate_random_bytes(16)
    var nonce = Marshalls.raw_to_base64(bytes)
    
    _mutex.lock()
    _stats.total_generated += 1
    _mutex.unlock()
    
    return nonce

func generate_request_id() -> String:
    var crypto = Crypto.new()
    var random_bytes = crypto.generate_random_bytes(8)
    var random = random_bytes.decode_u64(0)
    var id = "req_%d_%d" % [Time.get_unix_time_from_system(), random]
    
    _mutex.lock()
    _request_ids[id] = Time.get_ticks_msec()
    _mutex.unlock()
    
    return id

func sign_request(nonce: String, timestamp: int, secret: String = "") -> String:
    var key = _secret_key if secret.is_empty() else secret
    if key.is_empty():
        return ""
    
    var crypto = Crypto.new()
    var key_bytes = key.to_utf8_buffer()
    var msg = "%s:%d" % [nonce, timestamp]
    var hmac = crypto.hmac_sha256(key_bytes, msg.to_utf8_buffer())
    return Marshalls.raw_to_base64(hmac)

func verify_signature(nonce: String, timestamp: int, signature: String, secret: String = "") -> bool:
    var expected = sign_request(nonce, timestamp, secret)
    return expected == signature

func set_secret_key(key: String) -> void:
    _mutex.lock()
    _secret_key = key
    _mutex.unlock()

func validate_request(nonce: String, timestamp: int, request_id: String, path: String, fingerprint: String, signature: String = "") -> bool:
    _mutex.lock()
    var result = _validate_request_unlocked(nonce, timestamp, request_id, path, fingerprint, signature)
    _mutex.unlock()
    _cleanup()
    return result

func _validate_request_unlocked(nonce: String, timestamp: int, request_id: String, path: String, fingerprint: String, signature: String) -> bool:
    _stats.total_validated += 1
    
    if not _secret_key.is_empty():
        if not verify_signature(nonce, timestamp, signature):
            _stats.invalid_signature += 1
            return false
    
    var server_time = Time.get_unix_time_from_system() * 1000
    var time_diff = abs(server_time - timestamp)
    if time_diff > _time_window:
        _stats.time_window_rejected += 1
        return false
    
    if _used_nonces.has(nonce):
        _stats.replay_detected += 1
        return false
    
    if _request_ids.has(request_id):
        _stats.replay_detected += 1
        return false
    
    _used_nonces[nonce] = NonceEntry.new(Time.get_ticks_msec(), request_id, path, fingerprint, signature)
    _request_ids[request_id] = Time.get_ticks_msec()
    return true

func validate_batch(requests: Array) -> Array:
    var results = []
    _mutex.lock()
    for req in requests:
        var valid = false
        if req.has_all(["nonce", "timestamp", "request_id", "path", "fingerprint"]):
            var signature = req.get("signature", "")
            valid = _validate_request_unlocked(
                req.nonce,
                req.timestamp,
                req.request_id,
                req.path,
                req.fingerprint,
                signature
            )
        results.append(valid)
    _mutex.unlock()
    _cleanup()
    return results

func is_nonce_used(nonce: String) -> bool:
    _mutex.lock()
    var used = _used_nonces.has(nonce)
    _mutex.unlock()
    return used

func get_nonce_info(nonce: String) -> Dictionary:
    _mutex.lock()
    var result = {}
    if _used_nonces.has(nonce):
        var entry = _used_nonces[nonce]
        result = {
            "timestamp": entry.timestamp,
            "request_id": entry.request_id,
            "path": entry.path,
            "fingerprint": entry.fingerprint,
            "signature": entry.signature
        }
    _mutex.unlock()
    return result

func clear_expired():
    _mutex.lock()
    _cleanup()
    _mutex.unlock()

func reset():
    _mutex.lock()
    _used_nonces.clear()
    _request_ids.clear()
    _stats = {
        "total_generated": 0,
        "total_validated": 0,
        "replay_detected": 0,
        "time_window_rejected": 0,
        "expired_cleaned": 0,
        "invalid_signature": 0
    }
    _mutex.unlock()

func get_stats() -> Dictionary:
    _mutex.lock()
    var stats = _stats.duplicate()
    stats.active_nonces = _used_nonces.size()
    stats.active_request_ids = _request_ids.size()
    stats.has_secret_key = not _secret_key.is_empty()
    _mutex.unlock()
    return stats

func set_time_window(ms: int) -> void:
    _mutex.lock()
    _time_window = ms
    _mutex.unlock()