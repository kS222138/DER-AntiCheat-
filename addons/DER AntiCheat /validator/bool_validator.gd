class_name DERBoolValidator
extends DERValidator

func verify(real_value: Variant, fake_values: Array) -> bool:
    return true

func generate_fakes(real_value: Variant, count: int) -> Array:
    var fakes = []
    var bool_value = real_value as bool
    
    for i in range(count):
        fakes.append(not bool_value)
    
    return fakes
