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
var stats_chart
var log_exporter
var dock
var status_label
var stats_labels = {}
var _log_viewer
var _profiler
var _simulator
var _files_added = false
var _performance_monitor
var _thread_pool
var _object_pool

const MENU_ITEMS = [
    ["Control Panel", "_open_panel"],
    ["Quick Scan", "_quick_scan"],
    ["Verify Files", "_verify_files"],
    ["Archive", "_open_archive"],
    ["SL Protection", "_open_sl_protection"],
    ["Cloud", "_open_cloud_validator"],
    ["Statistics", "_show_stats"],
    ["Export Report", "_export_report"]
]

func _enter_tree():
    _init_modules()
    _create_dock()
    _setup_menu()
    logger.info("plugin", "DER AntiCheat v2.0.0 loaded")
    print("\n🛡️ DER AntiCheat v2.0.0 Enabled | Performance Optimized | 18 Modules Loaded\n")

func _exit_tree():
    _remove_menu()
    if dock:
        remove_control_from_docks(dock)
        dock.queue_free()
    print("\n🛡️ DER AntiCheat v2.0.0 Disabled\n")

func _init_modules():
    logger = preload("res://addons/DER AntiCheat /report/logger.gd").new()
    core = preload("res://addons/DER AntiCheat /core/vanguard_core.gd").new()
    pool = preload("res://addons/DER AntiCheat /core/pool.gd").new(logger)
    detector = preload("res://addons/DER AntiCheat /detection/detector.gd").new(logger)
    pool.set_detector(detector)

    file_validator = preload("res://addons/DER AntiCheat /security/file_validator.gd").new()
    file_validator.hash_type = 2
    file_validator.auto_verify = false

    archive_manager = preload("res://addons/DER AntiCheat /security/archive_manager.gd").new()
    archive_manager.max_slots = 10

    debug_detector = preload("res://addons/DER AntiCheat /detection_v2/debug_detector_v2.gd").new()
    debug_detector.level = 2

    rollback_detector = preload("res://addons/DER AntiCheat /security/rollback_detector.gd").new()
    save_limit = preload("res://addons/DER AntiCheat /security/save_limit.gd").new()
    save_limit.max_saves_per_minute = 10

    cloud_validator = preload("res://addons/DER AntiCheat /security/cloud_validator.gd").new()
    cloud_validator.mode = 1

    alert_manager = preload("res://addons/DER AntiCheat /report_v2/alert_manager.gd").new()
    stats_chart = preload("res://addons/DER AntiCheat /report_v2/stats_chart.gd").new()

    report_exporter = preload("res://addons/DER AntiCheat /report_v2/report_exporter.gd").new()
    report_exporter.set_data_source(self)
    report_exporter.export_completed.connect(_on_export_done)

    log_exporter = preload("res://addons/DER AntiCheat /devtools/log_exporter.gd").new()
    log_exporter.setup(logger)

    _log_viewer = preload("res://addons/DER AntiCheat /devtools/log_viewer.gd").new()
    _log_viewer.setup(logger)

    _profiler = preload("res://addons/DER AntiCheat /devtools/profiler.gd").new()
    _profiler.setup(detector, pool, file_validator, cloud_validator)

    _simulator = preload("res://addons/DER AntiCheat /devtools/cheat_simulator.gd").new()
    _simulator.setup(pool, detector, file_validator, archive_manager, save_limit, rollback_detector)
    
    _performance_monitor = preload("res://addons/DER AntiCheat /core/performance_monitor.gd").new()
    _thread_pool = preload("res://addons/DER AntiCheat /core/thread_pool.gd").new()
    _object_pool = preload("res://addons/DER AntiCheat /core/object_pool.gd").new(func(): pass)

    _add_critical_files()


func _setup_menu():
    for item in MENU_ITEMS:
        add_tool_menu_item(item[0], Callable(self, item[1]))

func _remove_menu():
    for item in MENU_ITEMS:
        remove_tool_menu_item(item[0])

func _add_critical_files():
    if _files_added:
        return
    _files_added = true
    
    if not detector or not detector.has_method("add_critical_file"):
        return

    var dir = DirAccess.open("res://")
    if dir:
        _scan_scripts("res://", dir)

