🛡️ DER AntiCheat

Version: 1.8.0
Godot Version: 4.6+
License: MIT

---

📦 What's New in v1.8.0

✅ Report System

Module Class Description
Dashboard DERDashboard Visual dashboard showing protected values, threat statistics, and health score
Alert Manager DERAlertManager Multi-level alerts (INFO/WARNING/HIGH/CRITICAL) with console, file, callback, and HTTP output
Stats Chart DERStatsChart Visual charts (Line/Bar/Pie) for threat statistics and trends
Report Exporter DERReportExporter Export reports in JSON/CSV/HTML formats with auto-export timer

---

✅ Existing Features (v1.0-v1.7)

Module Class Description
Memory Encryption VanguardValue Protects integers, floats, booleans, strings with fragmentation and honeypots
Value Pool DERPool Centralized management of protected values
Inject Detector DERInjectDetector DLL injection, code hooks, HemoLoader, Xposed, Magisk
Memory Scanner DERMemoryScanner Cheat Engine, GameGuardian, abnormal memory access
Multi Instance Detector DERMultiInstance Multiple game instances (process list, file lock, port)
VM Detector DERVMDetector VMware, VirtualBox, QEMU, Android emulators
Network Protection DERNetworkClient Packet encryption, HMAC, replay prevention, WebSocket
Request Signer DERSigner HMAC-SHA256 signature for request authentication
Heartbeat DERHeartbeat Connection monitoring with auto-reconnect
Obfuscator DERObfuscator Traffic obfuscation (Light/Medium/Heavy)
Request Queue DERRequestQueue Priority-based queuing with auto-retry
Batch Request DERBatchRequest Adaptive batch compression
Cache System DERCacheManager TTL-based cleanup, LRU eviction, encrypted persistence
Replay Protection DERReplayProtector Nonce + RequestID dual validation, HMAC-SHA256
Time Sync DERTimeSync NTP-style algorithm, HTTPS enforcement
Configuration DERConfigManager Load/save configs, presets, validation, diff tools
Archive Encryptor DERArchiveEncryptor AES-256-GCM encrypted save files
Archive Manager DERArchiveManager Multi-slot save management with auto-save
File Validator DERFileValidator SHA256 file integrity verification
Debug Detector V2 DERDebugDetectorV2 Advanced anti-debugging with 10 detection methods, 4 protection levels
Rollback Detector DERRollbackDetector Detects save file rollback (SL cheating)
Save Limit DERSaveLimit Limits save/load frequency to prevent SL spamming
Cloud Validator DERCloudValidator Client-side save validation against cloud hash

---

🚀 Quick Start

1️⃣ Installation

1. Download from Godot Asset Library or copy the addons/DER AntiCheat folder manually.
2. Open Project Settings → Plugins and enable DER AntiCheat.
3. Restart the editor.

---

2️⃣ Protect Game Values

```gdscript
var pool = DERPool.new()
var player_hp = VanguardValue.new(100)
pool.set_value("hp", player_hp)

func take_damage(amount):
    var current = pool.get_value("hp").get_value()
    pool.get_value("hp").set_value(current - amount)
```

---

3️⃣ Scan for Cheats

```gdscript
var threats = pool.scan_for_threats()
if threats.size() > 0:
    print("Cheat detected!")
```

---

4️⃣ Dashboard & Reports (New in v1.8.0)

```gdscript
# Create dashboard
var dashboard = DERDashboard.new()
dashboard.setup(alert_manager)

# Create alert manager
var alert = DERAlertManager.new()
alert.alert(DERAlertManager.AlertLevel.WARNING, "Suspicious activity detected")

# Export report
var exporter = DERReportExporter.new()
exporter.set_data_source(dashboard)
exporter.export_report("html")
```

---

5️⃣ SL Protection

```gdscript
var rollback = DERRollbackDetector.new()
var save_limit = DERSaveLimit.new()

func on_game_save(slot: int):
    save_limit.record_save(slot)
    rollback.record_save(slot, Time.get_unix_time_from_system(), game_version)

func on_game_load(slot: int):
    if not save_limit.can_load(slot):
        return
    save_limit.record_load(slot)
    if rollback.is_suspicious(slot):
        print("Rollback detected!")
```

---

6️⃣ Cloud Save Validation

```gdscript
var cloud = DERCloudValidator.new("https://api.yourserver.com", "player_id")
cloud.validate(slot, save_data, func(success, reason):
    if not success:
        print("Save tampered!")
)
```

---

7️⃣ Save File Encryption

```gdscript
var archive = DERArchiveManager.new("your_secret_password")
archive.save(0, {"level": 10, "hp": 100})
var loaded = archive.load(0)
```

---

8️⃣ File Integrity Verification

```gdscript
var validator = DERFileValidator.new()
validator.add_file("res://game/main.tscn", "expected_hash")
validator.verify_all()
```

---

9️⃣ Anti-Debug Protection

```gdscript
var debug = DERDebugDetectorV2.new()
debug.level = DERDebugDetectorV2.Level.HEAVY
debug.start()
debug.detected.connect(func(type, details): print("Debugger detected!"))
```

---

🔟 Use Detection System

```gdscript
var inject = DERInjectDetector.new()
var scanner = DERMemoryScanner.new()
var multi = DERMultiInstance.new()
var vm = DERVMDetector.new()
```

---

📦 Available Presets

Preset Description Best For
Development Detection disabled, easy debugging Development only
Testing Low intensity detection QA testing
Production Standard protection Most games
Light Low overhead, high performance Low-end devices
Balanced Balanced security & performance Mid-range devices
Strict Maximum security Competitive games

---

🔐 Security Features Summary

Feature v1.7.0 v1.8.0
Memory Encryption ✅ ✅
Network Protection ✅ ✅
Inject Detection ✅ ✅
VM Detection ✅ ✅
Configuration System ✅ ✅
Archive Encryption ✅ ✅
File Integrity ✅ ✅
Anti-Debug V2 ✅ ✅
Honeypot System ✅ ✅
Rollback Detection ✅ ✅
Save/Load Limit ✅ ✅
Cloud Validation ✅ ✅
Dashboard ❌ ✅
Alert Manager ❌ ✅
Stats Chart ❌ ✅
Report Exporter ❌ ✅

---

📄 License

MIT License — Free for personal and commercial use.

---

Made with ❤️ for the Godot community