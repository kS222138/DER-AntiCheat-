@tool
extends EditorPlugin

var core
var pool
var logger
var detector
var file_validator
var archive_manager
var debug_detector
var scan_timer = 0
var dock
var status_label
var stats_labels = {}

func _enter_tree():
	_init_logger()
	_init_core()
	_init_pool()
	_init_detector()
	_init_file_validator()
	_init_archive_manager()
	_init_debug_detector()
	
	_add_critical_files()
	_create_dock()
	
	add_tool_menu_item("🛡️ Vanguard Control Panel", Callable(self, "_open_panel"))
	add_tool_menu_item("⚡ Quick Security Scan", Callable(self, "_quick_scan"))
	add_tool_menu_item("📁 Verify Game Files", Callable(self, "_verify_files"))
	add_tool_menu_item("🔐 Archive Manager", Callable(self, "_open_archive"))
	add_tool_menu_item("📊 View Statistics", Callable(self, "_show_stats"))
	
	logger.info("plugin", "DER AntiCheat v1.6.0 loaded")
	
	print("\n🛡️ =======================================")
	print("🛡️  DER AntiCheat v1.6.0 已启用")
	print("🛡️  安全增强版 - 存档加密 + 文件校验 + 反调试")
	print("🛡️  状态: 🟢 运行中")
	print("🛡️  检测器: 11个已加载")
	print("🛡️  安全模块: 4个已加载")
	print("🛡️ =======================================\n")

func _exit_tree():
	remove_tool_menu_item("🛡️ Vanguard Control Panel")
	remove_tool_menu_item("⚡ Quick Security Scan")
	remove_tool_menu_item("📁 Verify Game Files")
	remove_tool_menu_item("🔐 Archive Manager")
	remove_tool_menu_item("📊 View Statistics")
	
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
	
	print("\n🛡️  DER AntiCheat v1.6.0 已禁用\n")

func _process(delta):
	scan_timer += delta
	if scan_timer > 5.0:
		scan_timer = 0
		_auto_scan()

func _init_logger():
	var logger_script = preload("report/logger.gd")
	logger = logger_script.new()

func _init_core():
	core = preload("core/vanguard_core.gd").new()

func _init_pool():
	var pool_script = preload("core/pool.gd")
	pool = pool_script.new(logger)

func _init_detector():
	var detector_script = preload("detection/detector.gd")
	detector = detector_script.new(logger)
	pool.set_detector(detector)

func _init_file_validator():
	var fv_script = preload("security/file_validator.gd")
	file_validator = fv_script.new()
	file_validator.hash_type = 2
	file_validator.auto_verify = false

func _init_archive_manager():
	var am_script = preload("security/archive_manager.gd")
	archive_manager = am_script.new()
	archive_manager.max_slots = 10
	archive_manager.auto_save = false

func _init_debug_detector():
	var dd_script = preload("detection_v2/debug_detector_v2.gd")
	debug_detector = dd_script.new()
	debug_detector.level = 2
	debug_detector.auto_quit = false
	debug_detector.verbose = true

func _add_critical_files():
	var files = [
		"res://addons/DER AntiCheat /plugin.gd",
		"res://addons/DER AntiCheat /core/value.gd",
		"res://addons/DER AntiCheat /detection/process_monitor.gd",
		"res://addons/DER AntiCheat /security/file_validator.gd",
		"res://addons/DER AntiCheat /security/archive_manager.gd"
	]
	for file in files:
		if detector and detector.has_method("add_critical_file"):
			detector.add_critical_file(file)
			
func _create_dock():
	dock = Control.new()
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.add_child(vbox)
	
	var title = Label.new()
	title.text = "🛡️ DER AntiCheat v1.6.0"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	vbox.add_child(title)
	
	var version = Label.new()
	version.text = "安全增强版 | 存档加密 | 文件校验 | 反调试"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(version)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)
	
	status_label = Label.new()
	status_label.text = "状态: 🟢 运行中"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)
	
	var grid = GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)
	
	_add_stat_row(grid, "受保护值:", "0", "values")
	_add_stat_row(grid, "检测威胁:", "0", "threats")
	_add_stat_row(grid, "严重告警:", "0", "critical")
	_add_stat_row(grid, "文件校验:", "0", "files")
	_add_stat_row(grid, "反调试触发:", "0", "debug")
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)
	
	var scan_btn = Button.new()
	scan_btn.text = "⚡ 立即安全扫描"
	scan_btn.pressed.connect(_quick_scan)
	vbox.add_child(scan_btn)
	
	var verify_btn = Button.new()
	verify_btn.text = "📁 验证游戏文件"
	verify_btn.pressed.connect(_verify_files)
	vbox.add_child(verify_btn)
	
	var archive_btn = Button.new()
	archive_btn.text = "🔐 存档管理器"
	archive_btn.pressed.connect(_open_archive)
	vbox.add_child(archive_btn)
	
	var panel_btn = Button.new()
	panel_btn.text = "📊 控制面板"
	panel_btn.pressed.connect(_open_panel)
	vbox.add_child(panel_btn)
	
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

func _add_stat_row(grid, label_text, default_value, key):
	var label = Label.new()
	label.text = label_text
	grid.add_child(label)
	
	var value = Label.new()
	value.text = default_value
	grid.add_child(value)
	stats_labels[key] = value

