class_name DERConfigPreset
extends RefCounted

enum PresetType {
	DEVELOPMENT,
	TESTING,
	PRODUCTION,
	LIGHT,
	BALANCED,
	STRICT,
	CUSTOM
}

const CONFIG_KEYS := [
	"enable_detection",
	"enable_report",
	"verify_interval",
	"disturb_min",
	"disturb_max",
	"protect_level"
]

const PRESETS := {
	PresetType.DEVELOPMENT: {
		"name": "Development",
		"description": "开发模式 - 禁用检测，方便调试",
		"enable_detection": false,
		"enable_report": false,
		"verify_interval": 5000,
		"disturb_min": 0,
		"disturb_max": 0,
		"protect_level": 0
	},
	PresetType.TESTING: {
		"name": "Testing",
		"description": "测试模式 - 低强度检测",
		"enable_detection": true,
		"enable_report": true,
		"verify_interval": 2000,
		"disturb_min": 1,
		"disturb_max": 3,
		"protect_level": 1
	},
	PresetType.PRODUCTION: {
		"name": "Production",
		"description": "生产模式 - 标准保护",
		"enable_detection": true,
		"enable_report": true,
		"verify_interval": 1000,
		"disturb_min": 2,
		"disturb_max": 5,
		"protect_level": 2
	},
	PresetType.LIGHT: {
		"name": "Light",
		"description": "轻量保护 - 高性能，低开销",
		"enable_detection": true,
		"enable_report": false,
		"verify_interval": 2000,
		"disturb_min": 1,
		"disturb_max": 2,
		"protect_level": 1
	},
	PresetType.BALANCED: {
		"name": "Balanced",
		"description": "平衡模式 - 安全与性能兼顾",
		"enable_detection": true,
		"enable_report": true,
		"verify_interval": 1000,
		"disturb_min": 2,
		"disturb_max": 5,
		"protect_level": 2
	},
	PresetType.STRICT: {
		"name": "Strict",
		"description": "严格模式 - 最高安全性",
		"enable_detection": true,
		"enable_report": true,
		"verify_interval": 500,
		"disturb_min": 5,
		"disturb_max": 15,
		"protect_level": 3
	}
}

const PRESET_DETAILS := {
	PresetType.LIGHT: {
		"performance_impact": "极低",
		"security_level": "基础",
		"recommended_for": ["低端设备", "性能敏感场景", "单机游戏"]
	},
	PresetType.BALANCED: {
		"performance_impact": "中等",
		"security_level": "标准",
		"recommended_for": ["中端设备", "多数联网游戏"]
	},
	PresetType.STRICT: {
		"performance_impact": "较高",
		"security_level": "高级",
		"recommended_for": ["高端设备", "竞技游戏", "高价值游戏"]
	},
	PresetType.DEVELOPMENT: {
		"performance_impact": "无",
		"security_level": "无",
		"recommended_for": ["开发调试"]
	},
	PresetType.TESTING: {
		"performance_impact": "极低",
		"security_level": "基础",
		"recommended_for": ["功能测试", "压力测试"]
	},
	PresetType.PRODUCTION: {
		"performance_impact": "中等",
		"security_level": "标准",
		"recommended_for": ["正式发布"]
	}
}

static func get_preset(type: PresetType) -> Dictionary:
	if not PRESETS.has(type):
		return {}
	return PRESETS[type].duplicate(true)

static func get_preset_details(type: PresetType) -> Dictionary:
	if not PRESET_DETAILS.has(type):
		return {}
	return PRESET_DETAILS[type].duplicate(true)

static func get_preset_names() -> Dictionary:
	var names = {}
	for type in PRESETS:
		names[type] = PRESETS[type]["name"]
	return names

static func get_preset_description(type: PresetType) -> String:
	if not PRESETS.has(type):
		return ""
	return PRESETS[type]["description"]

static func list_presets() -> Array:
	var list = []
	for type in PRESETS:
		list.append({
			"type": type,
			"name": PRESETS[type]["name"],
			"description": PRESETS[type]["description"]
		})
	return list

static func apply_preset(config: DERConfigManager, type: PresetType) -> bool:
	var preset = get_preset(type)
	if preset.is_empty():
		return false
	
	for key in CONFIG_KEYS:
		if preset.has(key):
			config.set_value(key, preset[key])
	
	return true

static func create_from_current(config: DERConfigManager, name: String, description: String = "") -> Dictionary:
	var preset = {
		"name": name,
		"description": description
	}
	for key in CONFIG_KEYS:
		preset[key] = config.get_value(key)
	return preset

static func compare_preset(current_config: Dictionary, preset: Dictionary) -> Array:
	var preset_config = {}
	for key in CONFIG_KEYS:
		if preset.has(key):
			preset_config[key] = preset[key]
	
	var diff_helper = DERConfigDiff.new()
	return diff_helper.compare(current_config, preset_config, false)

static func is_preset_active(current_config: Dictionary, preset: Dictionary) -> bool:
	return compare_preset(current_config, preset).is_empty()

static func validate_preset(preset: Dictionary) -> bool:
	if not preset.has("name"):
		push_error("DERConfigPreset: Missing name")
		return false
	
	for key in CONFIG_KEYS:
		if key == "verify_interval":
			if preset.get(key, 0) < 100:
				push_error("DERConfigPreset: verify_interval too small (< 100ms)")
				return false
		elif key == "protect_level":
			var level = preset.get(key, -1)
			if level < 0 or level > 3:
				push_error("DERConfigPreset: protect_level must be 0-3")
				return false
		elif key in ["disturb_min", "disturb_max"]:
			var min_val = preset.get("disturb_min", 0)
			var max_val = preset.get("disturb_max", 0)
			if min_val > max_val:
				push_error("DERConfigPreset: disturb_min > disturb_max")
				return false
	
	return true

static func export_preset(preset: Dictionary, path: String) -> int:
	if not validate_preset(preset):
		return ERR_INVALID_DATA
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify(preset, "\t"))
	return OK

static func import_preset(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("DERConfigPreset: Cannot open %s" % path)
		return {}
	
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("DERConfigPreset: Failed to parse %s: %s" % [path, json.get_error_message()])
		return {}
	
	var data = json.get_data()
	if not (data is Dictionary):
		push_error("DERConfigPreset: Invalid format in %s" % path)
		return {}
	
	if not validate_preset(data):
		push_error("DERConfigPreset: Invalid preset data in %s" % path)
		return {}
	
	return data

static func get_recommended_preset(device_rating: int = 0) -> PresetType:
	if device_rating <= 2:
		return PresetType.LIGHT
	elif device_rating <= 4:
		return PresetType.BALANCED
	else:
		return PresetType.STRICT

static func get_protect_level_name(level: int) -> String:
	match level:
		0: return "无保护"
		1: return "轻度保护"
		2: return "标准保护"
		3: return "严格保护"
		_: return "未知"

static func get_performance_impact(type: PresetType) -> String:
	var details = get_preset_details(type)
	return details.get("performance_impact", "未知")

static func get_security_level(type: PresetType) -> String:
	var details = get_preset_details(type)
	return details.get("security_level", "未知")

static func merge_preset(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in CONFIG_KEYS:
		if override.has(key):
			result[key] = override[key]
	if override.has("name"):
		result["name"] = override["name"]
	if override.has("description"):
		result["description"] = override["description"]
	return result