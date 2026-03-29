extends Node
class_name DERSaveLimit

@export var max_saves_per_minute: int = 10
@export var max_loads_per_minute: int = 10
@export var max_saves_per_hour: int = 50
@export var max_loads_per_hour: int = 50
@export var global_max_per_minute: int = 0
@export var cooldown_seconds: float = 2.0
@export var auto_reset: bool = true
@export var reset_interval: float = 3600.0
@export var max_attempts: int = 5

var _save_history: Dictionary = {}
var _load_history: Dictionary = {}
var _last_save_time: Dictionary = {}
var _last_load_time: Dictionary = {}
var _attempts: Dictionary = {}
var _reset_timer: Timer
var _cleanup_timer: Timer

signal save_blocked(slot: int, reason: String)
signal load_blocked(slot: int, reason: String)
signal rate_limit_warning(slot: int, action: String, count: int, limit: int)
signal cheat_attempt_detected(slot: int, attempts: int)

func _ready():
	if auto_reset:
		_setup_reset_timer()
	_setup_cleanup_timer()

func can_save(slot: int) -> bool:
	var now = Time.get_unix_time_from_system()
	
	if _last_save_time.has(slot):
		var elapsed = now - _last_save_time[slot]
		if elapsed < cooldown_seconds:
			save_blocked.emit(slot, "Cooldown: %.1f seconds remaining" % (cooldown_seconds - elapsed))
			_record_attempt(slot)
			return false
	
	if _is_rate_limited(_save_history, slot, max_saves_per_minute, 60.0):
		var count = _get_count_in_window(_save_history, slot, 60.0)
		rate_limit_warning.emit(slot, "save", count, max_saves_per_minute)
		save_blocked.emit(slot, "Rate limit: %d saves per minute exceeded" % max_saves_per_minute)
		_record_attempt(slot)
		return false
	
	if _is_rate_limited(_save_history, slot, max_saves_per_hour, 3600.0):
		var count = _get_count_in_window(_save_history, slot, 3600.0)
		rate_limit_warning.emit(slot, "save", count, max_saves_per_hour)
		save_blocked.emit(slot, "Rate limit: %d saves per hour exceeded" % max_saves_per_hour)
		_record_attempt(slot)
		return false
	
	if _is_global_rate_limited():
		save_blocked.emit(slot, "Global rate limit exceeded")
		_record_attempt(slot)
		return false
	
	return true

func can_load(slot: int) -> bool:
	var now = Time.get_unix_time_from_system()
	
	if _last_load_time.has(slot):
		var elapsed = now - _last_load_time[slot]
		if elapsed < cooldown_seconds:
			load_blocked.emit(slot, "Cooldown: %.1f seconds remaining" % (cooldown_seconds - elapsed))
			_record_attempt(slot)
			return false
	
	if _is_rate_limited(_load_history, slot, max_loads_per_minute, 60.0):
		var count = _get_count_in_window(_load_history, slot, 60.0)
		rate_limit_warning.emit(slot, "load", count, max_loads_per_minute)
		load_blocked.emit(slot, "Rate limit: %d loads per minute exceeded" % max_loads_per_minute)
		_record_attempt(slot)
		return false
	
	if _is_rate_limited(_load_history, slot, max_loads_per_hour, 3600.0):
		var count = _get_count_in_window(_load_history, slot, 3600.0)
		rate_limit_warning.emit(slot, "load", count, max_loads_per_hour)
		load_blocked.emit(slot, "Rate limit: %d loads per hour exceeded" % max_loads_per_hour)
		_record_attempt(slot)
		return false
	
	if _is_global_rate_limited():
		load_blocked.emit(slot, "Global rate limit exceeded")
		_record_attempt(slot)
		return false
	
	return true

func record_save(slot: int) -> void:
	var now = Time.get_unix_time_from_system()
	
	if not _save_history.has(slot):
		_save_history[slot] = []
	
	_save_history[slot].append(now)
	_last_save_time[slot] = now
	_clear_attempts(slot)

func record_load(slot: int) -> void:
	var now = Time.get_unix_time_from_system()
	
	if not _load_history.has(slot):
		_load_history[slot] = []
	
	_load_history[slot].append(now)
	_last_load_time[slot] = now
	_clear_attempts(slot)

func get_save_count(slot: int, window: float = 60.0) -> int:
	if not _save_history.has(slot):
		return 0
	return _get_count_in_window(_save_history, slot, window)

func get_load_count(slot: int, window: float = 60.0) -> int:
	if not _load_history.has(slot):
		return 0
	return _get_count_in_window(_load_history, slot, window)

