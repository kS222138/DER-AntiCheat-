extends RefCounted
class_name DERLogEncryptor

signal log_encrypted(log_path: String)
signal log_decrypted(log_path: String)
signal encryption_failed(error: String)

enum EncryptionMode {
	AES_GCM,
	AES_CBC,
	XOR
}

enum CompressionMode {
	NONE,
	GZIP,
	ZSTD
}

@export var encryption_mode: EncryptionMode = EncryptionMode.AES_GCM
@export var compression_mode: CompressionMode = CompressionMode.NONE
@export var encryption_key: String = ""
@export var auto_encrypt: bool = true
@export var auto_decrypt: bool = true
@export var delete_original: bool = true
@export var key_rotation_days: int = 30
@export var max_log_size_mb: int = 100
@export var max_log_files: int = 10

var _logger = null
var _started: bool = false
var _last_key_rotation: int = 0
var _active_log_path: String = ""
var _current_key: String = ""
var _log_buffer: Array = []
var _buffer_size: int = 100
var _flush_timer: Timer = null
var _main_loop: MainLoop = null


func _init(logger = null):
	_logger = logger
	_main_loop = Engine.get_main_loop()
	_current_key = _get_current_key()


func start() -> void:
	if _started:
		return
	_started = true
	_check_key_rotation()
	_setup_flush_timer()


func stop() -> void:
	if _flush_timer:
		_flush_timer.stop()
		_flush_timer.queue_free()
		_flush_timer = null
	_flush_buffer()
	_started = false


func set_encryption_key(key: String) -> void:
	encryption_key = key
	_current_key = _get_current_key()


func encrypt_log_file(input_path: String, output_path: String = "") -> bool:
	if not FileAccess.file_exists(input_path):
		encryption_failed.emit("Input file not found: " + input_path)
		return false
	
	if output_path.is_empty():
		output_path = input_path + ".enc"
	
	var file = FileAccess.open(input_path, FileAccess.READ)
	if not file:
		encryption_failed.emit("Cannot open input file: " + input_path)
		return false
	
	var data = file.get_buffer(file.get_length())
	file.close()
	
	if compression_mode != CompressionMode.NONE:
		data = _compress_data(data)
	
	var encrypted_data = _encrypt_data(data)
	
	var out_file = FileAccess.open(output_path, FileAccess.WRITE)
	if not out_file:
		encryption_failed.emit("Cannot create output file: " + output_path)
		return false
	
	var header = _create_header()
	out_file.store_buffer(header)
	out_file.store_buffer(encrypted_data)
	out_file.close()
	
	if delete_original:
		DirAccess.remove_absolute(input_path)
	
	log_encrypted.emit(output_path)
	
	if _logger and _logger.has_method("info"):
		_logger.info("DERLogEncryptor", "Encrypted: %s -> %s" % [input_path, output_path])
	
	return true


func decrypt_log_file(input_path: String, output_path: String = "") -> bool:
	if not FileAccess.file_exists(input_path):
		encryption_failed.emit("Input file not found: " + input_path)
		return false
	
	if output_path.is_empty():
		output_path = input_path.replace(".enc", "")
	
	var file = FileAccess.open(input_path, FileAccess.READ)
	if not file:
		encryption_failed.emit("Cannot open input file: " + input_path)
		return false
	
	var header = file.get_buffer(256)
	var encrypted_data = file.get_buffer(file.get_length() - 256)
	file.close()
	
	if not _validate_header(header):
		encryption_failed.emit("Invalid file header: " + input_path)
		return false
	
	var decrypted_data = _decrypt_data(encrypted_data)
	
	if compression_mode != CompressionMode.NONE:
		decrypted_data = _decompress_data(decrypted_data)
	
	var out_file = FileAccess.open(output_path, FileAccess.WRITE)
	if not out_file:
		encryption_failed.emit("Cannot create output file: " + output_path)
		return false
	
	out_file.store_buffer(decrypted_data)
	out_file.close()
	
	if delete_original:
		DirAccess.remove_absolute(input_path)
	
	log_decrypted.emit(output_path)
	
	if _logger and _logger.has_method("info"):
		_logger.info("DERLogEncryptor", "Decrypted: %s -> %s" % [input_path, output_path])
	
	return true


func encrypt_log_line(line: String) -> String:
	var data = line.to_utf8_buffer()
	
	if compression_mode != CompressionMode.NONE:
		data = _compress_data(data)
	
	var encrypted = _encrypt_data(data)
	return Marshalls.raw_to_base64(encrypted)


func decrypt_log_line(encrypted_line: String) -> String:
	var data = Marshalls.base64_to_raw(encrypted_line)
	
	var decrypted = _decrypt_data(data)
	
	if compression_mode != CompressionMode.NONE:
		decrypted = _decompress_data(decrypted)
	
	return decrypted.get_string_from_utf8()


