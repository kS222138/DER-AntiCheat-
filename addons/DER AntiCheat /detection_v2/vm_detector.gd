class_name DERVMDetector
extends RefCounted

enum VMRuntime { PHYSICAL, VMWARE, VIRTUALBOX, QEMU, KVM, XEN, HYPERV, ANDROID_EMU, BLUESTACKS, NOX, LDPLAYER, MEMU, UNKNOWN }
enum DetectionLevel { LOW, MEDIUM, HIGH, CRITICAL }

class VMThreat:
	var runtime: VMRuntime
	var level: DetectionLevel
	var details: Dictionary
	var timestamp: int
	
	func _init(r: VMRuntime, l: DetectionLevel, d: Dictionary):
		runtime = r
		level = l
		details = d
		timestamp = Time.get_unix_time_from_system()
	
	func _get_name() -> String:
		return ["PHYSICAL","VMWARE","VIRTUALBOX","QEMU","KVM","XEN","HYPERV","ANDROID_EMU","BLUESTACKS","NOX","LDPLAYER","MEMU","UNKNOWN"][runtime]
	
	func to_string() -> String:
		return "[%s] %s: %s" % [["LOW","MEDIUM","HIGH","CRITICAL"][level], _get_name(), JSON.stringify(details)]
	
	func to_dict() -> Dictionary:
		return {"runtime": runtime, "runtime_name": _get_name(), "level": level, "level_name": ["LOW","MEDIUM","HIGH","CRITICAL"][level], "details": details, "timestamp": timestamp}

const CPU_VENDOR_VM = ["VMware","VirtualBox","QEMU","KVM","Xen","Microsoft Hv"]
const VM_MAC_PREFIXES = ["00:0C:29","00:50:56","00:05:69","08:00:27"]
const VM_GPU_PATTERNS = ["VMware","VirtualBox","QEMU","Parallels"]
const SUSPICIOUS_PROCESSES = ["vboxservice","vboxtray","vmtoolsd","vmwaretray","qemu-ga"]

var _logger: DERLogger
var _enabled: bool = true
var _threats: Array[VMThreat] = []
var _on_threat: Callable
var _cached: VMRuntime = VMRuntime.UNKNOWN
var _last_scan: int = 0

func _init(logger: DERLogger = null):
	_logger = logger

func set_enabled(e: bool) -> void:
	_enabled = e

func set_threat_callback(cb: Callable) -> void:
	_on_threat = cb

func is_vm() -> bool:
	return _detect() != VMRuntime.PHYSICAL

func scan() -> Array[VMThreat]:
	if not _enabled:
		return []
	
	var threats: Array[VMThreat] = []
	var vm = _detect()
	if vm != VMRuntime.PHYSICAL:
		threats.append(VMThreat.new(vm, DetectionLevel.HIGH, {"type": _get_runtime_name(vm)}))
	
	threats.append_array(_check_cpu())
	threats.append_array(_check_memory())
	threats.append_array(_check_process())
	threats.append_array(_check_mac())
	threats.append_array(_check_gpu())
	
	for t in threats:
		_threats.append(t)
		if _logger:
			_logger.warning("vm", t.to_string())
		if _on_threat:
			_on_threat.call(t)
	
	return threats

func get_stats() -> Dictionary:
	return {"threats": _threats.size(), "is_vm": is_vm(), "type": _get_runtime_name(_detect())}

func _get_runtime_name(r: VMRuntime) -> String:
	return ["PHYSICAL","VMWARE","VIRTUALBOX","QEMU","KVM","XEN","HYPERV","ANDROID_EMU","BLUESTACKS","NOX","LDPLAYER","MEMU","UNKNOWN"][r]

func _detect() -> VMRuntime:
	var now = Time.get_ticks_msec()
	if now - _last_scan < 30000:
		return _cached
	_last_scan = now
	
	var r = VMRuntime.PHYSICAL
	if OS.has_feature("windows"):
		r = _detect_windows()
	elif OS.has_feature("linux"):
		r = _detect_linux()
	elif OS.has_feature("macos"):
		r = _detect_macos()
	elif OS.has_feature("android"):
		r = _detect_android()
	_cached = r
	return r

func _detect_windows() -> VMRuntime:
	var out = []
	if OS.execute("wmic", ["computersystem","get","model"], out) == 0:
		for l in out:
			var s = l.to_lower()
			if s.find("vmware") != -1:
				return VMRuntime.VMWARE
			if s.find("virtualbox") != -1:
				return VMRuntime.VIRTUALBOX
			if s.find("qemu") != -1:
				return VMRuntime.QEMU
			if s.find("hyper-v") != -1:
				return VMRuntime.HYPERV
	if _exists("C:\\Program Files\\VMware\\"):
		return VMRuntime.VMWARE
	if _exists("C:\\Program Files\\Oracle\\VirtualBox\\"):
		return VMRuntime.VIRTUALBOX
	return VMRuntime.PHYSICAL

