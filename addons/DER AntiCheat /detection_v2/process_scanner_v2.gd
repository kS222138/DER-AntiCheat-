extends RefCounted
class_name DERProcessScannerV2

signal suspicious_process_detected(process_name: String, process_type: String)
signal module_detected(module_name: String, module_type: String)
signal scan_completed(risk_score: float)

enum ScanLevel { LIGHT, MEDIUM, HEAVY, EXTREME }

@export var scan_level: ScanLevel = ScanLevel.HEAVY
@export var scan_interval: float = 10.0
@export var auto_kill: bool = false
@export var report_to_server: bool = false
@export var scan_modules: bool = true
@export var light_weight: float = 10.0
@export var medium_weight: float = 20.0
@export var heavy_weight: float = 40.0
@export var extreme_weight: float = 80.0

var _scan_timer: Timer = null
var _detected_processes: Dictionary = {}
var _detected_modules: Dictionary = {}
var _encoded_blacklist: Dictionary = {}
var _process_whitelist: Array = []
var _started: bool = false
var _pending_start: bool = false
var _main_loop: MainLoop = null

var _process_blacklist_raw: Dictionary = {
	"cheat_engine": ["cheatengine", "cheat engine", "CE", "cheatengine-x86_64"],
	"game_guardian": ["com.gameguardian", "gg", "gameguardian", "ggservice"],
	"memory_scanner": ["memory scanner", "memoryeditor", "memscan"],
	"debugger": ["x64dbg", "x32dbg", "ollydbg", "windbg", "ida", "gdb", "lldb"],
	"injector": ["injector", "loader", "hook", "hemoloader", "modloader"],
	"android_tools": ["frida", "xposed", "edxposed", "magisk", "substrate"],
	"emulator": ["nox", "bluestacks", "ldplayer", "memu", "genymotion"]
}

var _module_blacklist_raw: Dictionary = {
	"suspicious_so": ["libgg.so", "libfrida.so", "libsubstrate.so", "libxposed.so", "libandroid-hook.so"],
	"dll_inject": ["hook.dll", "inject.dll", "cheat.dll", "mod.dll", "xinput", "dxgi"],
	"script_mod": ["mods", "hemoloader", "script_backup", "autoexec"]
}


func _init():
	_decode_blacklists()
	_main_loop = Engine.get_main_loop()


func start():
	if _started:
		return
	_started = true
	if scan_level >= ScanLevel.MEDIUM:
		_start_scanning()


func stop():
	if _scan_timer:
		_scan_timer.stop()
		_scan_timer.queue_free()
		_scan_timer = null
	_started = false
	_pending_start = false


func _decode_blacklists():
	_encoded_blacklist.clear()
	for cat in _process_blacklist_raw:
		_encoded_blacklist["proc_" + cat] = []
		for name in _process_blacklist_raw[cat]:
			_encoded_blacklist["proc_" + cat].append(_decode_string(name))
	for cat in _module_blacklist_raw:
		_encoded_blacklist["mod_" + cat] = []
		for name in _module_blacklist_raw[cat]:
			_encoded_blacklist["mod_" + cat].append(_decode_string(name))


func _decode_string(s: String) -> String:
	var r = ""
	for i in s.length():
		r += char(s.unicode_at(i) ^ 0x66)
	return r


func _get_main_loop():
	if not _main_loop:
		_main_loop = Engine.get_main_loop()
	return _main_loop


func _add_child_to_root(node: Node):
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(node)
	else:
		# 延迟重试
		await Engine.get_main_loop().process_frame
		_add_child_to_root(node)


func _start_scanning():
	if _scan_timer or _pending_start:
		return
	_pending_start = true
	
	_scan_timer = Timer.new()
	_scan_timer.wait_time = scan_interval
	_scan_timer.autostart = true
	_scan_timer.timeout.connect(_scan)
	
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(_scan_timer)
		_pending_start = false
	else:
		await Engine.get_main_loop().process_frame
		if _started:
			var t = _get_main_loop()
			if t and t.has_method("root"):
				t.root.add_child(_scan_timer)
		_pending_start = false


func _get_total_weight() -> float:
	match scan_level:
		ScanLevel.LIGHT:
			return light_weight
		ScanLevel.MEDIUM:
			return medium_weight
		ScanLevel.HEAVY:
			return heavy_weight
		ScanLevel.EXTREME:
			return extreme_weight
	return heavy_weight


