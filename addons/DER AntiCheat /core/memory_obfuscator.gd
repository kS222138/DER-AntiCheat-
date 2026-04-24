extends RefCounted
class_name DERMemoryObfuscator

signal tamper_detected(region: String)
signal vm_detected(vm_type: String)
signal emulator_detected
signal scan_completed(score: float)
signal debugger_detected

enum ProtectionLevel { LIGHT, MEDIUM, HEAVY, EXTREME }
enum ObfuscateRegion { CODE, DATA, VTABLE }

@export var protection_level: ProtectionLevel = ProtectionLevel.HEAVY
@export var scan_interval: float = 5.0
@export var rolling_interval: float = 30.0
@export var auto_repair: bool = false
@export var enable_honeypot: bool = true
@export var kill_on_vm: bool = false
@export var kill_on_emulator: bool = false
@export var kill_on_debugger: bool = false
@export var max_scan_objects: int = 500
@export var enable_state_persistence: bool = true

var _region_hashes: Dictionary = {}
var _rolling_seed: int = 0
var _tamper_count: int = 0
var _scan_timer: Timer = null
var _rolling_timer: Timer = null
var _vm_detected: bool = false
var _emulator_detected: bool = false
var _platform_supported: bool = true
var _self_hash: int = 0
var _persist_path: String = "user://.der_cache"
var _encoded_signatures: Dictionary = {}
var _timing_baseline: int = 0
var _state_dirty: bool = false
var _last_self_check: int = 0
var _cached_objects: Array = []
var _last_object_scan: int = 0
var _cached_code_hash: int = 0
var _last_code_hash_time: int = 0

var _vm_signatures: Dictionary = {
	"vmware": ["VMware", "vmx", "vmx86"],
	"virtualbox": ["VBox", "vbox", "VirtualBox"],
	"qemu": ["qemu", "KVM", "QEMU"],
	"hyperv": ["Hyper-V", "hyperv"]
}

var _emulator_signatures: Dictionary = {
	"bluestacks": ["Bluestacks", "HD-Plus", "Bstk"],
	"nox": ["Nox", "nox_adb"],
	"ldplayer": ["ldplayer"],
	"memu": ["MEmu"],
	"android_emulator": ["qemu", "ranchu", "goldfish"]
}


func _init():
	var os_name = OS.get_name()
	if os_name in ["Web", "iOS"]:
		_platform_supported = false
		return
	_rolling_seed = (randi() ^ (Time.get_ticks_msec() & 0x7FFFFFFF)) % 0x7FFFFFFF
	_decode_signatures()
	if enable_state_persistence:
		load_state()
	_self_hash = _hash_self()
	_calibrate_timing_baseline()


func _decode_signatures():
	_encoded_signatures.clear()
	for vm in _vm_signatures:
		_encoded_signatures[vm] = []
		for sig in _vm_signatures[vm]:
			_encoded_signatures[vm].append(_decode_string(sig))
	for emu in _emulator_signatures:
		var key = "emu_" + emu
		_encoded_signatures[key] = []
		for sig in _emulator_signatures[emu]:
			_encoded_signatures[key].append(_decode_string(sig))


func _decode_string(s: String) -> String:
	var r = ""
	for i in s.length():
		r += char(s.unicode_at(i) ^ 0x55)
	return r


func _hash_self() -> int:
	var script = get_script()
	if not script or script.resource_path.is_empty():
		return 0
	var f = FileAccess.open(script.resource_path, FileAccess.READ)
	if not f:
		return 0
	var h = f.get_as_text().hash()
	f.close()
	return h


func _check_self_integrity() -> bool:
	if _self_hash == 0:
		return true
	var now = Time.get_ticks_msec()
	if now - _last_self_check < 60000:
		return true
	_last_self_check = now
	var cur = _hash_self()
	if cur == 0:
		tamper_detected.emit("SELF_MISSING")
		return false
	return cur == _self_hash


func _calibrate_timing_baseline():
	if _timing_baseline != 0:
		return
	var s = Time.get_ticks_usec()
	var x = 0
	for i in range(100000):
		x += i
	_timing_baseline = Time.get_ticks_usec() - s


func _check_timing_debug() -> bool:
	_calibrate_timing_baseline()
	var s = Time.get_ticks_usec()
	var x = 0
	for i in range(100000):
		x += i
	var e = Time.get_ticks_usec() - s
	return e > _timing_baseline * 1.5


func _check_debugger() -> bool:
	if _check_timing_debug():
		return true
	var os = OS.get_name()
	var procs = []
	if os == "Windows":
		procs = ["ollydbg", "x64dbg", "windbg", "ida", "gdb", "cheatengine"]
		var out = []
		OS.execute("tasklist", [], out)
		for line in out:
			var l = line.to_lower()
			for p in procs:
				if l.find(p) != -1:
					return true
	elif os == "Linux":
		procs = ["gdb", "lldb", "strace"]
		var out = []
		OS.execute("ps", ["-e"], out)
		for line in out:
			var l = line.to_lower()
			for p in procs:
				if l.find(p) != -1:
					return true
	elif os == "Android":
		var out = []
		OS.execute("ps", [], out)
		for line in out:
			if line.to_lower().find("gdbserver") != -1:
				return true
	return false


