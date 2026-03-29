extends Node
class_name DERRollbackDetector

enum Action { SAVE, LOAD, DELETE }

@export var enable_timestamp_check: bool = true
@export var enable_version_check: bool = true
@export var enable_playtime_check: bool = false
@export var strict_mode: bool = false
@export var alert_on_rollback: bool = true
@export var save_spam_threshold: float = 5.0
@export var spam_window: float = 60.0

var _slot_history: Dictionary = {}
var _session_start_time: float = 0.0
var _session_playtime: float = 0.0

signal rollback_detected(slot: int, old_timestamp: float, new_timestamp: float, action: Action)
signal suspicious_activity(slot: int, reason: String)

func _init():
	_session_start_time = Time.get_unix_time_from_system()

func record_save(slot: int, timestamp: float = -1.0, version: String = "", playtime: float = -1.0) -> void:
	var now = timestamp if timestamp >= 0 else Time.get_unix_time_from_system()
	var current_playtime = playtime if playtime >= 0 else _session_playtime
	
	if not _slot_history.has(slot):
		_slot_history[slot] = {
			"last_save": 0.0,
			"last_load": 0.0,
			"save_history": [],
			"version": version,
			"playtime": current_playtime,
			"save_count": 0,
			"load_count": 0
		}
	
	var history = _slot_history[slot]
	
	if enable_timestamp_check and history.last_save > now:
		_handle_rollback(slot, history.last_save, now, Action.SAVE)
	
	if enable_version_check and _is_version_downgrade(history.version, version):
		suspicious_activity.emit(slot, "Version downgrade: %s -> %s" % [history.version, version])
	
	if enable_playtime_check and current_playtime < history.playtime:
		suspicious_activity.emit(slot, "Playtime rollback: %.2f -> %.2f" % [history.playtime, current_playtime])
	
	history.last_save = now
	history.version = version
	history.playtime = current_playtime
	history.save_count += 1
	
	history.save_history.append({
		"timestamp": now,
		"version": version,
		"playtime": current_playtime
	})
	
	if history.save_history.size() > 50:
		history.save_history.pop_front()

func record_load(slot: int, timestamp: float = -1.0, version: String = "", playtime: float = -1.0) -> void:
	var now = timestamp if timestamp >= 0 else Time.get_unix_time_from_system()
	var load_playtime = playtime if playtime >= 0 else _session_playtime
	
	if not _slot_history.has(slot):
		_slot_history[slot] = {
			"last_save": 0.0,
			"last_load": 0.0,
			"save_history": [],
			"version": version,
			"playtime": load_playtime,
			"save_count": 0,
			"load_count": 0
		}
	
	var history = _slot_history[slot]
	
	if enable_timestamp_check and history.last_load > now:
		_handle_rollback(slot, history.last_load, now, Action.LOAD)
	
	if enable_version_check and _is_version_downgrade(history.version, version):
		suspicious_activity.emit(slot, "Version downgrade on load: %s -> %s" % [history.version, version])
	
	if enable_playtime_check and load_playtime < history.playtime:
		suspicious_activity.emit(slot, "Playtime rollback on load: %.2f -> %.2f" % [history.playtime, load_playtime])
	
	history.last_load = now
	history.version = version
	history.playtime = load_playtime
	history.load_count += 1

func record_delete(slot: int) -> void:
	if _slot_history.has(slot):
		_slot_history.erase(slot)

func check_slot(slot: int) -> Dictionary:
	if not _slot_history.has(slot):
		return {"exists": false, "suspicious": false}
	
	var history = _slot_history[slot]
	var now = Time.get_unix_time_from_system()
	var suspicious = false
	var reasons = []
	
	if enable_timestamp_check and history.last_save > now:
		suspicious = true
		reasons.append("Save timestamp in future")
	
	if enable_timestamp_check and history.last_load > now:
		suspicious = true
		reasons.append("Load timestamp in future")
	
	if is_save_spamming(slot):
		suspicious = true
		reasons.append("Save spamming detected")
	
	return {
		"exists": true,
		"suspicious": suspicious,
		"reasons": reasons,
		"last_save": history.last_save,
		"last_load": history.last_load,
		"save_count": history.save_count,
		"load_count": history.load_count,
		"version": history.version,
		"playtime": history.playtime
	}

