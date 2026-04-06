class_name DERPool
extends RefCounted

var _values: Dictionary = {}
var _detector
var _logger
var _auto_protect: bool = true
var _scan_timer: int = 0

func _init(logger = null):
    _logger = logger if logger else preload("../report/logger.gd").new()
    _detector = null
    _logger.info("pool", "DER Pool initialized")

func set_detector(detector) -> void:
    _detector = detector

func set_value(key: String, value: VanguardValue) -> void:
    _values[key] = value
    if _detector:
        _detector.register_object(value, key)
    VanguardCore.register(key, value)
    _logger.debug("pool", "Value protected: " + key)

func get_value(key: String) -> VanguardValue:
    if _values.has(key):
        if _auto_protect and _detector:
            if not _detector.verify_object(_values[key]):
                _logger.warning("pool", "Suspicious access to: " + key)
                return null
        return _values[key]
    return null

func remove_value(key: String) -> void:
    if _values.has(key):
        if _detector:
            _detector.unregister_object(_values[key])
        VanguardCore.unregister(key)
        _values.erase(key)
        _logger.debug("pool", "Value removed: " + key)

func scan_for_threats() -> Dictionary:
    var results = {}
    if _detector:
        results = _detector.scan_all()
    
    for key in _values:
        var v = _values[key]
        if v.get_detected_cheat_type() != value.CheatType.NONE:
            results[key] = {
                "cheat_type": v.get_detected_cheat_type(),
                "stats": v.get_stats()
            }
            _logger.warning("pool", "Cheat detected in " + key)
    
    return results

func add_critical_file(path: String) -> void:
    if _detector:
        _detector.add_critical_file(path)

func get_protection_status() -> Dictionary:
    return {
        "values_protected": _values.size(),
        "detectors_active": _detector != null,
        "auto_scan": _auto_protect,
        "threat_report": _detector.get_threat_report() if _detector else {}
    }

func _process(delta):
    if _auto_protect and _detector:
        _scan_timer += 1
        if _scan_timer >= 300:
            scan_for_threats()
            _scan_timer = 0