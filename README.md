🛡️ DER AntiCheat

Version: 2.3.0
Godot Version: 4.6+
License: MIT
[📖 中文文档](README_CN.md) | [English](README.md)
---

📦 What's New in v2.3.0

🆕 Developer Experience

| Module | Class | Description |
|--------|-------|-------------|
| Protection Presets | DERProtectionPreset | One-click setup with Light, Standard, and Competitive presets |
| Quick Setup API | - | `quick_setup("singleplayer|multiplayer|competitive")` one-liner |
| In-Game Debug Panel | DERInGamePanel | Runtime debug overlay with module management, real-time logs, and stats dashboard (Ctrl+Shift+F12) |
| Mobile Compatibility | - | Full Android and iOS support confirmed |

🆕 Preset System

| Preset | Modules | Best For |
|--------|---------|----------|
| Light | 6 | Single-player games, prototypes |
| Standard | 15 | Most multiplayer games |
| Competitive | 38 | Ranked matches, esports, high-value economies |

🆕 In-Game Debug Panel

- Ctrl+Shift+F12 to toggle
- Real-time module status (green/yellow/red indicators)
- Enable/disable modules at runtime
- Live log viewer with last 100 entries
- Runtime stats dashboard (FPS, memory, process ID)

---

📦 What's New in v2.2.0

🆕 New Security Modules

| Module | Class | Description |
|--------|-------|-------------|
| Speed Detector V2 | DERSpeedDetectorV2 | Time-based speed hack detection with multi-level sensitivity and anti-cheat calibration |
| Virtual Position Detector | DERVirtualPosDetector | GPS spoofing detection for location-based games with 5 detection levels |
| File Integrity Scanner | DERFileIntegrity | Game file integrity verification with SHA256, multiple scan modes, auto-repair |
| Offline Protector | DEROfflineProtector | Offline violation caching with retry queue, auto-flush on reconnect |
| Log Encryptor | DERLogEncryptor | AES-256-CBC encrypted log storage with compression and auto-rotation |

---

🆕 Detection Modules Upgraded

| Module | Class | Changes |
|--------|-------|---------|
| Speed Detector | DERSpeedDetectorV2 | Complete rewrite: time-based detection, sample window, 4 sensitivity levels |
| Multi Instance | DERMultiInstance | Added VirtualApp detection, sandbox detection, enhanced process filtering |
| Vanguard Value | VanguardValue | Added secondary verification, checksum validation, tamper detection |
| Config Manager | DERConfigManager | Added cloud hot-reload support, diff tools, config validation |

---

⚡ What's New in v2.1.0

| Module | Class | Description |
|--------|-------|-------------|
| CCU Optimizer | DERCCUOptimizer | Dynamic quality scaling based on player count and FPS |
| Consistency Validator | DERConsistencyValidator | Server-client state validation with 5 violation actions |
| False Positive Filter | DERFalsePositiveFilter | Device-tier based false positive reduction |
| Cloud Snapshot | DERCloudSnapshot | Encrypted cloud save sync with conflict resolution |
| Whitelist Manager | DERWhitelistManager | Hardware ID + device fingerprint whitelist |
| Encrypted Logger | DEREncryptedLogger | AES-256-CBC encrypted logging with auto-upload |
| Device Fingerprint | DERDeviceFingerprint | Cross-platform hardware fingerprinting |

---

⚡ Performance Updates (v2.0.0)

| Module | Class | Description |
|--------|-------|-------------|
| Thread Pool | DERThreadPool | High-performance thread pool with priority queues |
| Object Pool | DERObjectPool | Generic object pool reducing GC pressure by 70% |
| Performance Monitor | DERPerformanceMonitor | Real-time FPS, frame time, memory monitoring |

---

✅ Developer Tools (v1.9.0)

| Module | Class | Description |
|--------|-------|-------------|
| Log Viewer | DERLogViewer | View, search, and filter anti-cheat logs |
| Log Exporter | DERLogExporter | Export logs in JSON/CSV/TXT formats |
| Profiler | DERProfiler | Performance analyzer with execution time charts |
| Cheat Simulator | DERCheatSimulator | Simulate 8 cheat types to test detection |

