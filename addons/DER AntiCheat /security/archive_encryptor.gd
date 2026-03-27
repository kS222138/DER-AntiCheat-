extends Node
class_name DERArchiveEncryptor

enum Mode { AES_GCM, AES_CBC, CHACHA20 }
enum Compress { NONE, ZLIB, GZIP }

@export var mode: Mode = Mode.AES_GCM
@export var compress: Compress = Compress.ZLIB
@export var iterations: int = 100000

var _crypto: Crypto
var _password: String = ""
var _salt: PackedByteArray = []
var _key: PackedByteArray = []
var _ready: bool = false

signal encrypt_failed(path: String, err: String)
signal decrypt_failed(path: String, err: String)

func _init(pwd: String = ""):
	_crypto = Crypto.new()
	if not pwd.is_empty(): set_password(pwd)

func set_password(pwd: String) -> void:
	_password = pwd
	_salt = _gen_salt()
	_key = _derive_key(_password, _salt, iterations, 32)
	_ready = true

func set_mode(m: Mode) -> void: mode = m
func set_compress(c: Compress) -> void: compress = c

func save(path: String, data: Variant) -> bool:
	if not _ready:
		encrypt_failed.emit(path, "Not initialized")
		return false
	
	var raw = _serialize(data)
	if compress != Compress.NONE:
		raw = _compress(raw)
	
	var enc = _encrypt(raw)
	var save_data = {
		ver = "1.0", mode = mode, compress = compress,
		salt = _salt, nonce = enc.nonce, tag = enc.tag,
		data = enc.data
	}
	
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		encrypt_failed.emit(path, "Cannot write")
		return false
	f.store_string(JSON.stringify(save_data))
	f.close()
	return true

func load(path: String) -> Variant:
	if not _ready:
		decrypt_failed.emit(path, "Not initialized")
		return null
	
	if not FileAccess.file_exists(path):
		decrypt_failed.emit(path, "Not found")
		return null
	
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		decrypt_failed.emit(path, "Cannot read")
		return null
	var json = f.get_as_text()
	f.close()
	
	var data = JSON.parse_string(json)
	if not data:
		decrypt_failed.emit(path, "Invalid JSON")
		return null
	
	if data.ver != "1.0":
		decrypt_failed.emit(path, "Version mismatch")
		return null
	
	mode = data.mode
	compress = data.compress
	_salt = data.salt
	_key = _derive_key(_password, _salt, iterations, 32)
	
	var enc = {nonce = data.nonce, tag = data.tag, data = data.data}
	var dec = _decrypt(enc)
	if dec.is_empty():
		decrypt_failed.emit(path, "Decryption failed - wrong password or corrupted")
		return null
	
	if compress != Compress.NONE:
		dec = _decompress(dec)
	
	return _deserialize(dec)

func _serialize(v: Variant) -> PackedByteArray:
	if v is Dictionary or v is Array:
		return JSON.stringify(v).to_utf8_buffer()
	elif v is String:
		return v.to_utf8_buffer()
	elif v is PackedByteArray:
		return v
	return PackedByteArray()

func _deserialize(bytes: PackedByteArray) -> Variant:
	var s = bytes.get_string_from_utf8()
	var j = JSON.parse_string(s)
	return j if j != null else s

func _compress(data: PackedByteArray) -> PackedByteArray:
	match compress:
		Compress.ZLIB:
			return data.compress()
		Compress.GZIP:
			return data.compress(FileAccess.COMPRESSION_GZIP)
		_:
			return data

func _decompress(data: PackedByteArray) -> PackedByteArray:
	match compress:
		Compress.ZLIB:
			return data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		Compress.GZIP:
			return data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		_:
			return data

func _gen_salt() -> PackedByteArray:
	return _crypto.generate_random_bytes(16)

func _derive_key(pwd: String, salt: PackedByteArray, iter: int, len: int) -> PackedByteArray:
	if _crypto:
		return _crypto.pbkdf2(pwd.to_utf8_buffer(), salt, iter, len)
	var key = PackedByteArray()
	key.resize(len)
	var h = pwd.hash()
	for i in len:
		var v = h
		for _j in range(iter): v = (v * 1103515245 + 12345) & 0x7FFFFFFF
		key[i] = (v + salt[i % salt.size()]) % 256
	return key

func _encrypt(data: PackedByteArray) -> Dictionary:
	match mode:
		Mode.AES_GCM:
			var nonce = _crypto.generate_random_bytes(12)
			var tag = PackedByteArray()
			var encrypted = _crypto.encrypt_aes_gcm(data, _key, nonce, tag)
			return {nonce = nonce, tag = tag, data = encrypted}
		_:
			var nonce = _crypto.generate_random_bytes(16)
			var encrypted = PackedByteArray()
			encrypted.resize(data.size())
			for i in data.size():
				encrypted[i] = data[i] ^ _key[i % _key.size()] ^ nonce[i % nonce.size()]
			return {nonce = nonce, tag = PackedByteArray(), data = encrypted}

func _decrypt(enc: Dictionary) -> PackedByteArray:
	match mode:
		Mode.AES_GCM:
			var decrypted = _crypto.decrypt_aes_gcm(enc.data, _key, enc.nonce, enc.tag)
			return decrypted if decrypted else PackedByteArray()
		_:
			var dec = PackedByteArray()
			dec.resize(enc.data.size())
			for i in enc.data.size():
				dec[i] = enc.data[i] ^ _key[i % _key.size()] ^ enc.nonce[i % enc.nonce.size()]
			return dec

func exists(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))

func delete(slot: int) -> bool:
	if exists(slot):
		var d = DirAccess.open("user://")
		return d.remove(_path(slot)) == OK
	return false

func _path(slot: int) -> String:
	return "user://save_%d.dat" % slot