func _scan_scripts(path, dir):
    dir.list_dir_begin()
    var name = dir.get_next()
    while name != "":
        if not name.begins_with("."):
            var full = path + name
            if dir.current_is_dir():
                var sub_dir = DirAccess.open(full)
                if sub_dir:
                    _scan_scripts(full + "/", sub_dir)
            else:
                if name.ends_with(".gd"):
                    detector.add_critical_file(full)
        name = dir.get_next()

func _create_dock():
    dock = Control.new()
    dock.name = "DERAntiCheatDock"

    var vbox = VBoxContainer.new()
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    dock.add_child(vbox)

    var title = Label.new()
    title.text = "🛡️ DER AntiCheat v2.0.0"
    title.horizontal_alignment = 1
    title.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
    vbox.add_child(title)

    var tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(tabs)

    var status_page = _make_status_page()
    tabs.add_child(status_page)
    tabs.set_tab_title(0, "📊 Status")

    var log_page = VBoxContainer.new()
    log_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    log_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
    log_page.add_child(_log_viewer)
    tabs.add_child(log_page)
    tabs.set_tab_title(1, "📋 Logs")

    var prof_page = VBoxContainer.new()
    prof_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    prof_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
    prof_page.add_child(_profiler)
    tabs.add_child(prof_page)
    tabs.set_tab_title(2, "⚡ Profiler")

    var sim_page = _make_sim_page()
    tabs.add_child(sim_page)
    tabs.set_tab_title(3, "🎮 Simulator")

    var btn_hbox = HBoxContainer.new()
    btn_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    btn_hbox.add_theme_constant_override("separation", 6)
    vbox.add_child(btn_hbox)

    var refresh_btn = Button.new()
    refresh_btn.text = "🔄 Refresh All"
    refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    refresh_btn.pressed.connect(_refresh_all)
    btn_hbox.add_child(refresh_btn)

    var clear_logs_btn = Button.new()
    clear_logs_btn.text = "🗑️ Clear Logs"
    clear_logs_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    clear_logs_btn.pressed.connect(_clear_logs)
    btn_hbox.add_child(clear_logs_btn)

    add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

func _make_status_page():
    var page = VBoxContainer.new()
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_theme_constant_override("separation", 6)

    status_label = Label.new()
    status_label.text = "✅ Status: Ready"
    status_label.horizontal_alignment = 1
    status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
    page.add_child(status_label)

    var line = HSeparator.new()
    page.add_child(line)

    var grid = GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 20)
    grid.add_theme_constant_override("v_separation", 4)
    page.add_child(grid)

    var items = [
        ["values", "🛡️ Protected Values:", "0"],
        ["threats", "❗ Total Threats:", "0"],
        ["critical", "🔴 Critical:", "0"],
        ["files", "📁 Verified Files:", "0"],
        ["debug", "🐛 Anti-Debug Triggers:", "0"],
        ["rollback", "📌 Rollback Detections:", "0"],
        ["savelimit", "💾 Save Spam:", "0"]
    ]

    for item in items:
        var label = Label.new()
        label.text = item[1]
        grid.add_child(label)

        var value = Label.new()
        value.text = item[2]
        grid.add_child(value)
        stats_labels[item[0]] = value

    var btn_grid = GridContainer.new()
    btn_grid.columns = 2
    btn_grid.add_theme_constant_override("h_separation", 6)
    btn_grid.add_theme_constant_override("v_separation", 6)
    page.add_child(btn_grid)

    var actions = [
        ["⚡ Quick Scan", "_quick_scan"],
        ["📁 Verify Files", "_verify_files"],
        ["📈 Export Report", "_export_report"],
        ["📊 Control Panel", "_open_panel"]
    ]

    for action in actions:
        var btn = Button.new()
        btn.text = action[0]
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.pressed.connect(Callable(self, action[1]))
        btn_grid.add_child(btn)

    return page

