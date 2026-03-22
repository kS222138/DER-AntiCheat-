class_name DERCacheManager
extends RefCounted

class CacheEntry:
    var data: Variant
    var expire_time: int
    var last_access: int
    
    func _init(p_data, p_ttl_ms):
        data = p_data
        var now = Time.get_ticks_msec()
        expire_time = now + p_ttl_ms
        last_access = now
    
    func is_expired() -> bool:
        return Time.get_ticks_msec() > expire_time
    
    func touch():
        last_access = Time.get_ticks_msec()

var _cache: Dictionary = {}
var _default_ttl: int = 60000
var _max_size: int = 1000
var _cleanup_interval: int = 30000
var _last_cleanup: int = 0
var _mutex = Mutex.new()
var _crypto = Crypto.new()
var _crypto_key: CryptoKey = null

var _hits: int = 0
var _misses: int = 0
var _evictions: int = 0

func _init(p_default_ttl: int = 60000, p_max_size: int = 1000):
    _default_ttl = p_default_ttl
    _max_size = p_max_size
    _last_cleanup = Time.get_ticks_msec()

func generate_key() -> CryptoKey:
    var key = _crypto.generate_rsa(2048)
    return key

func set_encryption_key(key: CryptoKey) -> void:
    _mutex.lock()
    _crypto_key = key
    _mutex.unlock()

func _cleanup():
    var now = Time.get_ticks_msec()
    if now - _last_cleanup < _cleanup_interval:
        return
    
    _last_cleanup = now
    var expired_keys = []
    for key in _cache:
        if _cache[key].is_expired():
            expired_keys.append(key)
    
    for key in expired_keys:
        _cache.erase(key)
        _evictions += 1

func _ensure_size():
    if _cache.size() < _max_size:
        return
    
    var now = Time.get_ticks_msec()
    var entries = []
    for key in _cache:
        entries.append({
            "key": key,
            "last": _cache[key].last_access,
            "expire": _cache[key].expire_time
        })
    
    entries.sort_custom(func(a, b): 
        if a.expire <= now and b.expire > now:
            return true
        if b.expire <= now and a.expire > now:
            return false
        return a.last < b.last
    )
    
    var to_remove = _cache.size() - _max_size
    for i in range(to_remove):
        if i < entries.size():
            _cache.erase(entries[i].key)
            _evictions += 1

func _get_unlocked(key: StringName) -> Variant:
    if not _cache.has(key):
        _misses += 1
        return null
    
    var entry = _cache[key]
    if entry.is_expired():
        _cache.erase(key)
        _evictions += 1
        _misses += 1
        return null
    
    _hits += 1
    entry.touch()
    return entry.data

func set_with_ttl(key: StringName, value: Variant, ttl_ms: int) -> void:
    _mutex.lock()
    _cleanup()
    _cache[key] = CacheEntry.new(value, ttl_ms)
    _ensure_size()
    _mutex.unlock()

func set(key: StringName, value: Variant) -> void:
    set_with_ttl(key, value, _default_ttl)

func get(key: StringName) -> Variant:
    _mutex.lock()
    var result = _get_unlocked(key)
    _mutex.unlock()
    return result

func get_many(keys: Array) -> Dictionary:
    var result = {}
    _mutex.lock()
    for key in keys:
        var val = _get_unlocked(key)
        if val != null:
            result[key] = val
    _mutex.unlock()
    return result

func set_many(items: Dictionary, ttl_ms: int = -1) -> void:
    var ttl = ttl_ms if ttl_ms >= 0 else _default_ttl
    _mutex.lock()
    for key in items:
        _cache[key] = CacheEntry.new(items[key], ttl)
    _ensure_size()
    _mutex.unlock()

func has(key: StringName) -> bool:
    _mutex.lock()
    var exists = false
    if _cache.has(key) and not _cache[key].is_expired():
        exists = true
    _mutex.unlock()
    return exists

func remove(key: StringName) -> void:
    _mutex.lock()
    _cache.erase(key)
    _mutex.unlock()

func clear() -> void:
    _mutex.lock()
    _cache.clear()
    _hits = 0
    _misses = 0
    _evictions = 0
    _mutex.unlock()

func save_to_file(path: String, encrypt: bool = false) -> bool:
    var data = {
        "version": "1.0",
        "timestamp": Time.get_unix_time_from_system(),
        "entries": {}
    }
    
    _mutex.lock()
    var now = Time.get_ticks_msec()
    for key in _cache:
        var entry = _cache[key]
        if not entry.is_expired():
            data.entries[key] = {
                "data": entry.data,
                "expire_time": entry.expire_time - now
            }
    _mutex.unlock()
    
    var json_str = JSON.stringify(data)
    var final_data = json_str
    
    if encrypt and _crypto_key != null:
        var encrypted = _crypto.encrypt(_crypto_key, json_str.to_utf8_buffer())
        if encrypted:
            final_data = Marshalls.raw_to_base64(encrypted)
    
    var file = FileAccess.open(path, FileAccess.WRITE)
    if not file:
        return false
    file.store_string(final_data)
    return true

func load_from_file(path: String, encrypted: bool = false) -> bool:
    if not FileAccess.file_exists(path):
        return false
    
    var file = FileAccess.open(path, FileAccess.READ)
    if not file:
        return false
    
    var content = file.get_as_text()
    var data_str = content
    
    if encrypted and _crypto_key != null:
        var encrypted_data = Marshalls.base64_to_raw(content)
        var decrypted = _crypto.decrypt(_crypto_key, encrypted_data)
        if decrypted:
            data_str = decrypted.get_string_from_utf8()
    
    var data = JSON.parse_string(data_str)
    if not data or not data.has("entries"):
        return false
    
    _mutex.lock()
    var now = Time.get_ticks_msec()
    for key in data.entries:
        var entry_data = data.entries[key]
        var entry = CacheEntry.new(entry_data.data, 0)
        entry.expire_time = now + entry_data.expire_time
        entry.last_access = now
        _cache[key] = entry
    _mutex.unlock()
    return true

func get_stats() -> Dictionary:
    _mutex.lock()
    var stats = {
        "size": _cache.size(),
        "hits": _hits,
        "misses": _misses,
        "evictions": _evictions,
        "hit_ratio": float(_hits) / max(1, _hits + _misses),
        "encryption_enabled": _crypto_key != null
    }
    _mutex.unlock()
    return stats

func set_default_ttl(ms: int) -> void:
    _mutex.lock()
    _default_ttl = ms
    _mutex.unlock()

func set_max_size(size: int) -> void:
    _mutex.lock()
    _max_size = size
    _ensure_size()
    _mutex.unlock()

func set_cleanup_interval(ms: int) -> void:
    _mutex.lock()
    _cleanup_interval = ms
    _mutex.unlock()