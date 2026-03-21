class_name DERIntegrityCheck
extends RefCounted

var _file_hashes = {}
var _script_hashes = {}
var _critical_paths = [
    "res://project.godot",
    "res://addons/DER_Protection_System/plugin.gd",
    "res://addons/DER_Protection_System/core/value.gd",
    "res://addons/DER_Protection_System/core/pool.gd"
]
var _initialized = false

func _init():
    for path in _critical_paths:
        add_file_to_monitor(path)
    _initialized = true

func add_file_to_monitor(path):
    if FileAccess.file_exists(path):
        var file = FileAccess.open(path, FileAccess.READ)
        var content = file.get_as_text()
        _file_hashes[path] = content.hash()
        _script_hashes[path] = _hash_script_structure(content)

func _hash_script_structure(content):
    var structure = ""
    var lines = content.split("\n")
    for line in lines:
        var trimmed = line.strip_edges()
        if trimmed.begins_with("func ") or trimmed.begins_with("class_name") or trimmed.begins_with("extends"):
            structure += trimmed
    return structure.hash()

func check():
    if not _initialized:
        return 0.0
    
    var risk = 0.0
    var modified_files = []
    
    for path in _file_hashes:
        if FileAccess.file_exists(path):
            var file = FileAccess.open(path, FileAccess.READ)
            var content = file.get_as_text()
            var current_hash = content.hash()
            var current_struct = _hash_script_structure(content)
            
            if current_hash != _file_hashes[path]:
                modified_files.append({
                    "path": path,
                    "type": "content",
                    "original": _file_hashes[path],
                    "current": current_hash
                })
                risk += 0.4
            
            if current_struct != _script_hashes[path]:
                modified_files.append({
                    "path": path,
                    "type": "structure",
                    "original": _script_hashes[path],
                    "current": current_struct
                })
                risk += 0.6
    
    if modified_files.size() > 0:
        if Engine.has_singleton("VanguardCore"):
            VanguardCore.report("HIGH", "file_integrity_violation", {
                "files": modified_files
            })
    
    return mini(risk, 1.0)

func verify_plugin_integrity():
    return check() < 0.3