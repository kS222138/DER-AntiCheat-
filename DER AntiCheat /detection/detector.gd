class_name DERDetector
extends RefCounted

signal threat_detected(threat_type, confidence, data)

var process_monitor
var integrity_check
var memory_guard
var speed_detector
var debugger_detector
var packet_protector
var logger
var detector_list
var last_scan
var scan_interval

func _init(logger_obj = null):
    if logger_obj != null:
        logger = logger_obj
    else:
        var logger_script = preload("../report/logger.gd")
        if logger_script:
            logger = logger_script.new()
    
    detector_list = []
    last_scan = 0
    scan_interval = 5000
    
    _init_detectors()
    
    if logger != null:
        logger.info("detector", "Detectors ready: " + str(detector_list.size()))

func _init_detectors():
    var monitor_script = preload("process_monitor.gd")
    if monitor_script:
        process_monitor = monitor_script.new()
        if process_monitor != null:
            detector_list.append(process_monitor)
    
    var integrity_script = preload("integrity_check.gd")
    if integrity_script:
        integrity_check = integrity_script.new()
        if integrity_check != null:
            detector_list.append(integrity_check)
    
    var memory_script = preload("memory_guard.gd")
    if memory_script:
        memory_guard = memory_script.new()
        if memory_guard != null:
            detector_list.append(memory_guard)
    
    var speed_script = preload("speed_detector.gd")
    if speed_script:
        speed_detector = speed_script.new()
        if speed_detector != null:
            detector_list.append(speed_detector)
    
    var debugger_script = preload("debugger_detector.gd")
    if debugger_script:
        debugger_detector = debugger_script.new()
        if debugger_detector != null:
            detector_list.append(debugger_detector)
    
    var packet_script = preload("packet_protector.gd")
    if packet_script:
        packet_protector = packet_script.new()

func scan_all():
    var results = {}
    var current_time = Time.get_ticks_usec()
    
    if detector_list == null or detector_list.size() == 0:
        return results
    
    if current_time - last_scan < scan_interval:
        return results
    
    for detector in detector_list:
        if detector != null and detector.has_method("check"):
            var risk = detector.check()
            if risk != null and risk > 0:
                var name = "unknown"
                if detector.get_script() != null:
                    name = detector.get_script().get_global_name()
                results[name] = {
                    "risk": risk,
                    "time": current_time
                }
                
                if risk > 0.5:
                    threat_detected.emit(name, risk, {})
                    if logger != null:
                        logger.warning("detector", "Threat: " + name + " risk: " + str(risk))
    
    last_scan = current_time
    return results

func register_object(obj, name_str = ""):
    if memory_guard != null and memory_guard.has_method("track_allocation"):
        memory_guard.track_allocation(obj, name_str)

func unregister_object(obj):
    if memory_guard != null and memory_guard.has_method("track_free"):
        memory_guard.track_free(obj)

func verify_object(obj):
    if memory_guard != null and memory_guard.has_method("verify_access"):
        return memory_guard.verify_access(obj)
    return true

func add_critical_file(file_path):
    if integrity_check != null and integrity_check.has_method("add_file_to_monitor"):
        integrity_check.add_file_to_monitor(file_path)

func encrypt_data(data):
    if packet_protector != null and packet_protector.has_method("encrypt_packet"):
        return packet_protector.encrypt_packet(data)
    return data

func decrypt_data(data):
    if packet_protector != null and packet_protector.has_method("decrypt_packet"):
        return packet_protector.decrypt_packet(data)
    return data

func get_report():
    return {
        "last_scan": last_scan,
        "active": detector_list.size() if detector_list != null else 0,
        "threats": []
    }

func get_process_monitor():
    return process_monitor

func get_integrity_check():
    return integrity_check

func get_memory_guard():
    return memory_guard

func get_speed_detector():
    return speed_detector

func get_debugger_detector():
    return debugger_detector

func get_packet_protector():
    return packet_protector