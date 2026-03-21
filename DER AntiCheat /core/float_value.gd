class_name DERFloat
extends VanguardValue

func _init(initial_value: float):
    super(initial_value, null)

func get_value() -> float:
    return super.get_value() as float

func set_value(new_value):
    super.set_value(new_value)