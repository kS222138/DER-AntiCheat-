class_name DERConfigDiff
extends RefCounted

enum DiffType { ADDED, REMOVED, MODIFIED, TYPE_CHANGED }
enum ArrayMode { AS_WHOLE, BY_INDEX, AS_SET }

class DiffEntry:
	var key: String
	var type: DiffType
	var old_val: Variant
	var new_val: Variant
	
	func _init(k: String, t: DiffType, o, n):
		key = k
		type = t
		old_val = o
		new_val = n
	
	func to_string() -> String:
		var ts = ["+", "-", "~", "T"][type]
		match type:
			DiffType.ADDED:
				return "%s %s = %s" % [ts, key, str(new_val)]
			DiffType.REMOVED:
				return "%s %s (was %s)" % [ts, key, str(old_val)]
			_:
				return "%s %s (%s -> %s)" % [ts, key, str(old_val), str(new_val)]
	
	func to_dict() -> Dictionary:
		return {"key": key, "type": type, "old": old_val, "new": new_val}

const MAX_DEPTH = 100
const MAX_SIZE = 10 * 1024 * 1024

var _default_mode: ArrayMode = ArrayMode.AS_WHOLE
var _config_loader: Callable = _load_json
var _current_depth = 0
var _visited = {}

func set_mode(mode: ArrayMode) -> void:
	_default_mode = mode

func set_loader(loader: Callable) -> void:
	_config_loader = loader

func compare(old: Dictionary, new: Dictionary, deep: bool = false, mode: ArrayMode = -1) -> Array:
	var m = mode if mode != -1 else _default_mode
	_visited.clear()
	_current_depth = 0
	return _deep(old, new, "", m) if deep else _shallow(old, new)

func compare_files(a: String, b: String, deep: bool = false, mode: ArrayMode = -1) -> Array:
	if not FileAccess.file_exists(a) or not FileAccess.file_exists(b):
		return []
	var old = _config_loader.call(a)
	var new = _config_loader.call(b)
	if old.is_empty() or new.is_empty():
		return []
	return compare(old, new, deep, mode)

func export_json(diffs: Array, path: String) -> int:
	var data = []
	for d in diffs:
		data.append(d.to_dict())
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return ERR_CANT_CREATE
	f.store_string(JSON.stringify(data, "\t"))
	return OK

func report(diffs: Array) -> String:
	if diffs.is_empty():
		return "No differences"
	var s = "Config Diff Report\n"
	s += "========================================\n"
	for d in diffs:
		s += d.to_string() + "\n"
	s += "========================================\n"
	s += "Total: " + str(diffs.size())
	return s

func stats(diffs: Array) -> Dictionary:
	var r = {"added": 0, "removed": 0, "modified": 0, "type": 0}
	for d in diffs:
		match d.type:
			DiffType.ADDED:
				r.added += 1
			DiffType.REMOVED:
				r.removed += 1
			DiffType.MODIFIED:
				r.modified += 1
			DiffType.TYPE_CHANGED:
				r.type += 1
	r.total = diffs.size()
	return r

func _shallow(old: Dictionary, new: Dictionary) -> Array:
	var diffs = []
	var keys = old.keys() + new.keys()
	var seen = {}
	for k in keys:
		if seen.has(k):
			continue
		seen[k] = true
		var o = old.get(k)
		var n = new.get(k)
		if not old.has(k) and new.has(k):
			diffs.append(DiffEntry.new(k, DiffType.ADDED, null, n))
		elif old.has(k) and not new.has(k):
			diffs.append(DiffEntry.new(k, DiffType.REMOVED, o, null))
		elif typeof(o) != typeof(n):
			diffs.append(DiffEntry.new(k, DiffType.TYPE_CHANGED, o, n))
		elif o != n:
			diffs.append(DiffEntry.new(k, DiffType.MODIFIED, o, n))
	return diffs

