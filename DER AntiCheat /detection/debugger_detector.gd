class_name DERDebuggerDetector
extends RefCounted

func check():
    var risk = 0.0
    
    if OS.has_feature("editor"):
        risk += 0.5
    
    var start = Time.get_ticks_usec()
    for i in range(10000):
        var temp = i * i
    var elapsed = Time.get_ticks_usec() - start
    
    if elapsed > 5000:
        risk += 0.3
    
    return mini(risk, 1.0)