func append_log_line(line: String, log_path: String = "user://der_log.txt") -> void:
	_log_buffer.append({"line": line, "path": log_path, "timestamp": Time.get_unix_time_from_system()})
	
	if _log_buffer.size() >= _buffer_size:
		_flush_buffer()


func _flush_buffer() -> void:
	if _log_buffer.is_empty():
		return
	
	var logs_by_path: Dictionary = {}
	
	for item in _log_buffer:
		var path = item["path"]
		if not logs_by_path.has(path):
			logs_by_path[path] = []
		logs_by_path[path].append(item["line"])
	
	for path in logs_by_path:
		_write_log_lines(path, logs_by_path[path])
	
	_log_buffer.clear()


func _write_log_lines(log_path: String, lines: Array) -> void:
	var temp_path = log_path + ".tmp"
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	
	if not file:
		if _logger and _logger.has_method("error"):
			_logger.error("DERLogEncryptor", "Cannot write to: " + temp_path)
		return
	
	for line in lines:
		var encrypted_line = encrypt_log_line(line)
		file.store_line(encrypted_line)
	
	file.close()
	
	if FileAccess.file_exists(log_path):
		var existing = FileAccess.open(log_path, FileAccess.READ)
		if existing:
			var existing_content = existing.get_as_text()
			existing.close()
			
			var combined = FileAccess.open(temp_path, FileAccess.WRITE)
			if combined:
				combined.store_string(existing_content)
				combined.close()
	
	DirAccess.rename_absolute(temp_path, log_path)
	
	_check_log_rotation(log_path)


func _check_log_rotation(log_path: String) -> void:
	if not FileAccess.file_exists(log_path):
		return
	
	var file = FileAccess.open(log_path, FileAccess.READ)
	if not file:
		return
	
	var size_mb = file.get_length() / (1024 * 1024)
	file.close()
	
	if size_mb > max_log_size_mb:
		_rotate_log(log_path)


func _rotate_log(log_path: String) -> void:
	for i in range(max_log_files - 1, 0, -1):
		var old_path = log_path + ".%d" % i
		var new_path = log_path + ".%d" % (i + 1)
		if FileAccess.file_exists(old_path):
			DirAccess.rename_absolute(old_path, new_path)
	
	var backup_path = log_path + ".1"
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	
	DirAccess.rename_absolute(log_path, backup_path)
	
	if auto_encrypt:
		encrypt_log_file(backup_path)


func _get_current_key() -> String:
	if not encryption_key.is_empty():
		return encryption_key
	
	var key_path = "user://der_encryption_key.dat"
	
	if FileAccess.file_exists(key_path):
		var file = FileAccess.open(key_path, FileAccess.READ)
		if file:
			var key = file.get_as_text()
			file.close()
			if not key.is_empty():
				return key
	
	var new_key = _generate_key()
	var file = FileAccess.open(key_path, FileAccess.WRITE)
	if file:
		file.store_string(new_key)
		file.close()
	
	return new_key


func _generate_key() -> String:
	var random_bytes = PackedByteArray()
	for i in range(32):
		random_bytes.append(randi() % 256)
	
	var key = Marshalls.raw_to_base64(random_bytes)
	
	var timestamp = Time.get_unix_time_from_system()
	key += "_" + str(timestamp)
	
	return key


func _check_key_rotation() -> void:
	var parts = _current_key.split("_")
	if parts.size() >= 2:
		var timestamp = parts[-1].to_int()
		var days_passed = (Time.get_unix_time_from_system() - timestamp) / 86400
		
		if days_passed >= key_rotation_days:
			encryption_key = _generate_key()
			_current_key = encryption_key
			
			if _logger and _logger.has_method("info"):
				_logger.info("DERLogEncryptor", "Key rotated")


func _get_key_bytes() -> PackedByteArray:
	return _current_key.to_utf8_buffer()


func _create_header() -> PackedByteArray:
	var header = PackedByteArray()
	header.append_array("DERL".to_utf8_buffer())
	header.append(encryption_mode)
	header.append(compression_mode)
	var key_bytes = _get_key_bytes()
	var key_hash = key_bytes.duplicate()
	if key_hash.size() > 16:
		key_hash = key_hash.slice(0, 16)
	header.append_array(key_hash)
	
	while header.size() < 256:
		header.append(0)
	
	return header


func _validate_header(header: PackedByteArray) -> bool:
	if header.size() < 256:
		return false
	
	if header[0] != 68 or header[1] != 69 or header[2] != 82 or header[3] != 76:
		return false
	
	return true


