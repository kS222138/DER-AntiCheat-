class_name DERIntValidator
extends DERValidator

var _rng = RandomNumberGenerator.new()

func _init():
    _rng.randomize()

func verify(real_value: Variant, fake_values: Array) -> bool:
    # 检查真实值是否在合理范围内
    var int_value = real_value as int
    
    # 检查诱饵值是否包含真实值
    if fake_values.has(int_value):
        return false
    
    return true

func generate_fakes(real_value: Variant, count: int) -> Array:
    var fakes = []
    var int_value = real_value as int
    
    for i in range(count):
        var offset = _rng.randi_range(-10, 10)
        if offset == 0:
            offset = 1
        fakes.append(int_value + offset)
    
    return fakes