func _detect_linux() -> VMRuntime:
	var cpu = _read("/proc/cpuinfo")
	for v in CPU_VENDOR_VM:
		if cpu.to_lower().find(v.to_lower()) != -1:
			match v:
				"VMware":
					return VMRuntime.VMWARE
				"VirtualBox":
					return VMRuntime.VIRTUALBOX
				"QEMU":
					return VMRuntime.QEMU
				"KVM":
					return VMRuntime.KVM
				"Xen":
					return VMRuntime.XEN
				"Microsoft Hv":
					return VMRuntime.HYPERV
	var dmi = _read("/sys/class/dmi/id/product_name")
	if dmi.to_lower().find("vmware") != -1:
		return VMRuntime.VMWARE
	if dmi.to_lower().find("virtualbox") != -1:
		return VMRuntime.VIRTUALBOX
	if dmi.to_lower().find("qemu") != -1:
		return VMRuntime.QEMU
	return VMRuntime.PHYSICAL

func _detect_macos() -> VMRuntime:
	var out = []
	if OS.execute("system_profiler", ["SPHardwareDataType"], out) == 0:
		for l in out:
			if l.find("VMware") != -1:
				return VMRuntime.VMWARE
			if l.find("VirtualBox") != -1:
				return VMRuntime.VIRTUALBOX
	return VMRuntime.PHYSICAL

func _detect_android() -> VMRuntime:
	var build = _read("/system/build.prop")
	if build.find("bluestacks") != -1:
		return VMRuntime.BLUESTACKS
	if build.find("nox") != -1:
		return VMRuntime.NOX
	if build.find("ldplayer") != -1:
		return VMRuntime.LDPLAYER
	if build.find("memu") != -1:
		return VMRuntime.MEMU
	var out = []
	if OS.execute("getprop", ["ro.kernel.qemu"], out) == 0 and out.size() > 0:
		return VMRuntime.ANDROID_EMU
	return VMRuntime.PHYSICAL

func _check_cpu() -> Array[VMThreat]:
	var t: Array[VMThreat] = []
	if OS.get_processor_count() < 2:
		t.append(VMThreat.new(VMRuntime.UNKNOWN, DetectionLevel.LOW, {"cpu_count": OS.get_processor_count()}))
	var speed = _cpu_speed()
	if speed > 0 and speed < 1000:
		t.append(VMThreat.new(VMRuntime.UNKNOWN, DetectionLevel.MEDIUM, {"cpu_mhz": speed}))
	return t

func _check_memory() -> Array[VMThreat]:
	var t: Array[VMThreat] = []
	var mem = OS.get_memory_info().get("physical", 0) / 1048576
	if mem > 0 and mem < 512:
		t.append(VMThreat.new(VMRuntime.UNKNOWN, DetectionLevel.MEDIUM, {"memory_mb": mem}))
	return t

func _check_process() -> Array[VMThreat]:
	var t: Array[VMThreat] = []
	for p in SUSPICIOUS_PROCESSES:
		if _running(p):
			t.append(VMThreat.new(VMRuntime.UNKNOWN, DetectionLevel.HIGH, {"process": p}))
	return t

func _check_mac() -> Array[VMThreat]:
	var t: Array[VMThreat] = []
	var mac = _mac()
	for prefix in VM_MAC_PREFIXES:
		if mac.to_upper().begins_with(prefix):
			t.append(VMThreat.new(VMRuntime.UNKNOWN, DetectionLevel.HIGH, {"mac": mac}))
	return t

func _check_gpu() -> Array[VMThreat]:
	var t: Array[VMThreat] = []
	var gpu = _gpu()
	for p in VM_GPU_PATTERNS:
		if gpu.find(p) != -1:
			t.append(VMThreat.new(VMRuntime.UNKNOWN, DetectionLevel.HIGH, {"gpu": gpu}))
	return t

func _read(p: String) -> String:
	if not FileAccess.file_exists(p):
		return ""
	var f = FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f else ""

func _exists(p: String) -> bool:
	return DirAccess.dir_exists_absolute(p) or FileAccess.file_exists(p)

func _cpu_speed() -> int:
	if OS.has_feature("windows"):
		var out = []
		if OS.execute("wmic", ["cpu","get","maxclockspeed"], out) == 0:
			for l in out:
				var s = l.to_int()
				if s > 0:
					return s
	return 0

func _running(p: String) -> bool:
	var out = []
	if OS.has_feature("windows"):
		if OS.execute("tasklist", ["/fi","IMAGENAME eq "+p], out) == 0:
			for l in out:
				if l.find(p) != -1:
					return true
	else:
		if OS.execute("pgrep", [p], out) == 0:
			return out.size() > 0
	return false

func _mac() -> String:
	var out = []
	if OS.has_feature("windows"):
		if OS.execute("getmac", [], out) == 0:
			for l in out:
				var parts = l.split(" ")
				for part in parts:
					if part.find("-") != -1 or part.find(":") != -1:
						return part.strip_edges()
	else:
		if OS.execute("ifconfig", [], out) == 0:
			for l in out:
				if l.find("ether") != -1:
					var parts = l.split(" ")
					for part in parts:
						if part.find(":") != -1:
							return part.strip_edges()
	return ""

func _gpu() -> String:
	if OS.has_feature("windows"):
		var out = []
		if OS.execute("wmic", ["path","win32_VideoController","get","name"], out) == 0:
			for l in out:
				if l.strip_edges() != "" and l.find("Name") == -1:
					return l.strip_edges()
	elif OS.has_feature("linux"):
		var out = []
		if OS.execute("lspci", [], out) == 0:
			for l in out:
				if l.find("VGA") != -1:
					var parts = l.split(":")
					if parts.size() > 1:
						return parts[1].strip_edges()
	return ""