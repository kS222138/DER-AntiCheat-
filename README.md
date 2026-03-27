🛡️ DER AntiCheat

Version: 1.6.0
Godot Version: 4.6+
License: MIT

---

📦 What's New in v1.6.0

✅ Security Enhancement System

Module Class Description
Archive Encryptor DERArchiveEncryptor AES-256-GCM encrypted save files. Prevents save editors and tampering.
Archive Manager DERArchiveManager Multi-slot save management with auto-save, import/export, and integrity checks.
File Validator DERFileValidator SHA256 file integrity verification. Detects game file tampering.
Debug Detector V2 DERDebugDetectorV2 Advanced anti-debugging with 10 detection methods, 4 protection levels, and honeypot system.

---

✅ Existing Features (v1.0-v1.5)

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
Replay Protection DERReplayProtector Nonce + RequestID双重验证双重 validation
Time Sync DERTimeSync NTP-style algorithm, HTTPS enforcement
Configuration DERConfigManager Load/save configs, presets, validation, diff tools

---

🚀 Quick Start

1️⃣ Installation

1. Download from Godot Asset Library or copy the addons/DER AntiCheat folder manually.
2. Open Project Settings → Plugins and enable DER AntiCheat.
3. Restart the editor.

---

2️⃣ Protect Game Values

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

4️⃣ Save File Encryption (New in v1.6.0)

```gdscript
# Create encrypted archive manager
var archive = DERArchiveManager.new("your_secret_password")
archive.max_slots = 10

# Save game data
var save_data = {
    "level": 10,
    "hp": 100,
    "inventory": ["sword", "shield"]
}
archive.save(0, save_data)

# Load game data
var loaded = archive.load(0)
if loaded:
    print("Game loaded: ", loaded)

# Export save (for sharing)
archive.export_slot(0, "user://backup.json", DERArchiveManager.ExportMode.DECRYPTED)

# Auto-save every 30 seconds
archive.auto_save = true
archive.interval = 30.0
```

---

5️⃣ File Integrity Verification (New in v1.6.0)

```gdscript
# Create file validator
var validator = DERFileValidator.new()
validator.hash_type = DERFileValidator.HashType.SHA256

# Add critical files to verify
validator.add_file("res://game/main.tscn", "expected_sha256_hash")
validator.add_file("res://game/player.gd", "expected_sha256_hash")

# Verify all files
var results = validator.verify_all()
if results.values().has(false):
    print("Game files have been tampered with!")
    get_tree().quit()
```

---

6️⃣ Anti-Debug Protection (New in v1.6.0)

```gdscript
# Create debug detector
var debug = DERDebugDetectorV2.new()
debug.level = DERDebugDetectorV2.Level.HEAVY
debug.auto_quit = true
debug.verbose = true

# Start monitoring
debug.start()

# Connect signals
debug.detected.connect(func(type, details):
    print("Debugger detected: ", type)
    # Send report to server
)

debug.triggered.connect(func():
    print("Honeypot triggered - sending fake data")
)
```

---

7️⃣ Use Detection System

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

8️⃣ Use Network Client

```gdscript
# Create network client
var client = DERNetworkClient.new("https://api.yourgame.com", self)

# Connect to server
client.handshake(func(success, result):
    if success:
        print("Connected to server")
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

9️⃣ Use Network Enhancement

```gdscript
# Request signing
var signer = DERSigner.new()
var signed = signer.sign("/api/move", {"x": 100, "y": 200})

# Heartbeat monitoring (auto-reconnect)
var heartbeat = DERHeartbeat.new(client, get_tree())
heartbeat.start()
heartbeat.connection_lost.connect(func(): print("Connection lost!"))

# Traffic obfuscation
var obf = DERObfuscator.new()
obf.set_level(DERObfuscator.ObfuscateLevel.MEDIUM)
var encrypted = obf.obfuscate({"data": "secret"})

# Request queue (priority + retry)
var queue = DERRequestQueue.new(client, get_tree())
queue.add("/api/score", {"score": 100}, _on_score_sent, DERRequestQueue.Priority.HIGH)

# Batch request (combine multiple requests)
var batcher = DERBatchRequest.new(client, get_tree())
batcher.set_mode(DERBatchRequest.BatchMode.ADAPTIVE)
batcher.add("/api/log", {"event": "move"})
batcher.add("/api/log", {"event": "shoot"})
batcher.flush()
```

---

🔟 Use Configuration System

```gdscript
# Create config manager
var config = DERConfigManager.new()

# Load existing config
if config.load_config("user://anticheat.json"):
    print("Config loaded")
else:
    config.set_value("protect_level", 2)
    config.set_value("enable_detection", true)

# Apply a preset
DERConfigPreset.apply_preset(config, DERConfigPreset.PresetType.STRICT)

# Listen to changes
config.add_listener("protect_level", func(key, old, new):
    print("Protection level changed: %s -> %s" % [old, new])
)
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

Feature v1.5.0 v1.6.0
Memory Encryption ✅ ✅
Network Protection ✅ ✅
Inject Detection ✅ ✅
VM Detection ✅ ✅
Configuration System ✅ ✅
Archive Encryption ❌ ✅
File Integrity ❌ ✅
Anti-Debug V2 ❌ ✅
Honeypot System ❌ ✅

---

📄 License

MIT License — Free for personal and commercial use.
You may use, modify, and distribute this plugin freely.
The only requirement is to retain the copyright notice.

---

Made with ❤️ for the Godot community