func _deep(old, new, base: String, mode: ArrayMode) -> Array:
	var diffs = []
	_current_depth += 1
	if _current_depth > MAX_DEPTH:
		push_warning("DERConfigDiff: Max depth at %s" % base)
		_current_depth -= 1
		return []
	
	var oid = _get_id(old)
	var nid = _get_id(new)
	if (oid != -1 and _visited.has(oid)) or (nid != -1 and _visited.has(nid)):
		push_warning("DERConfigDiff: Circular ref at %s" % base)
		_current_depth -= 1
		return []
	if oid != -1:
		_visited[oid] = true
	if nid != -1:
		_visited[nid] = true
	
	if typeof(old) != typeof(new):
		diffs.append(DiffEntry.new(base, DiffType.TYPE_CHANGED, old, new))
	elif old is Dictionary and new is Dictionary:
		var keys = old.keys() + new.keys()
		var seen = {}
		for k in keys:
			if seen.has(k):
				continue
			seen[k] = true
			var sub = base + "." + k if base != "" else k
			var o = old.get(k)
			var n = new.get(k)
			if not old.has(k) and new.has(k):
				diffs.append(DiffEntry.new(sub, DiffType.ADDED, null, n))
			elif old.has(k) and not new.has(k):
				diffs.append(DiffEntry.new(sub, DiffType.REMOVED, o, null))
			else:
				diffs.append_array(_deep(o, n, sub, mode))
	elif old is Array and new is Array:
		match mode:
			ArrayMode.BY_INDEX:
				for i in range(max(old.size(), new.size())):
					var sub = base + "[" + str(i) + "]"
					if i >= old.size():
						diffs.append(DiffEntry.new(sub, DiffType.ADDED, null, new[i]))
					elif i >= new.size():
						diffs.append(DiffEntry.new(sub, DiffType.REMOVED, old[i], null))
					else:
						diffs.append_array(_deep(old[i], new[i], sub, mode))
			ArrayMode.AS_SET:
				var oset = _arr_to_set(old)
				var nset = _arr_to_set(new)
				for k in oset:
					if not nset.has(k):
						diffs.append(DiffEntry.new(base, DiffType.REMOVED, oset[k], null))
				for k in nset:
					if not oset.has(k):
						diffs.append(DiffEntry.new(base, DiffType.ADDED, null, nset[k]))
			_:
				if old != new:
					diffs.append(DiffEntry.new(base, DiffType.MODIFIED, old, new))
	elif old != new:
		diffs.append(DiffEntry.new(base, DiffType.MODIFIED, old, new))
	
	if oid != -1:
		_visited.erase(oid)
	if nid != -1:
		_visited.erase(nid)
	_current_depth -= 1
	return diffs

func _get_id(v) -> int:
	return v.get_instance_id() if v is Object or v is RefCounted else -1

func _arr_to_set(arr: Array) -> Dictionary:
	var d = {}
	for v in arr:
		var k = _hash(v)
		if not d.has(k):
			d[k] = v
	return d

func _hash(v) -> String:
	if v is Dictionary:
		var ks = v.keys()
		ks.sort()
		var p = []
		for k in ks:
			p.append(_hash(k) + ":" + _hash(v[k]))
		return "{" + ",".join(p) + "}"
	if v is Array:
		var p = []
		for i in v:
			p.append(_hash(i))
		return "[" + ",".join(p) + "]"
	return str(v)

func _load_json(p: String) -> Dictionary:
	var f = FileAccess.open(p, FileAccess.READ)
	if not f:
		push_error("DERConfigDiff: Cannot open %s" % p)
		return {}
	if f.get_length() > MAX_SIZE:
		push_error("DERConfigDiff: File too large %s" % p)
		return {}
	var j = JSON.new()
	var e = j.parse(f.get_as_text())
	if e != OK:
		push_error("DERConfigDiff: JSON error in %s: %s" % [p, j.get_error_message()])
		return {}
	var d = j.get_data()
	if d is Dictionary:
		return d
	push_error("DERConfigDiff: JSON root not a dict in %s" % p)
	return {}