func start():
	if not _platform_supported:
		return
	if _check_debugger():
		debugger_detected.emit()
		if kill_on_debugger:
			_trigger_meltdown()
			return
	_check_vm()
	_check_emulator()
	if _vm_detected and kill_on_vm:
		vm_detected.emit("VM")
		_trigger_meltdown()
		return
	if _emulator_detected and kill_on_emulator:
		emulator_detected.emit()
		_trigger_meltdown()
		return
	_scan_regions()
	_setup_timers()


func stop():
	if _scan_timer:
		_scan_timer.stop()
		_scan_timer.queue_free()
		_scan_timer = null
	if _rolling_timer:
		_rolling_timer.stop()
		_rolling_timer.queue_free()
		_rolling_timer = null


func _check_vm():
	var os = OS.get_name()
	if os == "Android":
		var props = _read_system_props()
		for vm in _encoded_signatures:
			if vm.begins_with("emu_"):
				continue
			for sig in _encoded_signatures[vm]:
				if props.find(sig) != -1:
					_vm_detected = true
					vm_detected.emit(vm)
					return
		var cpu = _read_file("/proc/cpuinfo")
		if cpu.find("hypervisor") != -1:
			_vm_detected = true
			vm_detected.emit("unknown")
			return
		if _check_timing_debug():
			_vm_detected = true
			vm_detected.emit("runtime")
			return
	elif os == "Windows":
		var out = []
		OS.execute("systeminfo", [], out)
		for line in out:
			var l = line.to_lower()
			for vm in _encoded_signatures:
				if vm.begins_with("emu_"):
					continue
				for sig in _encoded_signatures[vm]:
					if l.find(sig.to_lower()) != -1:
						_vm_detected = true
						vm_detected.emit(vm)
						return
	elif os == "Linux":
		var dmi = _read_file("/sys/class/dmi/id/product_name")
		for vm in _encoded_signatures:
			if vm.begins_with("emu_"):
				continue
			for sig in _encoded_signatures[vm]:
				if dmi.find(sig) != -1:
					_vm_detected = true
					vm_detected.emit(vm)
					return


func _check_emulator():
	if OS.get_name() != "Android":
		return
	var props = _read_system_props()
	for key in _encoded_signatures:
		if not key.begins_with("emu_"):
			continue
		for sig in _encoded_signatures[key]:
			if props.find(sig) != -1:
				_emulator_detected = true
				emulator_detected.emit()
				return
	var build = _read_file("/system/build.prop")
	if build.find("ro.kernel.qemu") != -1:
		_emulator_detected = true
		emulator_detected.emit()


func _read_system_props() -> String:
	var r = ""
	for p in ["/system/build.prop", "/default.prop"]:
		var c = _read_file(p)
		if c != "":
			r += c
	return r


func _read_file(p: String) -> String:
	if not FileAccess.file_exists(p):
		return ""
	var f = FileAccess.open(p, FileAccess.READ)
	if not f:
		return ""
	var c = f.get_as_text()
	f.close()
	return c


func _delayed_quit(tree):
	await tree.create_timer(randf_range(5, 30)).timeout
	tree.quit()


func _trigger_meltdown():
	_tamper_count = 999
	if enable_honeypot:
		var ml = Engine.get_main_loop()
		if ml:
			ml.set_meta("_der_honeypot", range(100))
	if enable_state_persistence:
		save_state()
	if not OS.has_feature("editor"):
		var tree = Engine.get_main_loop()
		if tree and tree.has_method("create_timer"):
			call_deferred("_delayed_quit", tree)


func _hash_code() -> int:
	var now = Time.get_ticks_msec()
	if now - _last_code_hash_time < 10000:
		return _cached_code_hash
	_last_code_hash_time = now
	var ms = Engine.get_main_loop().get_script()
	var h = 0
	if ms and ms.resource_path != "":
		var f = FileAccess.open(ms.resource_path, FileAccess.READ)
		if f:
			h = f.get_as_text().hash()
			f.close()
	_cached_code_hash = h
	return h


func _get_objects() -> Array:
	var now = Time.get_ticks_msec()
	if now - _last_object_scan < 30000:
		return _cached_objects
	_last_object_scan = now
	_cached_objects.clear()
	var ml = Engine.get_main_loop()
	if ml:
		_collect(ml, _cached_objects)
	return _cached_objects


