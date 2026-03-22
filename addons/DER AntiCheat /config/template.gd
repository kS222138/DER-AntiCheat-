class_name DERConfigTemplate
extends RefCounted

enum TemplateType {
	EMPTY,
	DEFAULT,
	MINIMAL,
	MAXIMUM,
	COMPETITIVE,
	CASUAL,
	DEVELOPMENT
}

const TEMPLATES := {
	TemplateType.EMPTY: {
		"name": "Empty",
		"description": "空模板 - 无任何配置",
		"config": {}
	},
	TemplateType.DEFAULT: {
		"name": "Default",
		"description": "默认模板 - 标准反作弊配置",
		"config": {
			"enable_detection": true,
			"enable_report": true,
			"verify_interval": 1000,
			"disturb_min": 2,
			"disturb_max": 5,
			"protect_level": 2
		}
	},
	TemplateType.MINIMAL: {
		"name": "Minimal",
		"description": "最小模板 - 基础保护，最低开销",
		"config": {
			"enable_detection": true,
			"enable_report": false,
			"verify_interval": 2000,
			"disturb_min": 1,
			"disturb_max": 2,
			"protect_level": 1
		}
	},
	TemplateType.MAXIMUM: {
		"name": "Maximum",
		"description": "最大模板 - 全面保护，最高安全",
		"config": {
			"enable_detection": true,
			"enable_report": true,
			"verify_interval": 500,
			"disturb_min": 5,
			"disturb_max": 15,
			"protect_level": 3
		}
	},
	TemplateType.COMPETITIVE: {
		"name": "Competitive",
		"description": "竞技模板 - 适合竞技游戏",
		"config": {
			"enable_detection": true,
			"enable_report": true,
			"verify_interval": 750,
			"disturb_min": 3,
			"disturb_max": 8,
			"protect_level": 3
		}
	},
	TemplateType.CASUAL: {
		"name": "Casual",
		"description": "休闲模板 - 适合单机/休闲游戏",
		"config": {
			"enable_detection": true,
			"enable_report": false,
			"verify_interval": 3000,
			"disturb_min": 1,
			"disturb_max": 3,
			"protect_level": 1
		}
	},
	TemplateType.DEVELOPMENT: {
		"name": "Development",
		"description": "开发模板 - 方便调试",
		"config": {
			"enable_detection": false,
			"enable_report": false,
			"verify_interval": 5000,
			"disturb_min": 0,
			"disturb_max": 0,
			"protect_level": 0
		}
	}
}

const TEMPLATE_DETAILS := {
	TemplateType.COMPETITIVE: {
		"performance_impact": "中等",
		"security_level": "高级",
		"recommended_for": ["竞技游戏", "多人对战", "排行榜游戏"]
	},
	TemplateType.CASUAL: {
		"performance_impact": "极低",
		"security_level": "基础",
		"recommended_for": ["单机游戏", "休闲游戏", "解谜游戏"]
	},
	TemplateType.MAXIMUM: {
		"performance_impact": "较高",
		"security_level": "高级",
		"recommended_for": ["竞技游戏", "高价值游戏", "敏感数据保护"]
	},
	TemplateType.MINIMAL: {
		"performance_impact": "极低",
		"security_level": "基础",
		"recommended_for": ["低端设备", "性能敏感场景"]
	},
	TemplateType.DEFAULT: {
		"performance_impact": "中等",
		"security_level": "标准",
		"recommended_for": ["多数游戏", "平衡配置"]
	}
}

const TEMPLATE_VERSION := 1

static func get_template(type: TemplateType) -> Dictionary:
	if not TEMPLATES.has(type):
		return {}
	return TEMPLATES[type].duplicate(true)

static func get_template_details(type: TemplateType) -> Dictionary:
	if not TEMPLATE_DETAILS.has(type):
		return {}
	return TEMPLATE_DETAILS[type].duplicate(true)

static func get_template_names() -> Dictionary:
	var names = {}
	for type in TEMPLATES:
		names[type] = TEMPLATES[type]["name"]
	return names

static func get_template_description(type: TemplateType) -> String:
	if not TEMPLATES.has(type):
		return ""
	return TEMPLATES[type]["description"]

static func list_templates() -> Array:
	var list = []
	for type in TEMPLATES:
		list.append({
			"type": type,
			"name": TEMPLATES[type]["name"],
			"description": TEMPLATES[type]["description"],
			"config": TEMPLATES[type]["config"].duplicate(true)
		})
	return list

static func apply_template(config: DERConfigManager, type: TemplateType) -> bool:
	var template = get_template(type)
	if template.is_empty():
		return false
	
	for key in template["config"]:
		config.set_value(key, template["config"][key])
	
	return true

