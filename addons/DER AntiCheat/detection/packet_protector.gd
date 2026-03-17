class_name DERPacketProtector
extends RefCounted

var _crypto
var _session_key
var _session_id
var _sequence_number = 0
var _last_packet_time = 0
var _packet_history = []

func _init():
    _crypto = Crypto.new()
    _session_id = str(Time.get_unix_time_from_system()) + "_" + str(randi())
    _generate_session_key()

func _generate_session_key():
    _session_key = _crypto.generate_random_bytes(32)

func encrypt_packet(data):
    var packet = {
        "seq": _sequence_number,
        "time": Time.get_unix_time_from_system(),
        "data": data,
        "session": _session_id
    }
    
    var json = JSON.stringify(packet)
    var bytes = json.to_utf8_buffer()
    
    var iv = _crypto.generate_random_bytes(16)
    var encrypted = _crypto.encrypt_with_iv(_session_key, iv, bytes)
    
    _sequence_number += 1
    _last_packet_time = Time.get_ticks_usec()
    
    return {
        "iv": Marshalls.raw_to_base64(iv),
        "data": Marshalls.raw_to_base64(encrypted)
    }

func decrypt_packet(encrypted):
    if encrypted == null or typeof(encrypted) != TYPE_DICTIONARY:
        return null
    
    if not encrypted.has("iv") or not encrypted.has("data"):
        return null
    
    var iv = Marshalls.base64_to_raw(encrypted.iv)
    var data = Marshalls.base64_to_raw(encrypted.data)
    
    if iv.is_empty() or data.is_empty():
        return null
    
    var decrypted = _crypto.decrypt_with_iv(_session_key, iv, data)
    if decrypted.is_empty():
        return null
    
    var json = decrypted.get_string_from_utf8()
    if json.is_empty():
        return null
    
    var packet = JSON.parse_string(json)
    if packet == null or typeof(packet) != TYPE_DICTIONARY:
        return null
    
    if not packet.has("session") or not packet.has("seq") or not packet.has("time") or not packet.has("data"):
        return null
    
    if packet.session != _session_id:
        if Engine.has_singleton("VanguardCore"):
            VanguardCore.report("HIGH", "packet_session_mismatch", {"session": packet.session})
        return null
    
    var now = Time.get_unix_time_from_system()
    if abs(now - packet.time) > 30:
        if Engine.has_singleton("VanguardCore"):
            VanguardCore.report("HIGH", "packet_timeout", {"time": packet.time, "now": now})
        return null
    
    _packet_history.append(packet.seq)
    if _packet_history.size() > 10:
        _packet_history.pop_front()
    
    _check_replay_attack(packet.seq)
    
    return packet.data

func _check_replay_attack(seq):
    var count = 0
    for s in _packet_history:
        if s == seq:
            count += 1
    
    if count > 1:
        if Engine.has_singleton("VanguardCore"):
            VanguardCore.report("CRITICAL", "replay_attack", {"sequence": seq})

func get_session_key():
    return Marshalls.raw_to_base64(_session_key)

func set_session_key(key_str):
    _session_key = Marshalls.base64_to_raw(key_str)