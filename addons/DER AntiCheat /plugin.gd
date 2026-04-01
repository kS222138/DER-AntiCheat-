@tool
extends EditorPlugin

var core
var pool
var logger
var detector
var file_validator
var archive_manager
var debug_detector
var rollback_detector
var save_limit
var cloud_validator
var alert_manager
var report_exporter
var dashboard
var stats_chart
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
	_init_rollback_detector()
	_init_save_limit()
	_init_cloud_validator()
	_init_report_system()
	
	_add_critical_files()
	_create_dock()
	
	add_tool_menu_item("🛡️ Control Panel / 控制面板", Callable(self, "_open_panel"))
	add_tool_menu_item("⚡ Quick Scan / 快速扫描", Callable(self, "_quick_scan"))
	add_tool_menu_item("📁 Verify Files / 验证文件", Callable(self, "_verify_files"))
	add_tool_menu_item("🔐 Archive / 存档", Callable(self, "_open_archive"))
	add_tool_menu_item("⏱️ SL Protection / SL防护", Callable(self, "_open_sl_protection"))
	add_tool_menu_item("☁️ Cloud / 云存档", Callable(self, "_open_cloud_validator"))
	add_tool_menu_item("📊 Statistics / 统计", Callable(self, "_show_stats"))
	add_tool_menu_item("📈 Export Report / 导出报告", Callable(self, "_export_report"))
	
	logger.info("plugin", "DER AntiCheat v1.8.0 loaded")
	
	print("\n🛡️ =======================================")
	print("🛡️  DER AntiCheat v1.8.0 已启用 / Enabled")
	print("🛡️  报告系统 / Report System - 手动扫描 / Manual Scan Only")
	print("🛡️  状态 / Status: 🟢 运行中 / Running")
	print("🛡️  检测器 / Detectors: 11个已加载 / Loaded")
	print("🛡️  安全模块 / Security Modules: 10个已加载 / Loaded")
	print("🛡️ =======================================\n")

func _exit_tree():
	remove_tool_menu_item("🛡️ Control Panel / 控制面板")
	remove_tool_menu_item("⚡ Quick Scan / 快速扫描")
	remove_tool_menu_item("📁 Verify Files / 验证文件")
	remove_tool_menu_item("🔐 Archive / 存档")
	remove_tool_menu_item("⏱️ SL Protection / SL防护")
	remove_tool_menu_item("☁️ Cloud / 云存档")
	remove_tool_menu_item("📊 Statistics / 统计")
	remove_tool_menu_item("📈 Export Report / 导出报告")
	
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
	
	print("\n🛡️  DER AntiCheat v1.8.0 已禁用 / Disabled\n")

func _init_logger():
	var script = preload("report/logger.gd")
	logger = script.new()

func _init_core():
	core = preload("core/vanguard_core.gd").new()

func _init_pool():
	var script = preload("core/pool.gd")
	pool = script.new(logger)

func _init_detector():
	var script = preload("detection/detector.gd")
	detector = script.new(logger)
	pool.set_detector(detector)

func _init_file_validator():
	var script = preload("security/file_validator.gd")
	file_validator = script.new()
	file_validator.hash_type = 2
	file_validator.auto_verify = false

func _init_archive_manager():
	var script = preload("security/archive_manager.gd")
	archive_manager = script.new()
	archive_manager.max_slots = 10
	archive_manager.auto_save = false

func _init_debug_detector():
	var script = preload("detection_v2/debug_detector_v2.gd")
	debug_detector = script.new()
	debug_detector.level = 2
	debug_detector.auto_quit = false
	debug_detector.verbose = true

func _init_rollback_detector():
	var script = preload("security/rollback_detector.gd")
	rollback_detector = script.new()
	rollback_detector.enable_timestamp_check = true
	rollback_detector.enable_version_check = true

