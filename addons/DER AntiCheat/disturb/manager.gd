class_name DERDisturbManager
extends RefCounted

var _base_count: int = 3
var _values: Dictionary = {}
var _rng = RandomNumberGenerator.new()

func _init():
    _rng.randomize()

func set_base_count(count: int) -> void:
    _base_count = count
    _regenerate_all()

func register_value(key: String, value) -> void:
    _values[key] = value

func unregister_value(key: String) -> void:
    _values.erase(key)

func _regenerate_all() -> void:
    for key in _values:
        var value = _values[key]
        if value.has_method("_generate_fakes"):
            value._generate_fakes()

func clear() -> void:
    _values.clear()

func adjust_for_risk(risk_level: float) -> int:
    var new_count = _base_count + int(risk_level * 5)
    return clampi(new_count, 2, 20)