class_name DERInt
extends VanguardValue

func _init(initial_value: int):
    super(initial_value, null)

func get_value() -> int:
    return super.get_value() as int

func set_value(new_value) -> void:
    super.set_value(new_value)