func _init_save_limit():
	var script = preload("security/save_limit.gd")
	save_limit = script.new()
	save_limit.max_saves_per_minute = 10
	save_limit.max_loads_per_minute = 10
	save_limit.cooldown_seconds = 2.0

func _init_cloud_validator():
	var script = preload("security/cloud_validator.gd")
	cloud_validator = script.new()
	cloud_validator.mode = 1
	cloud_validator.check_interval = 60.0
	cloud_validator.auto_repair = false
	cloud_validator.timeout = 5.0

func _init_report_system():
	var alert_script = preload("report_v2/alert_manager.gd")
	alert_manager = alert_script.new()
	
	var chart_script = preload("report_v2/stats_chart.gd")
	stats_chart = chart_script.new()
	
	var exporter_script = preload("report_v2/report_exporter.gd")
	report_exporter = exporter_script.new()
	report_exporter.set_data_source(self)
	report_exporter.export_completed.connect(_on_export_done)

func _add_critical_files():
	var files = [
		"res://addons/DER AntiCheat /plugin.gd",
		"res://addons/DER AntiCheat /core/value.gd",
		"res://addons/DER AntiCheat /detection/process_monitor.gd",
		"res://addons/DER AntiCheat /security/file_validator.gd",
		"res://addons/DER AntiCheat /security/archive_manager.gd",
		"res://addons/DER AntiCheat /security/rollback_detector.gd",
		"res://addons/DER AntiCheat /security/save_limit.gd"
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
	title.text = "🛡️ DER AntiCheat v1.8.0"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	vbox.add_child(title)
	
	var version = Label.new()
	version.text = "Report System / 报告系统 | Manual Scan / 手动扫描"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(version)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)
	
	status_label = Label.new()
	status_label.text = "Status / 状态: 🟢 Ready / 就绪"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)
	
	var grid = GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)
	
	_add_stat_row(grid, "Protected / 受保护值:", "0", "values")
	_add_stat_row(grid, "Threats / 检测威胁:", "0", "threats")
	_add_stat_row(grid, "Critical / 严重告警:", "0", "critical")
	_add_stat_row(grid, "Files / 文件校验:", "0", "files")
	_add_stat_row(grid, "Anti-Debug / 反调试:", "0", "debug")
	_add_stat_row(grid, "Rollback / 回滚检测:", "0", "rollback")
	_add_stat_row(grid, "SL Limit / SL限制:", "0", "savelimit")
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)
	
	var scan_btn = Button.new()
	scan_btn.text = "⚡ Quick Scan / 快速扫描"
	scan_btn.pressed.connect(_quick_scan)
	vbox.add_child(scan_btn)
	
	var verify_btn = Button.new()
	verify_btn.text = "📁 Verify Files / 验证文件"
	verify_btn.pressed.connect(_verify_files)
	vbox.add_child(verify_btn)
	
	var export_btn = Button.new()
	export_btn.text = "📈 Export Report / 导出报告"
	export_btn.pressed.connect(_export_report)
	vbox.add_child(export_btn)
	
	var panel_btn = Button.new()
	panel_btn.text = "📊 Control Panel / 控制面板"
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