func _scan_regions():
	if not _check_self_integrity():
		_tamper_count += 2
		tamper_detected.emit("SELF_HOOK")
		if _tamper_count >= 3:
			_trigger_meltdown()
		return
	
	var score = 100.0
	var regions = _get_regions()
	var total = float(regions.size())
	
	for r in regions:
		var h = _hash_region(r)
		if not _region_hashes.has(r):
			_region_hashes[r] = h
		elif h != _region_hashes[r]:
			_tamper_count += 1
			tamper_detected.emit(_region_name(r))
			score -= 100.0 / total
			if auto_repair:
				_region_hashes[r] = h
			_state_dirty = true
			if _tamper_count >= 3:
				_trigger_meltdown()
				return
	
	if _state_dirty and enable_state_persistence:
		save_state()
		_state_dirty = false
	
	scan_completed.emit(max(score, 0.0))


func _region_name(r: int) -> String:
	match r:
		ObfuscateRegion.CODE: return "CODE"
		ObfuscateRegion.DATA: return "DATA"
		ObfuscateRegion.VTABLE: return "VTABLE"
	return "UNKNOWN"


func _get_regions() -> Array:
	match protection_level:
		ProtectionLevel.LIGHT:
			return [ObfuscateRegion.CODE]
		ProtectionLevel.MEDIUM:
			return [ObfuscateRegion.CODE, ObfuscateRegion.VTABLE]
		_:
			return [ObfuscateRegion.CODE, ObfuscateRegion.DATA, ObfuscateRegion.VTABLE]


func _hash_region(r: int) -> int:
	var h = _rolling_seed
	match r:
		ObfuscateRegion.CODE:
			h ^= _hash_code()
		ObfuscateRegion.DATA:
			var mem = OS.get_memory_info()
			h ^= mem.get("static", 0)
			h ^= mem.get("dynamic", 0)
		ObfuscateRegion.VTABLE:
			var objs = _get_objects()
			var c = 0
			for o in objs:
				if c >= max_scan_objects:
					break
				h ^= str(o.get_class(), ":", o.get_path()).hash()
				c += 1
	return h


func _collect(n: Node, r: Array):
	if r.size() >= max_scan_objects:
		return
	r.append(n)
	for c in n.get_children():
		_collect(c, r)


func _rolling_hash():
	_rolling_seed = hash(str(_rolling_seed) + str(Time.get_ticks_msec()))


func _setup_timers():
	var ml = Engine.get_main_loop()
	if not ml:
		return
	if _scan_timer:
		_scan_timer.queue_free()
	_scan_timer = Timer.new()
	_scan_timer.wait_time = scan_interval
	_scan_timer.autostart = true
	_scan_timer.timeout.connect(_scan_regions)
	ml.root.add_child(_scan_timer)
	if protection_level >= ProtectionLevel.MEDIUM:
		if _rolling_timer:
			_rolling_timer.queue_free()
		_rolling_timer = Timer.new()
		_rolling_timer.wait_time = rolling_interval
		_rolling_timer.autostart = true
		_rolling_timer.timeout.connect(_rolling_hash)
		ml.root.add_child(_rolling_timer)


func save_state():
	if not enable_state_persistence:
		return
	var cfg = ConfigFile.new()
	cfg.set_value("ac", "tc", _tamper_count)
	cfg.set_value("ac", "rs", _rolling_seed)
	cfg.save(_persist_path)


func load_state():
	if not enable_state_persistence:
		return
	var cfg = ConfigFile.new()
	if cfg.load(_persist_path) == OK:
		_tamper_count = cfg.get_value("ac", "tc", 0)
		_rolling_seed = cfg.get_value("ac", "rs", _rolling_seed)


func reset_state():
	_tamper_count = 0
	_region_hashes.clear()
	_rolling_seed = (randi() ^ (Time.get_ticks_msec() & 0x7FFFFFFF)) % 0x7FFFFFFF
	if enable_state_persistence:
		DirAccess.open("user://").remove(_persist_path)


func get_integrity_score() -> float:
	var total = 0.0
	var max_score = 0.0
	for r in _get_regions():
		max_score += 100.0
		if _region_hashes.has(r) and _hash_region(r) == _region_hashes[r]:
			total += 100.0
	return total / max_score * 100.0 if max_score > 0 else 100.0


func is_vm() -> bool: return _vm_detected
func is_emulator() -> bool: return _emulator_detected
func get_tamper_count() -> int: return _tamper_count


func reset():
	_tamper_count = 0
	_region_hashes.clear()
	_rolling_seed = (randi() ^ (Time.get_ticks_msec() & 0x7FFFFFFF)) % 0x7FFFFFFF
	_scan_regions()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERMemoryObfuscator:
	var o = DERMemoryObfuscator.new()
	for k in config:
		if k in o:
			o.set(k, config[k])
	node.tree_entered.connect(o.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(o.stop.bind())
	return o
