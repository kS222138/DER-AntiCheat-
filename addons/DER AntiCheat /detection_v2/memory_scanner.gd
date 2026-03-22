class_name DERMemoryScanner
extends RefCounted

enum ScanType {
	CE_STYLE,
	GG_STYLE,
	FUZZY,
	UNKNOWN
}

enum DetectionLevel {
	LOW,
	MEDIUM,
	HIGH,
	CRITICAL
}

class ScanThreat:
	var type: ScanType
	var level: DetectionLevel
	var details: Dictionary
	var timestamp: int
	
	func _init(t: ScanType, l: DetectionLevel, d: Dictionary):
		type = t
		level = l
		details = d
		timestamp = Time.get_unix_time_from_system()
	
	func to_string() -> String:
		var type_str = ["CE", "GG", "FUZZY", "UNKNOWN"][type]
		var level_str = ["LOW", "MEDIUM", "HIGH", "CRITICAL"][level]
		return "[%s] %s: %s" % [level_str, type_str, JSON.stringify(details)]
	
	func to_dict() -> Dictionary:
		return {
			"type": type,
			"type_name": ["CE_STYLE", "GG_STYLE", "FUZZY", "UNKNOWN"][type],
			"level": level,
			"level_name": ["LOW", "MEDIUM", "HIGH", "CRITICAL"][level],
			"details": details,
			"timestamp": timestamp
		}

const SCAN_THRESHOLDS = {
	"reads_per_second": 1000,
	"writes_per_second": 500,
	"pattern_scan_frequency": 10,
	"memory_access_spike": 5.0
}

const SUSPICIOUS_PATTERNS = [
	"cheat engine",
	"game guardian",
	"memory scanner",
	"value search",
	"memory editor"
]

const MAX_HISTORY_SIZE := 500
const HISTORY_TIME_WINDOW := 5000
const PROCESS_SCAN_INTERVAL := 10000

var _logger: DERLogger
var _enabled: bool = true
var _scan_interval: float = 2.0
var _threats: Array[ScanThreat] = []
var _read_count: int = 0
var _write_count: int = 0
var _last_reset: int = 0
var _last_process_scan: int = 0
var _peak_read_rate: float = 0.0
var _peak_write_rate: float = 0.0
var _access_history: Array = []
var _whitelist: Array[String] = []
var _on_threat_detected: Callable
var _scan_timer: SceneTreeTimer
var _tree: SceneTree

func _init(logger: DERLogger = null):
	_logger = logger
	_last_reset = Time.get_ticks_msec()
	_last_process_scan = Time.get_ticks_msec()

func set_enabled(enabled: bool) -> void:
	_enabled = enabled

func set_scan_interval(interval: float) -> void:
	_scan_interval = interval

func set_threat_callback(callback: Callable) -> void:
	_on_threat_detected = callback

func add_to_whitelist(pattern: String) -> void:
	_whitelist.append(pattern)

func start_continuous_scan(tree: SceneTree) -> void:
	_tree = tree
	_scan_continuous()

func stop_continuous_scan() -> void:
	_scan_timer = null

func record_read() -> void:
	_read_count += 1
	_update_access_history("read")

func record_write() -> void:
	_write_count += 1
	_update_access_history("write")

func scan() -> Array[ScanThreat]:
	if not _enabled:
		return []
	
	var threats: Array[ScanThreat] = []
	_reset_counts_if_needed()
	
	threats.append_array(_detect_rate_anomaly())
	threats.append_array(_detect_pattern_scan())
	threats.append_array(_detect_access_spike())
	threats.append_array(_detect_scanning_process())
	threats.append_array(_detect_fuzzy_search())
	
	for t in threats:
		if _is_whitelisted(t.details):
			continue
		_threats.append(t)
		if _logger:
			_logger.warning("memory", t.to_string())
		if _on_threat_detected:
			_on_threat_detected.call(t)
	
	return threats

func get_threats() -> Array[ScanThreat]:
	return _threats.duplicate()

func clear_threats() -> void:
	_threats.clear()

func get_stats() -> Dictionary:
	return {
		"total_threats": _threats.size(),
		"current_read_rate": _get_read_rate(),
		"current_write_rate": _get_write_rate(),
		"peak_read_rate": _peak_read_rate,
		"peak_write_rate": _peak_write_rate,
		"enabled": _enabled
	}

func generate_report() -> String:
	var report = "Memory Scanner Detection Report\n"
	report += "========================================\n"
	report += "Total threats: " + str(_threats.size()) + "\n"
	
	var by_type = _count_by_type()
	if not by_type.is_empty():
		report += "\nBy type:\n"
		for t in by_type:
			report += "  " + t + ": " + str(by_type[t]) + "\n"
	
	var by_level = _count_by_level()
	if not by_level.is_empty():
		report += "\nBy level:\n"
		for l in by_level:
			report += "  " + l + ": " + str(by_level[l]) + "\n"
	
	return report

func _scan_continuous() -> void:
	if not _enabled or not _tree:
		return
	scan()
	_scan_timer = _tree.create_timer(_scan_interval)
	await _scan_timer.timeout
	_scan_continuous()

func _reset_counts_if_needed() -> void:
	var now = Time.get_ticks_msec()
	if now - _last_reset > 1000:
		_peak_read_rate = max(_peak_read_rate, _get_read_rate())
		_peak_write_rate = max(_peak_write_rate, _get_write_rate())
		_read_count = 0
		_write_count = 0
		_last_reset = now

func _get_read_rate() -> float:
	var now = Time.get_ticks_msec()
	var elapsed = max(1, now - _last_reset)
	return _read_count / (elapsed / 1000.0)

func _get_write_rate() -> float:
	var now = Time.get_ticks_msec()
	var elapsed = max(1, now - _last_reset)
	return _write_count / (elapsed / 1000.0)