func _quick_scan():
	logger.info("plugin", "Starting security scan / 开始安全扫描")
	
	print("\n🔍 ========= Security Scan / 安全扫描 =========")
	var total_risk = 0.0
	var threats_found = []
	
	if detector:
		var scan_results = detector.scan_all()
		for result in scan_results.values():
			threats_found.append(result)
			total_risk += result.risk
			print("  [DETECTED] ", result.type, " - Risk: ", result.risk)
	
	if file_validator:
		var file_results = file_validator.verify_all()
		var corrupted = 0
		for ok in file_results.values():
			if not ok:
				corrupted += 1
		if corrupted > 0:
			total_risk += 0.8
			print("  [DETECTED] File Integrity / 文件完整性 - ", corrupted, " files corrupted / 文件损坏")
	
	if debug_detector and debug_detector.is_detected():
		total_risk += 1.0
		print("  [DETECTED] Debugger Detected / 检测到调试器")
	
	if rollback_detector and rollback_detector.is_suspicious(0):
		total_risk += 0.9
		print("  [DETECTED] Rollback Detected / 检测到存档回滚")
	
	if save_limit and save_limit.get_save_count(0, 60) > 20:
		total_risk += 0.7
		print("  [DETECTED] Save Spam Detected / 检测到保存刷屏")
	
	print("==============================================")
	print("  Total Risk / 总风险: ", total_risk)
	
	if total_risk > 2.0:
		print("  Result / 结果: 🔴 HIGH RISK / 高风险")
		status_label.text = "Status / 状态: 🔴 High Risk / 高风险"
		logger.warning("plugin", "High risk scan results / 高风险扫描结果")
	elif total_risk > 0.5:
		print("  Result / 结果: 🟡 MEDIUM RISK / 中风险")
		status_label.text = "Status / 状态: 🟡 Medium Risk / 中风险"
		logger.warning("plugin", "Medium risk scan results / 中风险扫描结果")
	else:
		print("  Result / 结果: 🟢 SAFE / 安全")
		status_label.text = "Status / 状态: 🟢 Ready / 就绪"
		logger.info("plugin", "Scan complete - Safe / 扫描完成 - 安全")
	
	print("==============================================\n")
	_update_stats()

func _verify_files():
	logger.info("plugin", "Verifying game files / 验证游戏文件")
	
	if not file_validator:
		return
	
	print("\n📁 ========= File Integrity Check / 文件完整性校验 =========")
	var results = file_validator.verify_all()
	var passed = 0
	var failed = 0
	
	for ok in results.values():
		if ok:
			passed += 1
		else:
			failed += 1
	
	print("  Total files / 总文件数: ", passed + failed)
	print("  Passed / 通过: ", passed)
	print("  Failed / 失败: ", failed)
	
	if failed > 0:
		print("\n  ⚠️ Tampered files / 被篡改文件:")
		for file in results:
			if not results[file]:
				print("    - ", file)
	
	print("========================================================\n")
	_update_stats()

func _open_archive():
	print("\n🔐 ========= Archive Manager / 存档管理器 =========")
	print("  Features / 功能:")
	print("    - AES-256-GCM encryption / AES-256-GCM加密")
	print("    - Multi-slot management / 多槽位管理")
	print("    - Auto-save / 自动保存")
	print("    - Import/Export / 导入/导出")
	print("\n  Usage / 使用:")
	print("    var am = DERArchiveManager.new(\"password\")")
	print("    am.save(0, game_data)")
	print("    var data = am.load(0)")
	print("==================================================\n")

func _open_sl_protection():
	print("\n⏱️ ========= SL Protection Settings / SL防护设置 =========")
	print("  Detection Modes / 检测模式:")
	print("    - Save rollback detection / 存档回滚检测")
	print("    - Save frequency limit / 保存频率限制")
	print("    - Load frequency limit / 加载频率限制")
	print("\n  Current Settings / 当前设置:")
	print("    Max saves per minute: ", save_limit.max_saves_per_minute)
	print("    Max loads per minute: ", save_limit.max_loads_per_minute)
	print("    Cooldown: ", save_limit.cooldown_seconds, "s")
	print("\n  Usage / 使用:")
	print("    save_limit.max_saves_per_minute = 5")
	print("    save_limit.cheat_attempt_detected.connect(_on_cheat)")
	print("======================================================\n")

func _open_cloud_validator():
	print("\n☁️ ========= Cloud Validator / 云存档校验 =========")
	print("  Features / 功能:")
	print("    - Client-cloud hash comparison / 客户端云端哈希比对")
	print("    - Offline mode / 离线模式")
	print("    - Retry mechanism / 重试机制")
	print("\n  Usage / 使用:")
	print("    var cloud = DERCloudValidator.new(\"https://api.server.com\", \"player_id\")")
	print("    cloud.validate(slot, save_data, func(success):")
	print("        if not success: print('Save tampered!')")
	print("    )")
	print("==================================================\n")

