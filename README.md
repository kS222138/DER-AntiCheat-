# 🛡️ DER AntiCheat

**Version:** 1.3.0  
**Godot Version:** 4.6+  
**License:** MIT  

---

## 📦 What's New in v1.3.0

### ✅ Configuration System
- **Config Manager** (`DERConfigManager`) - Load, save, and manage configurations with auto-save
- **Config Diff** (`DERConfigDiff`) - Compare configurations with deep recursion and array modes
- **Config Preset** (`DERConfigPreset`) - 7 ready-to-use presets (Development, Testing, Production, Light, Balanced, Strict)
- **Config Template** (`DERConfigTemplate`) - Reusable configuration templates with import/export
- **Config Validator** (`DERConfigValidator`) - Validate configurations with custom rules and auto-fix

### ✅ Core Features (from v1.0-v1.2)
- **Memory Encryption** (`VanguardValue`) - Protect integers, floats, booleans, strings with fragmentation and honeypots
- **Value Pool** (`DERPool`) - Centralized management of protected values
- **Detectors** - Anti-debug, memory scanner, speed hack, integrity checks
- **Network Protection** - Packet encryption, HMAC signatures, replay prevention, WebSocket, resume downloads
- **Cache System** (`DERCacheManager`) - TTL-based auto cleanup, LRU eviction, thread-safe, encrypted persistence
- **Replay Protection** (`DERReplayProtector`) - Nonce + RequestID双重验证双重 validation, HMAC-SHA256
- **Time Synchronization** (`DERTimeSync`) - NTP-style algorithm, HTTPS enforcement, certificate pinning

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
        print("⚠️ Cheat detected!")
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

5. Configuration System (New in v1.3.0)

```gdscript
# Create config manager
var config = DERConfigManager.new()

# Load configuration
if config.load_config("user://anticheat.json"):
    print("Config loaded")

# Get/Set values
config.set_value("protect_level", 2)
var level = config.get_value("protect_level", 1)

# Apply preset
DERConfigPreset.apply_preset(config, DERConfigPreset.PresetType.STRICT)

# Listen to changes
config.add_listener("protect_level", func(key, old, new):
    print("Protection level changed: %s -> %s" % [old, new])
)

# Auto save
config.set_auto_save(true)

# Compare configurations
var diff = DERConfigDiff.new()
var diffs = diff.compare_files("old.json", "new.json")
print(diff.generate_report(diffs))

# Validate configuration
var validator = DERConfigValidator.new()
if not validator.validate_config(config.get_all(), true):
    print("Config has errors, auto-fixed")
```

6. Network Client Setup

```gdscript
var client = DERNetworkClient.new("https://api.yourgame.com", self)

# Optional configuration
client.set_debug_mode(true)
client.set_compression_level(CompressionLevel.ADAPTIVE)

# Connect to server
client.handshake(func(success, result):
    if success:
        print("✅ Connected to server")
        print("Session key: ", client.get_protector().get_session_key())
    else:
        print("❌ Connection failed: ", result)
)
```

7. Send Encrypted Data

```gdscript
func send_player_position(x, y):
    var data = {
        "x": x,
        "y": y,
        "timestamp": Time.get_unix_time_from_system()
    }
    client.send("/api/player/move", data, func(success, result):
        if success:
            print("✅ Position updated")
        else:
            print("❌ Move failed: ", result)
    )

# Send with priority (bypass rate limits)
func send_critical_action(action):
    client.send_data_with_priority("/api/combat/action", action,
        RequestPriority.CRITICAL,
        func(success, result):
            if success:
                print("✅ Critical action sent")
    )
```

8. WebSocket for Real-time Communication

```gdscript
func connect_to_chat():
    client.ws_connect("/chat", func(success, ws):
        if success:
            print("✅ WebSocket connected")
            client.ws_send("/chat", {
                "type": "join",
                "username": "Player1"
            })
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