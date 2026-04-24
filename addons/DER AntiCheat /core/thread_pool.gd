extends Node
class_name ThreadPool

enum Priority {
	LOW = 0,
	NORMAL = 1,
	HIGH = 2,
	CRITICAL = 3
}

enum TaskStatus {
	PENDING,
	RUNNING,
	COMPLETED,
	FAILED,
	CANCELLED
}

@export var min_threads: int = 2
@export var max_threads: int = 8
@export var retry_base_delay: float = 0.1
@export var max_retries: int = 3
@export var scale_cooldown_ms: int = 1000

signal task_completed(task_id: int, result: Variant)
signal task_failed(task_id: int, error: String)
signal task_cancelled(task_id: int)

class Task:
	var id: int
	var callable: Callable
	var priority: int
	var timeout: float
	var retry: int
	var max_retries: int
	var status: int
	var result: Variant
	var error: String
	var timer: SceneTreeTimer
	
	func _init(p_id: int, p_callable: Callable, p_priority: int, p_timeout: float, p_max_retries: int):
		id = p_id
		callable = p_callable
		priority = p_priority
		timeout = p_timeout
		retry = 0
		max_retries = p_max_retries
		status = TaskStatus.PENDING
		result = null
		error = ""
		timer = null

class Worker:
	var thread: Thread
	var sem: Semaphore
	var busy: bool
	var stop: bool
	var id: int
	
	func _init(p_id: int):
		id = p_id
		sem = Semaphore.new()
		busy = false
		stop = false
		thread = Thread.new()

var _workers: Array[Worker] = []
var _queues: Array[Array] = []
var _task_map: Dictionary = {}
var _next_task_id: int = 0
var _mutex: Mutex = Mutex.new()
var _shutting_down: bool = false
var _last_scale_time: int = 0

func _ready():
	for i in range(Priority.CRITICAL + 1):
		_queues.append([])
	
	for i in range(min_threads):
		_create_worker()

func submit(task_callable: Callable, priority: int = Priority.NORMAL, timeout: float = 0.0, task_max_retries: int = -1) -> int:
	_mutex.lock()
	var task_id = _next_task_id
	_next_task_id += 1
	
	var retries = task_max_retries
	if retries < 0:
		retries = max_retries
	
	var task = Task.new(task_id, task_callable, priority, timeout, retries)
	_queues[priority].push_back(task)
	_task_map[task_id] = task
	_mutex.unlock()
	
	_wake_one()
	return task_id

func cancel(task_id: int) -> bool:
	_mutex.lock()
	var task = _task_map.get(task_id)
	if task and task.status == TaskStatus.PENDING:
		task.status = TaskStatus.CANCELLED
		_remove_from_queue(task_id)
		_task_map.erase(task_id)
		_mutex.unlock()
		task_cancelled.emit(task_id)
		return true
	_mutex.unlock()
	return false

func get_status(task_id: int) -> int:
	_mutex.lock()
	var task = _task_map.get(task_id)
	var status = task.status if task else -1
	_mutex.unlock()
	return status

func get_stats() -> Dictionary:
	_mutex.lock()
	var pending = 0
	for q in _queues:
		pending += q.size()
	var busy = 0
	for w in _workers:
		if w.busy:
			busy += 1
	var stats = {
		"workers": _workers.size(),
		"busy": busy,
		"idle": _workers.size() - busy,
		"pending": pending,
		"total_tasks": _task_map.size()
	}
	_mutex.unlock()
	return stats

func wait_for_all():
	while true:
		_mutex.lock()
		var pending = 0
		for q in _queues:
			pending += q.size()
		var running = 0
		for task in _task_map.values():
			if task.status == TaskStatus.RUNNING:
				running += 1
		var done = (pending == 0 and running == 0)
		_mutex.unlock()
		if done:
			break
		await get_tree().process_frame

func shutdown(force: bool = false):
	_shutting_down = true
	if not force:
		await wait_for_all()
	
	_mutex.lock()
	for w in _workers:
		w.stop = true
		w.sem.post()
	_mutex.unlock()
	
	for w in _workers:
		if w.thread.is_started():
			w.thread.wait_to_finish()
	
	_workers.clear()
	_queues.clear()
	_task_map.clear()

