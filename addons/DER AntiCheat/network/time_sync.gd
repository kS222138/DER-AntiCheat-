class_name DERTimeSync
extends RefCounted

const DEFAULT_SYNC_INTERVAL: int = 60000
const DEFAULT_SAMPLE_COUNT: int = 15
const MAX_TIME_OFFSET: int = 300000
const SYNC_TIMEOUT: int = 5000
const MIN_SAMPLES_FOR_SYNC: int = 3

var _server_time_offset: int = 0
var _last_sync_time: int = 0
var _sync_interval: int = DEFAULT_SYNC_INTERVAL
var _sample_count: int = DEFAULT_SAMPLE_COUNT
var _time_samples: Array = []
var _mutex = Mutex.new()
var _http_node: Node
var _endpoint: String
var _sync_in_progress: bool = false
var _pending_callbacks: Array = []
var _crypto = Crypto.new()
var _trusted_cert: X509Certificate = null
var _shared_secret: PackedByteArray = []
var _stats = {
    "sync_attempts": 0,
    "sync_success": 0,
    "sync_failed": 0,
    "last_offset": 0,
    "avg_latency": 0,
    "min_latency": 0,
    "max_latency": 0,
    "security_errors": 0
}

signal time_synced(offset: int, latency: int)
signal sync_failed(error: String)

func _init(endpoint: String, http_node: Node):
    if not endpoint.begins_with("https://"):
        push_error("DERTimeSync: HTTP is not allowed, use HTTPS")
        _endpoint = "https://" + endpoint.trim_prefix("http://")
    else:
        _endpoint = endpoint
    _http_node = http_node
    _last_sync_time = Time.get_ticks_msec()

func set_trusted_cert(cert_path: String) -> bool:
    if not FileAccess.file_exists(cert_path):
        return false
    
    var file = FileAccess.open(cert_path, FileAccess.READ)
    if not file:
        return false
    
    var cert = X509Certificate.new()
    if cert.load(file.get_as_text()) != OK:
        return false
    
    _trusted_cert = cert
    return true

func set_shared_secret(secret: PackedByteArray) -> void:
    _shared_secret = secret

func sync_time(callback: Callable = Callable()) -> void:
    _mutex.lock()
    if _sync_in_progress:
        if callback.is_valid():
            _pending_callbacks.append(callback)
        _mutex.unlock()
        return
    
    _sync_in_progress = true
    if callback.is_valid():
        _pending_callbacks.append(callback)
    _mutex.unlock()
    
    _stats.sync_attempts += 1
    _perform_time_sync()

func _perform_time_sync():
    var client_time = Time.get_unix_time_from_system() * 1000
    var start_time = Time.get_ticks_usec()
    var nonce = _crypto.generate_random_bytes(16)
    
    var http = HTTPRequest.new()
    _http_node.add_child(http)
    http.timeout = SYNC_TIMEOUT / 1000.0
    
    if _trusted_cert:
        var tls_opts = TLSOptions.client(_trusted_cert)
        http.set_tls_options(tls_opts)
    
    var headers = ["Content-Type: application/json"]
    var body_data = {
        "client_time": client_time,
        "request_id": "sync_%d" % start_time,
        "nonce": Marshalls.raw_to_base64(nonce)
    }
    
    if _shared_secret.size() > 0:
        var msg = "%d:%s" % [client_time, Marshalls.raw_to_base64(nonce)]
        var hmac = _crypto.hmac_sha256(_shared_secret, msg.to_utf8_buffer())
        body_data["signature"] = Marshalls.raw_to_base64(hmac)
    
    var body = JSON.stringify(body_data)
    
    http.request_completed.connect(_on_sync_response.bind(http, start_time, client_time, nonce))
    http.request(_endpoint + "/time", headers, HTTPClient.METHOD_POST, body)

