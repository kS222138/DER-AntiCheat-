class_name DERList
extends VanguardValue

var _items: Array = []

func _init(initial_value: Array):
    super(initial_value, null)
    _items = initial_value.duplicate()

func get_value() -> Array:
    super.get_value()
    return _items.duplicate()

func set_value(new_value) -> void:
    if new_value is Array:
        _items = new_value.duplicate()
    super.set_value(new_value)

func append(item: Variant) -> void:
    _items.append(item)
    set_value(_items)

func remove_at(index: int) -> void:
    _items.remove_at(index)
    set_value(_items)

func size() -> int:
    return _items.size()

func get_item(index: int) -> Variant:
    return _items[index]

func is_empty() -> bool:
    return _items.is_empty()