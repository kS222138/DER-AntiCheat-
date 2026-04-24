# 🛡️ DER AntiCheat

**Godot 4 引擎最全面的开源反作弊框架**

[![Godot](https://img.shields.io/badge/Godot-4.6%2B-blue?logo=godot-engine)](https://godotengine.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.3.0-orange)]()

DER AntiCheat 是一个专为 Godot 4.6+ 设计的模块化反作弊框架，包含 **38 个集成模块**，覆盖内存加密、注入检测、网络验证、设备指纹、云端取证和性能优化等安全领域。

---

## 📦 版本亮点

### v2.3.0 - 开发者体验更新

- **预设配置系统**：一键加载 Light（轻量）/ Standard（标准）/ Competitive（竞技）三套预设
- **快速集成 API**：`quick_setup("multiplayer")` 一行代码启动
- **移动端兼容**：完整支持 Android 和 iOS 平台
- **Inspector 可视化编辑**：所有预设参数可在编辑器中直接调整

### v2.2.0 - 实用功能更新

- **反加速器检测**：检测变速齿轮、Cheat Engine Speedhack
- **反虚拟定位**：检测 GPS 伪造
- **文件完整性校验**：自动扫描核心文件是否被篡改
- **离线模式防护**：断网时缓存违规数据，联网后自动上报
- **日志加密存储**：本地 SQLite + AES 加密存储

### v2.1.0 - 网络安全更新

- CCU 优化器、一致性验证器、误报过滤器
- 加密云快照、设备白名单、加密日志系统
- 跨平台设备指纹

### v2.0.0 - 性能优化更新

- 高性能线程池 + 对象池
- 性能监控器
- 异步检测管线，GC 暂停减少 70%

---

## 🚀 快速开始

### 安装

1. 从 Godot Asset Library 下载，或手动复制 `addons/DER AntiCheat/` 文件夹
2. 打开项目设置 → 插件 → 启用 DER AntiCheat
3. 重启编辑器

### 一键配置（v2.3.0 新增）

```gdscript
# 单机游戏 - 仅启用基础内存加密和加速器检测
DERAntiCheat.quick_setup("singleplayer")

# 多人游戏 - 启用注入检测、反调试、存档保护
DERAntiCheat.quick_setup("multiplayer")

# 竞技游戏 - 启用全部 38 个模块
DERAntiCheat.quick_setup("competitive")
```

手动配置

```gdscript
# 加载预设配置
DERAntiCheat.load_preset("standard")

# 或逐个模块启用
var detector = DERDetector.new()
detector.start()
```

保护游戏数值

```gdscript
var hp = VanguardValue.new(100)
hp.value_changed.connect(func(old, new): print("HP changed: ", old, " -> ", new))
hp.access_detected.connect(func(type): print("Abnormal access: ", type))

# 读取和修改
print(hp.get_value())  # 100
hp.set_value(80)       # 自动加密存储
```

检测加速器

```gdscript
var speed_detector = DERSpeedDetectorV2.new()
speed_detector.sensitivity = DERSpeedDetectorV2.Sensitivity.HIGH
speed_detector.start()

speed_detector.speed_hack_detected.connect(func(ratio, details):
    print("Speed hack detected! Ratio: ", ratio)
)

func _process(delta):
    speed_detector.process_frame(delta)
```

---

📊 模块总览

分类 模块 说明
核心防护 VanguardValue, Pool, MemoryObfuscator, ThreadPool, ObjectPool, PerformanceMonitor 内存加密、对象池、性能监控
注入检测 InjectDetector, MemoryScanner, HookDetector, ProcessScannerV2, MultiInstance, VMDetector DLL注入、内存扫描、虚拟机检测
反调试 DebuggerDetector, DebugDetectorV2, IntegrityCheck 调试器检测、文件完整性
网络防护 NetworkClient, PacketProtector, ReplayProtector, TimeSync, ConsistencyValidator, CCUOptimizer 网络加密、数据一致性、CCU优化
加速检测 SpeedDetector, SpeedDetectorV2, VirtualPosDetector 变速齿轮、虚拟定位
存档保护 ArchiveEncryptor, ArchiveManager, FileValidator, RollbackDetector, SaveLimit, CloudValidator, CloudSnapshot 存档加密、回滚检测、云存档
设备安全 DeviceFingerprint, WhitelistManager 设备指纹、白名单管理
日志监控 EncryptedLogger, AlertManager, ReportExporter, Dashboard, StatsChart, LogExporter 加密日志、告警、报表
开发工具 Profiler, CheatSimulator, FileIntegrity, OfflineProtector, LogEncryptor 性能分析、作弊模拟、离线防护

---

📦 预设配置

预设 启用模块数 适用场景 性能影响
Light ~6 单机游戏、原型开发 极低
Standard ~15 普通多人游戏 低
Competitive 全部 38 排行榜、电竞、高价值经济 中等

---

📈 性能数据

指标 v1.9.0 v2.0.0 v2.3.0
内存占用 200MB 100MB 95MB
启动时间 500ms 300ms 280ms
扫描卡顿 50ms 20ms 18ms
GC 暂停 10ms 3ms 3ms
模块总数 28 31 38

---

🔐 安全特性

· AES-256-CBC 加密核
· 防篡改校验和 + 蜜罐诱饵
· 模块化架构：按需启用，零浪费
· 跨平台：Windows / Linux / macOS / Android / iOS
· 移动端优化：低功耗、低内存占用
· MIT 开源：免费商用，社区驱动

---

🌐 社区与支持

· GitHub: https://github.com/kS222138/DER-AntiCheat-
· Godot Asset Library: 搜索 "DER AntiCheat"
· 问题反馈: GitHub Issues

---

📄 许可证

MIT License - 免费用于个人和商业项目。

---

感谢使用 DER AntiCheat！如果你觉得这个项目有帮助，欢迎在 GitHub 上点一个 Star ⭐