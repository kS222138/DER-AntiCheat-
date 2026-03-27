extends Node
class_name DERDebugDetectorV2

enum Type { NONE, WINDOWS, GDSCRIPT, PTRACE, TIMING, DEBUGGER_PROC, HANDLE, ENV, VM, UNKNOWN }
enum Level { LIGHT, MEDIUM, HEAVY, EXTREME }

@export var level: Level = Level.MEDIUM
@export var interval: float = 2.0
@export var auto_quit: bool = false
@export var honeypot: bool = true
@export var timing_threshold: float = 0.3
@export var timing_loop: int = 500000
@export var verbose: bool = false

var _run: bool = false
var _timer: Timer
var _detected: bool = false
var _count: int = 0
var _timing: Array = []

signal detected(type: Type, details: Dictionary)
signal evaded()
signal triggered()

func _ready():
	_timer = Timer.new()
	_timer.wait_time = interval
	_timer.timeout.connect(_scan)
	add_child(_timer)

func start(): _start()
func stop(): _stop()
func is_detected(): return _detected
func get_count(): return _count
func reset(): _count = 0
func stats(): return {run=_run,detected=_detected,count=_count,level=level}

func _start():
	if _run: return
	_run = true
	_timer.start()
	_log("Started")

func _stop():
	if not _run: return
	_run = false
	_timer.stop()
	_log("Stopped")

func _scan():
	if not _run: return
	var r = _check()
	if r.detected:
		_detected = true
		_count += 1
		_log_detection(r.type, r.details)
		detected.emit(r.type, r.details)
		if auto_quit: _quit()
		elif honeypot: _trigger()
	else:
		if _detected: evaded.emit()
		_detected = false

func _check() -> Dictionary:
	var r = {detected=false, type=Type.NONE, details={}}
	r = _add(r, _ptrace(), Type.PTRACE, {ptrace=true})
	r = _add(r, _present(), Type.WINDOWS, {present=true})
	r = _add(r, OS.is_debug_build(), Type.GDSCRIPT, {debug=true})
	r = _add(r, _proc(), Type.DEBUGGER_PROC, {proc=true})
	if level >= Level.MEDIUM:
		r = _add(r, _timing_check(), Type.TIMING, {timing=true})
		r = _add(r, _vm(), Type.VM, {vm=true})
	if level >= Level.HEAVY:
		r = _add(r, _handle(), Type.HANDLE, {handle=true})
	if level >= Level.EXTREME:
		r = _add(r, _env(), Type.ENV, {env=true})
	return r

func _add(r, cond: bool, t: Type, d: Dictionary) -> Dictionary:
	if cond:
		r.detected = true
		if r.type == Type.NONE: r.type = t
		for k in d: r.details[k] = d[k]
	return r

func _ptrace() -> bool:
	if OS.get_name() in ["Linux","Android"]:
		var f = FileAccess.open("/proc/self/status", FileAccess.READ)
		if f:
			var c = f.get_as_text()
			f.close()
			for l in c.split("\n"):
				if l.begins_with("TracerPid:") and l.split(":")[1].strip_edges()!="0": return true
	return false

func _present() -> bool:
	var n = OS.get_name()
	if n == "Windows":
		for f in ["IsDebuggerPresent","NtCurrentPeb","BeingDebugged"]:
			if _native(f): return true
	elif n == "Linux":
		var f = FileAccess.open("/proc/self/stat", FileAccess.READ)
		if f:
			var c = f.get_as_text()
			f.close()
			var p = c.split(" ")
			if p.size()>8 and p[7]!="0": return true
	elif n == "macOS":
		var f = FileAccess.open("/proc/self/status", FileAccess.READ)
		if f:
			var c = f.get_as_text()
			f.close()
			if c.find("TracerPid:")!=-1: return true
	return false

func _native(_f): return false

func _timing_check() -> bool:
	var s = Time.get_ticks_usec()
	var d = 0
	for i in range(timing_loop): d += i
	var e = Time.get_ticks_usec() - s
	_timing.append(e)
	if _timing.size() > 10: _timing.pop_front()
	if _timing.size() >= 5:
		var avg = 0.0
		for t in _timing: avg += t
		avg /= _timing.size()
		var dev = 0.0
		for t in _timing: dev += abs(t - avg)
		dev /= _timing.size()
		if dev > avg * timing_threshold: return true
	return false

func _vm() -> bool:
	for i in ["vbox","vmware","qemu","virtualbox","VBoxGuest","VMwareTray"]:
		if _running(i): return true
	if _cpu().find("hypervisor") != -1: return true
	return false

func _proc() -> bool:
	for p in ["ollydbg","x64dbg","x32dbg","windbg","ida","gdb","lldb","dnspy","cheatengine"]:
		if _running(p): return true
	return false

func _running(name: String) -> bool:
	var n = OS.get_name()
	var cmd = []
	if n == "Windows": cmd = ["tasklist"]
	elif n in ["Linux","Android"]: cmd = ["ps","-e"]
	elif n == "macOS": cmd = ["ps","-ax"]
	else: return false
	var out = []
	if OS.execute(cmd[0], cmd.slice(1), out) == OK:
		for l in out:
			if l.to_lower().find(name.to_lower()) != -1: return true
	return false

func _cpu() -> String:
	var n = OS.get_name()
	if n in ["Linux","Android"]:
		var f = FileAccess.open("/proc/cpuinfo", FileAccess.READ)
		if f: var c = f.get_as_text(); f.close(); return c.to_lower()
	elif n == "Windows":
		var out = []
		if OS.execute("wmic", ["cpu","get","name"], out) == OK:
			for l in out:
				if l.to_lower().find("hypervisor") != -1: return "hypervisor"
	elif n == "macOS":
		var out = []
		if OS.execute("sysctl", ["-n","machdep.cpu.brand_string"], out) == OK:
			for l in out:
				if l.to_lower().find("virtual") != -1: return "hypervisor"
	return ""

func _handle() -> bool:
	var p = "user://test.tmp"
	var f = FileAccess.open(p, FileAccess.WRITE)
	if not f: return true
	f.store_string("test")
	f.close()
	var g = FileAccess.open(p, FileAccess.READ)
	if not g:
		var d = DirAccess.open("user://")
		if d: d.remove(p)
		return true
	g.close()
	var d2 = DirAccess.open("user://")
	if d2: d2.remove(p)
	return false

func _env() -> bool:
	for e in ["DISPLAY","SSH_CONNECTION","REMOTE_ADDR"]:
		if not OS.get_environment(e).is_empty(): return true
	return false

func _trigger():
	triggered.emit()
	_log("Honeypot triggered")

func _quit():
	_log("Quitting")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

func _log(m): if verbose: print("DERDebug: ", m)
func _log_detection(t, d): if verbose: print("DERDebug: ", Type.keys()[t], " ", d)