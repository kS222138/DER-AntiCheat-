class_name DERProcessMonitor
extends RefCounted

var _blacklist = [
    "godot-mcp",
    "gdb",
    "lldb",
    "cheatengine",
    "x64dbg",
    "ollydbg",
    "windbg",
    "x32dbg",
    "processhacker",
    "wireshark",
    "frida",
    "radare2",
    "ghidra",
    "ida"
]

var _dangerous_patterns = [
    "\\$\\(",
    "`.*`",
    "\\|.*\\|",
    "&.*&",
    ";.*;",
    "\\|\\|",
    "&&"
]

func check() -> float:
    var risk = 0.0
    var threats = _scan_processes()
    
    for threat in threats:
        if Engine.has_singleton("VanguardCore"):
            VanguardCore.report("CRITICAL", "dangerous_process", {
                "process": threat,
                "cve": "CVE-2026-25546"
            })
        _terminate_process(threat)
        risk += 0.8
    
    if not _check_command_line():
        if Engine.has_singleton("VanguardCore"):
            VanguardCore.report("HIGH", "suspicious_command", {
                "args": OS.get_cmdline_args()
            })
        risk += 0.5
    
    return mini(risk, 1.0)

func _scan_processes() -> Array:
    var found = []
    var os_name = OS.get_name()
    
    if os_name == "Windows":
        var output = []
        OS.execute("tasklist", [], output)
        for line in output:
            var lower = line.to_lower()
            for bad in _blacklist:
                if lower.contains(bad):
                    found.append(bad)
                    
    elif os_name == "Linux" or os_name == "Android":
        var output = []
        OS.execute("ps", ["aux"], output)
        for line in output:
            var lower = line.to_lower()
            for bad in _blacklist:
                if lower.contains(bad):
                    found.append(bad)
                    
    elif os_name == "macOS":
        var output = []
        OS.execute("ps", ["-ax"], output)
        for line in output:
            var lower = line.to_lower()
            for bad in _blacklist:
                if lower.contains(bad):
                    found.append(bad)
    
    return found

func _terminate_process(process_name: String) -> void:
    var os_name = OS.get_name()
    
    if os_name == "Windows":
        OS.execute("taskkill", ["/F", "/IM", process_name])
    elif os_name == "Linux" or os_name == "macOS" or os_name == "Android":
        OS.execute("pkill", ["-f", process_name])

func _check_command_line() -> bool:
    var args = OS.get_cmdline_args()
    for arg in args:
        for pattern in _dangerous_patterns:
            var regex = RegEx.create_from_string(pattern)
            if regex.search(arg):
                return false
    return true