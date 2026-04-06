extends Control
class_name DERLogViewer

@export var max_lines: int = 1000
@export var refresh_interval: float = 1.0
@export var show_timestamp: bool = true
@export var show_level: bool = true
@export var show_type: bool = true
@export var auto_scroll: bool = true

var _logger = null
var _logs = []
var _filtered_logs = []
var _filter_level = ""
var _filter_type = ""
var _filter_text = ""
var _timer = null

var _log_display = null
var _level_option = null
var _type_option = null
var _search_line = null
var _status_label = null

signal export_requested(format)

func _ready():
	_setup_ui()
	_setup_timer()

func setup(logger):
	_logger = logger
	refresh()

func _setup_ui():
	size = Vector2(700, 500)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)
	
	var filter_hbox = HBoxContainer.new()
	filter_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(filter_hbox)
	
	var level_label = Label.new()
	level_label.text = "Level:"
	filter_hbox.add_child(level_label)
	
	_level_option = OptionButton.new()
	_level_option.add_item("All")
	_level_option.add_item("DEBUG")
	_level_option.add_item("INFO")
	_level_option.add_item("WARNING")
	_level_option.add_item("ERROR")
	_level_option.item_selected.connect(_on_level_changed)
	filter_hbox.add_child(_level_option)
	
	var type_label = Label.new()
	type_label.text = "Type:"
	filter_hbox.add_child(type_label)
	
	_type_option = OptionButton.new()
	_type_option.add_item("All")
	_type_option.item_selected.connect(_on_type_changed)
	filter_hbox.add_child(_type_option)
	
	var search_label = Label.new()
	search_label.text = "Search:"
	filter_hbox.add_child(search_label)
	
	_search_line = LineEdit.new()
	_search_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_line.text_changed.connect(_on_search_changed)
	filter_hbox.add_child(_search_line)
	
	var refresh_btn = Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(refresh)
	filter_hbox.add_child(refresh_btn)
	
	var export_btn = Button.new()
	export_btn.text = "Export"
	export_btn.pressed.connect(_on_export)
	filter_hbox.add_child(export_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_clear_logs)
	filter_hbox.add_child(clear_btn)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	_log_display = RichTextLabel.new()
	_log_display.bbcode_enabled = true
	_log_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_display.scroll_following = auto_scroll
	scroll.add_child(_log_display)
	
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_status_label)

func _setup_timer():
	_timer = Timer.new()
	_timer.wait_time = refresh_interval
	_timer.autostart = true
	_timer.timeout.connect(refresh)
	add_child(_timer)

func refresh():
	if _logger == null:
		return
	
	if _logger.has_method("get_logs"):
		_logs = _logger.get_logs()
	elif _logger.has_method("export"):
		var exported = _logger.export()
		_logs = exported.get("logs", [])
	
	_update_type_filter()
	_apply_filters()
	_update_display()
	_update_status()

func _update_type_filter():
	if _type_option == null:
		return
	var current = _type_option.get_selected_id()
	var types = {}
	for log in _logs:
		var t = log.get("type", "unknown")
		types[t] = true
	
	_type_option.clear()
	_type_option.add_item("All")
	for t in types.keys():
		_type_option.add_item(t)
	
	if current >= 0 and current < _type_option.item_count:
		_type_option.select(current)
	else:
		_type_option.select(0)

func _apply_filters():
	_filtered_logs = []
	for log in _logs:
		if _filter_level != "" and log.get("level", "") != _filter_level:
			continue
		if _filter_type != "" and log.get("type", "") != _filter_type:
			continue
		if _filter_text != "":
			var msg = log.get("message", "").to_lower()
			if msg.find(_filter_text.to_lower()) == -1:
				continue
		_filtered_logs.append(log)
	
	if _filtered_logs.size() > max_lines:
		_filtered_logs = _filtered_logs.slice(-max_lines)

func _update_display():
	if _log_display == null:
		return
	_log_display.clear()
	
	for log in _filtered_logs:
		var line = ""
		if show_timestamp:
			line += "[" + str(log.get("timestamp", "?")) + "] "
		if show_level:
			var level = log.get("level", "INFO")
			var color = _get_level_color(level)
			line += "[color=%s]%s[/color] " % [color, level]
		if show_type:
			line += "(" + log.get("type", "?") + ") "
		line += log.get("message", "")
		_log_display.append_text(line + "\n")

func _update_status():
	if _status_label == null:
		return
	_status_label.text = "Total: %d | Filtered: %d" % [_logs.size(), _filtered_logs.size()]

func _get_level_color(level):
	match level:
		"ERROR": return "#e74c3c"
		"WARNING": return "#f39c12"
		"INFO": return "#2ecc71"
		"DEBUG": return "#95a5a6"
	return "#ffffff"

func _on_level_changed(idx):
	if idx == 0:
		_filter_level = ""
	else:
		_filter_level = _level_option.get_item_text(idx)
	_apply_filters()
	_update_display()
	_update_status()

func _on_type_changed(idx):
	if idx == 0:
		_filter_type = ""
	else:
		_filter_type = _type_option.get_item_text(idx)
	_apply_filters()
	_update_display()
	_update_status()

func _on_search_changed(text):
	_filter_text = text
	_apply_filters()
	_update_display()
	_update_status()

func _on_export():
	export_requested.emit("csv")

func _clear_logs():
	if _logger and _logger.has_method("clear_logs"):
		_logger.clear_logs()
	refresh()