static func create_template(name: String, description: String, config: Dictionary) -> Dictionary:
	return {
		"version": TEMPLATE_VERSION,
		"name": name,
		"description": description,
		"config": config
	}

static func create_from_config(config: DERConfigManager, name: String, description: String = "") -> Dictionary:
	return create_template(name, description, config.get_all(true))

static func create_from_preset(preset_type: int, name: String = "", description: String = "") -> Dictionary:
	var preset = DERConfigPreset.get_preset(preset_type)
	if preset.is_empty():
		return {}
	
	var config_dict = {}
	for key in DERConfigPreset.CONFIG_KEYS:
		if preset.has(key):
			config_dict[key] = preset[key]
	
	var template_name = name
	if template_name == "":
		template_name = preset.get("name", "Untitled")
	
	var template_desc = description
	if template_desc == "":
		template_desc = preset.get("description", "")
	
	return create_template(template_name, template_desc, config_dict)

static func clone_template(template: Dictionary, new_name: String, new_description: String = "") -> Dictionary:
	var cloned = template.duplicate(true)
	cloned["name"] = new_name
	if new_description != "":
		cloned["description"] = new_description
	return cloned

static func compare_template(current_config: Dictionary, template: Dictionary) -> Array:
	var template_config = template.get("config", {})
	var diff_helper = DERConfigDiff.new()
	return diff_helper.compare(current_config, template_config, false)

static func get_template_diff_summary(current_config: Dictionary, template: Dictionary) -> Dictionary:
	var diffs = compare_template(current_config, template)
	var summary = {
		"total": diffs.size(),
		"modified": 0,
		"type_changed": 0
	}
	for d in diffs:
		match d.type:
			DERConfigDiff.DiffType.MODIFIED:
				summary.modified += 1
			DERConfigDiff.DiffType.TYPE_CHANGED:
				summary.type_changed += 1
	return summary

static func is_template_active(current_config: Dictionary, template: Dictionary) -> bool:
	return compare_template(current_config, template).is_empty()

static func validate_template(template: Dictionary, strict: bool = false) -> bool:
	if not template.has("name"):
		push_error("DERConfigTemplate: Missing name")
		return false
	
	if not template.has("config"):
		push_error("DERConfigTemplate: Missing config")
		return false
	
	if not template["config"] is Dictionary:
		push_error("DERConfigTemplate: Config must be a dictionary")
		return false
	
	if strict:
		for key in DERConfigPreset.CONFIG_KEYS:
			if not template["config"].has(key):
				push_error("DERConfigTemplate: Missing required config key: %s" % key)
				return false
		
		var interval = template["config"].get("verify_interval", 0)
		if interval < 100:
			push_error("DERConfigTemplate: verify_interval must be >= 100ms")
			return false
		
		var min_val = template["config"].get("disturb_min", 0)
		var max_val = template["config"].get("disturb_max", 0)
		if min_val > max_val:
			push_error("DERConfigTemplate: disturb_min > disturb_max")
			return false
		
		var level = template["config"].get("protect_level", -1)
		if level < 0 or level > 3:
			push_error("DERConfigTemplate: protect_level must be 0-3")
			return false
	
	return true

static func export_template(template: Dictionary, path: String) -> int:
	if not validate_template(template):
		return ERR_INVALID_DATA
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify(template, "\t"))
	return OK

static func import_template(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("DERConfigTemplate: Cannot open %s" % path)
		return {}
	
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("DERConfigTemplate: Failed to parse %s: %s" % [path, json.get_error_message()])
		return {}
	
	var data = json.get_data()
	if not (data is Dictionary):
		push_error("DERConfigTemplate: Invalid format in %s" % path)
		return {}
	
	if not validate_template(data):
		push_error("DERConfigTemplate: Invalid template data in %s" % path)
		return {}
	
	return data

static func merge_templates(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	
	if override.has("name"):
		result["name"] = override["name"]
	if override.has("description"):
		result["description"] = override["description"]
	
	if override.has("config"):
		for key in override["config"]:
			result["config"][key] = override["config"][key]
	
	return result

static func get_template_summary(template: Dictionary) -> Dictionary:
	var config = template.get("config", {})
	return {
		"name": template.get("name", "Unknown"),
		"description": template.get("description", ""),
		"enable_detection": config.get("enable_detection", false),
		"enable_report": config.get("enable_report", false),
		"verify_interval": config.get("verify_interval", 0),
		"disturb_min": config.get("disturb_min", 0),
		"disturb_max": config.get("disturb_max", 0),
		"protect_level": config.get("protect_level", 0)
	}

static func get_performance_impact(type: TemplateType) -> String:
	var details = get_template_details(type)
	return details.get("performance_impact", "未知")

static func get_security_level(type: TemplateType) -> String:
	var details = get_template_details(type)
	return details.get("security_level", "未知")