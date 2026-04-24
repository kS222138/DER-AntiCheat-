extends RefCounted
class_name DERCloudSnapshot

signal snapshot_uploaded(snapshot_id: String, slot: int)
signal snapshot_loaded(snapshot_id: String, slot: int)
signal snapshot_conflict(slot: int, local_hash: String, cloud_hash: String)
signal snapshot_corrupted(slot: int, reason: String)
signal network_error(slot: int, error: String)

enum SyncMode {
	PUSH_ON_SAVE,
	PULL_ON_LOAD,
	BIDIRECTIONAL,
	MANUAL
}

enum ConflictResolution {
	SERVER_WINS,
	CLIENT_WINS,
	NEWEST_WINS,
	ASK_USER
}

@export var enabled: bool = true
@export var sync_mode: SyncMode = SyncMode.BIDIRECTIONAL
@export var conflict_resolution: ConflictResolution = ConflictResolution.NEWEST_WINS
@export var server_url: String = "https://your-server.com/api/snapshot"
@export var api_key: String = ""
@export var timeout: float = 10.0
@export var max_retries: int = 3
@export var retry_delay: float = 1.0
@export var enable_compression: bool = true
@export var enable_encryption: bool = true
@export var auto_sync_interval: float = 300.0
@export var max_snapshots_per_slot: int = 10

var _snapshot_cache: Dictionary = {}
var _sync_timer: Timer = null
var _pending_uploads: Dictionary = {}
var _pending_downloads: Dictionary = {}
var _started: bool = false
var _main_loop: MainLoop = null
var _encryption_key: PackedByteArray = []
var _aes: AESContext = null


func _init():
	_main_loop = Engine.get_main_loop()
	_aes = AESContext.new()
	_generate_encryption_key()


func _generate_encryption_key():
	_encryption_key = Crypto.new().generate_random_bytes(32)


func start():
	if _started:
		return
	_started = true
	
	if auto_sync_interval > 0:
		_setup_sync_timer()


func stop():
	if _sync_timer:
		_sync_timer.stop()
		_sync_timer.queue_free()
		_sync_timer = null
	_started = false


func _setup_sync_timer():
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		return
	
	_sync_timer = Timer.new()
	_sync_timer.wait_time = auto_sync_interval
	_sync_timer.autostart = true
	_sync_timer.timeout.connect(_auto_sync)
	tree.root.add_child(_sync_timer)


func upload_snapshot(slot: int, data: Variant, metadata: Dictionary = {}) -> String:
	if not enabled:
		return ""
	
	var snapshot_id = _generate_snapshot_id(slot)
	var processed_data = data
	
	if enable_compression:
		processed_data = _compress_data(processed_data)
	
	if enable_encryption:
		processed_data = _encrypt_data(processed_data)
	
	var payload = {
		"snapshot_id": snapshot_id,
		"slot": slot,
		"data": processed_data,
		"compressed": enable_compression,
		"encrypted": enable_encryption,
		"metadata": metadata,
		"timestamp": Time.get_unix_time_from_system(),
		"client_version": ProjectSettings.get_setting("application/config/version", "1.0")
	}
	
	_send_request("/upload", payload, snapshot_id, "upload")
	return snapshot_id


func load_snapshot(slot: int, snapshot_id: String = "") -> Variant:
	if not enabled:
		return null
	
	var cache_key = str(slot) + ":" + snapshot_id if snapshot_id != "" else str(slot)
	if _snapshot_cache.has(cache_key):
		return _snapshot_cache[cache_key]
	
	_pending_downloads[slot] = {
		"snapshot_id": snapshot_id,
		"callback": null,
		"timestamp": Time.get_ticks_msec()
	}
	
	var payload = {
		"slot": slot,
		"snapshot_id": snapshot_id,
		"client_version": ProjectSettings.get_setting("application/config/version", "1.0")
	}
	
	_send_request("/load", payload, str(slot), "load")
	return null


func load_snapshot_async(slot: int, callback: Callable, snapshot_id: String = ""):
	if not enabled:
		if callback.is_valid():
			callback.call(null, false, "disabled")
		return
	
	_pending_downloads[slot] = {
		"snapshot_id": snapshot_id,
		"callback": callback,
		"timestamp": Time.get_ticks_msec()
	}
	
	var payload = {
		"slot": slot,
		"snapshot_id": snapshot_id,
		"client_version": ProjectSettings.get_setting("application/config/version", "1.0")
	}
	
	_send_request("/load", payload, str(slot), "load")


func list_snapshots(slot: int, callback: Callable = Callable()):
	if not enabled:
		if callback.is_valid():
			callback.call([])
		return
	
	var request_id = "list_" + str(slot)
	_pending_downloads[request_id] = {
		"slot": slot,
		"callback": callback,
		"type": "list"
	}
	
	var payload = {
		"slot": slot,
		"client_version": ProjectSettings.get_setting("application/config/version", "1.0")
	}
	
	_send_request("/list", payload, request_id, "list")


