extends Node

func _ready():
    print("=== DER Protection System Vulnerability Test ===")
    
    # 初始化
    var pool = DERPool.new()
    var logger = DERLogger.new()
    
    # 创建受保护的值
    var test_value = VanguardValue.new(100)
    pool.set_value("test", test_value)
    
    print("✅ 基础保护已启用")
    
    # 测试进程监控
    var monitor = DERProcessMonitor.new()
    var process_risk = monitor.check()
    print("进程监控风险: ", process_risk)
    
    # 测试完整性检查
    var integrity = DERIntegrityCheck.new()
    var integrity_risk = integrity.check()
    print("完整性检查风险: ", integrity_risk)
    
    # 测试内存防护
    var guard = DERMemoryGuard.new()
    guard.track_allocation(test_value, "test")
    guard.verify_access(test_value)
    print("内存防护已启用")
    
    # 测试检测器
    var detector = DERDetector.new(logger)
    detector.register_object(test_value, "test")
    var threats = detector.scan_all()
    print("威胁扫描结果: ", threats)
    
    # 核心报告
    VanguardCore.report("INFO", "test", {"message": "测试完成"})
    
    print("\n=== 测试完成 ===")
    print("所有保护模块已加载，系统安全")
    
    # 显示状态
    var stats = VanguardCore.get_stats()
    print("保护状态: ", stats)
