extends Control
class_name DERProfiler

@export var refresh_interval: float = 1.0
@export var max_history: int = 60
@export var modules: Array[String] = ["Detector", "Value Pool", "File Validator", "Network Client"]

var _detector = null
var _pool = null
var _file_validator = null
var _network_client = null

var _history: Array = []
var _timer: Timer

var _tree: Tree
var _chart: Control
var _status_label: Label
var _fps_label: Label
var _memory_label: Label
var _stats_label: Label

var _ui_ready: bool = false
var _ui_created: bool = false

signal profile_updated(data: Dictionary)

func _ready():
    _setup_ui()
    _setup_timer()
    if _chart:
        _chart.draw.connect(_draw_chart)
    _ui_ready = true
    refresh()

func setup(detector, pool = null, file_validator = null, network_client = null):
    _detector = detector
    _pool = pool
    _file_validator = file_validator
    _network_client = network_client
    if _ui_ready:
        refresh()

func _add_child_safe(parent: Node, child: Node) -> void:
    if not parent or not child:
        return
    if child.get_parent():
        child.get_parent().remove_child(child)
    parent.add_child(child)

func _setup_ui():
    if _ui_created:
        return
    _ui_created = true
    
    await ready  # 等待节点进入场景树
    
    size = Vector2(600, 500)
    
    var vbox = VBoxContainer.new()
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _add_child_safe(self, vbox)
    
    var toolbar = HBoxContainer.new()
    vbox.add_child(toolbar)
    
    var refresh_btn = Button.new()
    refresh_btn.text = "Refresh"
    refresh_btn.pressed.connect(refresh)
    toolbar.add_child(refresh_btn)
    
    var reset_btn = Button.new()
    reset_btn.text = "Reset"
    reset_btn.pressed.connect(_reset_history)
    toolbar.add_child(reset_btn)
    
    var export_btn = Button.new()
    export_btn.text = "Export"
    export_btn.pressed.connect(_export_report)
    toolbar.add_child(export_btn)
    
    _fps_label = Label.new()
    _fps_label.text = "FPS: --"
    toolbar.add_child(_fps_label)
    
    _memory_label = Label.new()
    _memory_label.text = "Mem: -- MB"
    toolbar.add_child(_memory_label)
    
    _status_label = Label.new()
    _status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    toolbar.add_child(_status_label)
    
    var hs = HSplitContainer.new()
    hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(hs)
    
    _tree = Tree.new()
    _tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tree.columns = 3
    _tree.set_column_title(0, "Module")
    _tree.set_column_title(1, "Time (ms)")
    _tree.set_column_title(2, "% of Total")
    _tree.set_column_expand(0, true)
    _tree.set_column_expand(1, false)
    _tree.set_column_expand(2, false)
    hs.add_child(_tree)
    
    var right_vbox = VBoxContainer.new()
    right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hs.add_child(right_vbox)
    
    _chart = Control.new()
    _chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_vbox.add_child(_chart)
    
    _stats_label = Label.new()
    _stats_label.text = "Total: 0ms | Avg: 0ms | Peak: 0ms"
    right_vbox.add_child(_stats_label)

func _setup_timer():
    _timer = Timer.new()
    _timer.wait_time = refresh_interval
    _timer.autostart = true
    _timer.timeout.connect(refresh)
    _add_child_safe(self, _timer)

func refresh():
    if not _ui_ready:
        return
    var data = _collect_data()
    _update_tree(data)
    _update_history(data)
    _update_chart()
    _update_status(data)
    _update_metrics()
    profile_updated.emit(data)

func _collect_data() -> Dictionary:
    var data = {
        "timestamp": Time.get_unix_time_from_system(),
        "modules": {},
        "fps": Engine.get_frames_per_second(),
        "memory": OS.get_static_memory_usage() / 1024 / 1024
    }
    
    for module in modules:
        var node = _get_module_node(module)
        if node and node.has_method("_get_perf_time"):
            var elapsed = node._get_perf_time()
            data.modules[module] = elapsed
        elif node:
            var start = Time.get_ticks_usec()
            _measure_module(module, node)
            var elapsed = (Time.get_ticks_usec() - start) / 1000.0
            data.modules[module] = elapsed
        else:
            data.modules[module] = 0.0
    
    var total = 0.0
    for t in data.modules.values():
        total += t
    data["total"] = total
    
    return data

func _get_module_node(module):
    match module:
        "Detector":
            return _detector
        "Value Pool":
            return _pool
        "File Validator":
            return _file_validator
        "Network Client":
            return _network_client
    return null

