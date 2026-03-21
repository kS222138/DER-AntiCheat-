class_name DERSettings
extends RefCounted

# 保护级别
enum ProtectLevel {
    LIGHT,      # 低保护，高性能
    MEDIUM,     # 中等保护
    HEAVY,      # 高保护，低性能
    CUSTOM      # 自定义
}

var protect_level: ProtectLevel = ProtectLevel.MEDIUM
var enable_detection: bool = true
var enable_report: bool = true
var disturb_min: int = 2
var disturb_max: int = 10
var verify_interval: int = 1000  # 毫秒

func load_from_file(path: String) -> bool:
    # 从文件加载配置
    return true

func save_to_file(path: String) -> bool:
    # 保存配置到文件
    return true
