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
	_init_rollback_detector()
	_init_save_limit()
	_init_cloud_validator()
	
	_add_critical_files()
	_create_dock()
	
	add_tool_menu_item("🛡️ Vanguard Control Panel / 控制面板", Callable(self, "_open_panel"))
	add_tool_menu_item("⚡ Quick Security Scan / 快速安全扫描", Callable(self, "_quick_scan"))
	add_tool_menu_item("📁 Verify Game Files / 验证游戏文件", Callable(self, "_verify_files"))
	add_tool_menu_item("🔐 Archive Manager / 存档管理器", Callable(self, "_open_archive"))
	add_tool_menu_item("⏱️ SL Protection / SL防护", Callable(self, "_open_sl_protection"))
	add_tool_menu_item("☁️ Cloud Validator / 云存档校验", Callable(self, "_open_cloud_validator"))
	add_tool_menu_item("📊 View Statistics / 查看统计", Callable(self, "_show_stats"))
	
	logger.info("plugin", "DER AntiCheat v1.7.0 loaded")
	
	print("\n🛡️ =======================================")
	print("🛡️  DER AntiCheat v1.7.0 已启用 / Enabled")
	print("🛡️  游戏专属版 / Game Edition - SL防护 + 云存档校验 / SL Protection + Cloud Validation")
	print("🛡️  状态 / Status: 🟢 运行中 / Running")
	print("🛡️  检测器 / Detectors: 11个已加载 / Loaded")
	print("🛡️  安全模块 / Security Modules: 7个已加载 / Loaded")
	print("🛡️ =======================================\n")

func _exit_tree():
	remove_tool_menu_item("🛡️ Vanguard Control Panel / 控制面板")
	remove_tool_menu_item("⚡ Quick Security Scan / 快速安全扫描")
	remove_tool_menu_item("📁 Verify Game Files / 验证游戏文件")
	remove_tool_menu_item("🔐 Archive Manager / 存档管理器")
	remove_tool_menu_item("⏱️ SL Protection / SL防护")
	remove_tool_menu_item("☁️ Cloud Validator / 云存档校验")
	remove_tool_menu_item("📊 View Statistics / 查看统计")
	
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
	
	print("\n🛡️  DER AntiCheat v1.7.0 已禁用 / Disabled\n")

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

func _init_rollback_detector():
	var rd_script = preload("security/rollback_detector.gd")
	rollback_detector = rd_script.new()
	rollback_detector.enable_timestamp_check = true
	rollback_detector.enable_version_check = true
	rollback_detector.alert_on_rollback = true

func _init_save_limit():
	var sl_script = preload("security/save_limit.gd")
	save_limit = sl_script.new()
	save_limit.max_saves_per_minute = 10
	save_limit.max_loads_per_minute = 10
	save_limit.max_saves_per_hour = 50
	save_limit.max_loads_per_hour = 50
	save_limit.cooldown_seconds = 2.0

func _init_cloud_validator():
	var cv_script = preload("security/cloud_validator.gd")
	cloud_validator = cv_script.new()
	cloud_validator.mode = 1
	cloud_validator.check_interval = 60.0
	cloud_validator.auto_repair = false
	cloud_validator.timeout = 5.0
	cloud_validator.max_retries = 3

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
	title.text = "🛡️ DER AntiCheat v1.7.0"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	vbox.add_child(title)
	
	var version = Label.new()
	version.text = "游戏专属版 / Game Edition | SL防护 / SL Protection | 云存档校验 / Cloud Validation"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(version)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)
	
	status_label = Label.new()
	status_label.text = "状态 / Status: 🟢 运行中 / Running"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)
	
	var grid = GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)
	
	_add_stat_row(grid, "受保护值 / Protected Values:", "0", "values")
	_add_stat_row(grid, "检测威胁 / Threats Detected:", "0", "threats")
	_add_stat_row(grid, "严重告警 / Critical Alerts:", "0", "critical")
	_add_stat_row(grid, "文件校验 / Files Verified:", "0", "files")
	_add_stat_row(grid, "反调试触发 / Anti-Debug Triggers:", "0", "debug")
	_add_stat_row(grid, "回滚检测 / Rollback Detected:", "0", "rollback")
	_add_stat_row(grid, "SL限制 / SL Limit:", "0", "savelimit")
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)
	
	var scan_btn = Button.new()
	scan_btn.text = "⚡ 立即安全扫描 / Quick Security Scan"
	scan_btn.pressed.connect(_quick_scan)
	vbox.add_child(scan_btn)
	
	var verify_btn = Button.new()
	verify_btn.text = "📁 验证游戏文件 / Verify Game Files"
	verify_btn.pressed.connect(_verify_files)
	vbox.add_child(verify_btn)
	
	var archive_btn = Button.new()
	archive_btn.text = "🔐 存档管理器 / Archive Manager"
	archive_btn.pressed.connect(_open_archive)
	vbox.add_child(archive_btn)
	
	var sl_btn = Button.new()
	sl_btn.text = "⏱️ SL防护设置 / SL Protection Settings"
	sl_btn.pressed.connect(_open_sl_protection)
	vbox.add_child(sl_btn)
	
	var cloud_btn = Button.new()
	cloud_btn.text = "☁️ 云存档校验 / Cloud Validator"
	cloud_btn.pressed.connect(_open_cloud_validator)
	vbox.add_child(cloud_btn)
	
	var panel_btn = Button.new()
	panel_btn.text = "📊 控制面板 / Control Panel"
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
		status_label.text = "状态 / Status: ⚠️ 检测到威胁 / Threat Detected"
		logger.warning("plugin", "自动扫描发现威胁 / Auto-scan found threats")
	else:
		status_label.text = "状态 / Status: 🟢 运行中 / Running"
	
	_update_stats()