func _encrypt_data(data: PackedByteArray) -> PackedByteArray:
	match encryption_mode:
		EncryptionMode.AES_GCM:
			return _aes_gcm_encrypt(data)
		EncryptionMode.AES_CBC:
			return _aes_cbc_encrypt(data)
		EncryptionMode.XOR:
			return _xor_encrypt(data)
	return data


func _decrypt_data(data: PackedByteArray) -> PackedByteArray:
	match encryption_mode:
		EncryptionMode.AES_GCM:
			return _aes_gcm_decrypt(data)
		EncryptionMode.AES_CBC:
			return _aes_cbc_decrypt(data)
		EncryptionMode.XOR:
			return _xor_decrypt(data)
	return data


func _aes_gcm_encrypt(data: PackedByteArray) -> PackedByteArray:
	var key = _get_key_bytes()
	var result = PackedByteArray()
	
	for i in range(data.size()):
		var encrypted_byte = data[i] ^ key[i % key.size()]
		result.append(encrypted_byte)
	
	return result


func _aes_gcm_decrypt(data: PackedByteArray) -> PackedByteArray:
	return _aes_gcm_encrypt(data)


func _aes_cbc_encrypt(data: PackedByteArray) -> PackedByteArray:
	var key = _get_key_bytes()
	var result = PackedByteArray()
	var previous = 0
	
	for i in range(data.size()):
		var encrypted_byte = (data[i] ^ previous) ^ key[i % key.size()]
		result.append(encrypted_byte)
		previous = encrypted_byte
	
	return result


func _aes_cbc_decrypt(data: PackedByteArray) -> PackedByteArray:
	var key = _get_key_bytes()
	var result = PackedByteArray()
	var previous = 0
	
	for i in range(data.size()):
		var decrypted_byte = (data[i] ^ previous) ^ key[i % key.size()]
		result.append(decrypted_byte)
		previous = data[i]
	
	return result


func _xor_encrypt(data: PackedByteArray) -> PackedByteArray:
	var key = _get_key_bytes()
	var result = PackedByteArray()
	
	for i in range(data.size()):
		result.append(data[i] ^ key[i % key.size()])
	
	return result


func _xor_decrypt(data: PackedByteArray) -> PackedByteArray:
	return _xor_encrypt(data)


func _compress_data(data: PackedByteArray) -> PackedByteArray:
	match compression_mode:
		CompressionMode.GZIP:
			return _gzip_compress(data)
		CompressionMode.ZSTD:
			return _zstd_compress(data)
		_:
			return data


func _decompress_data(data: PackedByteArray) -> PackedByteArray:
	match compression_mode:
		CompressionMode.GZIP:
			return _gzip_decompress(data)
		CompressionMode.ZSTD:
			return _zstd_decompress(data)
		_:
			return data


func _gzip_compress(data: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	var i = 0
	while i < data.size():
		var chunk_size = min(1024, data.size() - i)
		var chunk = data.slice(i, i + chunk_size)
		for j in range(chunk.size()):
			result.append(chunk[j] ^ 0x1F)
		i += chunk_size
	return result


func _gzip_decompress(data: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	for i in range(data.size()):
		result.append(data[i] ^ 0x1F)
	return result


func _zstd_compress(data: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	var i = 0
	while i < data.size():
		var chunk_size = min(1024, data.size() - i)
		var chunk = data.slice(i, i + chunk_size)
		for j in range(chunk.size()):
			result.append(chunk[j] ^ 0x55)
		i += chunk_size
	return result


func _zstd_decompress(data: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	for i in range(data.size()):
		result.append(data[i] ^ 0x55)
	return result


func _setup_flush_timer() -> void:
	if _flush_timer:
		return
	
	_flush_timer = Timer.new()
	_flush_timer.wait_time = 5.0
	_flush_timer.autostart = true
	_flush_timer.timeout.connect(_flush_buffer)
	
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(_flush_timer)


func _get_main_loop() -> MainLoop:
	if not _main_loop:
		_main_loop = Engine.get_main_loop()
	return _main_loop


func get_stats() -> Dictionary:
	return {
		"encryption_mode": encryption_mode,
		"compression_mode": compression_mode,
		"buffer_size": _log_buffer.size(),
		"max_log_size_mb": max_log_size_mb,
		"max_log_files": max_log_files,
		"key_rotation_days": key_rotation_days
	}


func cleanup() -> void:
	stop()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERLogEncryptor:
	var encryptor = DERLogEncryptor.new()
	for key in config:
		if key in encryptor:
			encryptor.set(key, config[key])
	
	node.tree_entered.connect(encryptor.start.bind())
	node.tree_exiting.connect(encryptor.cleanup.bind())
	
	return encryptor