func get_last_save_time(slot: int) -> float:
	return _last_save_time.get(slot, 0.0)

func get_last_load_time(slot: int) -> float:
	return _last_load_time.get(slot, 0.0)

func get_cooldown_remaining(slot: int, action: String) -> float:
	var last_time = _last_save_time.get(slot, 0.0) if action == "save" else _last_load_time.get(slot, 0.0)
	if last_time == 0.0:
		return 0.0
	var elapsed = Time.get_unix_time_from_system() - last_time
	return max(0.0, cooldown_seconds - elapsed)

func reset_slot(slot: int) -> void:
	_save_history.erase(slot)
	_load_history.erase(slot)
	_last_save_time.erase(slot)
	_last_load_time.erase(slot)
	_attempts.erase(slot)

func reset_all() -> void:
	_save_history.clear()
	_load_history.clear()
	_last_save_time.clear()
	_last_load_time.clear()
	_attempts.clear()

func set_limits(save_per_min: int, load_per_min: int, save_per_hour: int, load_per_hour: int) -> void:
	max_saves_per_minute = save_per_min
	max_loads_per_minute = load_per_min
	max_saves_per_hour = save_per_hour
	max_loads_per_hour = load_per_hour

func set_cooldown(seconds: float) -> void:
	cooldown_seconds = seconds

func _is_rate_limited(history: Dictionary, slot: int, limit: int, window: float) -> bool:
	if limit <= 0:
		return false
	var count = _get_count_in_window(history, slot, window)
	return count >= limit

func _get_count_in_window(history: Dictionary, slot: int, window: float) -> int:
	if not history.has(slot):
		return 0
	
	var arr = history[slot]
	if arr.is_empty():
		return 0
	
	var cutoff = Time.get_unix_time_from_system() - window
	var left = 0
	var right = arr.size()
	
	while left < right:
		var mid = (left + right) / 2
		if arr[mid] >= cutoff:
			right = mid
		else:
			left = mid + 1
	
	return arr.size() - left

func _is_global_rate_limited() -> bool:
	if global_max_per_minute <= 0:
		return false
	
	var total = 0
	for slot in _save_history:
		total += _get_count_in_window(_save_history, slot, 60.0)
	
	return total >= global_max_per_minute

func _record_attempt(slot: int) -> void:
	var attempts = _attempts.get(slot, 0) + 1
	_attempts[slot] = attempts
	
	if attempts >= max_attempts:
		cheat_attempt_detected.emit(slot, attempts)
		_attempts[slot] = 0

func _clear_attempts(slot: int) -> void:
	_attempts.erase(slot)

func _cleanup_all_history() -> void:
	var cutoff = Time.get_unix_time_from_system() - 3600.0
	
	for slot in _save_history.keys():
		_save_history[slot] = _save_history[slot].filter(func(t): return t >= cutoff)
	
	for slot in _load_history.keys():
		_load_history[slot] = _load_history[slot].filter(func(t): return t >= cutoff)

func _setup_reset_timer() -> void:
	_reset_timer = Timer.new()
	_reset_timer.wait_time = reset_interval
	_reset_timer.autostart = true
	_reset_timer.timeout.connect(_auto_reset)
	add_child(_reset_timer)

func _setup_cleanup_timer() -> void:
	_cleanup_timer = Timer.new()
	_cleanup_timer.wait_time = 300.0
	_cleanup_timer.autostart = true
	_cleanup_timer.timeout.connect(_auto_cleanup)
	add_child(_cleanup_timer)

func _auto_reset() -> void:
	reset_all()

func _auto_cleanup() -> void:
	_cleanup_all_history()

func get_stats() -> Dictionary:
	var stats = {
		"active_slots": {},
		"total_saves": 0,
		"total_loads": 0,
		"cooldown": cooldown_seconds,
		"max_attempts": max_attempts,
		"limits": {
			"saves_per_min": max_saves_per_minute,
			"loads_per_min": max_loads_per_minute,
			"saves_per_hour": max_saves_per_hour,
			"loads_per_hour": max_loads_per_hour,
			"global_per_min": global_max_per_minute
		}
	}
	
	for slot in _save_history:
		stats.active_slots[slot] = {
			"saves": _save_history[slot].size(),
			"loads": _load_history.get(slot, []).size(),
			"last_save": _last_save_time.get(slot, 0),
			"last_load": _last_load_time.get(slot, 0),
			"attempts": _attempts.get(slot, 0)
		}
		stats.total_saves += _save_history[slot].size()
	
	for slot in _load_history:
		stats.total_loads += _load_history[slot].size()
	
	return stats