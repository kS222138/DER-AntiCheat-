extends Node
class_name DERCheatSimulator

enum CheatType {
    MEMORY_EDIT = 0,
    DEBUGGER_ATTACH = 1,
    FILE_TAMPER = 2,
    REPLAY_ATTACK = 3,
    SPEED_HACK = 4,
    INJECTION = 5,
    SAVE_ROLLBACK = 6,
    SAVE_SPAM = 7
}

signal cheat_simulated(type: CheatType, success: bool)
signal cheat_detected(type: CheatType, detection: Dictionary)

var _pool = null
var _detector = null
var _archive = null
var _save_limit = null
var _rollback = null
var _file_validator = null

func setup(pool, detector, file_validator = null, archive = null, save_limit = null, rollback = null):
    _pool = pool
    _detector = detector
    _file_validator = file_validator
    _archive = archive
    _save_limit = save_limit
    _rollback = rollback

func simulate(type: CheatType) -> Dictionary:
    var result = {"type": type, "success": false, "detected": false, "message": "", "details": {}}
    match type:
        CheatType.MEMORY_EDIT:
            result = _simulate_memory_edit()
        CheatType.DEBUGGER_ATTACH:
            result = _simulate_debugger_attach()
        CheatType.FILE_TAMPER:
            result = _simulate_file_tamper()
        CheatType.REPLAY_ATTACK:
            result = _simulate_replay_attack()
        CheatType.SPEED_HACK:
            result = _simulate_speed_hack()
        CheatType.INJECTION:
            result = _simulate_injection()
        CheatType.SAVE_ROLLBACK:
            result = _simulate_save_rollback()
        CheatType.SAVE_SPAM:
            result = _simulate_save_spam()
    if result.detected:
        cheat_detected.emit(type, result)
    cheat_simulated.emit(type, result.success)
    return result

func _simulate_memory_edit() -> Dictionary:
    var result = {"type": CheatType.MEMORY_EDIT, "success": false, "detected": false, "message": "", "details": {}}
    if not _pool:
        result.message = "No value pool set"
        return result
    
    var test_key = "_simulate_test_value"
    var test_val = VanguardValue.new(12345)
    _pool.set_value(test_key, test_val)
    
    var original = test_val.get_value()
    test_val.set_value(99999)
    var modified = test_val.get_value()
    
    if modified == 99999:
        result.success = true
        result.details = {"original": original, "modified": modified}
        var threats = _pool.scan_for_threats()
        for t in threats:
            if t.key == test_key:
                result.detected = true
                result.message = "Memory edit detected: %d -> %d" % [original, modified]
                break
        if not result.detected:
            result.message = "Memory edit succeeded but not detected"
    else:
        result.message = "Memory edit failed"
    
    _pool.remove_value(test_key)
    return result

func _simulate_debugger_attach() -> Dictionary:
    var result = {"type": CheatType.DEBUGGER_ATTACH, "success": false, "detected": false, "message": ""}
    if not _detector:
        result.message = "No detector set"
        return result
    
    result.success = true
    if _detector.has_method("simulate_debugger"):
        result.detected = _detector.simulate_debugger()
        result.message = "Debugger attach simulated" + (" - Detected!" if result.detected else "")
    else:
        result.message = "Debugger simulation not supported"
    return result

func _simulate_file_tamper() -> Dictionary:
    var result = {"type": CheatType.FILE_TAMPER, "success": false, "detected": false, "message": ""}
    var test_path = "user://_simulate_test.txt"
    
    var file = FileAccess.open(test_path, FileAccess.WRITE)
    if file:
        file.store_string("original content")
        file.close()
        result.success = true
        
        var tampered = FileAccess.open(test_path, FileAccess.WRITE)
        if tampered:
            tampered.store_string("tampered content")
            tampered.close()
            result.message = "File tampered"
        else:
            result.message = "File created but tamper failed"
        
        if _file_validator and _file_validator.has_method("is_corrupted"):
            result.detected = _file_validator.is_corrupted(test_path, true)
            if result.detected:
                result.message += " - Detected!"
    
    if FileAccess.file_exists(test_path):
        DirAccess.remove_absolute(test_path)
    return result

