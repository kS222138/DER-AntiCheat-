class_name DERStringValidator
extends DERValidator

var _rng = RandomNumberGenerator.new()

func _init():
    _rng.randomize()

func verify(real_value: Variant, fake_values: Array) -> bool:
    return true

func generate_fakes(real_value: Variant, count: int) -> Array:
    var fakes = []
    var str_value = real_value as String
    
    for i in range(count):
        var fake = str_value + "_" + str(_rng.randi_range(100, 999))
        fakes.append(fake)
    
    return fakes
