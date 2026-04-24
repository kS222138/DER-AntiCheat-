@tool
extends CanvasLayer
class_name DERInGamePanel

signal module_toggled(module_name: String, enabled: bool)
signal panel_opened()
signal panel_closed()

const DEFAULT_HOTKEY: Key = KEY_F12
const DEFAULT_PASSWORD: String = ""

@export var hotkey: Key = DEFAULT_HOTKEY
@export var require_ctrl: bool = true
@export var require_shift: bool = true
@export var password: String = DEFAULT_PASSWORD
@export var max_log_lines: int = 100
@export var enabled: bool = true

var _unlocked: bool = false
var _visible: bool = false
var _modules: Dictionary = {}
var _log_buffer: Array[String] = []

var _backdrop: ColorRect
var _password_gate: PanelContainer
var _password_input: LineEdit
var _password_error: Label
var _main_panel: PanelContainer
var _tab_container: TabContainer
var _module_list: VBoxContainer
var _log_view: RichTextLabel
var _stats_view: RichTextLabel
var _close_button: Button
var _title_label: Label


func _ready() -> void:
	if not enabled:
		return
	
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	
	_build_ui()
	hide_all()
	
	if OS.is_debug_build() and password.is_empty():
		_unlocked = true
	
	var director = _get_director()
	if director and director.has_signal("dev_log_line"):
		director.dev_log_line.connect(_on_dev_log_line)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == hotkey:
			if (not require_ctrl or event.ctrl_pressed) and (not require_shift or event.shift_pressed):
				_toggle_panel()
				get_viewport().set_input_as_handled()


func hide_all() -> void:
	_visible = false
	_backdrop.visible = false
	_password_gate.visible = false
	_main_panel.visible = false


func _toggle_panel() -> void:
	if _visible and _main_panel.visible:
		hide_all()
		panel_closed.emit()
		return
	
	if not _unlocked and not password.is_empty():
		_show_password_gate()
	else:
		_show_main_panel()


func _show_password_gate() -> void:
	_visible = true
	_backdrop.visible = true
	_password_gate.visible = true
	_main_panel.visible = false
	_password_input.text = ""
	_password_error.visible = false
	_password_input.grab_focus()