func _quick_scan():
	logger.info("plugin", "开始安全扫描 / Starting security scan")
	
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
	
	if rollback_detector and rollback_detector.is_suspicious(0):
		results["rollback"] = {"risk": 0.9}
		total_risk += 0.9
	
	if save_limit and save_limit.get_save_count(0, 60) > 20:
		results["save_spam"] = {"risk": 0.7}
		total_risk += 0.7
	
	if total_risk > 2.0:
		logger.warning("plugin", "高风险扫描结果 / High risk scan results")
		status_label.text = "状态 / Status: 🔴 高风险 / High Risk"
	elif total_risk > 0.5:
		logger.warning("plugin", "中风险扫描结果 / Medium risk scan results")
		status_label.text = "状态 / Status: 🟡 中风险 / Medium Risk"
	else:
		logger.info("plugin", "扫描完成 - 安全 / Scan complete - Safe")
		status_label.text = "状态 / Status: 🟢 运行中 / Running"
	
	_update_stats()

func _verify_files():
	logger.info("plugin", "开始验证游戏文件 / Starting file verification")
	
	if not file_validator:
		logger.error("plugin", "文件验证器未初始化 / File validator not initialized")
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
	
	print("\n📁 文件完整性校验结果 / File Integrity Results")
	print("================================")
	print("总文件数 / Total files: ", total)
	print("通过 / Passed: ", passed)
	print("失败 / Failed: ", failed)
	
	if failed > 0:
		print("\n⚠️ 以下文件可能被篡改 / Following files may be tampered:")
		for file in results:
			if not results[file]:
				print("  - ", file)
	
	logger.info("plugin", "文件校验完成 / File verification complete: %d/%d 通过 / passed" % [passed, total])
	_update_stats()

func _open_archive():
	logger.info("plugin", "打开存档管理器 / Opening archive manager")
	
	print("\n🔐 存档管理器 / Archive Manager (v1.7.0)")
	print("================================")
	print("支持功能 / Features:")
	print("  - AES-256-GCM 加密 / Encryption")
	print("  - 多槽位管理 / Multi-slot management (最多10个 / max 10)")
	print("  - 自动保存/导入/导出 / Auto-save/import/export")
	print("  - 防篡改校验 / Anti-tamper verification")
	print("")
	print("使用示例 / Usage Example:")
	print("  var am = DERArchiveManager.new(\"your_password\")")
	print("  am.save(0, game_data)")
	print("  var data = am.load(0)")
	print("================================")

func _open_sl_protection():
	logger.info("plugin", "打开SL防护设置 / Opening SL protection settings")
	
	print("\n⏱️ SL防护设置 / SL Protection Settings (v1.7.0)")
	print("================================")
	print("检测模式 / Detection Modes:")
	print("  - 存档回滚检测 / Save rollback detection: 检测时间倒退 / Detect time reversal")
	print("  - 保存频率限制 / Save frequency limit: 防止疯狂SL / Prevent excessive saving")
	print("  - 加载频率限制 / Load frequency limit: 防止反复读档 / Prevent excessive loading")
	print("")
	print("当前设置 / Current Settings:")
	print("  每分钟最多保存 / Max saves per minute: ", save_limit.max_saves_per_minute)
	print("  每分钟最多加载 / Max loads per minute: ", save_limit.max_loads_per_minute)
	print("  每小时最多保存 / Max saves per hour: ", save_limit.max_saves_per_hour)
	print("  每小时最多加载 / Max loads per hour: ", save_limit.max_loads_per_hour)
	print("  操作冷却 / Operation cooldown: ", save_limit.cooldown_seconds, "秒 / seconds")
	print("")
	print("使用示例 / Usage Example:")
	print("  save_limit.max_saves_per_minute = 5")
	print("  save_limit.set_cooldown(3.0)")
	print("  save_limit.cheat_attempt_detected.connect(_on_cheat)")
	print("================================")