func _measure_module(module, node):
    match module:
        "Detector":
            if node.has_method("scan_all"):
                node.scan_all()
        "Value Pool":
            if node.has_method("scan_for_threats"):
                node.scan_for_threats()
        "File Validator":
            if node.has_method("verify_all"):
                node.verify_all()
        "Network Client":
            if node.has_method("get_stats"):
                node.get_stats()

func _update_tree(data: Dictionary):
    if not _tree:
        return
    _tree.clear()
    var root = _tree.create_item()
    
    var total = data.get("total", 0)
    var total_item = _tree.create_item(root)
    total_item.set_text(0, "TOTAL")
    total_item.set_text(1, "%.2f ms" % total)
    
    for name in data.modules:
        var item = _tree.create_item(root)
        item.set_text(0, name)
        item.set_text(1, "%.2f ms" % data.modules[name])
        
        var percent = (data.modules[name] / total) * 100 if total > 0 else 0
        item.set_text(2, "%.1f%%" % percent)
        
        if percent > 50:
            item.set_custom_color(0, Color(0.9, 0.2, 0.2))

func _update_history(data: Dictionary):
    _history.append(data)
    if _history.size() > max_history:
        _history.pop_front()

func _update_chart():
    if _chart:
        _chart.queue_redraw()

func _draw_chart():
    if not _chart or _history.is_empty():
        return
    
    var padding = 20
    var width = _chart.size.x - padding * 2
    var height = _chart.size.y - padding * 2
    if width <= 0 or height <= 0:
        return
    
    var step_x = width / max_history
    
    var max_total = 0.0
    for h in _history:
        max_total = max(max_total, h.get("total", 0))
    if max_total <= 0:
        max_total = 1
    
    _chart.draw_line(Vector2(padding, padding), Vector2(padding, padding + height), Color(0.5, 0.5, 0.5), 1.0)
    _chart.draw_line(Vector2(padding, padding + height), Vector2(padding + width, padding + height), Color(0.5, 0.5, 0.5), 1.0)
    
    var points = []
    for i in range(_history.size()):
        var x = padding + i * step_x
        var total = _history[i].get("total", 0)
        var y = padding + height - (total / max_total) * height
        points.append(Vector2(x, y))
    
    for i in range(points.size() - 1):
        _chart.draw_line(points[i], points[i + 1], Color(0.3, 0.6, 0.9), 2.0)
    
    for point in points:
        _chart.draw_circle(point, 3, Color(0.3, 0.6, 0.9))
        _chart.draw_circle(point, 1.5, Color.WHITE)

func _update_status(data: Dictionary):
    if not _status_label:
        return
    var total = data.get("total", 0)
    var avg = 0.0
    var peak = 0.0
    for h in _history:
        var t = h.get("total", 0)
        avg += t
        if t > peak:
            peak = t
    if _history.size() > 0:
        avg /= _history.size()
    
    _status_label.text = "Total: %.2f ms | Avg: %.2f ms | Peak: %.2f ms" % [total, avg, peak]

func _update_metrics():
    if not _fps_label or not _memory_label:
        return
    var data = _collect_data()
    _fps_label.text = "FPS: %d" % data.get("fps", 0)
    _memory_label.text = "Mem: %.1f MB" % data.get("memory", 0)

func _reset_history():
    _history.clear()
    if _chart:
        _chart.queue_redraw()

func _export_report():
    var data = {
        "stats": get_stats(),
        "history": _history,
        "timestamp": Time.get_datetime_string_from_system(false, true)  
    }
    var timestamp = Time.get_datetime_string_from_system(false, true).replace(":", "-")  
    var path = "user://profiler_report_%s.json" % timestamp
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data, "\t"))
        file.close()
        print("Profiler report saved: ", path)

func get_bottlenecks() -> Array:
    var bottlenecks = []
    var data = _collect_data()
    var total = data.get("total", 0)
    if total <= 0:
        return bottlenecks
    
    for name in data.modules:
        var percent = (data.modules[name] / total) * 100
        if percent > 50:
            bottlenecks.append({"module": name, "percent": percent, "time": data.modules[name]})
    
    bottlenecks.sort_custom(func(a, b): return a.percent > b.percent)
    return bottlenecks

func get_stats() -> Dictionary:
    var avg = 0.0
    var peak = 0.0
    for h in _history:
        var t = h.get("total", 0)
        avg += t
        if t > peak:
            peak = t
    if _history.size() > 0:
        avg /= _history.size()
    
    return {
        "current": _collect_data().get("total", 0),
        "average": avg,
        "peak": peak,
        "samples": _history.size(),
        "bottlenecks": get_bottlenecks()
    }