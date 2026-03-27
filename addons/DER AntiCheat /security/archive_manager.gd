extends Node
class_name DERArchiveManager

enum ExportMode { ENCRYPTED, DECRYPTED }

@export var max_slots: int = 10
@export var auto_save: bool = false
@export var interval: float = 60.0
@export var validate: bool = true

var _enc: DERArchiveEncryptor
var _timer: Timer
var _cur: int = -1
var _cache: Dictionary = {}

signal saved(slot: int, meta: Dictionary)
signal loaded(slot: int, meta: Dictionary)
signal deleted(slot: int)
signal corrupted(slot: int, err: String)

func _init(pwd: String = ""):
	_enc = DERArchiveEncryptor.new(pwd)
	if auto_save: _setup()

func set_password(p: String): _enc = DERArchiveEncryptor.new(p)
func set_mode(m): _enc.set_mode(m)
func set_compress(c): _enc.set_compress(c)
func set_iterations(i: int): _enc.iterations = i

func save(slot: int, data: Variant, meta: Dictionary = {}) -> bool:
	if slot < 0 or slot >= max_slots: return false
	var save_data = {d=data, m=meta, t=Time.get_unix_time_from_system(), v=ProjectSettings.get_setting("application/config/version", "1.0")}
	var ok = _enc.save(_path(slot), save_data)
	if ok: _cache[slot] = save_data; _cur = slot; saved.emit(slot, meta)
	return ok

func load(slot: int) -> Variant:
	if slot < 0 or slot >= max_slots: return null
	if _cache.has(slot): return _cache[slot].get("d", _cache[slot])
	var raw = _enc.load(_path(slot))
	if raw != null:
		if raw is Dictionary and raw.has("d"):
			_cache[slot] = raw; _cur = slot; loaded.emit(slot, raw.get("m", {})); return raw.d
		_cache[slot] = {"d": raw, "m": {}, "t": 0}; _cur = slot; loaded.emit(slot, {}); return raw
	corrupted.emit(slot, "Load failed"); return null

func load_meta(slot: int) -> Dictionary:
	if slot < 0 or slot >= max_slots: return {}
	if _cache.has(slot): return _cache[slot].get("m", {})
	var raw = _enc.load(_path(slot))
	if raw is Dictionary and raw.has("m"): return raw.m
	return {}

func delete(slot: int) -> bool:
	if slot < 0 or slot >= max_slots: return false
	var ok = _enc.delete(slot)
	if ok: _cache.erase(slot); if _cur == slot: _cur = -1; deleted.emit(slot)
	return ok

func exists(slot: int) -> bool: return _enc.exists(slot)
func get_current() -> int: return _cur
func get_cache(slot: int) -> Variant: var c = _cache.get(slot); return c.get("d", c) if c else null

func clear_cache(slot: int = -1):
	if slot >= 0:
		_cache.erase(slot)
	else:
		_cache.clear()

func list() -> Array:
	var slots = []
	for i in range(max_slots):
		if exists(i): slots.append(info(i))
	return slots

func info(slot: int) -> Dictionary:
	if not exists(slot): return {slot=slot, exists=false}
	var f = FileAccess.open(_path(slot), FileAccess.READ)
	if not f: return {slot=slot, exists=true, error="Cannot read"}
	var json = f.get_as_text(); f.close()
	var data = JSON.parse_string(json)
	var r = {slot=slot, exists=true}
	if data:
		r.version = data.get("ver", "unknown")
		if data.has("d") and data.d is Dictionary:
			var m = data.get("m", {})
			r.timestamp = data.get("t", 0)
			r.game_version = data.get("v", "")
			if m.has("level"): r.level = m.level
			if m.has("time"): r.time = m.time
	else: r.error = "Invalid"
	var s = _stats(slot); r.size = s.size; r.cached = s.cached
	return r

func _stats(slot: int) -> Dictionary:
	var p = _path(slot)
	if not FileAccess.file_exists(p): return {slot=slot, exists=false}
	var f = FileAccess.open(p, FileAccess.READ)
	if not f: return {slot=slot, exists=true, error="Cannot read"}
	var sz = f.get_length(); f.close()
	return {slot=slot, exists=true, size=sz, cached=_cache.has(slot)}

func save_all() -> Dictionary:
	var r = {}
	for s in _cache: r[s] = save(s, _cache[s].get("d", _cache[s]), _cache[s].get("m", {}))
	return r

func delete_all() -> int:
	var c = 0
	for i in range(max_slots): if delete(i): c += 1
	return c

func export_slot(slot: int, path: String, mode: ExportMode = ExportMode.ENCRYPTED) -> bool:
	if not exists(slot):
		return false
	
	if mode == ExportMode.DECRYPTED:
		var data = self.load(slot)
		if data == null:
			return false
		
		var export_data = {
			"data": data,
			"export_time": Time.get_unix_time_from_system()
		}
		
		var f = FileAccess.open(path, FileAccess.WRITE)
		if not f:
			return false
		f.store_string(JSON.stringify(export_data))
		f.close()
		return true
	
	else:  # ENCRYPTED
		var src_path = _path(slot)
		var src = FileAccess.open(src_path, FileAccess.READ)
		if not src:
			return false
		
		var file_data = src.get_as_text()
		src.close()
		
		var dst = FileAccess.open(path, FileAccess.WRITE)
		if not dst:
			return false
		dst.store_string(file_data)
		dst.close()
		return true

func import_slot(slot: int, path: String, mode: ExportMode = ExportMode.ENCRYPTED) -> bool:
	if not FileAccess.file_exists(path): return false
	var f = FileAccess.open(path, FileAccess.READ)
	if not f: return false
	var data = f.get_as_text(); f.close()
	if mode == ExportMode.DECRYPTED:
		var p = JSON.parse_string(data)
		if not p or not p.has("d"): return false
		if validate:
			var tmp = _enc.save("user://_test.dat", p.d)
			if not tmp: return false
			_enc.delete(999)
			DirAccess.remove_absolute("user://_test.dat")
		return save(slot, p.d)
	else:
		var dst = FileAccess.open(_path(slot), FileAccess.WRITE)
		if not dst: return false
		dst.store_string(data); dst.close()
		if validate:
			var test = _enc.load(_path(slot))
			if test == null:
				delete(slot)
				return false
		_cache.erase(slot)
		return true

func _path(slot: int) -> String: 
	return "user://save_%d.dat" % slot

func _setup():
	_timer = Timer.new()
	_timer.wait_time = interval
	_timer.autostart = true
	_timer.timeout.connect(_auto)
	add_child(_timer)

func _auto():
	if _cur >= 0 and _cache.has(_cur):
		var c = _cache[_cur]
		save(_cur, c.get("d", c), c.get("m", {}))