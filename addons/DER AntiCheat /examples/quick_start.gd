extends Node2D

# DER Protection System 快速开始示例

var pool: DERPool
var logger: DERLogger

func _ready():
    # 初始化
    pool = DERPool.new()
    logger = DERLogger.new()
    
    # 创建受保护的数值
    var player_hp = DERInt.new(100)
    var player_gold = DERInt.new(500)
    var player_name = DERString.new("Hero")
    
    # 存入池子
    pool.set_value("hp", player_hp)
    pool.set_value("gold", player_gold)
    pool.set_value("name", player_name)
    
    # 使用数值
    print("HP: ", pool.get_value("hp").get_value())
    print("Gold: ", pool.get_value("gold").get_value())
    
    # 修改数值
    pool.get_value("hp").set_value(80)
    print("HP after damage: ", pool.get_value("hp").get_value())

func _process(delta):
    # 主动检测示例
    var speed_detector = DERSpeedDetector.new()
    var risk = speed_detector.check()
    if risk > 0.5:
        logger.warning("detection", "检测到加速器！")
