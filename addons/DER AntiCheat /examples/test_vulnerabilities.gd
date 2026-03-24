extends Node2D

# DER AntiCheat v1.5.0 Quick Start Example
# DER AntiCheat v1.5.0 快速开始示例

var pool: DERPool
var logger: DERLogger
var client: DERNetworkClient

func _ready():
    # Initialize / 初始化
    pool = DERPool.new()
    logger = DERLogger.new()
    
    # Create protected values / 创建受保护的数值
    var player_hp = VanguardValue.new(100)
    var player_gold = VanguardValue.new(500)
    var player_name = VanguardValue.new("Hero")
    
    # Store in pool / 存入池子
    pool.set_value("hp", player_hp)
    pool.set_value("gold", player_gold)
    pool.set_value("name", player_name)
    
    # Use values / 使用数值
    print("HP: ", pool.get_value("hp").get_value())
    print("Gold: ", pool.get_value("gold").get_value())
    
    # Modify values / 修改数值
    pool.get_value("hp").set_value(80)
    print("HP after damage: ", pool.get_value("hp").get_value())
    
    # Configuration system example / 配置系统示例
    var config = DERConfigManager.new()
    config.load_config("user://anticheat.json")
    config.set_value("protect_level", 2)
    print("Protect level: ", config.get_value("protect_level"))
    
    # Preset example / 预设示例
    DERConfigPreset.apply_preset(config, DERConfigPreset.PresetType.STRICT)
    print("Applied strict preset / 已应用严格模式预设")
    
    # Create network client for heartbeat and queue examples
    client = DERNetworkClient.new("https://example.com", self)

func _process(delta):
    # Active detection example / 主动检测示例
    var speed_detector = DERSpeedDetector.new()
    var risk = speed_detector.check()
    if risk > 0.5:
        logger.warning("detection", "Speed hack detected! / 检测到加速器！")
    
    # Inject detection example (v1.4.0)
    var inject = DERInjectDetector.new()
    var threats = inject.scan()
    if threats.size() > 0:
        logger.warning("inject", "Injection detected! / 检测到注入！")
    
    # Memory scanner example (v1.4.0)
    var scanner = DERMemoryScanner.new()
    scanner.record_read()
    var scan_threats = scanner.scan()
    if scan_threats.size() > 0:
        logger.warning("memory", "Memory scanner detected! / 检测到内存扫描！")
    
    # VM detector example (v1.4.0)
    var vm = DERVMDetector.new()
    if vm.is_vm():
        logger.warning("vm", "Running in virtual machine! / 运行在虚拟机中！")
    
    # Multi instance example (v1.4.0)
    var multi = DERMultiInstance.new()
    if not multi.is_single_instance():
        logger.warning("multi", "Multiple instances detected! / 检测到多开！")
    
    # Heartbeat example (v1.5.0)
    var heartbeat = DERHeartbeat.new(client, get_tree())
    if not heartbeat.is_online():
        logger.warning("heartbeat", "Connection lost! / 连接断开！")
    
    # Obfuscator example (v1.5.0)
    var obfuscator = DERObfuscator.new()
    obfuscator.set_level(DERObfuscator.ObfuscateLevel.MEDIUM)
    var data = {"x": 100, "y": 200}
    var obfuscated = obfuscator.obfuscate(data)
    
    # Queue example (v1.5.0)
    var queue = DERRequestQueue.new(client, get_tree())
    queue.add("/api/move", data, _on_request_complete)
    
    # Signer example (v1.5.0)
    var signer = DERSigner.new()
    var signed = signer.sign("/api/move", data)

func _on_request_complete(success, response):
    if success:
        print("Request succeeded / 请求成功")
    else:
        print("Request failed / 请求失败")