---

✅ Core Features (v1.0-v1.8)

| Module | Class | Description |
|--------|-------|-------------|
| Memory Encryption | VanguardValue | Protects values with fragmentation and honeypots |
| Value Pool | DERPool | Centralized management of protected values |
| Inject Detector | DERInjectDetector | DLL injection, code hooks, HemoLoader, Xposed, Magisk |
| Memory Scanner | DERMemoryScanner | Cheat Engine, GameGuardian, abnormal memory access |
| Multi Instance | DERMultiInstance | Multiple game instance detection |
| VM Detector | DERVMDetector | VMware, VirtualBox, QEMU, Android emulators |
| Network Client | DERNetworkClient | Packet encryption, HMAC, replay prevention |
| Request Signer | DERSigner | HMAC-SHA256 request authentication |
| Heartbeat | DERHeartbeat | Connection monitoring with auto-reconnect |
| Obfuscator | DERObfuscator | Traffic obfuscation (Light/Medium/Heavy) |
| Request Queue | DERRequestQueue | Priority-based queuing with auto-retry |
| Batch Request | DERBatchRequest | Adaptive batch compression |
| Cache Manager | DERCacheManager | TTL cleanup, LRU eviction, encrypted persistence |
| Replay Protection | DERReplayProtector | Nonce + RequestID dual validation |
| Time Sync | DERTimeSync | NTP-style algorithm, HTTPS enforcement |
| Config Manager | DERConfigManager | Load/save configs, presets, validation, diff tools |
| Archive Encryptor | DERArchiveEncryptor | AES-256-GCM encrypted save files |
| Archive Manager | DERArchiveManager | Multi-slot save management with auto-save |
| File Validator | DERFileValidator | SHA256 file integrity verification |
| Debug Detector V2 | DERDebugDetectorV2 | 10 detection methods, 4 protection levels |
| Rollback Detector | DERRollbackDetector | Save file rollback detection |
| Save Limit | DERSaveLimit | Save/load frequency limiting |
| Cloud Validator | DERCloudValidator | Client-side save validation |
| Dashboard | DERDashboard | Visual dashboard with health score |
| Alert Manager | DERAlertManager | Multi-level alerts (console/file/callback/HTTP) |
| Stats Chart | DERStatsChart | Line/Bar/Pie charts for threat statistics |
| Report Exporter | DERReportExporter | JSON/CSV/HTML report export |

---

🚀 Quick Start

1️⃣ Installation

1. Download from Godot Asset Library or copy `addons/DER AntiCheat/` manually
2. Open Project Settings → Plugins and enable DER AntiCheat
3. Restart the editor

---

2️⃣ One-Click Setup (New in v2.3.0)

```gdscript
# Single-player game — basic memory protection + speed hack detection
DERAntiCheat.quick_setup("singleplayer")

# Multiplayer game — add injection detection, anti-debug, save protection
DERAntiCheat.quick_setup("multiplayer")

# Competitive game — enable all 38 modules
DERAntiCheat.quick_setup("competitive")
```

---

3️⃣ In-Game Debug Panel (New in v2.3.0)

· Press Ctrl+Shift+F12 during gameplay to open the debug overlay
· View real-time module status with color indicators
· Enable/disable individual modules at runtime
· Monitor FPS, memory, and violation logs live

---

4️⃣ Speed Detector V2 (v2.2.0)

```gdscript
var speed_detector = DERSpeedDetectorV2.new()
speed_detector.sensitivity = DERSpeedDetectorV2.Sensitivity.HIGH
speed_detector.speed_hack_detected.connect(func(ratio, details):
    print("Speed hack detected! Ratio: ", ratio)
)

func _process(delta):
    speed_detector.process_frame(delta)
```

---

5️⃣ Virtual Position Detector (v2.2.0)