func _on_sync_response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, start_time: int, client_send_time: int, sent_nonce: PackedByteArray):
    var latency = (Time.get_ticks_usec() - start_time) / 1000
    http.queue_free()
    
    if result != HTTPRequest.RESULT_SUCCESS or code != 200:
        _handle_sync_failed("HTTP error: %d, code: %d" % [result, code])
        return
    
    var json = JSON.parse_string(body.get_string_from_utf8())
    if not json or not json.has("server_time"):
        _handle_sync_failed("Invalid server response")
        return
    
    if json.has("nonce"):
        var received_nonce = Marshalls.base64_to_raw(json.nonce)
        if received_nonce != sent_nonce:
            _stats.security_errors += 1
            _handle_sync_failed("Nonce mismatch")
            return
    
    if _shared_secret.size() > 0 and json.has("signature"):
        var msg = "%d:%s" % [json.server_time, json.nonce]
        var expected = _crypto.hmac_sha256(_shared_secret, msg.to_utf8_buffer())
        var received = Marshalls.base64_to_raw(json.signature)
        if received != expected:
            _stats.security_errors += 1
            _handle_sync_failed("Signature mismatch")
            return
    
    var server_time = json.server_time * 1000
    var client_receive_time = Time.get_unix_time_from_system() * 1000
    
    var estimated_server_time = server_time + (latency / 2)
    var time_offset = estimated_server_time - client_receive_time
    
    _time_samples.append({
        "offset": time_offset,
        "latency": latency,
        "timestamp": Time.get_ticks_msec()
    })
    
    if _time_samples.size() > _sample_count:
        _time_samples.pop_front()
    
    _update_stats(latency)
    _calculate_offset()
    
    _mutex.lock()
    _last_sync_time = Time.get_ticks_msec()
    _sync_in_progress = false
    var callbacks = _pending_callbacks.duplicate()
    _pending_callbacks.clear()
    _mutex.unlock()
    
    _stats.sync_success += 1
    time_synced.emit(_server_time_offset, latency)
    
    for cb in callbacks:
        if cb.is_valid():
            cb.call(true, _server_time_offset, latency)

func _handle_sync_failed(error: String):
    _mutex.lock()
    _sync_in_progress = false
    var callbacks = _pending_callbacks.duplicate()
    _pending_callbacks.clear()
    _mutex.unlock()
    
    _stats.sync_failed += 1
    sync_failed.emit(error)
    
    for cb in callbacks:
        if cb.is_valid():
            cb.call(false, 0, 0)

func _calculate_offset():
    if _time_samples.size() < MIN_SAMPLES_FOR_SYNC:
        return
    
    var valid_samples = []
    var now = Time.get_ticks_msec()
    for s in _time_samples:
        if now - s.timestamp < MAX_TIME_OFFSET:
            valid_samples.append(s)
    
    if valid_samples.size() < MIN_SAMPLES_FOR_SYNC:
        return
    
    valid_samples.sort_custom(func(a, b): return a.latency < b.latency)
    
    var keep_count = max(MIN_SAMPLES_FOR_SYNC, int(valid_samples.size() * 0.7))
    var best_samples = valid_samples.slice(0, keep_count)
    
    var offsets = []
    for s in best_samples:
        offsets.append(s.offset)
    offsets.sort()
    
    var mid = offsets.size() / 2
    _server_time_offset = offsets[mid]

func get_server_time() -> int:
    return Time.get_unix_time_from_system() * 1000 + _server_time_offset

func get_server_timestamp() -> int:
    return get_server_time()

func get_time_offset() -> int:
    return _server_time_offset

func needs_sync() -> bool:
    return Time.get_ticks_msec() - _last_sync_time > _sync_interval

func force_sync(callback: Callable = Callable()) -> void:
    _last_sync_time = 0
    sync_time(callback)

func _update_stats(latency: int):
    if _stats.min_latency == 0 or latency < _stats.min_latency:
        _stats.min_latency = latency
    if latency > _stats.max_latency:
        _stats.max_latency = latency
    
    var total = _stats.avg_latency * (_stats.sync_success - 1) + latency
    _stats.avg_latency = total / max(1, _stats.sync_success)
    _stats.last_offset = _server_time_offset

func get_stats() -> Dictionary:
    _mutex.lock()
    var stats = _stats.duplicate()
    stats.current_offset = _server_time_offset
    stats.last_sync = _last_sync_time
    stats.sample_count = _time_samples.size()
    stats.needs_sync = needs_sync()
    stats.security_level = "high" if _trusted_cert != null and _shared_secret.size() > 0 else "medium"
    _mutex.unlock()
    return stats

func set_sync_interval(ms: int) -> void:
    _mutex.lock()
    _sync_interval = ms
    _mutex.unlock()

func set_sample_count(count: int) -> void:
    _mutex.lock()
    _sample_count = max(MIN_SAMPLES_FOR_SYNC, count)
    if _time_samples.size() > _sample_count:
        _time_samples = _time_samples.slice(-_sample_count)
    _mutex.unlock()

func clear_samples():
    _mutex.lock()
    _time_samples.clear()
    _mutex.unlock()

func reset():
    _mutex.lock()
    _server_time_offset = 0
    _last_sync_time = Time.get_ticks_msec()
    _time_samples.clear()
    _sync_in_progress = false
    _pending_callbacks.clear()
    _stats = {
        "sync_attempts": 0,
        "sync_success": 0,
        "sync_failed": 0,
        "last_offset": 0,
        "avg_latency": 0,
        "min_latency": 0,
        "max_latency": 0,
        "security_errors": 0
    }
    _mutex.unlock()