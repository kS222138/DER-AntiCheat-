@tool
extends Resource
class_name DERProtectionPreset

@export_group("Metadata")
@export var preset_name: String = "Custom"
@export_multiline var preset_description: String = ""
@export var preset_icon: String = ""

@export_group("Core Protection")
@export var vanguard_value_enabled: bool = true
@export var pool_enabled: bool = true
@export var memory_obfuscator_enabled: bool = false
@export var thread_pool_enabled: bool = true
@export var object_pool_enabled: bool = true
@export var performance_monitor_enabled: bool = false

@export_group("Injection Detection")
@export var inject_detector_enabled: bool = true
@export var memory_scanner_enabled: bool = true
@export var hook_detector_enabled: bool = true
@export var process_scanner_v2_enabled: bool = true
@export var multi_instance_enabled: bool = false
@export var vm_detector_enabled: bool = false

@export_group("Anti-Debug")
@export var debugger_detector_enabled: bool = true
@export var debug_detector_v2_enabled: bool = false
@export var integrity_check_enabled: bool = true

@export_group("Network Protection")
@export var network_client_enabled: bool = false
@export var packet_protector_enabled: bool = false
@export var replay_protector_enabled: bool = false
@export var time_sync_enabled: bool = false
@export var consistency_validator_enabled: bool = false
@export var ccu_optimizer_enabled: bool = false

@export_group("Speed & Position")
@export var speed_detector_enabled: bool = true
@export var speed_detector_v2_enabled: bool = true
@export var virtual_pos_detector_enabled: bool = false

@export_group("Storage & Save")
@export var archive_encryptor_enabled: bool = false
@export var archive_manager_enabled: bool = false
@export var file_validator_enabled: bool = true
@export var rollback_detector_enabled: bool = false
@export var save_limit_enabled: bool = false
@export var cloud_validator_enabled: bool = false
@export var cloud_snapshot_enabled: bool = false

@export_group("Device & Access")
@export var device_fingerprint_enabled: bool = false
@export var whitelist_manager_enabled: bool = false

@export_group("Logging & Monitoring")
@export var encrypted_logger_enabled: bool = false
@export var alert_manager_enabled: bool = false
@export var report_exporter_enabled: bool = false
@export var dashboard_enabled: bool = false
@export var stats_chart_enabled: bool = false
@export var log_exporter_enabled: bool = false

@export_group("Dev Tools")
@export var profiler_enabled: bool = false
@export var cheat_simulator_enabled: bool = false
@export var file_integrity_enabled: bool = false
@export var offline_protector_enabled: bool = false
@export var log_encryptor_enabled: bool = false