func get_save_history(slot: int) -> Array:
	if not _slot_history.has(slot):
		return []
	return _slot_history[slot].save_history

func get_save_count(slot: int, time_window: float = -1.0) -> int:
	if not _slot_history.has(slot):
		return 0
	
	if time_window <= 0:
		return _slot_history[slot].save_count
	
	var cutoff = Time.get_unix_time_from_system() - time_window
	var count = 0
	for entry in _slot_history[slot].save_history:
		if entry.timestamp >= cutoff:
			count += 1
	return count

func get_save_frequency(slot: int, window: float = 60.0) -> float:
	var count = get_save_count(slot, window)
	return count / window

func is_save_spamming(slot: int) -> bool:
	return get_save_frequency(slot, spam_window) > save_spam_threshold

func get_last_save_time(slot: int) -> float:
	if not _slot_history.has(slot):
		return 0.0
	return _slot_history[slot].last_save

func get_last_load_time(slot: int) -> float:
	if not _slot_history.has(slot):
		return 0.0
	return _slot_history[slot].last_load

func detect_anomaly_pattern(slot: int) -> Dictionary:
	var history = get_save_history(slot)
	if history.size() < 10:
		return {"pattern": "insufficient_data", "size": history.size()}
	
	var intervals = []
	for i in range(1, history.size()):
		intervals.append(history[i].timestamp - history[i-1].timestamp)
	
	var avg = 0.0
	for i in intervals:
		avg += i
	avg /= intervals.size()
	
	var std = 0.0
	for i in intervals:
		std += (i - avg) * (i - avg)
	std = sqrt(std / intervals.size())
	
	var is_regular = std < avg * 0.3
	var is_fast = avg < 5.0
	var suspicious = is_regular and is_fast and intervals.size() > 5
	
	return {
		"pattern": "regular" if is_regular else "irregular",
		"avg_interval": avg,
		"std_dev": std,
		"sample_count": intervals.size(),
		"suspicious": suspicious
	}

func update_playtime(delta: float) -> void:
	_session_playtime += delta

func reset_session() -> void:
	_session_start_time = Time.get_unix_time_from_system()
	_session_playtime = 0.0

func reset_slot(slot: int) -> void:
	_slot_history.erase(slot)

func reset_all() -> void:
	_slot_history.clear()

func save_history_to_file(path: String) -> bool:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(_slot_history))
	f.close()
	return true

func load_history_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data:
		_slot_history = data
		return true
	return false

func _is_version_downgrade(old_ver: String, new_ver: String) -> bool:
	if old_ver.is_empty() or new_ver.is_empty():
		return false
	
	var parts1 = old_ver.split(".")
	var parts2 = new_ver.split(".")
	
	for i in range(min(parts1.size(), parts2.size())):
		var n1 = parts1[i].to_int()
		var n2 = parts2[i].to_int()
		if n1 != n2:
			return n1 > n2
	
	return parts1.size() > parts2.size()

func _handle_rollback(slot: int, old_time: float, new_time: float, action: Action) -> void:
	rollback_detected.emit(slot, old_time, new_time, action)
	
	if alert_on_rollback:
		var action_str = "SAVE" if action == Action.SAVE else "LOAD"
		push_warning("DERRollbackDetector: Rollback detected on slot %d! %s: %f -> %f" % [slot, action_str, old_time, new_time])

func is_suspicious(slot: int) -> bool:
	return check_slot(slot).get("suspicious", false)

func get_stats() -> Dictionary:
	var total_saves = 0
	var total_loads = 0
	var spamming_slots = []
	
	for slot in _slot_history:
		var h = _slot_history[slot]
		total_saves += h.save_count
		total_loads += h.load_count
		if is_save_spamming(slot):
			spamming_slots.append(slot)
	
	return {
		"active_slots": _slot_history.size(),
		"total_saves": total_saves,
		"total_loads": total_loads,
		"spamming_slots": spamming_slots,
		"session_playtime": _session_playtime,
		"session_start": _session_start_time,
		"timestamp_check": enable_timestamp_check,
		"version_check": enable_version_check,
		"playtime_check": enable_playtime_check,
		"spam_threshold": save_spam_threshold,
		"spam_window": spam_window,
		"strict_mode": strict_mode
	}