func _make_sim_page():
    var page = VBoxContainer.new()
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_theme_constant_override("separation", 6)

    var label = Label.new()
    label.text = "🎮 Select Cheat Type to Simulate:"
    page.add_child(label)

    var list = ItemList.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_child(list)

    var result_label = Label.new()
    result_label.text = ""
    result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
    result_label.custom_minimum_size = Vector2(0, 60)
    page.add_child(result_label)

    var btn_hbox = HBoxContainer.new()
    btn_hbox.add_theme_constant_override("separation", 6)
    page.add_child(btn_hbox)

    var cheat_type_map = {}

    var sim_btn = Button.new()
    sim_btn.text = "▶ Simulate"
    sim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sim_btn.pressed.connect(func():
        var idx_list = list.get_selected_items()
        if idx_list.is_empty():
            result_label.text = "❗ Please select a cheat type"
            return
        var idx = idx_list[0]
        if not cheat_type_map.has(idx):
            result_label.text = "❗ Invalid selection"
            return
        var type = cheat_type_map[idx]
        var r = _simulator.simulate(type)
        var status = "✅" if r.success else "❌"
        var detected = "🔴 DETECTED" if r.detected else "🟢 Not Detected"
        result_label.text = "%s Simulate: %s\nDetected: %s\n%s" % [status, "Success" if r.success else "Failed", detected, r.message]
    )
    btn_hbox.add_child(sim_btn)

    var all_btn = Button.new()
    all_btn.text = "🎲 Simulate All"
    all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    all_btn.pressed.connect(func():
        var results = _simulator.simulate_all()
        var detected = 0
        for r in results.values():
            if r.detected:
                detected += 1
        var rate = 0.0
        if results.size() > 0:
            rate = float(detected) / results.size() * 100
        result_label.text = "📊 Simulated: %d cheats\nDetected: %d (%.1f%%)" % [results.size(), detected, rate]
    )
    btn_hbox.add_child(all_btn)

    var clear_btn = Button.new()
    clear_btn.text = "🗑️ Clear"
    clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    clear_btn.pressed.connect(func():
        result_label.text = ""
    )
    btn_hbox.add_child(clear_btn)

    page.ready.connect(func():
        list.clear()
        cheat_type_map.clear()
        var cheats = _simulator.get_available_cheats()
        for i in range(cheats.size()):
            var t = cheats[i]
            var name = DERCheatSimulator.CheatType.keys()[t]
            list.add_item(name)
            cheat_type_map[i] = t
    )

    return page

func _clear_logs():
    if logger and logger.has_method("clear_logs"):
        logger.clear_logs()
        if _log_viewer:
            _log_viewer.refresh()
        print("📋 Logs cleared")

func _refresh_all():
    if _log_viewer:
        _log_viewer.refresh()
    if _profiler:
        _profiler.refresh()
    _update_stats()

func _quick_scan():
    logger.info("plugin", "Starting security scan")
    print("\n🔍 ========= Security Scan =========")
    var risk = 0.0
    var threats = []
    if detector:
        var results = detector.scan_all()
        for r in results.values():
            threats.append(r)
            risk += r.risk
            print("  🔴 ", r.get("type", "Unknown"), " - Risk: ", r.get("risk", 0))
    if file_validator:
        var results = file_validator.verify_all()
        var corrupted = 0
        for ok in results.values():
            if not ok:
                corrupted += 1
        if corrupted > 0:
            risk += 0.8
            print("  📁 File Integrity - ", corrupted, " corrupted files")
    if debug_detector and debug_detector.is_detected():
        risk += 1.0
        print("  🐛 Debugger Detected")
    if rollback_detector and rollback_detector.is_suspicious(0):
        risk += 0.9
        print("  📌 Save Rollback Detected")
    if save_limit and save_limit.get_save_count(0, 60) > 20:
        risk += 0.7
        print("  💾 Save Spam Detected")
    print("----------------------------------------")
    print("  Total Risk Score: ", risk)
    var status = "✅ SAFE"
    var color = Color(0.3, 0.8, 0.3)
    if risk > 2.0:
        status = "🔴 HIGH RISK"
        color = Color(0.9, 0.2, 0.2)
    elif risk > 0.5:
        status = "🟡 MEDIUM RISK"
        color = Color(0.9, 0.7, 0.2)
    print("  Result: ", status)
    print("========================================\n")
    status_label.text = "Status: " + status
    status_label.add_theme_color_override("font_color", color)
    _update_stats()
    if threats.size() > 0:
        logger.warning("plugin", "Scan found %d threats, risk: %.2f" % [threats.size(), risk])
    else:
        logger.info("plugin", "Scan complete - Safe")

