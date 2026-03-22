class_name DERBool
extends VanguardValue

func _init(initial_value: bool):
    super(initial_value, null)

func get_value() -> bool:
    return super.get_value() as bool

func set_value(new_value) -> void:
    super.set_value(new_value)