func _simulate_replay_attack() -> Dictionary:
    var result = {"type": CheatType.REPLAY_ATTACK, "success": false, "detected": false, "message": ""}
    if not _detector or not _detector.has_method("check_replay"):
        result.message = "Replay protection not available"
        return result
    
    result.success = true
    result.detected = _detector.check_replay("test_request", "test_nonce")
    result.message = "Replay attack simulated" + (" - Detected!" if result.detected else "")
    return result

func _simulate_speed_hack() -> Dictionary:
    var result = {"type": CheatType.SPEED_HACK, "success": false, "detected": false, "message": ""}
    if not _detector or not _detector.has_method("check_speed"):
        result.message = "Speed hack detection not available"
        return result
    
    result.success = true
    result.detected = _detector.check_speed(2.0)
    result.message = "Speed hack simulated (2x)" + (" - Detected!" if result.detected else "")
    return result

func _simulate_injection() -> Dictionary:
    var result = {"type": CheatType.INJECTION, "success": false, "detected": false, "message": ""}
    if not _detector or not _detector.has_method("check_injection"):
        result.message = "Injection detection not available"
        return result
    
    result.success = true
    result.detected = _detector.check_injection("test_dll")
    result.message = "Injection simulated" + (" - Detected!" if result.detected else "")
    return result

func _simulate_save_rollback() -> Dictionary:
    var result = {"type": CheatType.SAVE_ROLLBACK, "success": false, "detected": false, "message": ""}
    if not _rollback:
        result.message = "Rollback detector not set"
        return result
    
    var slot = 999
    var now = Time.get_unix_time_from_system()
    
    if _rollback.has_method("record_save_with_time"):
        _rollback.record_save_with_time(slot, now)
        _rollback.record_save_with_time(slot, now - 100)
    else:
        _rollback.record_save(slot, now)
        _rollback.record_save(slot, now - 100)
    
    result.success = true
    if _rollback.is_suspicious(slot):
        result.detected = true
        result.message = "Save rollback detected"
    else:
        result.message = "Save rollback not detected"
    
    _rollback.reset_slot(slot)
    return result

func _simulate_save_spam() -> Dictionary:
    var result = {"type": CheatType.SAVE_SPAM, "success": false, "detected": false, "message": ""}
    if not _save_limit:
        result.message = "Save limit not set"
        return result
    
    var slot = 999
    for i in range(15):
        _save_limit.record_save(slot)
    
    result.success = true
    if _save_limit.get_save_count(slot, 60) >= 10:
        result.detected = true
        result.message = "Save spam detected after %d saves" % 15
    else:
        result.message = "Save spam not detected"
    
    _save_limit.reset_slot(slot)
    return result

func simulate_all() -> Dictionary:
    var results = {}
    for type in CheatType.values():
        results[type] = simulate(type)
    return results

func simulate_sequence(types: Array, delay: float = 1.0) -> void:
    for type in types:
        simulate(type)
        if delay > 0:
            var start = Time.get_ticks_msec()
            while Time.get_ticks_msec() - start < delay * 1000:
                await Engine.get_main_loop().process_frame

func generate_report() -> Dictionary:
    var results = simulate_all()
    var detected = 0
    for r in results.values():
        if r.detected:
            detected += 1
    return {
        "total": results.size(),
        "detected": detected,
        "success_rate": float(detected) / results.size() * 100 if results.size() > 0 else 0,
        "details": results
    }

func get_available_cheats() -> Array:
    var available = []
    if _pool: available.append(CheatType.MEMORY_EDIT)
    if _detector:
        if _detector.has_method("simulate_debugger"): available.append(CheatType.DEBUGGER_ATTACH)
        if _detector.has_method("check_replay"): available.append(CheatType.REPLAY_ATTACK)
        if _detector.has_method("check_speed"): available.append(CheatType.SPEED_HACK)
        if _detector.has_method("check_injection"): available.append(CheatType.INJECTION)
    if _file_validator: available.append(CheatType.FILE_TAMPER)
    if _rollback: available.append(CheatType.SAVE_ROLLBACK)
    if _save_limit: available.append(CheatType.SAVE_SPAM)
    return available