func _export_report():
	if report_exporter:
		report_exporter.export_report("html")
		print("📈 Exporting report / 导出报告中...")

func _on_export_done(path, format):
	print("📈 Report exported / 报告已导出: ", path)

func _open_panel():
	var stats = VanguardCore.get_stats()
	var threats = VanguardCore.get_threat_log()
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	var rollback_stats = rollback_detector.get_stats() if rollback_detector else {}
	var save_stats = save_limit.get_stats() if save_limit else {}
	
	print("\n🛡️ ========= Vanguard Control Panel v1.8.0 ==========")
	print("\n📊 Core Statistics / 核心统计")
	print("  Protected Values / 受保护值: ", stats.values_protected)
	print("  Total Threats / 总威胁: ", stats.total_threats)
	print("  Critical Threats / 严重威胁: ", stats.critical_threats)
	print("\n🔐 Security Modules / 安全模块")
	print("  File Verification / 文件校验: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
	print("  Anti-Debug Triggers / 反调试触发: ", debug_count)
	print("  Rollback Detection / 回滚检测: ", rollback_stats.get("active_slots", 0))
	print("  SL Limit / SL限制: ", save_stats.get("total_saves", 0))
	print("\n📁 Recent Threats / 最近威胁:")
	if threats.size() > 0:
		for t in threats.slice(-5):
			print("  [%s] %s" % [t.level, t.type])
	else:
		print("  None / 无")
	print("\n🛡️ ==================================================\n")
	_update_stats()

func _show_stats():
	var stats = VanguardCore.get_stats()
	var logs = logger.export() if logger else {}
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	var rollback_stats = rollback_detector.get_stats() if rollback_detector else {}
	var save_stats = save_limit.get_stats() if save_limit else {}
	
	print("\n📊 ========= Protection Statistics ==========")
	print("Runtime / 运行时间: ", Time.get_datetime_string_from_system())
	print("Plugin Version / 插件版本: 1.8.0")
	print("\nCore Protection / 核心保护:")
	print("  Protected Values / 受保护值: ", stats.values_protected)
	print("  Total Threats / 总威胁: ", stats.total_threats)
	print("  Critical Threats / 严重威胁: ", stats.critical_threats)
	print("\nSecurity Enhancement / 安全增强:")
	print("  File Verification / 文件校验: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
	print("  Corrupted Files / 损坏文件: ", file_stats.get("corrupted", 0))
	print("  Anti-Debug Triggers / 反调试触发: ", debug_count)
	print("  Rollback Detection / 回滚检测: ", rollback_stats.get("active_slots", 0))
	print("  Total Saves / 总保存: ", save_stats.get("total_saves", 0))
	print("  Total Loads / 总加载: ", save_stats.get("total_loads", 0))
	print("\nLog Statistics / 日志统计:")
	print("  Total Logs / 总日志: ", logs.get("total", 0))
	print("  Warnings / 警告: ", logs.get("by_level", {}).get("warning", 0))
	print("  Errors / 错误: ", logs.get("by_level", {}).get("error", 0))
	print("============================================\n")

func _update_stats():
	var stats = VanguardCore.get_stats()
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	var rollback_stats = rollback_detector.get_stats() if rollback_detector else {}
	var save_stats = save_limit.get_stats() if save_limit else {}
	
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
	if stats_labels.has("rollback"):
		stats_labels.rollback.text = str(rollback_stats.get("active_slots", 0))
	if stats_labels.has("savelimit"):
		stats_labels.savelimit.text = str(save_stats.get("total_saves", 0))

func get_plugin_name():
	return "DER AntiCheat v1.8.0"