func _show_main_panel() -> void:
	_visible = true
	_backdrop.visible = true
	_password_gate.visible = false
	_main_panel.visible = true
	_refresh_all()
	panel_opened.emit()


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.anchors_preset = Control.PRESET_FULL_RECT
	_backdrop.color = Color(0.05, 0.07, 0.12, 0.85)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	add_child(_backdrop)
	
	_password_gate = PanelContainer.new()
	_password_gate.name = "PasswordGate"
	_password_gate.anchors_preset = Control.PRESET_CENTER
	_password_gate.offset_left = -200
	_password_gate.offset_top = -80
	_password_gate.offset_right = 200
	_password_gate.offset_bottom = 80
	add_child(_password_gate)
	
	var gate_vbox = VBoxContainer.new()
	gate_vbox.add_theme_constant_override("separation", 10)
	_password_gate.add_child(gate_vbox)
	
	var gate_title = Label.new()
	gate_title.text = "DER AntiCheat - Developer Access"
	gate_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gate_vbox.add_child(gate_title)
	
	_password_input = LineEdit.new()
	_password_input.placeholder_text = "Enter developer password"
	_password_input.secret = true
	_password_input.text_submitted.connect(_on_password_submitted)
	gate_vbox.add_child(_password_input)
	
	_password_error = Label.new()
	_password_error.text = "Incorrect password"
	_password_error.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	_password_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_password_error.visible = false
	gate_vbox.add_child(_password_error)
	
	var gate_buttons = HBoxContainer.new()
	gate_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	gate_vbox.add_child(gate_buttons)
	
	var unlock_btn = Button.new()
	unlock_btn.text = "Unlock"
	unlock_btn.pressed.connect(func(): _on_password_submitted(_password_input.text))
	gate_buttons.add_child(unlock_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(hide_all)
	gate_buttons.add_child(cancel_btn)
	
	_main_panel = PanelContainer.new()
	_main_panel.name = "MainPanel"
	_main_panel.anchors_preset = Control.PRESET_FULL_RECT
	_main_panel.offset_left = 40
	_main_panel.offset_top = 40
	_main_panel.offset_right = -40
	_main_panel.offset_bottom = -60
	add_child(_main_panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_main_panel.add_child(main_vbox)
	
	var header = HBoxContainer.new()
	main_vbox.add_child(header)
	
	_title_label = Label.new()
	_title_label.text = "DER AntiCheat - In-Game Panel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): hide_all(); panel_closed.emit())
	header.add_child(_close_button)
	
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_tab_container)
	
	var modules_tab = ScrollContainer.new()
	modules_tab.name = "Modules"
	_tab_container.add_child(modules_tab)
	
	_module_list = VBoxContainer.new()
	_module_list.add_theme_constant_override("separation", 4)
	modules_tab.add_child(_module_list)
	
	var log_tab = ScrollContainer.new()
	log_tab.name = "Log"
	_tab_container.add_child(log_tab)
	
	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_tab.add_child(_log_view)
	
	var stats_tab = ScrollContainer.new()
	stats_tab.name = "Stats"
	_tab_container.add_child(stats_tab)
	
	_stats_view = RichTextLabel.new()
	_stats_view.bbcode_enabled = true
	_stats_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_tab.add_child(_stats_view)


func _on_password_submitted(input_text: String) -> void:
	if input_text == password:
		_unlocked = true
		_show_main_panel()
	else:
		_password_error.visible = true
		_password_input.text = ""


func _on_backdrop_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_all()
		panel_closed.emit()


func _on_dev_log_line(text: String) -> void:
	_log_buffer.append(text)
	while _log_buffer.size() > max_log_lines:
		_log_buffer.pop_front()
	
	if _main_panel.visible:
		_render_log()


func _refresh_all() -> void:
	_collect_modules()
	_render_modules()
	_render_log()
	_render_stats()


func _collect_modules() -> void:
	_modules.clear()
	var director = _get_director()
	if not director:
		return
	
	for property_name in director.get_property_list():
		var prop = property_name.name
		if prop.begins_with("_detector_") or prop.begins_with("detector_") or prop.ends_with("_detector"):
			var module = director.get(prop)
			if module and module.has_method("get_details"):
				_modules[prop] = module


func _render_modules() -> void:
	for child in _module_list.get_children():
		child.queue_free()
	
	if _modules.is_empty():
		var label = Label.new()
		label.text = "No modules detected. Ensure DER AntiCheat is running."
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_module_list.add_child(label)
		return
	
	for module_name in _modules:
		var module = _modules[module_name]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		
		var status_indicator = ColorRect.new()
		status_indicator.custom_minimum_size = Vector2(14, 14)
		var details = module.get_details() if module.has_method("get_details") else {}
		var is_active = details.get("enabled", false)
		var has_threat = details.get("is_hacked", false) or details.get("is_fake", false)
		if has_threat:
			status_indicator.color = Color(0.9, 0.2, 0.2)
		elif is_active:
			status_indicator.color = Color(0.2, 0.8, 0.2)
		else:
			status_indicator.color = Color(0.4, 0.4, 0.4)
		row.add_child(status_indicator)
		
		var name_label = Label.new()
		name_label.text = module_name.replace("_", " ").capitalize()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		
		var toggle_btn = Button.new()
		toggle_btn.text = "Disable" if is_active else "Enable"
		toggle_btn.custom_minimum_size = Vector2(70, 28)
		toggle_btn.pressed.connect(func():
			var mod = _modules[module_name]
			if mod and mod.has_method("set_enabled"):
				mod.set_enabled(not mod.get_details().get("enabled", false))
				_refresh_all()
				module_toggled.emit(module_name, mod.get_details().get("enabled", false))
		)
		row.add_child(toggle_btn)
		
		_module_list.add_child(row)


func _render_log() -> void:
	_log_view.clear()
	for line in _log_buffer:
		_log_view.append_text(line + "\n")


func _render_stats() -> void:
	var director = _get_director()
	if not director:
		_stats_view.text = "Director not available."
		return
	
	var stats_text = "[b]DER AntiCheat Runtime Stats[/b]\n\n"
	stats_text += "FPS: %d\n" % Engine.get_frames_per_second()
	stats_text += "Memory: %.1f MB\n" % (OS.get_static_memory_usage() / 1048576.0)
	stats_text += "Process ID: %d\n" % OS.get_process_id()
	stats_text += "Debug Build: %s\n" % ("Yes" if OS.is_debug_build() else "No")
	stats_text += "Time: %s\n" % Time.get_datetime_string_from_system(false, true)
	
	if director.has_method("get_stats"):
		var stats = director.get_stats()
		stats_text += "\n[b]Module Stats:[/b]\n"
		for key in stats:
			stats_text += "  %s: %s\n" % [key, stats[key]]
	
	_stats_view.text = stats_text


func _get_director():
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.has_method("root"):
		var root = main_loop.root
		if root.has_node("AntiCheat"):
			return root.get_node("AntiCheat")
	return null


static func quick_create(password: String = "") -> DERInGamePanel:
	var panel = DERInGamePanel.new()
	panel.password = password
	return panel