func delete_snapshot(slot: int, snapshot_id: String, callback: Callable = Callable()):
	if not enabled:
		if callback.is_valid():
			callback.call(false)
		return
	
	var request_id = "delete_" + str(slot) + "_" + snapshot_id
	_pending_downloads[request_id] = {
		"callback": callback,
		"type": "delete"
	}
	
	var payload = {
		"slot": slot,
		"snapshot_id": snapshot_id,
		"client_version": ProjectSettings.get_setting("application/config/version", "1.0")
	}
	
	_send_request("/delete", payload, request_id, "delete")


func check_conflict(slot: int, local_hash: String, callback: Callable):
	if not enabled:
		if callback.is_valid():
			callback.call(false)
		return
	
	var request_id = "conflict_" + str(slot)
	_pending_downloads[request_id] = {
		"callback": callback,
		"type": "conflict",
		"local_hash": local_hash
	}
	
	var payload = {
		"slot": slot,
		"hash": local_hash,
		"client_version": ProjectSettings.get_setting("application/config/version", "1.0")
	}
	
	_send_request("/check", payload, request_id, "check")


func _send_request(endpoint: String, payload: Dictionary, request_id: String, request_type: String):
	var tree = _main_loop
	if not tree or not tree.has_method("root"):
		_handle_network_error(request_id, "No main loop")
		return
	
	var http = HTTPRequest.new()
	http.timeout = timeout
	tree.root.add_child(http)
	
	var body = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	if not api_key.is_empty():
		headers.append("X-API-Key: " + api_key)
	
	_pending_uploads[request_id] = {
		"http": http,
		"type": request_type,
		"retries": 0,
		"timestamp": Time.get_ticks_msec(),
		"payload": payload,
		"endpoint": endpoint
	}
	
	http.request_completed.connect(_on_request_complete.bind(request_id, request_type), CONNECT_ONE_SHOT)
	http.request(server_url + endpoint, headers, HTTPClient.METHOD_POST, body)


func _on_request_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request_id: String, request_type: String):
	if not _pending_uploads.has(request_id):
		return
	
	var request_info = _pending_uploads[request_id]
	var http = request_info["http"]
	
	_pending_uploads.erase(request_id)
	
	if is_instance_valid(http):
		http.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if request_info["retries"] < max_retries:
			request_info["retries"] += 1
			_pending_uploads[request_id] = request_info
			
			var tree = _main_loop
			if tree and tree.has_method("create_timer"):
				await tree.create_timer(retry_delay).timeout
				_retry_request(request_id, request_info)
		else:
			_handle_network_error(request_id, "HTTP error: %d, code: %d" % [result, response_code])
		return
	
	var response = JSON.parse_string(body.get_string_from_utf8())
	if response == null:
		_handle_network_error(request_id, "Invalid JSON response")
		return
	
	match request_type:
		"upload":
			_handle_upload_response(request_id, response)
		"load":
			_handle_load_response(request_id, response)
		"list":
			_handle_list_response(request_id, response)
		"delete":
			_handle_delete_response(request_id, response)
		"check":
			_handle_check_response(request_id, response)


func _retry_request(request_id: String, request_info: Dictionary):
	var http = HTTPRequest.new()
	http.timeout = timeout
	var tree = _main_loop
	if tree and tree.has_method("root"):
		tree.root.add_child(http)
	
	request_info["http"] = http
	_pending_uploads[request_id] = request_info
	
	var payload = request_info.get("payload", {})
	var endpoint = request_info.get("endpoint", "")
	
	var headers = ["Content-Type: application/json"]
	if not api_key.is_empty():
		headers.append("X-API-Key: " + api_key)
	
	http.request_completed.connect(_on_request_complete.bind(request_id, request_info.get("type", "")), CONNECT_ONE_SHOT)
	http.request(server_url + endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))


func _handle_upload_response(request_id: String, response: Dictionary):
	var slot = response.get("slot", -1)
	var snapshot_id = response.get("snapshot_id", "")
	
	if response.get("success", false):
		snapshot_uploaded.emit(snapshot_id, slot)
	else:
		network_error.emit(slot, response.get("error", "Unknown error"))


func _handle_load_response(request_id: String, response: Dictionary):
	var slot = response.get("slot", -1)
	var snapshot_id = response.get("snapshot_id", "")
	
	if not response.get("success", false):
		if _pending_downloads.has(slot):
			var info = _pending_downloads[slot]
			if info.has("callback") and info.callback.is_valid():
				info.callback.call(null, false, response.get("error", "Unknown error"))
			_pending_downloads.erase(slot)
		network_error.emit(slot, response.get("error", "Unknown error"))
		return
	
	var data = response.get("data", null)
	
	if data == null:
		network_error.emit(slot, "No data in response")
		return
	
	if enable_encryption:
		data = _decrypt_data(data)
	
	if enable_compression:
		data = _decompress_data(data)
	
	var cache_key = str(slot) + ":" + snapshot_id if snapshot_id != "" else str(slot)
	_snapshot_cache[cache_key] = data
	
	if _pending_downloads.has(slot):
		var info = _pending_downloads[slot]
		if info.has("callback") and info.callback.is_valid():
			info.callback.call(data, true, "")
		_pending_downloads.erase(slot)
	
	snapshot_loaded.emit(snapshot_id, slot)


