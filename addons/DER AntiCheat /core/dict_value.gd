class_name DERDict
extends VanguardValue

var _items: Dictionary = {}

func _init(initial_value: Dictionary):
    super(initial_value,)
    _items = initial_value.duplicate()

func get_value() -> Dictionary:
    super.get_value()
    return _items.duplicate()

func set_value(new_value):
    if new_value is Dictionary:
        _items = new_value.duplicate()
    super.set_value(new_value)

func get_item(key: String) -> Variant:
    return _items.get(key)

func set_item(key: String, value: Variant) -> void:
    _items[key] = value
    set_value(_items)

func has_key(key: String) -> bool:
    return _items.has(key)

func keys() -> Array:
    return _items.keys()