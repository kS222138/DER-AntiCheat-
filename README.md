# 🛡️ DER AntiCheat

**Version:** 1.5.0  
**Godot Version:** 4.6+  
**License:** MIT  

---

## 📦 What's New in v1.5.0

### ✅ Network Enhancement System

| Module | Class | Description |
|--------|-------|-------------|
| **Request Signer** | `DERSigner` | Adds HMAC-SHA256 signature to every request. Prevents伪造攻击 (forgery attacks). |
| **Heartbeat** | `DERHeartbeat` | Monitors connection status. Automatically reconnects when disconnected. |
| **Obfuscator** | `DERObfuscator` | Scrambles network traffic. 3 levels: Light / Medium / Heavy. |
| **Request Queue** | `DERRequestQueue` | Queues requests with priorities. Automatically retries on failure. |
| **Batch Request** | `DERBatchRequest` | Combines multiple requests into one. Saves bandwidth with compression. |

### ✅ Enhanced Detection System (from v1.4.0)

| Module | Class | Detection Target |
|--------|-------|------------------|
| **Inject Detector** | `DERInjectDetector` | DLL injection, code hooks, HemoLoader, Xposed, Magisk |
| **Memory Scanner** | `DERMemoryScanner` | Cheat Engine, GameGuardian, abnormal memory access |
| **Multi Instance Detector** | `DERMultiInstance` | Multiple game instances (process list, file lock, port) |
| **VM Detector** | `DERVMDetector` | VMware, VirtualBox, QEMU, Android emulators (Bluestacks, Nox, etc.) |

### ✅ Core Features (from v1.0-v1.3)

| Module | Class | Description |
|--------|-------|-------------|
| **Memory Encryption** | `VanguardValue` | Protects integers, floats, booleans, strings with fragmentation and honeypots |
| **Value Pool** | `DERPool` | Centralized management of protected values |
| **Network Protection** | `DERNetworkClient` | Packet encryption, HMAC, replay prevention, WebSocket |
| **Cache System** | `DERCacheManager` | TTL-based cleanup, LRU eviction, encrypted persistence |
| **Replay Protection** | `DERReplayProtector` | Nonce + RequestID双重验证双重 validation, HMAC-SHA256 |
| **Time Sync** | `DERTimeSync` | NTP-style algorithm, HTTPS enforcement, certificate pinning |
| **Configuration** | `DERConfigManager` | Load/save configs, presets, validation, diff tools |

---

## 🚀 Quick Start

### 1️⃣ Installation

1. Download from **Godot Asset Library** or copy the `addons/DER AntiCheat` folder manually.
2. Open **Project Settings → Plugins** and enable **DER AntiCheat**.
3. Restart the editor.

---

### 2️⃣ Protect Game Values

```gdscript
# Create a value pool
var pool = DERPool.new()

# Create protected values
var player_hp = VanguardValue.new(100)
var player_gold = VanguardValue.new(500)

# Register them
pool.set_value("hp", player_hp)
pool.set_value("gold", player_gold)

# Use them (always use get_value() and set_value())
func take_damage(amount):
    var current = pool.get_value("hp").get_value()
    pool.get_value("hp").set_value(current - amount)

func add_gold(amount):
    var current = pool.get_value("gold").get_value()
    pool.get_value("gold").set_value(current + amount)
```

---

3️⃣ Scan for Cheats

```gdscript
# Check if any protected values have been tampered with
var threats = pool.scan_for_threats()
if threats.size() > 0:
    print("Cheat detected!")
    for threat in threats:
        print("Type: ", threat.type)
        print("Risk: ", threat.risk)
```

---

4️⃣ Auto-Scan (every 5 seconds)

```gdscript
func _ready():
    var timer = Timer.new()
    timer.wait_time = 5.0
    timer.timeout.connect(_auto_scan)
    add_child(timer)
    timer.start()

func _auto_scan():
    var threats = pool.scan_for_threats()
    if threats.size() > 0:
        print("Cheating detected! Taking action...")
        # Add your own punishment logic here (e.g., kick player, send to server)
```

---

5️⃣ Use Detection System

```gdscript
# Inject detection (DLL injection, HemoLoader, etc.)
var inject = DERInjectDetector.new()
inject.set_threat_callback(func(threat):
    print("Inject threat: ", threat.to_string())
)

# Memory scanner (Cheat Engine, GameGuardian)
var scanner = DERMemoryScanner.new()
scanner.start_continuous_scan(get_tree())

# Multi-instance detection
var multi = DERMultiInstance.new()
if not multi.is_single_instance():
    print("Multiple instances detected! This can be used for cheating.")

# VM/Emulator detection
var vm = DERVMDetector.new()
if vm.is_vm():
    print("Running in: ", vm.get_stats().type)
```

---

6️⃣ Use Configuration System

```gdscript
# Create config manager
var config = DERConfigManager.new()

# Load existing config (or create default)
if config.load_config("user://anticheat.json"):
    print("Config loaded")
else:
    # Set default values
    config.set_value("protect_level", 2)
    config.set_value("enable_detection", true)
    config.save_config()

# Apply a preset
DERConfigPreset.apply_preset(config, DERConfigPreset.PresetType.STRICT)

# Listen to changes
config.add_listener("protect_level", func(key, old, new):
    print("Protection level changed: %s -> %s" % [old, new])
)

# Auto-save when values change
config.set_auto_save(true)
```

---

7️⃣ Use Network Client

```gdscript
# Create network client
var client = DERNetworkClient.new("https://api.yourgame.com", self)

# Optional configuration
client.set_debug_mode(true)
client.set_compression_level(CompressionLevel.ADAPTIVE)

# Connect to server
client.handshake(func(success, result):
    if success:
        print("Connected to server")
        print("Session key: ", client.get_protector().get_session_key())
    else:
        print("Connection failed: ", result)
)

# Send encrypted data
func send_score(score):
    client.send("/api/score", {"score": score}, func(success, result):
        if success:
            print("Score uploaded")
        else:
            print("Upload failed: ", result)
    )
```

---

8️⃣ Use Network Enhancement (v1.5.0)

```gdscript
# Request signing (prevents伪造 attacks)
var signer = DERSigner.new()
var signed = signer.sign("/api/move", {"x": 100, "y": 200})

# Heartbeat monitoring (auto-reconnect)
var heartbeat = DERHeartbeat.new(client, get_tree())
heartbeat.start()
heartbeat.connection_lost.connect(func(): print("Connection lost! Entering offline mode."))
heartbeat.connection_restored.connect(func(): print("Connection restored!"))

# Traffic obfuscation (hide your data from packet sniffers)
var obf = DERObfuscator.new()
obf.set_level(DERObfuscator.ObfuscateLevel.MEDIUM)
var encrypted = obf.obfuscate({"data": "secret"})

# Request queue (priority + retry)
var queue = DERRequestQueue.new(client, get_tree())
queue.set_max_concurrent(3)  # Send up to 3 requests at once
queue.add("/api/score", {"score": 100}, _on_score_sent, DERRequestQueue.Priority.HIGH)

# Batch request (combine multiple requests)
var batcher = DERBatchRequest.new(client, get_tree())
batcher.set_mode(DERBatchRequest.BatchMode.ADAPTIVE)
batcher.add("/api/log", {"event": "move"})
batcher.add("/api/log", {"event": "shoot"})
batcher.flush()  # Send all at once
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

📄 License

MIT License — Free for personal and commercial use.
You may use, modify, and distribute this plugin freely.
The only requirement is to retain the copyright notice.

---

Made with ❤️ for the Godot community