func _handle_list_response(request_id: String, response: Dictionary):
	var snapshots = response.get("snapshots", [])
	
	if _pending_downloads.has(request_id):
		var info = _pending_downloads[request_id]
		if info.has("callback") and info.callback.is_valid():
			info.callback.call(snapshots)
		_pending_downloads.erase(request_id)


func _handle_delete_response(request_id: String, response: Dictionary):
	var success = response.get("success", false)
	
	if _pending_downloads.has(request_id):
		var info = _pending_downloads[request_id]
		if info.has("callback") and info.callback.is_valid():
			info.callback.call(success)
		_pending_downloads.erase(request_id)


func _handle_check_response(request_id: String, response: Dictionary):
	var has_conflict = response.get("conflict", false)
	var cloud_hash = response.get("cloud_hash", "")
	
	if _pending_downloads.has(request_id):
		var info = _pending_downloads[request_id]
		var local_hash = info.get("local_hash", "")
		
		if has_conflict:
			var slot = int(request_id.replace("conflict_", ""))
			snapshot_conflict.emit(slot, local_hash, cloud_hash)
		
		if info.has("callback") and info.callback.is_valid():
			info.callback.call(has_conflict, cloud_hash)
		_pending_downloads.erase(request_id)


func _handle_network_error(request_id: String, error: String):
	var slot = -1
	if request_id.is_valid_int():
		slot = request_id.to_int()
	
	network_error.emit(slot, error)
	
	if _pending_downloads.has(request_id):
		var info = _pending_downloads[request_id]
		if info.has("callback") and info.callback.is_valid():
			info.callback.call(null, false, error)
		_pending_downloads.erase(request_id)


func _generate_snapshot_id(slot: int) -> String:
	var timestamp = Time.get_unix_time_from_system()
	var random = randi() % 10000
	return "snapshot_%d_%d_%d" % [slot, timestamp, random]


func _compress_data(data: Variant) -> Variant:
	var json = JSON.stringify(data)
	var bytes = json.to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(compressed)


func _decompress_data(data: Variant) -> Variant:
	var bytes = Marshalls.base64_to_raw(data)
	var decompressed = bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	var json = decompressed.get_string_from_utf8()
	return JSON.parse_string(json)


func _encrypt_data(data: Variant) -> Variant:
	var json = JSON.stringify(data)
	var bytes = json.to_utf8_buffer()
	
	_aes.start(AESContext.MODE_CBC_ENCRYPT, _encryption_key)
	var encrypted = _aes.update(bytes)
	_aes.finish()  
	_aes.reset()
	
	return Marshalls.raw_to_base64(encrypted)


func _decrypt_data(data: Variant) -> Variant:
	var bytes = Marshalls.base64_to_raw(data)
	
	_aes.start(AESContext.MODE_CBC_DECRYPT, _encryption_key)
	var decrypted = _aes.update(bytes)
	_aes.finish()  
	_aes.reset()
	
	var json = decrypted.get_string_from_utf8()
	return JSON.parse_string(json)


func _auto_sync():
	if sync_mode == SyncMode.PUSH_ON_SAVE or sync_mode == SyncMode.BIDIRECTIONAL:
		for slot in _snapshot_cache:
			var data = _snapshot_cache[slot]
			if data != null:
				upload_snapshot(slot, data)


func get_cached_snapshot(slot: int, snapshot_id: String = "") -> Variant:
	var cache_key = str(slot) + ":" + snapshot_id if snapshot_id != "" else str(slot)
	return _snapshot_cache.get(cache_key, null)


func clear_cache(slot: int = -1):
	if slot >= 0:
		var to_remove = []
		for key in _snapshot_cache:
			if key.begins_with(str(slot) + ":"):
				to_remove.append(key)
		for key in to_remove:
			_snapshot_cache.erase(key)
	else:
		_snapshot_cache.clear()


func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"sync_mode": sync_mode,
		"cached_snapshots": _snapshot_cache.size(),
		"pending_uploads": _pending_uploads.size(),
		"pending_downloads": _pending_downloads.size(),
		"server_url": server_url,
		"compression": enable_compression,
		"encryption": enable_encryption
	}


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERCloudSnapshot:
	var snapshot = DERCloudSnapshot.new()
	for key in config:
		if key in snapshot:
			snapshot.set(key, config[key])
	
	node.tree_entered.connect(snapshot.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(snapshot.stop.bind())
	return snapshot