func _auto_scan():
	if not pool:
		return
	
	var threats = pool.scan_for_threats()
	var core_stats = VanguardCore.get_stats()
	
	if threats.size() > 0 or core_stats.critical_threats > 0:
		status_label.text = "状态: ⚠️ 检测到威胁"
		logger.warning("plugin", "自动扫描发现威胁")
	else:
		status_label.text = "状态: 🟢 运行中"
	
	_update_stats()

func _quick_scan():
	logger.info("plugin", "开始安全扫描")
	
	var results = {}
	var total_risk = 0.0
	
	if detector:
		var scan_results = detector.scan_all()
		for result in scan_results.values():
			results[result.type] = result
			total_risk += result.risk
	
	if file_validator:
		var file_results = file_validator.verify_all()
		var corrupted = 0
		for ok in file_results.values():
			if not ok:
				corrupted += 1
		if corrupted > 0:
			results["file_integrity"] = {"risk": 0.8, "count": corrupted}
			total_risk += 0.8
	
	if debug_detector and debug_detector.is_detected():
		results["debugger"] = {"risk": 1.0}
		total_risk += 1.0
	
	if total_risk > 2.0:
		logger.warning("plugin", "高风险扫描结果")
		status_label.text = "状态: 🔴 高风险"
	elif total_risk > 0.5:
		logger.warning("plugin", "中风险扫描结果")
		status_label.text = "状态: 🟡 中风险"
	else:
		logger.info("plugin", "扫描完成 - 安全")
		status_label.text = "状态: 🟢 运行中"
	
	_update_stats()

func _verify_files():
	logger.info("plugin", "开始验证游戏文件")
	
	if not file_validator:
		logger.error("plugin", "文件验证器未初始化")
		return
	
	var results = file_validator.verify_all()
	var total = results.size()
	var passed = 0
	var failed = 0
	
	for ok in results.values():
		if ok:
			passed += 1
		else:
			failed += 1
	
	print("\n📁 文件完整性校验结果")
	print("================================")
	print("总文件数: ", total)
	print("通过: ", passed)
	print("失败: ", failed)
	
	if failed > 0:
		print("\n⚠️ 以下文件可能被篡改:")
		for file in results:
			if not results[file]:
				print("  - ", file)
	
	logger.info("plugin", "文件校验完成: %d/%d 通过" % [passed, total])
	_update_stats()

func _open_archive():
	logger.info("plugin", "打开存档管理器")
	
	print("\n🔐 存档管理器 (v1.6.0)")
	print("================================")
	print("支持功能:")
	print("  - AES-256-GCM 加密")
	print("  - 多槽位管理 (最多10个)")
	print("  - 自动保存/导入/导出")
	print("  - 防篡改校验")
	print("")
	print("使用示例:")
	print("  var am = DERArchiveManager.new(\"your_password\")")
	print("  am.save(0, game_data)")
	print("  var data = am.load(0)")
	print("================================")

func _open_panel():
	var stats = VanguardCore.get_stats()
	var threats = VanguardCore.get_threat_log()
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	
	print("\n🛡️ ========= Vanguard Control Panel v1.6.0 ==========")
	print("")
	print("📊 核心统计")
	print("  受保护值: ", stats.values_protected)
	print("  总威胁数: ", stats.total_threats)
	print("  严重威胁: ", stats.critical_threats)
	print("")
	print("🔐 安全模块")
	print("  文件校验: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
	print("  反调试触发: ", debug_count)
	print("")
	print("📁 最近威胁:")
	if threats.size() > 0:
		for t in threats.slice(-5):
			print("  [%s] %s" % [t.level, t.type])
	else:
		print("  无")
	print("")
	print("🛡️ ==================================================\n")
	
	_update_stats()

func _show_stats():
	var stats = VanguardCore.get_stats()
	var logs = logger.export() if logger else {}
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	
	print("\n📊 ========= Protection Statistics ==========")
	print("运行时间: ", Time.get_datetime_string_from_system())
	print("插件版本: 1.6.0")
	print("")
	print("核心保护:")
	print("  受保护值: ", stats.values_protected)
	print("  总威胁: ", stats.total_threats)
	print("  严重威胁: ", stats.critical_threats)
	print("")
	print("安全增强:")
	print("  文件校验: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
	print("  损坏文件: ", file_stats.get("corrupted", 0))
	print("  反调试触发: ", debug_count)
	print("")
	print("日志统计:")
	print("  总日志: ", logs.get("total", 0))
	print("  警告: ", logs.get("by_level", {}).get("warning", 0))
	print("  错误: ", logs.get("by_level", {}).get("error", 0))
	print("============================================\n")

func _update_stats():
	var stats = VanguardCore.get_stats()
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	
	if stats_labels.has("values"):
		stats_labels.values.text = str(stats.values_protected)
	if stats_labels.has("threats"):
		stats_labels.threats.text = str(stats.total_threats)
	if stats_labels.has("critical"):
		stats_labels.critical.text = str(stats.critical_threats)
	if stats_labels.has("files"):
		stats_labels.files.text = str(file_stats.get("verified", 0))
	if stats_labels.has("debug"):
		stats_labels.debug.text = str(debug_count)

func get_plugin_name():
	return "DER AntiCheat v1.6.0"