func _open_cloud_validator():
	logger.info("plugin", "打开云存档校验 / Opening cloud validator")
	
	print("\n☁️ 云存档校验 / Cloud Validator (v1.7.0)")
	print("================================")
	print("功能 / Features:")
	print("  - 客户端与云端哈希比对 / Client-cloud hash comparison")
	print("  - 冲突检测与自动修复(可选) / Conflict detection with optional auto-repair")
	print("  - 离线模式支持 / Offline mode support")
	print("  - 重试机制 / Retry mechanism")
	print("")
	print("使用示例 / Usage Example:")
	print("  var cloud = DERCloudValidator.new(\"https://api.yourserver.com\", \"player_id\")")
	print("  cloud.validate(slot, save_data, func(success):")
	print("      if not success: print('存档被篡改! / Save tampered!')")
	print("  )")
	print("================================")

func _open_panel():
	var stats = VanguardCore.get_stats()
	var threats = VanguardCore.get_threat_log()
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	var rollback_suspicious = rollback_detector.get_stats() if rollback_detector else {}
	var save_stats = save_limit.get_stats() if save_limit else {}
	
	print("\n🛡️ ========= Vanguard Control Panel v1.7.0 ==========")
	print("")
	print("📊 核心统计 / Core Statistics")
	print("  受保护值 / Protected Values: ", stats.values_protected)
	print("  总威胁数 / Total Threats: ", stats.total_threats)
	print("  严重威胁 / Critical Threats: ", stats.critical_threats)
	print("")
	print("🔐 安全模块 / Security Modules")
	print("  文件校验 / File Verification: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
	print("  反调试触发 / Anti-Debug Triggers: ", debug_count)
	print("  回滚检测 / Rollback Detection: ", rollback_suspicious.get("active_slots", 0), " 个活跃槽位 / active slots")
	print("  SL限制 / SL Limit: ", save_stats.get("total_saves", 0), " 次保存 / saves")
	print("")
	print("📁 最近威胁 / Recent Threats:")
	if threats.size() > 0:
		for t in threats.slice(-5):
			print("  [%s] %s" % [t.level, t.type])
	else:
		print("  无 / None")
	print("")
	print("🛡️ ==================================================\n")
	
	_update_stats()

func _show_stats():
	var stats = VanguardCore.get_stats()
	var logs = logger.export() if logger else {}
	var file_stats = file_validator.get_stats() if file_validator else {}
	var debug_count = debug_detector.get_count() if debug_detector else 0
	var rollback_stats = rollback_detector.get_stats() if rollback_detector else {}
	var save_stats = save_limit.get_stats() if save_limit else {}
	
	print("\n📊 ========= Protection Statistics ==========")
	print("运行时间 / Runtime: ", Time.get_datetime_string_from_system())
	print("插件版本 / Plugin Version: 1.7.0")
	print("")
	print("核心保护 / Core Protection:")
	print("  受保护值 / Protected Values: ", stats.values_protected)
	print("  总威胁 / Total Threats: ", stats.total_threats)
	print("  严重威胁 / Critical Threats: ", stats.critical_threats)
	print("")
	print("安全增强 / Security Enhancement:")
	print("  文件校验 / File Verification: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
	print("  损坏文件 / Corrupted Files: ", file_stats.get("corrupted", 0))
	print("  反调试触发 / Anti-Debug Triggers: ", debug_count)
	print("  回滚检测 / Rollback Detection: ", rollback_stats.get("active_slots", 0), " 个槽位 / slots")
	print("  总保存次数 / Total Saves: ", save_stats.get("total_saves", 0))
	print("  总加载次数 / Total Loads: ", save_stats.get("total_loads", 0))
	print("")
	print("日志统计 / Log Statistics:")
	print("  总日志 / Total Logs: ", logs.get("total", 0))
	print("  警告 / Warnings: ", logs.get("by_level", {}).get("warning", 0))
	print("  错误 / Errors: ", logs.get("by_level", {}).get("error", 0))
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
	return "DER AntiCheat v1.7.0"