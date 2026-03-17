class_name DERValidator
extends RefCounted
# 验证器基类

func verify(real_value: Variant, fake_values: Array) -> bool:
    # 子类实现
    return true

func generate_fakes(real_value: Variant, count: int) -> Array:
    # 子类实现
    return []