func _verify_files():
    if not file_validator:
        return
    logger.info("plugin", "Verifying game files")
    print("\n📁 ========= File Integrity Check =========")
    var results = file_validator.verify_all()
    var passed = 0
    var failed = 0
    var corrupted_files = []
    for file in results:
        if results[file]:
            passed += 1
        else:
            failed += 1
            corrupted_files.append(file)
    print("  Total Files: ", passed + failed)
    print("  ✅ Passed: ", passed)
    print("  ❌ Failed: ", failed)
    if failed > 0:
        print("\n  ❗ Tampered Files:")
        for f in corrupted_files:
            print("    - ", f.get_file())
    print("==========================================\n")
    if failed > 0:
        logger.warning("plugin", "File integrity check failed: %d corrupted files" % failed)
    else:
        logger.info("plugin", "File integrity check passed")
    _update_stats()

func _open_archive():
    print("\n🔐 ========= Archive Manager =========")
    print("  Usage: archive_manager.save(slot, data)")
    print("         archive_manager.load(slot)")
    print("  Features: AES-256-GCM encryption, 10 slots")
    print("====================================\n")

func _open_sl_protection():
    print("\n📌 ========= SL Protection =========")
    print("  Settings:")
    print("    Max saves/min: ", save_limit.max_saves_per_minute)
    print("    Max loads/min: ", save_limit.max_loads_per_minute)
    print("    Cooldown: ", save_limit.cooldown_seconds, "s")
    print("\n  Detection: rollback_detector.is_suspicious(slot)")
    print("            save_limit.get_save_count(slot, 60)")
    print("==================================\n")

func _open_cloud_validator():
    print("\n☁️ ========= Cloud Validator =========")
    print("  Usage: cloud_validator.validate(slot, data, callback)")
    print("         cloud_validator.upload(slot, data)")
    print("  Mode: ", cloud_validator.mode)
    print("  Timeout: ", cloud_validator.timeout, "s")
    print("==================================\n")

func _export_report():
    if report_exporter:
        report_exporter.export_report("html")
        print("📈 Exporting report...")

func _on_export_done(path, format):
    print("📄 Report exported: ", path)

func _open_panel():
    var stats = VanguardCore.get_stats()
    var threats = VanguardCore.get_threat_log()
    var file_stats = file_validator.get_stats() if file_validator else {}
    var debug_count = debug_detector.get_count() if debug_detector else 0
    var rollback_stats = rollback_detector.get_stats() if rollback_detector else {}
    var save_stats = save_limit.get_stats() if save_limit else {}
    print("\n🛡️ ========= Control Panel =========")
    print("  Protected Values: ", stats.values_protected)
    print("  Total Threats: ", stats.total_threats)
    print("  Critical Threats: ", stats.critical_threats)
    print("")
    print("  File Verification: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
    print("  Anti-Debug Triggers: ", debug_count)
    print("  Rollback Detections: ", rollback_stats.get("active_slots", 0))
    print("  SL Limit Saves: ", save_stats.get("total_saves", 0))
    print("")
    print("  Recent Threats:")
    if threats.size() > 0:
        for t in threats.slice(-5):
            print("    [", t.level, "] ", t.type)
    else:
        print("    None")
    print("================================\n")
    _update_stats()

func _show_stats():
    var stats = VanguardCore.get_stats()
    var logs = logger.export() if logger else {}
    var file_stats = file_validator.get_stats() if file_validator else {}
    var debug_count = debug_detector.get_count() if debug_detector else 0
    var rollback_stats = rollback_detector.get_stats() if rollback_detector else {}
    var save_stats = save_limit.get_stats() if save_limit else {}
    print("\n📊 ========= Statistics =========")
    print("  Runtime: ", Time.get_datetime_string_from_system())
    print("  Version: 2.0.0")
    print("")
    print("  Protected Values: ", stats.values_protected)
    print("  Total Threats: ", stats.total_threats)
    print("  Critical Threats: ", stats.critical_threats)
    print("")
    print("  File Verification: ", file_stats.get("verified", 0), "/", file_stats.get("total", 0))
    print("  Anti-Debug Triggers: ", debug_count)
    print("  Rollback Detections: ", rollback_stats.get("active_slots", 0))
    print("  Total Saves: ", save_stats.get("total_saves", 0))
    print("  Total Loads: ", save_stats.get("total_loads", 0))
    print("")
    print("  Logs: ", logs.get("total", 0))
    print("    Warnings: ", logs.get("by_level", {}).get("warning", 0))
    print("    Errors: ", logs.get("by_level", {}).get("error", 0))
    print("==============================\n")

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
    return "DER AntiCheat v2.0.0"