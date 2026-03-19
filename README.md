# 🛡️ DER AntiCheat

**Version:** 1.2.0  
**Godot Version:** 4.6+  
**License:** MIT  

---

## 📦 What's New in v1.2.0

### ✅ Cache System (`DERCacheManager`)
- TTL-based auto cleanup
- LRU eviction strategy (expired first, then least recently used)
- Thread-safe (Mutex protected)
- Batch operations (`get_many` / `set_many`)
- Optional encrypted persistence (`save_to_file` / `load_from_file`)
- Full statistics (hit ratio / evictions / encryption status)

### ✅ Replay Protection System (`DERReplayProtector`)
- Replay attack prevention (Nonce + RequestID双重验证)
- Time window validation (default 60 seconds)
- HMAC-SHA256 signature verification
- Cryptographically secure random numbers (Crypto)
- Auto cleanup of expired nonces
- Batch validation interface

### ✅ Time Synchronization System (`DERTimeSync`)
- NTP-style time synchronization algorithm
- HTTPS enforcement (prevents MITM attacks)
- Optional certificate pinning
- Optional request signing (HMAC-SHA256)
- Latency sampling (keeps 70% lowest latency samples)
- Median offset calculation
- Security status monitoring

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

5. Network Client Setup

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

6. Send Encrypted Data

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

7. WebSocket for Real-time Communication

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

📄 License

MIT License — Free for personal and commercial use.

---

Made with ❤️ for the Godot community