func _scan():
	var total_weight = _get_total_weight()
	var risk = 0.0
	var os = OS.get_name()
	
	if os == "Windows":
		risk += _scan_windows()
	elif os == "Linux":
		risk += _scan_linux()
	elif os == "Android":
		risk += _scan_android()
	
	if scan_modules and (os == "Android" or os == "Windows"):
		risk += _scan_modules()
	
	risk = min(risk, total_weight)
	var score = (1.0 - risk / total_weight) * 100.0 if total_weight > 0 else 100.0
	scan_completed.emit(score)
	
	if risk > total_weight * 0.7 and auto_kill:
		_trigger_response()
	
	_cleanup_old_entries()


func _is_whitelisted(proc_name: String) -> bool:
	for w in _process_whitelist:
		if proc_name.to_lower().find(w.to_lower()) != -1:
			return true
	return false


func _report(proc_name: String, proc_type: String):
	if not report_to_server:
		return
	var data = {
		"process": proc_name,
		"type": proc_type,
		"timestamp": Time.get_unix_time_from_system(),
		"device": OS.get_unique_id(),
		"platform": OS.get_name()
	}
	_do_report(data)


func _do_report(data: Dictionary):
	var http = HTTPRequest.new()
	var tree = _get_main_loop()
	if tree and tree.has_method("root"):
		tree.root.add_child(http)
	else:
		await Engine.get_main_loop().process_frame
		var t = _get_main_loop()
		if t and t.has_method("root"):
			t.root.add_child(http)
		else:
			http.queue_free()
			return
	
	var body = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	http.request_completed.connect(func(): http.queue_free())
	http.request("https://your-server.com/api/anticheat/report", headers, HTTPClient.METHOD_POST, body)


func _scan_windows() -> float:
	var risk = 0.0
	var out = []
	var exit_code = OS.execute("tasklist", [], out, true)
	if exit_code != 0:
		return 0.0
	
	for line in out:
		var lower = line.to_lower()
		for key in _encoded_blacklist:
			if not key.begins_with("proc_"):
				continue
			for name in _encoded_blacklist[key]:
				if lower.find(name) != -1:
					var proc_name = _extract_process_name(line)
					if _is_whitelisted(proc_name):
						continue
					if not _detected_processes.has(proc_name):
						_detected_processes[proc_name] = {"time": Time.get_ticks_msec(), "type": key.replace("proc_", "")}
						suspicious_process_detected.emit(proc_name, key.replace("proc_", ""))
						_report(proc_name, key.replace("proc_", ""))
					risk += 1.0
					break
	return risk


func _scan_linux() -> float:
	var risk = 0.0
	var out = []
	var exit_code = OS.execute("ps", ["-e"], out, true)
	if exit_code != 0:
		return 0.0
	
	for line in out:
		var lower = line.to_lower()
		for key in _encoded_blacklist:
			if not key.begins_with("proc_"):
				continue
			for name in _encoded_blacklist[key]:
				if lower.find(name) != -1:
					var parts = line.strip_edges().split(" ")
					var proc_name = parts[-1] if parts.size() > 0 else "unknown"
					if _is_whitelisted(proc_name):
						continue
					if not _detected_processes.has(proc_name):
						_detected_processes[proc_name] = {"time": Time.get_ticks_msec(), "type": key.replace("proc_", "")}
						suspicious_process_detected.emit(proc_name, key.replace("proc_", ""))
						_report(proc_name, key.replace("proc_", ""))
					risk += 1.0
					break
	return risk


func _scan_android() -> float:
	var risk = 0.0
	var out = []
	var exit_code = OS.execute("ps", [], out, true)
	if exit_code != 0:
		return 0.0
	
	for line in out:
		var lower = line.to_lower()
		for key in _encoded_blacklist:
			if not key.begins_with("proc_"):
				continue
			for name in _encoded_blacklist[key]:
				if lower.find(name) != -1:
					var parts = line.strip_edges().split(" ")
					var proc_name = parts[-1] if parts.size() > 0 else "unknown"
					if _is_whitelisted(proc_name):
						continue
					if not _detected_processes.has(proc_name):
						_detected_processes[proc_name] = {"time": Time.get_ticks_msec(), "type": key.replace("proc_", "")}
						suspicious_process_detected.emit(proc_name, key.replace("proc_", ""))
						_report(proc_name, key.replace("proc_", ""))
					risk += 2.0
					break
	
	if scan_level >= ScanLevel.EXTREME:
		risk += _scan_android_maps()
	
	return risk


func _scan_android_maps() -> float:
	var risk = 0.0
	var maps = _read_file("/proc/self/maps")
	if maps == "":
		return 0.0
	var lower = maps.to_lower()
	var suspicious_paths = ["/data/local/tmp", "/sdcard", "/storage/emulated", "memfd", "linjector"]
	for path in suspicious_paths:
		if lower.find(path) != -1:
			risk += 0.5
	return min(risk, 3.0)


