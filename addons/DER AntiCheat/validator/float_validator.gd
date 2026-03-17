class_name DERFloatValidator
extends DERValidator

var _rng = RandomNumberGenerator.new()

func _init():
    _rng.randomize()

func verify(real_value: Variant, fake_values: Array) -> bool:
    return true

func generate_fakes(real_value: Variant, count: int) -> Array:
    var fakes = []
    var float_value = real_value as float
    
    for i in range(count):
        var offset = _rng.randf_range(-1.0, 1.0)
        if abs(offset) < 0.01:
            offset = 0.1
        fakes.append(float_value + offset)
    
    return fakes