```gdscript
var pos_detector = DERVirtualPosDetector.new()
pos_detector.detection_level = DERVirtualPosDetector.DetectionLevel.STANDARD
pos_detector.max_speed_kmh = 300.0

pos_detector.location_fake_detected.connect(func(details):
    print("GPS spoof detected!")
)

func on_location_update(lat, lon, accuracy):
    pos_detector.update_location(lat, lon, accuracy)
```

---

6️⃣ File Integrity Scanner (v2.2.0)

```gdscript
var integrity = DERFileIntegrity.new()
integrity.scan_mode = DERFileIntegrity.ScanMode.NORMAL
integrity.hash_algorithm = DERFileIntegrity.HashAlgorithm.SHA256

integrity.save_manifest("user://file_manifest.json")
integrity.file_tampered.connect(func(path, expected, current):
    print("File tampered: ", path)
)

integrity.start()
```

---

7️⃣ CCU Optimizer (v2.1.0)

```gdscript
var optimizer = DERCCUOptimizer.new()
optimizer.target_fps = 60
optimizer.max_players = 1000

optimizer.update_fps(Engine.get_frames_per_second())
optimizer.update_player_count(current_players)

optimizer.quality_scaled.connect(func(level):
    print("Quality scaled to: ", optimizer.get_quality_level_name(level))
)
```

---

8️⃣ Consistency Validator (v2.1.0)

```gdscript
var validator = DERConsistencyValidator.new()
validator.max_position_error = 5.0
validator.max_velocity_error = 10.0

validator.update_server_state(player_id, {"position": server_pos, "health": server_hp})
validator.update_local_state(player_id, {"position": local_pos, "health": local_hp})

validator.inconsistency_detected.connect(func(type, local, server):
    print("Inconsistency: ", type)
)
```

---

📊 Performance Comparison

Metric v1.9.0 v2.0.0 v2.2.0 v2.3.0
Memory Usage 200MB 100MB 92MB 90MB
Startup Time 500ms 300ms 260ms 250ms
Scan Lag 50ms 20ms 15ms 12ms
GC Pauses 10ms 3ms 2ms 2ms
Modules Count 28 31 43 43

---

📦 Available Presets

Preset Description Best For
Light 6 modules Single-player games, prototypes
Standard 15 modules Most multiplayer games
Competitive 38 modules Ranked matches, esports, high-value economies

---

🔐 Security Features Summary

Feature v2.0.0 v2.1.0 v2.2.0 v2.3.0
Protection Presets ❌ ❌ ❌ ✅
In-Game Debug Panel ❌ ❌ ❌ ✅
Quick Setup API ❌ ❌ ❌ ✅
Mobile Compatibility ❌ ❌ ❌ ✅
Speed Detector V2 ❌ ❌ ✅ ✅
Virtual Position Detector ❌ ❌ ✅ ✅
File Integrity Scanner ❌ ❌ ✅ ✅
Offline Protector ❌ ❌ ✅ ✅
Log Encryptor ❌ ❌ ✅ ✅
CCU Optimizer ❌ ✅ ✅ ✅
Consistency Validator ❌ ✅ ✅ ✅
False Positive Filter ❌ ✅ ✅ ✅
Cloud Snapshot ❌ ✅ ✅ ✅
Whitelist Manager ❌ ✅ ✅ ✅
Encrypted Logger ❌ ✅ ✅ ✅
Device Fingerprint ❌ ✅ ✅ ✅
Memory Encryption ✅ ✅ ✅ ✅
Thread Pool ✅ ✅ ✅ ✅
Object Pool ✅ ✅ ✅ ✅
Inject Detection ✅ ✅ ✅ ✅
VM Detection ✅ ✅ ✅ ✅
Anti-Debug V2 ✅ ✅ ✅ ✅
Rollback Detection ✅ ✅ ✅ ✅
Save/Load Limit ✅ ✅ ✅ ✅
Dashboard ✅ ✅ ✅ ✅
Alert Manager ✅ ✅ ✅ ✅
Report Exporter ✅ ✅ ✅ ✅

---

📄 License

MIT License — Free for personal and commercial use.

---

Made with ❤️ for the Godot community