func _scan_modules() -> float:
	var risk = 0.0
	var os = OS.get_name()
	
	if os == "Windows":
		var out = []
		var exit_code = OS.execute("tasklist", ["/m"], out, true)
		if exit_code == 0:
			for line in out:
				var lower = line.to_lower()
				for key in _encoded_blacklist:
					if not key.begins_with("mod_"):
						continue
					for name in _encoded_blacklist[key]:
						if lower.find(name) != -1:
							var module_name = _extract_module_name(line)
							if not _detected_modules.has(module_name):
								_detected_modules[module_name] = {"time": Time.get_ticks_msec(), "type": key.replace("mod_", "")}
								module_detected.emit(module_name, key.replace("mod_", ""))
							risk += 0.5
							break
	
	elif os == "Android":
		var packages = _get_installed_packages()
		for key in _encoded_blacklist:
			if not key.begins_with("mod_"):
				continue
			for name in _encoded_blacklist[key]:
				if packages.find(name) != -1:
					if not _detected_modules.has(name):
						_detected_modules[name] = {"time": Time.get_ticks_msec(), "type": key.replace("mod_", "")}
						module_detected.emit(name, key.replace("mod_", ""))
					risk += 0.5
		
		var maps = _read_file("/proc/self/maps")
		for key in _encoded_blacklist:
			if not key.begins_with("mod_"):
				continue
			for name in _encoded_blacklist[key]:
				if maps.find(name) != -1:
					if not _detected_modules.has(name):
						_detected_modules[name] = {"time": Time.get_ticks_msec(), "type": key.replace("mod_", "")}
						module_detected.emit(name, key.replace("mod_", ""))
					risk += 1.0
					break
	
	return risk


func _get_installed_packages() -> String:
	var out = []
	var exit_code = OS.execute("pm", ["list", "packages"], out, true)
	if exit_code != 0:
		return ""
	var result = ""
	for line in out:
		result += line.to_lower() + "\n"
	return result


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var c = f.get_as_text()
	f.close()
	return c


func _extract_process_name(line: String) -> String:
	var parts = line.strip_edges().split(" ")
	for part in parts:
		if part.ends_with(".exe"):
			return part
		if part.ends_with(".dll"):
			return part
	return parts[-1] if parts.size() > 0 else "unknown"


func _extract_module_name(line: String) -> String:
	var parts = line.strip_edges().split(" ")
	for part in parts:
		if part.ends_with(".dll") or part.ends_with(".so"):
			return part
	return "unknown"


func _trigger_response():
	if not auto_kill:
		return
	var os = OS.get_name()
	for proc in _detected_processes.keys():
		var proc_name = proc
		if os == "Windows" and not proc_name.ends_with(".exe"):
			proc_name += ".exe"
		if os == "Windows":
			OS.execute("taskkill", ["/F", "/IM", proc_name], [], true)
		elif os == "Linux" or os == "Android":
			OS.execute("pkill", ["-f", proc_name], [], true)


func _cleanup_old_entries():
	var now = Time.get_ticks_msec()
	var to_remove = []
	for proc in _detected_processes:
		if now - _detected_processes[proc]["time"] > 60000:
			to_remove.append(proc)
	for proc in to_remove:
		_detected_processes.erase(proc)
	
	to_remove.clear()
	for mod in _detected_modules:
		if now - _detected_modules[mod]["time"] > 60000:
			to_remove.append(mod)
	for mod in to_remove:
		_detected_modules.erase(mod)


func get_detected_processes() -> Dictionary:
	return _detected_processes.duplicate()


func get_detected_modules() -> Dictionary:
	return _detected_modules.duplicate()


func add_to_whitelist(process_names: Array):
	_process_whitelist.append_array(process_names)


func add_custom_blacklist(category: String, names: Array):
	if not _process_blacklist_raw.has(category):
		_process_blacklist_raw[category] = []
	for name in names:
		if name not in _process_blacklist_raw[category]:
			_process_blacklist_raw[category].append(name)
	_encoded_blacklist["proc_" + category] = []
	for n in _process_blacklist_raw[category]:
		_encoded_blacklist["proc_" + category].append(_decode_string(n))


func reset():
	_detected_processes.clear()
	_detected_modules.clear()


func is_clean() -> bool:
	return _detected_processes.is_empty() and _detected_modules.is_empty()


static func attach_to_node(node: Node, config: Dictionary = {}) -> DERProcessScannerV2:
	var scanner = DERProcessScannerV2.new()
	for k in config:
		if k in scanner:
			scanner.set(k, config[k])
	node.tree_entered.connect(scanner.start.bind(), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(scanner.stop.bind())
	return scanner
