# 🛡️ DER AntiCheat

**Version:** 1.4.0  
**Godot Version:** 4.6+  
**License:** MIT  

---

## 📦 What's New in v1.4.0

### ✅ Enhanced Detection System
- **Inject Detector** (`DERInjectDetector`) - Detect DLL injection, code hooks, script injection (HemoLoader), memory patches, and framework hooks (Xposed/Magisk)
- **Memory Scanner** (`DERMemoryScanner`) - Detect Cheat Engine, GameGuardian, memory scan patterns, and abnormal access rates
- **Multi Instance Detector** (`DERMultiInstance`) - Prevent game from being opened multiple times via process list, file lock, and port detection
- **VM Detector** (`DERVMDetector`) - Detect virtual machines (VMware, VirtualBox, QEMU, KVM) and Android emulators (Bluestacks, Nox, LDPlayer, MEmu)

### ✅ Core Features (from v1.0-v1.3)
- **Memory Encryption** (`VanguardValue`) - Protect integers, floats, booleans, strings with fragmentation and honeypots
- **Value Pool** (`DERPool`) - Centralized management of protected values
- **Network Protection** - Packet encryption, HMAC signatures, replay prevention, WebSocket, resume downloads
- **Cache System** (`DERCacheManager`) - TTL-based auto cleanup, LRU eviction, thread-safe, encrypted persistence
- **Replay Protection** (`DERReplayProtector`) - Nonce + RequestID双重验证双重 validation, HMAC-SHA256
- **Time Synchronization** (`DERTimeSync`) - NTP-style algorithm, HTTPS enforcement, certificate pinning
- **Configuration System** - Manager, diff, preset, template, validator with auto-save and hot-reload

---

## 🚀 Quick Start

### 1. Installation
```bash
# Download from Asset Library or copy the addons/ folder
# Enable plugin in Project Settings
```

2. Protect Game Values

```gdscript
var pool = DERPool.new()
var player_hp = VanguardValue.new(100)
pool.set_value("hp", player_hp)

func take_damage(amount):
    var current = pool.get_value("hp").get_value()
    pool.get_value("hp").set_value(current - amount)
```

3. Scan for Cheats

```gdscript
func check_for_cheats() -> bool:
    var threats = pool.scan_for_threats()
    if threats.size() > 0:
        print("Cheat detected!")
        for threat in threats:
            print("Type: ", threat.type)
            print("Risk: ", threat.risk)
        return true
    return false
```

4. Auto-Scan (every 5 seconds)

```gdscript
func _ready():
    var timer = Timer.new()
    timer.wait_time = 5.0
    timer.timeout.connect(_on_scan_timer)
    add_child(timer)
    timer.start()

func _on_scan_timer():
    if check_for_cheats():
        print("Cheating detected! Taking action...")
```

5. Detection System (New in v1.4.0)

```gdscript
# Inject detection
var inject = DERInjectDetector.new()
inject.set_threat_callback(func(threat):
    print("Inject threat: ", threat.to_string())
)

# Memory scanner
var scanner = DERMemoryScanner.new()
scanner.start_continuous_scan(get_tree())

# Multi instance
var multi = DERMultiInstance.new()
if not multi.is_single_instance():
    print("Multiple instances detected!")

# VM detection
var vm = DERVMDetector.new()
if vm.is_vm():
    print("Running in: ", vm.get_stats().type)
```

6. Configuration System

```gdscript
var config = DERConfigManager.new()
config.load_config("user://anticheat.json")
config.set_value("protect_level", 2)
DERConfigPreset.apply_preset(config, DERConfigPreset.PresetType.STRICT)
config.set_auto_save(true)
```

7. Network Client Setup

```gdscript
var client = DERNetworkClient.new("https://api.yourgame.com", self)
client.set_debug_mode(true)
client.set_compression_level(CompressionLevel.ADAPTIVE)
client.handshake(func(success, result):
    if success:
        print("Connected to server")
)
```

---

📦 Available Presets

Preset Description Use Case
Development Disable detection, easy debugging Development only
Testing Low intensity detection QA testing
Production Standard protection Most games
Light Low overhead, high performance Low-end devices
Balanced Balanced security & performance Mid-range devices
Strict Maximum security Competitive games

---

📄 License

MIT License — Free for personal and commercial use.

---

Made with ❤️ for the Godot community