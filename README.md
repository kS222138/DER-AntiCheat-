🛡️ DER AntiCheat

Version: 1.7.0
Godot Version: 4.6+
License: MIT

---

📦 What's New in v1.7.0

✅ SL Protection & Cloud Validation System

Module Class Description
Rollback Detector DERRollbackDetector Detects save file rollback (loading older saves). Prevents SL (Save/Load) cheating.
Save Limit DERSaveLimit Limits save/load frequency. Prevents rapid SL spamming.
Cloud Validator DERCloudValidator Client-side save validation against cloud hash. Detects save tampering.

---

✅ Existing Features (v1.0-v1.6)

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

4️⃣ SL Protection (New in v1.7.0)

```gdscript
# Create rollback detector
var rollback = DERRollbackDetector.new()
rollback.enable_timestamp_check = true
rollback.enable_version_check = true

# Create save limiter
var save_limit = DERSaveLimit.new()
save_limit.max_saves_per_minute = 10
save_limit.max_loads_per_minute = 10
save_limit.cooldown_seconds = 2.0

# Record save/load operations
func on_game_save(slot: int):
    save_limit.record_save(slot)
    rollback.record_save(slot, Time.get_unix_time_from_system(), game_version)

func on_game_load(slot: int):
    if not save_limit.can_load(slot):
        print("Loading blocked - too frequent!")
        return
    save_limit.record_load(slot)
    
    if rollback.is_suspicious(slot):
        print("Rollback detected - loading older save!")
        # Handle accordingly

# Detect cheat attempts
save_limit.cheat_attempt_detected.connect(func(slot, attempts):
    print("Cheat attempt detected on slot ", slot, " attempts: ", attempts)
    # Report to server
)
```

---

5️⃣ Cloud Save Validation (New in v1.7.0)

```gdscript
# Create cloud validator
var cloud = DERCloudValidator.new("https://api.yourserver.com", "player_id")
cloud.auto_repair = false
cloud.max_retries = 3

# Validate save file
func on_save_game(slot: int, save_data: Dictionary):
    # Upload to cloud
    cloud.upload(slot, save_data)
    
    # Validate after upload
    cloud.validate(slot, save_data, func(success, reason):
        if success:
            print("Save validated successfully")
        else:
            print("Save validation failed: ", reason)
            # Save may be corrupted or tampered
    )

# Check cloud hash
cloud.fetch_cloud_hash(slot, func(hash, success):
    if success:
        print("Cloud hash: ", hash)
)
```

---

6️⃣ Save File Encryption

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
```

---

7️⃣ File Integrity Verification

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

8️⃣ Anti-Debug Protection

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
)

debug.triggered.connect(func():
    print("Honeypot triggered - sending fake data")
)
```

---

9️⃣ Use Detection System

```gdscript
# Inject detection
var inject = DERInjectDetector.new()
inject.set_threat_callback(func(threat):
    print("Inject threat: ", threat.to_string())
)

# Memory scanner
var scanner = DERMemoryScanner.new()
scanner.start_continuous_scan(get_tree())

# Multi-instance detection
var multi = DERMultiInstance.new()
if not multi.is_single_instance():
    print("Multiple instances detected!")

# VM detection
var vm = DERVMDetector.new()
if vm.is_vm():
    print("Running in: ", vm.get_stats().type)
```

---

🔟 Use Network Client

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

Feature v1.6.0 v1.7.0
Memory Encryption ✅ ✅
Network Protection ✅ ✅
Inject Detection ✅ ✅
VM Detection ✅ ✅
Configuration System ✅ ✅
Archive Encryption ✅ ✅
File Integrity ✅ ✅
Anti-Debug V2 ✅ ✅
Honeypot System ✅ ✅
Rollback Detection ❌ ✅
Save/Load Limit ❌ ✅
Cloud Validation ❌ ✅

---

📄 License

MIT License — Free for personal and commercial use.
You may use, modify, and distribute this plugin freely.
The only requirement is to retain the copyright notice.

---

Made with ❤️ for the Godot community