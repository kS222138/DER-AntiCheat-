@tool
extends EditorPlugin

var core
var pool
var logger
var detector
var scan_timer = 0
var dock
var status_label
var stats_labels = {}

func _enter_tree():
    var logger_script = preload("report/logger.gd")
    logger = logger_script.new()
    
    core = VanguardCore.new()
    
    var pool_script = preload("core/pool.gd")
    pool = pool_script.new(logger)
    
    var detector_script = preload("detection/detector.gd")
    detector = detector_script.new(logger)
    
    pool.set_detector(detector)
    
    _add_critical_files()
    _create_dock()
    
    add_tool_menu_item("Vanguard Control Panel", Callable(self, "_open_panel"))
    add_tool_menu_item("Quick Scan", Callable(self, "_quick_scan"))
    add_tool_menu_item("View Stats", Callable(self, "_show_stats"))
    
    logger.info("plugin", "DER Protection System loaded")
    
    print("\n🛡️ ===============================")
    print("🛡️  DER AntiCheat 已启用")
    print("🛡️  版本: 1.2.0")
    print("🛡️  状态: 运行中")
    print("🛡️  检测器: 3个已加载")
    print("🛡️ ===============================\n")

func _exit_tree():
    remove_tool_menu_item("Vanguard Control Panel")
    remove_tool_menu_item("Quick Scan")
    remove_tool_menu_item("View Stats")
    
    if dock:
        remove_control_from_docks(dock)
        dock.queue_free()
    
    print("\n🛡️  DER Protection System 已禁用\n")

func _process(delta):
    scan_timer += delta
    if scan_timer > 3.0:
        scan_timer = 0
        _auto_scan()

func _add_critical_files():
    var files = [
        "res://project.godot",
        "res://addons/DER_Protection_System/plugin.gd",
        "res://addons/DER_Protection_System/core/value.gd",
        "res://addons/DER_Protection_System/detection/process_monitor.gd"
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
    title.text = "DER Protection System"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)
    
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
    
    var scan_btn = Button.new()
    scan_btn.text = "立即扫描"
    scan_btn.pressed.connect(_quick_scan)
    vbox.add_child(scan_btn)
    
    var panel_btn = Button.new()
    panel_btn.text = "控制面板"
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
    var threats = pool.scan_for_threats()
    var core_stats = VanguardCore.get_stats()
    
    if threats.size() > 0 or core_stats.critical_threats > 0:
        status_label.text = "状态: ⚠️ 检测到威胁"
        logger.warning("plugin", "自动扫描发现威胁")
    else:
        status_label.text = "状态: 🟢 运行中"
    
    _update_stats()

func _quick_scan():
    logger.info("plugin", "开始快速扫描")
    if detector:
        var scan_results = detector.scan_all()
        var has_threat = false
        
        for result in scan_results.values():
            if result.risk > 0.5:
                has_threat = true
                break
        
        if has_threat:
            logger.warning("plugin", "扫描发现高风险")
            status_label.text = "状态: 🔴 高风险"
        else:
            logger.info("plugin", "扫描完成 - 安全")
            status_label.text = "状态: 🟢 运行中"
    else:
        logger.error("plugin", "检测器未初始化")
    
    _update_stats()

func _open_panel():
    var stats = VanguardCore.get_stats()
    var threats = VanguardCore.get_threat_log()
    
    print("\n=== Vanguard Control Panel ===")
    print("受保护的值: ", stats.values_protected)
    print("总威胁数: ", stats.total_threats)
    print("严重威胁: ", stats.critical_threats)
    
    if threats.size() > 0:
        print("\n最近威胁:")
        for t in threats.slice(-5):
            print("  [%s] %s" % [t.level, t.type])
    
    _update_stats()

func _show_stats():
    var stats = VanguardCore.get_stats()
    var logs = logger.export()
    
    print("\n=== Protection Statistics ===")
    print("运行时间: ", Time.get_datetime_string_from_system())
    print("受保护值: ", stats.values_protected)
    print("总威胁: ", stats.total_threats)
    print("严重威胁: ", stats.critical_threats)
    print("日志总数: ", logs.total)
    print("警告日志: ", logs.by_level.warning)
    print("错误日志: ", logs.by_level.error)

func _update_stats():
    var stats = VanguardCore.get_stats()
    
    if stats_labels.has("values"):
        stats_labels.values.text = str(stats.values_protected)
    if stats_labels.has("threats"):
        stats_labels.threats.text = str(stats.total_threats)
    if stats_labels.has("critical"):
        stats_labels.critical.text = str(stats.critical_threats)

func get_plugin_name():
    return "DER Protection System"

func get_plugin_icon():
    return preload("res://icon.svg")