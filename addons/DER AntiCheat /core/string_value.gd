class_name DERString
extends VanguardValue

func _init(initial_value: String):
    super(initial_value)

func get_value() -> String:
    return super.get_value() as String

func set_value(new_value) -> void:
    super.set_value(new_value)