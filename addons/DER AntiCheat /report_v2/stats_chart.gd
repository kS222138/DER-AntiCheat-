extends Control
class_name DERStatsChart

enum ChartType { LINE, BAR, PIE }

@export var chart_type: ChartType = ChartType.LINE
@export var chart_title: String = ""
@export var width: int = 400
@export var height: int = 300
@export var show_grid: bool = true
@export var show_legend: bool = true

var _data: Dictionary = {}
var _labels: Array = []
var _values: Array = []
var _colors: Array = []
var _dashboard: DERDashboard
var _animation_progress: float = 1.0

func setup(dashboard: DERDashboard):
	_dashboard = dashboard
	_update_data()
	queue_redraw()

func set_data(labels: Array, values: Array, colors: Array = []):
	_labels = labels
	_values = values
	_colors = colors
	queue_redraw()

func set_chart_type(type: ChartType):
	chart_type = type
	queue_redraw()

func animate():
	_animation_progress = 0.0
	var tween = create_tween()
	tween.tween_property(self, "_animation_progress", 1.0, 0.5)

func _update_data():
	if _dashboard == null:
		return
	
	var stats = _dashboard.get_stats()
	_labels = ["Critical", "High", "Warning", "Info"]
	_values = [
		stats.get("critical", 0),
		stats.get("high", 0),
		stats.get("warning", 0),
		stats.get("info", 0)
	]
	_colors = [Color(0.91, 0.27, 0.24), Color(0.9, 0.42, 0.13), Color(0.95, 0.61, 0.07), Color(0.31, 0.6, 0.86)]

func _draw():
	var rect = Rect2(Vector2.ZERO, size)
	var chart_rect = Rect2(60, 30, size.x - 80, size.y - 60)
	
	if chart_title != "":
		_draw_title()
	
	match chart_type:
		ChartType.LINE:
			_draw_line_chart(chart_rect)
		ChartType.BAR:
			_draw_bar_chart(chart_rect)
		ChartType.PIE:
			_draw_pie_chart(chart_rect)

func _draw_title():
	var font_size = 16
	var font = ThemeDB.fallback_font
	var title_width = font.get_string_size(chart_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var title_x = (size.x - title_width) / 2
	draw_string(font, Vector2(title_x, 25), chart_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _draw_line_chart(rect):
	if _values.is_empty():
		return
	
	var max_value = _get_max_value()
	var step_x = rect.size.x / max(1, _values.size() - 1)
	var points = []
	
	for i in range(_values.size()):
		var x = rect.position.x + i * step_x
		var animated_value = _values[i] * _animation_progress
		var y = rect.position.y + rect.size.y - (animated_value / max_value) * rect.size.y
		points.append(Vector2(x, y))
	
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], Color(0.31, 0.6, 0.86), 2.0)
	
	for i in range(points.size()):
		draw_circle(points[i], 4, Color(0.31, 0.6, 0.86))
		draw_circle(points[i], 2, Color.WHITE)
		
		var label = str(int(_values[i]))
		var label_width = _get_text_width(label, 10)
		var label_x = points[i].x - label_width / 2
		var label_y = points[i].y - 15
		draw_string(ThemeDB.fallback_font, Vector2(label_x, label_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	
	_draw_axes(rect, max_value)

func _draw_bar_chart(rect):
	if _values.is_empty():
		return
	
	var max_value = _get_max_value()
	var bar_width = rect.size.x / _values.size() * 0.7
	var bar_spacing = rect.size.x / _values.size() * 0.3
	var start_x = rect.position.x + bar_spacing / 2
	
	for i in range(_values.size()):
		var bar_height = (_values[i] / max_value) * rect.size.y * _animation_progress
		var bar_rect = Rect2(
			start_x + i * (bar_width + bar_spacing / _values.size()),
			rect.position.y + rect.size.y - bar_height,
			bar_width,
			bar_height
		)
		
		var color = _get_color_for_index(i)
		draw_rect(bar_rect, color)
		
		var label = str(int(_values[i]))
		var label_width = _get_text_width(label, 10)
		var label_x = bar_rect.position.x + bar_width / 2 - label_width / 2
		var label_y = bar_rect.position.y - 5
		draw_string(ThemeDB.fallback_font, Vector2(label_x, label_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		
		var name = _labels[i] if i < _labels.size() else ""
		var name_width = _get_text_width(name, 10)
		var name_x = bar_rect.position.x + bar_width / 2 - name_width / 2
		var name_y = rect.position.y + rect.size.y + 15
		draw_string(ThemeDB.fallback_font, Vector2(name_x, name_y), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	
	_draw_axes(rect, max_value)

func _draw_pie_chart(rect):
	if _values.is_empty():
		return
	
	var total = 0
	for v in _values:
		total += v
	
	if total == 0:
		return
	
	var center = rect.position + rect.size / 2
	var radius = min(rect.size.x, rect.size.y) / 2
	var start_angle = -90.0
	
	for i in range(_values.size()):
		var angle = 360.0 * _values[i] / total * _animation_progress
		var end_angle = start_angle + angle
		
		var color = _get_color_for_index(i)
		_draw_pie_slice(center, radius, start_angle, end_angle, color)
		
		if show_legend:
			var legend_x = rect.position.x + rect.size.x + 10
			var legend_y = rect.position.y + i * 20
			draw_rect(Rect2(legend_x, legend_y, 12, 12), color)
			var label = "%s: %d" % [_labels[i], _values[i]]
			draw_string(ThemeDB.fallback_font, Vector2(legend_x + 18, legend_y + 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		
		start_angle = end_angle

func _draw_pie_slice(center, radius, start_angle, end_angle, color):
	var points = [center]
	var angle_step = 5.0
	var angle = start_angle
	
	while angle <= end_angle:
		var rad = deg_to_rad(angle)
		var x = center.x + radius * cos(rad)
		var y = center.y + radius * sin(rad)
		points.append(Vector2(x, y))
		angle += angle_step
	
	angle = end_angle
	var rad = deg_to_rad(angle)
	var x = center.x + radius * cos(rad)
	var y = center.y + radius * sin(rad)
	points.append(Vector2(x, y))
	
	if points.size() > 2:
		draw_polygon(points, PackedColorArray([color]))

func _draw_axes(rect, max_value):
	if not show_grid:
		return
	
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(0.5, 0.5, 0.5), 1.0)
	draw_line(rect.position, rect.position + Vector2(0, rect.size.y), Color(0.5, 0.5, 0.5), 1.0)
	
	var y_step = rect.size.y / 4
	for i in range(5):
		var y = rect.position.y + i * y_step
		var value = max_value * (1 - i / 4.0)
		var value_str = str(int(value))
		var label_width = _get_text_width(value_str, 10)
		var label_x = rect.position.x - label_width - 5
		
		draw_line(Vector2(rect.position.x - 5, y), Vector2(rect.position.x, y), Color(0.5, 0.5, 0.5), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(label_x, y + 3), value_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

func _get_max_value():
	var max_val = 0
	for v in _values:
		if v > max_val:
			max_val = v
	return max(max_val, 1)

func _get_color_for_index(index):
	if index < _colors.size():
		return _colors[index]
	var hue = (index * 0.2) % 1.0
	return Color.from_hsv(hue, 0.8, 0.8)

func _get_text_width(text, font_size):
	var font = ThemeDB.fallback_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func update_chart():
	_update_data()
	queue_redraw()

func refresh():
	update_chart()