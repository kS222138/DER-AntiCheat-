class_name DERConfigValidator
extends RefCounted

enum ValidationLevel {
	INFO,
	WARNING,
	ERROR
}

class ValidationResult:
	var key: String
	var level: ValidationLevel
	var message: String
	var value: Variant
	var expected: Variant
	
	func _init(k: String, l: ValidationLevel, msg: String, v = null, e = null):
		key = k
		level = l
		message = msg
		value = v
		expected = e
	
	func to_string() -> String:
		var level_str = ["INFO", "WARNING", "ERROR"][level]
		var msg = "[%s] %s: %s" % [level_str, key, message]
		if value != null:
			msg += " (value: %s)" % str(value)
		if expected != null:
			msg += " (expected: %s)" % str(expected)
		return msg
	
	func to_dict() -> Dictionary:
		return {
			"key": key,
			"level": level,
			"level_name": ["INFO", "WARNING", "ERROR"][level],
			"message": message,
			"value": value,
			"expected": expected
		}

var _rules: Dictionary = {}
var _custom_validators: Dictionary = {}
var _on_error: Callable

func _init():
	_setup_default_rules()

func _setup_default_rules():
	_rules = {
		"enable_detection": {
			"type": TYPE_BOOL,
			"required": true,
			"default": true
		},
		"enable_report": {
			"type": TYPE_BOOL,
			"required": true,
			"default": true
		},
		"verify_interval": {
			"type": TYPE_INT,
			"required": true,
			"min": 100,
			"max": 10000,
			"default": 1000
		},
		"disturb_min": {
			"type": TYPE_INT,
			"required": true,
			"min": 0,
			"max": 50,
			"default": 2
		},
		"disturb_max": {
			"type": TYPE_INT,
			"required": true,
			"min": 0,
			"max": 50,
			"default": 5
		},
		"protect_level": {
			"type": TYPE_INT,
			"required": true,
			"min": 0,
			"max": 3,
			"default": 2
		}
	}

func add_rule(key: String, rule: Dictionary) -> void:
	_rules[key] = rule

func remove_rule(key: String) -> void:
	_rules.erase(key)

func add_custom_validator(key: String, validator: Callable) -> void:
	_custom_validators[key] = validator

func remove_custom_validator(key: String) -> void:
	_custom_validators.erase(key)

func set_error_handler(callback: Callable) -> void:
	_on_error = callback

func _create_result(key: String, level: ValidationLevel, msg: String, val, exp) -> ValidationResult:
	return ValidationResult.new(key, level, msg, val, exp)

func _emit_error(result: ValidationResult) -> void:
	if _on_error and result.level == ValidationLevel.ERROR:
		_on_error.call(result)

func validate(config: Dictionary) -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	
	for key in _rules:
		var rule = _rules[key]
		var value = config.get(key)
		
		if value == null and rule.get("required", false):
			var result = _create_result(key, ValidationLevel.ERROR, "Missing required key", value, rule.get("default"))
			results.append(result)
			_emit_error(result)
			continue
		
		if value == null:
			continue
		
		if rule.has("type") and typeof(value) != rule["type"]:
			var result = _create_result(key, ValidationLevel.ERROR, "Type mismatch", value, rule["type"])
			results.append(result)
			_emit_error(result)
			continue
		
		if rule.has("min") and value < rule["min"]:
			var result = _create_result(key, ValidationLevel.WARNING, "Value below minimum", value, rule["min"])
			results.append(result)
		
		if rule.has("max") and value > rule["max"]:
			var result = _create_result(key, ValidationLevel.WARNING, "Value above maximum", value, rule["max"])
			results.append(result)
		
		if rule.has("values") and not value in rule["values"]:
			var result = _create_result(key, ValidationLevel.ERROR, "Invalid value", value, rule["values"])
			results.append(result)
			_emit_error(result)
	
	if config.has("disturb_min") and config.has("disturb_max"):
		var min_val = config["disturb_min"]
		var max_val = config["disturb_max"]
		if min_val > max_val:
			var result = _create_result("disturb_min", ValidationLevel.WARNING, "disturb_min > disturb_max", min_val, max_val)
			results.append(result)
	
	for key in config:
		if not _rules.has(key) and key != "name" and key != "description":
			var result = _create_result(key, ValidationLevel.INFO, "Unknown key", config[key], null)
			results.append(result)
	
	for key in _custom_validators:
		if config.has(key):
			var result = _custom_validators[key].call(config[key])
			if result != null:
				results.append(result)
				if result.level == ValidationLevel.ERROR:
					_emit_error(result)
	
	return results

func validate_config(config: Dictionary, auto_fix: bool = false) -> bool:
	var results = validate(config)
	var has_error = false
	
	for r in results:
		if r.level == ValidationLevel.ERROR:
			has_error = true
			if auto_fix and r.expected != null:
				config[r.key] = r.expected
	
	return not has_error

func fix_config(config: Dictionary) -> Dictionary:
	var fixed = config.duplicate(true)
	
	for key in _rules:
		var rule = _rules[key]
		
		if not fixed.has(key):
			if rule.get("required", false) and rule.has("default"):
				fixed[key] = rule["default"]
			continue
		
		var value = fixed[key]
		
		if rule.has("type") and typeof(value) != rule["type"]:
			if rule.has("default"):
				fixed[key] = rule["default"]
			continue
		
		if rule.has("min") and value < rule["min"]:
			fixed[key] = rule["min"]
		elif rule.has("max") and value > rule["max"]:
			fixed[key] = rule["max"]
		elif rule.has("values") and not value in rule["values"]:
			if rule.has("default"):
				fixed[key] = rule["default"]
	
	if fixed.has("disturb_min") and fixed.has("disturb_max"):
		if fixed["disturb_min"] > fixed["disturb_max"]:
			fixed["disturb_max"] = fixed["disturb_min"] + 1
	
	return fixed

func get_default_config() -> Dictionary:
	var default_config = {}
	for key in _rules:
		if _rules[key].has("default"):
			default_config[key] = _rules[key]["default"]
	return default_config

func get_rule_info(key: String) -> Dictionary:
	return _rules.get(key, {})

func get_all_rules() -> Dictionary:
	return _rules.duplicate(true)

func export_rules(path: String) -> int:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify(_rules, "\t"))
	return OK

func import_rules(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		return false
	var data = json.get_data()
	if data is Dictionary:
		_rules = data
		return true
	return false

func generate_report(results: Array[ValidationResult]) -> String:
	if results.is_empty():
		return "Configuration is valid. No issues found."
	
	var report = "Configuration Validation Report\n"
	report += "========================================\n"
	
	var counts = {"ERROR": 0, "WARNING": 0, "INFO": 0}
	for r in results:
		var level_name = ["INFO", "WARNING", "ERROR"][r.level]
		counts[level_name] += 1
		report += r.to_string() + "\n"
	
	report += "========================================\n"
	report += "Summary: " + str(counts.ERROR) + " errors, " + str(counts.WARNING) + " warnings, " + str(counts.INFO) + " info"
	return report

func validate_batch(configs: Array) -> Array:
	var results = []
	for config in configs:
		results.append(validate(config))
	return results

static func create_range_rule(type: int, required: bool, min_val, max_val, default_val) -> Dictionary:
	return {
		"type": type,
		"required": required,
		"min": min_val,
		"max": max_val,
		"default": default_val
	}

static func create_enum_rule(type: int, required: bool, values: Array, default_val) -> Dictionary:
	return {
		"type": type,
		"required": required,
		"values": values,
		"default": default_val
	}