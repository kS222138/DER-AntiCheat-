extends Control
class_name DERDashboard

@export var refresh_interval: float = 1.0
@export var show_charts: bool = true
@export var max_history: int = 60
@export var auto_refresh: bool = true
@export var dashboard_size: Vector2 = Vector2(400, 300)

@export var label_total: Label
@export var label_critical: Label
@export var label_high: Label
@export var label_warning: Label
@export var label_info: Label
@export var label_health: Label
@export var label_status: Label
@export var chart_color: Color = Color(0.3, 0.8, 0.3)

var _alert_manager: DERAlertManager
var _history: Array = []
var _timer: Timer
var _stats: Dictionary = {}

signal dashboard_updated(stats: Dictionary)

func _ready():
	size = dashboard_size
	if auto_refresh:
		_setup_timer()
	_setup_ui()

func setup(alert_manager: DERAlertManager) -> void:
	_alert_manager = alert_manager
	_refresh()

func _setup_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = refresh_interval
	_timer.autostart = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)

func _setup_ui() -> void:
	visible = true
	_update_labels()

func _refresh() -> void:
	if _alert_manager:
		_stats = _alert_manager.get_stats()
		_update_history()
		_update_labels()
		queue_redraw()
		dashboard_updated.emit(_stats)

func _update_history() -> void:
	var current = {
		"time": Time.get_unix_time_from_system(),
		"total": _stats.get("total", 0),
		"info": _stats.get("info", 0),
		"warning": _stats.get("warning", 0),
		"high": _stats.get("high", 0),
		"critical": _stats.get("critical", 0)
	}
	_history.append(current)
	if _history.size() > max_history:
		_history.pop_front()

func _update_labels() -> void:
	if label_total:
		label_total.text = "Total: %d" % _stats.get("total", 0)
	if label_critical:
		label_critical.text = "Critical: %d" % _stats.get("critical", 0)
	if label_high:
		label_high.text = "High: %d" % _stats.get("high", 0)
	if label_warning:
		label_warning.text = "Warning: %d" % _stats.get("warning", 0)
	if label_info:
		label_info.text = "Info: %d" % _stats.get("info", 0)
	if label_health:
		label_health.text = "Health: %.1f" % get_health_score()
	if label_status:
		label_status.text = "Status: %s" % get_health_status()
		label_status.add_theme_color_override("font_color", _get_status_color())

func _draw():
	if not show_charts or _history.size() < 2:
		return
	
	var width = size.x - 20
	var height = size.y - 20
	var start_x = 10
	var start_y = 10
	
	var critical_points = []
	var high_points = []
	var warning_points = []
	
	for i in range(_history.size()):
		var x = start_x + (i * width / max_history)
		var critical_y = start_y + height - (_history[i].critical * 5)
		var high_y = start_y + height - (_history[i].high * 3)
		var warning_y = start_y + height - (_history[i].warning * 2)
		
		critical_points.append(Vector2(x, critical_y))
		high_points.append(Vector2(x, high_y))
		warning_points.append(Vector2(x, warning_y))
	
	if critical_points.size() > 1:
		draw_polyline(critical_points, Color.RED, 2.0)
	if high_points.size() > 1:
		draw_polyline(high_points, Color.ORANGE, 1.5)
	if warning_points.size() > 1:
		draw_polyline(warning_points, Color.YELLOW, 1.0)

func get_total_threats() -> int:
	return _stats.get("total", 0)

func get_critical_threats() -> int:
	return _stats.get("critical", 0)

func get_warning_threats() -> int:
	return _stats.get("warning", 0)

func get_high_threats() -> int:
	return _stats.get("high", 0)

func get_info_threats() -> int:
	return _stats.get("info", 0)

func get_history() -> Array:
	return _history.duplicate()

func get_stats() -> Dictionary:
	return _stats.duplicate()

func get_health_score() -> float:
	var total = _stats.get("total", 0)
	if total == 0:
		return 100.0
	
	var critical = _stats.get("critical", 0)
	var high = _stats.get("high", 0)
	var warning = _stats.get("warning", 0)
	
	var score = 100.0
	score -= critical * 15.0
	score -= high * 5.0
	score -= warning * 1.0
	return clamp(score, 0.0, 100.0)

func get_health_status() -> String:
	var score = get_health_score()
	if score >= 90:
		return "Excellent"
	elif score >= 70:
		return "Good"
	elif score >= 50:
		return "Fair"
	elif score >= 30:
		return "Poor"
	else:
		return "Critical"

func _get_status_color() -> Color:
	var score = get_health_score()
	if score >= 70:
		return Color(0.3, 0.8, 0.3)
	elif score >= 50:
		return Color(0.8, 0.8, 0.2)
	else:
		return Color(0.8, 0.2, 0.2)

func get_alert_rate(window: float = 60.0) -> float:
	var cutoff = Time.get_unix_time_from_system() - window
	var count = 0
	for entry in _history:
		if entry.time >= cutoff:
			count += entry.total
	return count / window

func export_to_dict() -> Dictionary:
	return {
		"stats": _stats,
		"history": _history,
		"health_score": get_health_score(),
		"health_status": get_health_status(),
		"alert_rate": get_alert_rate(),
		"timestamp": Time.get_unix_time_from_system()
	}