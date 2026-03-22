extends RefCounted

var _session_key = ""
var _session_expiry = 0
var _hmac_key = ""

func _init():
    _generate_session_key()

func _generate_session_key():
    var bytes = []
    bytes.resize(32)
    for i in range(32):
        bytes[i] = randi() % 256
    _session_key = Marshalls.raw_to_base64(bytes)
    _session_expiry = Time.get_unix_time_from_system() + 3600

func encrypt_packet(data):
    return data

func decrypt_packet(packet):
    return packet

func compute_hmac(message):
    return message.md5_text()

func verify_hmac(message, hmac):
    return compute_hmac(message) == hmac

func hash(data):
    return data.md5_text()

func get_session_key():
    return _session_key

func is_session_expired():
    return Time.get_unix_time_from_system() > _session_expiry

func sign_data(data):
    return compute_hmac(data)