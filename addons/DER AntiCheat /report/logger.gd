class_name DERLogger
extends RefCounted

enum Level { DEBUG, INFO, WARNING, ERROR, CRITICAL }

var _logs: Array = []
var _max_size: int = 1000
var _callbacks: Dictionary = {}
var _alert_threshold: Level = Level.WARNING

func debug(module: String, message: String) -> void:
    _log(Level.DEBUG, module, message)

func info(module: String, message: String) -> void:
    _log(Level.INFO, module, message)

func warning(module: String, message: String) -> void:
    _log(Level.WARNING, module, message)

func error(module: String, message: String) -> void:
    _log(Level.ERROR, module, message)

func critical(module: String, message: String, data: Dictionary = {}) -> void:
    _log(Level.CRITICAL, module, message, data)

func log(level: String, module: String, message: String, data: Dictionary = {}) -> void:
    var lvl = Level.INFO
    match level:
        "DEBUG": lvl = Level.DEBUG
        "INFO": lvl = Level.INFO
        "WARNING": lvl = Level.WARNING
        "ERROR": lvl = Level.ERROR
        "CRITICAL": lvl = Level.CRITICAL
    _log(lvl, module, message, data)

func _log(level: Level, module: String, message: String, data: Dictionary = {}) -> void:
    var entry = {
        "time": Time.get_datetime_string_from_system(false, true),
        "timestamp": Time.get_unix_time_from_system(),
        "level": level,
        "module": module,
        "message": message,
        "data": data
    }
    
    _logs.append(entry)
    if _logs.size() > _max_size:
        _logs.pop_front()
    
    if _callbacks.has(level):
        for cb in _callbacks[level]:
            cb.call(entry)
    
    if level >= _alert_threshold:
        if OS.is_debug_build():
            var level_str = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"][level]
            print("[%s][%s] %s" % [level_str, module, message])
            if data.size() > 0:
                print("  Data: ", data)

func on(level: Level, callback: Callable) -> void:
    if not _callbacks.has(level):
        _callbacks[level] = []
    _callbacks[level].append(callback)

func get_logs(level: Level = -1) -> Array:
    if level == -1:
        return _logs.duplicate()
    return _logs.filter(func(l): return l.level == level)

func get_critical_logs() -> Array:
    return _logs.filter(func(l): return l.level == Level.CRITICAL or l.level == Level.ERROR)

func export() -> Dictionary:
    return {
        "total": _logs.size(),
        "by_level": {
            "debug": _logs.filter(func(l): return l.level == Level.DEBUG).size(),
            "info": _logs.filter(func(l): return l.level == Level.INFO).size(),
            "warning": _logs.filter(func(l): return l.level == Level.WARNING).size(),
            "error": _logs.filter(func(l): return l.level == Level.ERROR).size(),
            "critical": _logs.filter(func(l): return l.level == Level.CRITICAL).size()
        },
        "recent": _logs.slice(-10),
        "critical": get_critical_logs().slice(-5)
    }