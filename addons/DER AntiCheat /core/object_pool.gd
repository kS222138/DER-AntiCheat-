extends RefCounted
class_name ObjectPool

signal object_acquired(obj: RefCounted)
signal object_released(obj: RefCounted)
signal pool_full(size: int)

enum EvictionPolicy {
	FIFO,
	LRU,
	LFU
}

@export var max_size: int = 100
@export var initial_size: int = 10
@export var eviction_policy: EvictionPolicy = EvictionPolicy.LRU
@export var auto_cleanup: bool = true
@export var cleanup_interval: float = 60.0
@export var max_idle_time: float = 300.0

var _pool: Array = []
var _active_objects: Dictionary = {}
var _factory: Callable
var _reset_func: Callable
var _destroy_func: Callable
var _access_times: Dictionary = {}
var _access_counts: Dictionary = {}
var _creation_times: Dictionary = {}
var _cleanup_timer: Timer = null
var _tree: SceneTree = null


func _init(factory: Callable, reset_func: Callable = Callable(), destroy_func: Callable = Callable()):
	_factory = factory
	_reset_func = reset_func
	_destroy_func = destroy_func


func setup(tree: SceneTree) -> void:
	_tree = tree
	if auto_cleanup:
		_setup_cleanup_timer()


func initialize() -> void:
	var now = Time.get_ticks_msec()
	for i in range(initial_size):
		var obj = _factory.call()
		_pool.append(obj)
		_creation_times[obj] = now
		_access_times[obj] = now


func acquire() -> RefCounted:
	var obj: RefCounted = null
	
	if _pool.is_empty():
		obj = _factory.call()
		_creation_times[obj] = Time.get_ticks_msec()
	else:
		obj = _pool.pop_back()
		_update_access(obj)
	
	_active_objects[obj] = true
	object_acquired.emit(obj)
	return obj


func release(obj: RefCounted) -> bool:
	if not _active_objects.has(obj):
		return false
	
	_active_objects.erase(obj)
	
	if _reset_func.is_valid():
		_reset_func.call(obj)
	
	if _pool.size() < max_size:
		_pool.append(obj)
		object_released.emit(obj)
	else:
		_destroy(obj)
	
	return true


func _destroy(obj: RefCounted) -> void:
	_active_objects.erase(obj)
	
	if _destroy_func.is_valid():
		_destroy_func.call(obj)
	# RefCounted 自动管理生命周期，不手动 free


func get_pool_size() -> int:
	return _pool.size()


func get_active_count() -> int:
	return _active_objects.size()


func get_total_objects() -> int:
	return _pool.size() + _active_objects.size()


func clear_pool() -> void:
	if _active_objects.size() > 0:
		push_warning("ObjectPool.clear_pool(): %d active objects still exist" % _active_objects.size())
	
	for obj in _pool:
		if _destroy_func.is_valid():
			_destroy_func.call(obj)
	_pool.clear()


func cleanup_idle() -> void:
	var now = Time.get_ticks_msec()
	var to_remove = []
	
	for obj in _pool:
		var last_access = _access_times.get(obj, now)
		if now - last_access > max_idle_time * 1000:
			to_remove.append(obj)
	
	for obj in to_remove:
		_pool.erase(obj)
		_cleanup_object(obj)


func _update_access(obj: RefCounted) -> void:
	var now = Time.get_ticks_msec()
	_access_times[obj] = now
	
	var count = _access_counts.get(obj, 0)
	_access_counts[obj] = count + 1


func _cleanup_object(obj: RefCounted) -> void:
	_creation_times.erase(obj)
	_access_times.erase(obj)
	_access_counts.erase(obj)
	
	if _destroy_func.is_valid():
		_destroy_func.call(obj)


func _setup_cleanup_timer() -> void:
	if not _tree:
		return
	
	_cleanup_timer = Timer.new()
	_cleanup_timer.wait_time = cleanup_interval
	_cleanup_timer.autostart = true
	_cleanup_timer.timeout.connect(cleanup_idle)
	_tree.root.add_child(_cleanup_timer)


func shutdown() -> void:
	if _cleanup_timer:
		_cleanup_timer.queue_free()
		_cleanup_timer = null
	clear_pool()


func get_stats() -> Dictionary:
	return {
		"pool_size": _pool.size(),
		"active_count": _active_objects.size(),
		"total_objects": get_total_objects(),
		"max_size": max_size,
		"eviction_policy": eviction_policy,
		"auto_cleanup": auto_cleanup,
		"cleanup_interval": cleanup_interval,
		"max_idle_time": max_idle_time
	}


func shrink() -> void:
	var target_size = max_size / 2
	
	while _pool.size() > target_size:
		var obj = _select_victim()
		_pool.erase(obj)
		_cleanup_object(obj)
	
	pool_full.emit(_pool.size())


func _select_victim() -> RefCounted:
	match eviction_policy:
		EvictionPolicy.FIFO:
			return _pool[0]
		EvictionPolicy.LRU:
			var oldest = _pool[0]
			var oldest_time = _access_times.get(oldest, 0)
			for obj in _pool:
				var time = _access_times.get(obj, 0)
				if time < oldest_time:
					oldest = obj
					oldest_time = time
			return oldest
		EvictionPolicy.LFU:
			var least_used = _pool[0]
			var least_count = _access_counts.get(least_used, 0)
			for obj in _pool:
				var count = _access_counts.get(obj, 0)
				if count < least_count:
					least_used = obj
					least_count = count
			return least_used
		_:
			return _pool[0]


func reset_stats() -> void:
	_access_times.clear()
	_access_counts.clear()