func _update_access_history(type: String) -> void:
	var now = Time.get_ticks_msec()
	_access_history.append({"time": now, "type": type})
	
	while _access_history.size() > 0 and now - _access_history[0].time > HISTORY_TIME_WINDOW:
		_access_history.pop_front()
	
	while _access_history.size() > MAX_HISTORY_SIZE:
		_access_history.pop_front()

func _detect_rate_anomaly() -> Array[ScanThreat]:
	var threats: Array[ScanThreat] = []
	
	var read_rate = _get_read_rate()
	if read_rate > SCAN_THRESHOLDS["reads_per_second"]:
		threats.append(ScanThreat.new(
			ScanType.CE_STYLE,
			DetectionLevel.HIGH,
			{"rate": read_rate, "type": "read", "threshold": SCAN_THRESHOLDS["reads_per_second"]}
		))
	
	var write_rate = _get_write_rate()
	if write_rate > SCAN_THRESHOLDS["writes_per_second"]:
		threats.append(ScanThreat.new(
			ScanType.CE_STYLE,
			DetectionLevel.HIGH,
			{"rate": write_rate, "type": "write", "threshold": SCAN_THRESHOLDS["writes_per_second"]}
		))
	
	return threats

func _detect_pattern_scan() -> Array[ScanThreat]:
	var threats: Array[ScanThreat] = []
	
	if _access_history.size() < 20:
		return threats
	
	var consecutive_reads = 0
	var max_consecutive_reads = 0
	
	for record in _access_history:
		if record.type == "read":
			consecutive_reads += 1
			max_consecutive_reads = max(max_consecutive_reads, consecutive_reads)
		else:
			consecutive_reads = 0
	
	var alternating = 0
	var last_type = ""
	for record in _access_history:
		if last_type != "" and record.type != last_type:
			alternating += 1
		last_type = record.type
	
	var alternating_ratio = alternating / max(1.0, _access_history.size())
	
	if max_consecutive_reads > 50:
		threats.append(ScanThreat.new(
			ScanType.CE_STYLE,
			DetectionLevel.MEDIUM,
			{"pattern": "consecutive_reads", "count": max_consecutive_reads}
		))
	
	if alternating_ratio > 0.8:
		threats.append(ScanThreat.new(
			ScanType.CE_STYLE,
			DetectionLevel.HIGH,
			{"pattern": "alternating_access", "ratio": alternating_ratio}
		))
	
	return threats

func _detect_access_spike() -> Array[ScanThreat]:
	var threats: Array[ScanThreat] = []
	
	if _access_history.size() < 50:
		return threats
	
	var recent_window = 500
	var old_window = 5000
	
	var recent = 0
	var older = 0
	var now = Time.get_ticks_msec()
	
	for record in _access_history:
		var age = now - record.time
		if age < recent_window:
			recent += 1
		elif age < recent_window + old_window:
			older += 1
	
	var spike_ratio = recent / max(1.0, older)
	if spike_ratio > SCAN_THRESHOLDS["memory_access_spike"]:
		threats.append(ScanThreat.new(
			ScanType.UNKNOWN,
			DetectionLevel.MEDIUM,
			{"spike_ratio": spike_ratio, "recent": recent, "older": older}
		))
	
	return threats

func _detect_scanning_process() -> Array[ScanThreat]:
	var threats: Array[ScanThreat] = []
	var now = Time.get_ticks_msec()
	
	if now - _last_process_scan < PROCESS_SCAN_INTERVAL:
		return threats
	_last_process_scan = now
	
	if OS.has_feature("windows"):
		var output = []
		var exit_code = OS.execute("tasklist", [], output)
		if exit_code == 0:
			for line in output:
				var line_lower = line.to_lower()
				for pattern in SUSPICIOUS_PATTERNS:
					if line_lower.find(pattern) != -1:
						threats.append(ScanThreat.new(
							ScanType.UNKNOWN,
							DetectionLevel.HIGH,
							{"process": line.strip_edges(), "pattern": pattern}
						))
	
	if OS.has_feature("android"):
		var output = []
		var exit_code = OS.execute("ps", [], output)
		if exit_code == 0:
			for line in output:
				var line_lower = line.to_lower()
				for pattern in SUSPICIOUS_PATTERNS:
					if line_lower.find(pattern) != -1:
						threats.append(ScanThreat.new(
							ScanType.GG_STYLE,
							DetectionLevel.HIGH,
							{"process": line.strip_edges(), "pattern": pattern}
						))
	
	return threats

func _detect_fuzzy_search() -> Array[ScanThreat]:
	var threats: Array[ScanThreat] = []
	
	if _access_history.size() < 50:
		return threats
	
	var reads = 0
	var writes = 0
	for record in _access_history:
		if record.type == "read":
			reads += 1
		else:
			writes += 1
	
	if reads > 100 and writes < reads * 0.01:
		threats.append(ScanThreat.new(
			ScanType.FUZZY,
			DetectionLevel.HIGH,
			{"reads": reads, "writes": writes, "ratio": writes / max(1, reads)}
		))
	
	return threats

func _is_whitelisted(details: Dictionary) -> bool:
	for pattern in _whitelist:
		if JSON.stringify(details).find(pattern) != -1:
			return true
	return false

func _count_by_type() -> Dictionary:
	var counts = {}
	for t in _threats:
		var name = ["CE", "GG", "FUZZY", "UNKNOWN"][t.type]
		counts[name] = counts.get(name, 0) + 1
	return counts

func _count_by_level() -> Dictionary:
	var counts = {}
	for t in _threats:
		var name = ["LOW", "MEDIUM", "HIGH", "CRITICAL"][t.level]
		counts[name] = counts.get(name, 0) + 1
	return counts