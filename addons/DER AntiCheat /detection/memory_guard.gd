class_name DERMemoryGuard
extends RefCounted

var _allocations = {}
var _freed_objects = []
var _suspicious_patterns = []

func track_allocation(obj, name = ""):
    var id = obj.get_instance_id()
    _allocations[id] = {
        "object": obj,
        "name": name,
        "alloc_time": Time.get_ticks_usec(),
        "alloc_stack": get_stack(),
        "verify_count": 0
    }

func track_free(obj):
    var id = obj.get_instance_id()
    if _allocations.has(id):
        _freed_objects.append({
            "id": id,
            "name": _allocations[id].name,
            "free_time": Time.get_ticks_usec(),
            "alloc_time": _allocations[id].alloc_time
        })
        _allocations.erase(id)

func verify_access(obj):
    var id = obj.get_instance_id()
    
    for freed in _freed_objects:
        if freed.id == id:
            if Engine.has_singleton("VanguardCore"):
                VanguardCore.report("CRITICAL", "use_after_free", {
                    "object_id": id,
                    "freed_time": freed.free_time,
                    "current_time": Time.get_ticks_usec()
                })
            return false
    
    if _allocations.has(id):
        _allocations[id].verify_count += 1
        if _allocations[id].verify_count > 10000:
            _suspicious_patterns.append({
                "type": "高频访问",
                "object": id,
                "count": _allocations[id].verify_count
            })
    
    return true

func check():
    var risk = 0.0
    
    for pattern in _suspicious_patterns:
        risk += 0.3
    
    if _freed_objects.size() > 100:
        risk += 0.2
    
    return mini(risk, 1.0)