func _create_worker():
	var worker = Worker.new(_workers.size())
	_workers.append(worker)
	worker.thread.start(_worker_loop.bind(worker))

func _remove_worker():
	if _workers.size() <= min_threads:
		return
	var worker = _workers.pop_back()
	worker.stop = true
	worker.sem.post()
	if worker.thread.is_started():
		worker.thread.wait_to_finish()

func _worker_loop(worker: Worker):
	while not worker.stop:
		var task = _get_task()
		if task == null:
			worker.sem.wait()
			continue
		
		worker.busy = true
		_execute(task)
		worker.busy = false
		
		_mutex.lock()
		var should_scale = _should_scale_down()
		_mutex.unlock()
		if should_scale:
			_scale_down()

func _get_task():
	_mutex.lock()
	for p in range(Priority.CRITICAL, -1, -1):
		if _queues[p].size() > 0:
			var task = _queues[p].pop_front()
			if task.status == TaskStatus.PENDING:
				task.status = TaskStatus.RUNNING
				_mutex.unlock()
				return task
			else:
				_mutex.unlock()
				return null
	_mutex.unlock()
	return null

func _execute(task: Task):
	if task.timeout > 0:
		task.timer = get_tree().create_timer(task.timeout, false)
		task.timer.timeout.connect(_on_task_timeout.bind(task.id))
	
	var result = null
	var error = ""
	var success = false
	
	if task.callable.is_valid():
		var call_result = task.callable.call()
		if call_result is Dictionary and call_result.has("error"):
			error = call_result.error
			success = false
		else:
			result = call_result
			success = true
	else:
		error = "Invalid callable"
		success = false
	
	if task.timer:
		task.timer.timeout.disconnect(_on_task_timeout.bind(task.id))
	
	if success:
		_mutex.lock()
		task.status = TaskStatus.COMPLETED
		task.result = result
		_task_map.erase(task.id)
		_mutex.unlock()
		task_completed.emit(task.id, result)
	else:
		_handle_failure(task, error)

func _handle_failure(task: Task, error: String):
	if task.retry < task.max_retries:
		task.retry += 1
		task.status = TaskStatus.PENDING
		task.error = error
		
		var delay = pow(2.0, task.retry - 1) * retry_base_delay
		await get_tree().create_timer(delay).timeout
		
		_mutex.lock()
		_queues[task.priority].push_back(task)
		_mutex.unlock()
		_wake_one()
	else:
		_mutex.lock()
		task.status = TaskStatus.FAILED
		task.error = error
		_task_map.erase(task.id)
		_mutex.unlock()
		task_failed.emit(task.id, error)

func _on_task_timeout(task_id: int):
	_mutex.lock()
	var task = _task_map.get(task_id)
	if task and task.status == TaskStatus.RUNNING:
		task.status = TaskStatus.FAILED
		task.error = "Timeout after %.2f seconds" % task.timeout
		_task_map.erase(task_id)
		_mutex.unlock()
		task_failed.emit(task_id, task.error)
	else:
		_mutex.unlock()

func _wake_one():
	_mutex.lock()
	for w in _workers:
		if not w.busy and not w.stop:
			w.sem.post()
			_mutex.unlock()
			return
	
	if _workers.size() < max_threads:
		var now = Time.get_ticks_msec()
		if now - _last_scale_time >= scale_cooldown_ms:
			_last_scale_time = now
			_create_worker()
	_mutex.unlock()

func _should_scale_down() -> bool:
	var now = Time.get_ticks_msec()
	if now - _last_scale_time < scale_cooldown_ms:
		return false
	
	var pending = 0
	for q in _queues:
		pending += q.size()
	
	var busy = 0
	for w in _workers:
		if w.busy:
			busy += 1
	
	return pending == 0 and busy == 0 and _workers.size() > min_threads

func _scale_down():
	_mutex.lock()
	var now = Time.get_ticks_msec()
	if now - _last_scale_time >= scale_cooldown_ms and _workers.size() > min_threads:
		_last_scale_time = now
		_remove_worker()
	_mutex.unlock()

func _remove_from_queue(task_id: int):
	for p in range(Priority.CRITICAL + 1):
		for i in range(_queues[p].size()):
			if _queues[p][i].id == task_id:
				_queues[p].remove_at(i)
				return

func _exit_tree():
	if not _shutting_down:
		shutdown(true)
