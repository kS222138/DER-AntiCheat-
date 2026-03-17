class_name DERNetworkClient
extends RefCounted

signal network_quality_changed(old_quality, new_quality)
signal request_completed(request_id, success, time_ms, error_code)
signal connection_state_changed(old_state, new_state)
signal file_transfer_progress(transfer_id, progress, speed)
signal security_alert(alert_type, severity, details)
signal connection_lost()
signal connection_restored()

enum RequestPriority { LOW, NORMAL, HIGH, CRITICAL }
enum CompressionLevel { NONE, FAST, BEST, ADAPTIVE }
enum NetworkQuality { UNKNOWN, POOR, FAIR, GOOD, EXCELLENT }
enum ConnectionState { DISCONNECTED, CONNECTING, HANDSHAKE, CONNECTED, RECONNECTING, OFFLINE }
enum NetworkError {
    OK, HANDSHAKE_REQUIRED, RATE_LIMITED, REQUEST_FAILED, CONNECTION_FAILED,
    RESPONSE_TIMEOUT, INVALID_RESPONSE, SESSION_EXPIRED, NETWORK_UNAVAILABLE,
    CERTIFICATE_ERROR, BATCH_ERROR, BANDWIDTH_EXCEEDED, INVALID_CERTIFICATE,
    PROXY_ERROR, REQUEST_CANCELLED, SERVER_ERROR, CLIENT_ERROR, PARSING_ERROR, CIRCUIT_OPEN
}

class AtomicCounter:
    var _value = 0
    var _mutex = Mutex.new()
    func inc(): _mutex.lock(); _value += 1; var r = _value; _mutex.unlock(); return r

class CircuitBreaker:
    enum State { CLOSED, OPEN, HALF_OPEN }
    var _state = State.CLOSED
    var _failures = 0
    var _threshold = 5
    var _timeout = 30.0
    var _last_fail = 0
    var _mutex = Mutex.new()
    
    func success():
        _mutex.lock()
        if _state == State.HALF_OPEN: _state = State.CLOSED; _failures = 0
        _mutex.unlock()
    
    func failure():
        _mutex.lock()
        _failures += 1; _last_fail = Time.get_unix_time_from_system()
        if _state == State.CLOSED and _failures >= _threshold: _state = State.OPEN
        elif _state == State.HALF_OPEN: _state = State.OPEN
        _mutex.unlock()
    
    func allow():
        _mutex.lock()
        var r = false
        if _state == State.CLOSED: r = true
        elif _state == State.OPEN:
            if Time.get_unix_time_from_system() - _last_fail > _timeout:
                _state = State.HALF_OPEN; r = true
        elif _state == State.HALF_OPEN: r = true
        _mutex.unlock()
        return r

var _protector
var _http_node
var _endpoint
var _timeout = 5.0
var _retry_count = 3
var _retry_delay = 1.0
var _max_rps = 20
var _pending = {}
var _req_counter = AtomicCounter.new()
var _req_times = []
var _handshake_done = false
var _conn_state = ConnectionState.DISCONNECTED
var _cleanup_timer
var _cancelled = {}
var _http_pool = []
var _max_conn = 4
var _conn_index = 0
var _debug = false
var _heartbeat_timer
var _heartbeat_int = 30.0
var _compress_lvl = CompressionLevel.ADAPTIVE
var _queues = { RequestPriority.LOW: [], RequestPriority.NORMAL: [], RequestPriority.HIGH: [], RequestPriority.CRITICAL: [] }
var _net_quality = NetworkQuality.UNKNOWN
var _latency = []
var _reconnect_attempts = 0
var _max_reconnect = 5
var _req_timeouts = {}
var _bandwidth_used = 0
var _bandwidth_limit = 1048576
var _bandwidth_reset = 0
var _dns_cache = {}
var _dns_ttl = 300
var _dns_queue = []
var _dns_resolving = {}
var _coalescing = {}
var _coalesce_window = 0.1
var _offline = false
var _offline_q = []
var _stats = {
    "sent": 0, "succeeded": 0, "failed": 0, "bytes_sent": 0,
    "bytes_recv": 0, "avg_latency": 0.0, "cache_hits": 0, "coalesced": 0
}
var _ws_clients = {}
var _ws_urls = {}
var _alerts = { "high_latency": false }
var _config = {
    "timeout": 5.0, "retry_count": 3, "retry_delay": 1.0, "max_rps": 20,
    "max_conn": 4, "heartbeat_int": 30.0, "bandwidth_limit": 1048576,
    "compress_lvl": CompressionLevel.ADAPTIVE, "debug": false,
    "cert_pinning": true, "auto_reconnect": true
}
var _breaker = CircuitBreaker.new()
var _main_thread = -1
var _transfers = {}
var _transfer_counter = AtomicCounter.new()

func _init(endpoint, owner = null):
    _main_thread = OS.get_thread_caller_id()
    _protector = DERPacketProtector.new()
    _endpoint = _validate(endpoint)
    _http_node = owner if owner else _make_node()
    for i in _max_conn: _http_pool.append(_make_http())
    _setup_cert_pinning()
    _start_cleanup()
    load_config()
    _measure_latency()

func _validate(url): return url.replace("http://", "https://") if not url.begins_with("https://") else url

func _make_node():
    var n = Node.new()
    n.name = "DERHTTPNode"
    if Engine.get_main_loop(): Engine.get_main_loop().root.add_child(n)
    return n

func _make_http():
    var h = HTTPRequest.new()
    _http_node.add_child(h)
    h.timeout = _timeout
    h.set_download_chunk_size(65536)
    h.set_max_redirects(5)
    return h

func _setup_cert_pinning():
    if not _config.cert_pinning: return
    var cert = _load_cert()
    if not cert: return
    for h in _http_pool:
        var opts = TLSOptions.client(cert, "")
        h.set_tls_options(opts)

func _load_cert():
    for p in ["res://certificates/server.crt", "user://certificates/server.crt"]:
        if FileAccess.file_exists(p):
            var f = FileAccess.open(p, FileAccess.READ)
            if f:
                var c = X509Certificate.new()
                if c.load(f.get_as_text()) == OK: return c
    return null

func _get_http():
    if not _breaker.allow(): return null
    for i in _http_pool.size():
        _conn_index = (_conn_index + 1) % _http_pool.size()
        var h = _http_pool[_conn_index]
        if h.is_ready(): return h
    return null

func _start_cleanup():
    if not _http_node or not _http_node.get_tree(): return
    _cleanup_timer = _http_node.get_tree().create_timer(5.0)
    _cleanup_timer.timeout.connect(_on_cleanup)

func _on_cleanup():
    _cleanup_old()
    _process_dns()
    _start_cleanup()

func _cleanup_old():
    var now = Time.get_ticks_msec()
    var expired = []
    for id in _pending:
        if now - _pending[id].timestamp > _timeout * 2000: expired.append(id)
    for id in expired:
        if _pending[id].callback: _pending[id].callback.call(false, _err_resp(NetworkError.RESPONSE_TIMEOUT))
        _pending.erase(id)
        request_completed.emit(id, false, Time.get_ticks_msec() - _pending[id].timestamp, NetworkError.RESPONSE_TIMEOUT)

func _dns_lookup(host, cb):
    if _dns_cache.has(host):
        var e = _dns_cache[host]
        if Time.get_unix_time_from_system() - e.t < _dns_ttl:
            _stats.cache_hits += 1; cb.call(e.ip); return
    _dns_queue.append({ "host": host, "cb": cb })
    _process_dns()

func _process_dns():
    if _dns_queue.is_empty() or _dns_resolving.size() >= 2: return
    var task = _dns_queue.pop_front()
    if _dns_resolving.has(task.host): _dns_queue.append(task); return
    _dns_resolving[task.host] = true
    var t = Thread.new()
    t.start(func(): 
        var ip = IP.resolve_hostname(task.host)
        call_deferred("_on_dns", task.host, ip, task.cb)
    )

func _on_dns(host, ip, cb):
    _dns_resolving.erase(host)
    if ip: _dns_cache[host] = { "ip": ip, "t": Time.get_unix_time_from_system() }
    cb.call(ip)
    _process_dns()

func net_available():
    var sem = Semaphore.new()
    var ok = false
    var host = _endpoint.split("://")[1].split("/")[0]
    _dns_lookup(host, func(ip): ok = ip != ""; sem.post())
    sem.wait()
    return ok

func _check_bw(size):
    var now = Time.get_ticks_msec() / 1000.0
    if now - _bandwidth_reset >= 1.0: _bandwidth_used = 0; _bandwidth_reset = now
    if _bandwidth_used + size > _bandwidth_limit: return false
    _bandwidth_used += size; return true

func _start_timeout(id, ms):
    var t = _http_node.get_tree().create_timer(ms / 1000.0, false)
    t.timeout.connect(_on_timeout.bind(id))
    _req_timeouts[id] = t

func _on_timeout(id):
    if _pending.has(id):
        var r = _pending[id]
        if r.callback: r.callback.call(false, _err_resp(NetworkError.RESPONSE_TIMEOUT))
        _pending.erase(id)
        request_completed.emit(id, false, Time.get_ticks_msec() - r.timestamp, NetworkError.RESPONSE_TIMEOUT)
    if _req_timeouts.has(id): _req_timeouts[id].queue_free(); _req_timeouts.erase(id)

func _coalesce(key, data, cb):
    if not _coalescing.has(key):
        _coalescing[key] = { "data": [], "cbs": [], "timer": _http_node.get_tree().create_timer(_coalesce_window) }
        _coalescing[key].timer.timeout.connect(_send_coalesced.bind(key))
    _coalescing[key].data.append(data)
    _coalescing[key].cbs.append(cb)

func _send_coalesced(key):
    if not _coalescing.has(key): return
    var c = _coalescing[key]
    _coalescing.erase(key)
    _stats.coalesced += c.data.size()
    send_batch(c.data, func(ok, res):
        for i in c.cbs.size():
            if c.cbs[i]: c.cbs[i].call(ok and res.size() > i, res[i] if ok and res.size() > i else res)
    )

func _map_err(r):
    match r:
        HTTPRequest.RESULT_CANT_CONNECT: return NetworkError.CONNECTION_FAILED
        HTTPRequest.RESULT_CANT_RESOLVE: return NetworkError.NETWORK_UNAVAILABLE
        HTTPRequest.RESULT_TIMEOUT: return NetworkError.RESPONSE_TIMEOUT
        HTTPRequest.RESULT_NO_RESPONSE: return NetworkError.RESPONSE_TIMEOUT
        HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return NetworkError.BANDWIDTH_EXCEEDED
        HTTPRequest.RESULT_REQUEST_FAILED: return NetworkError.REQUEST_FAILED
        HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: return NetworkError.INVALID_RESPONSE
        HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: return NetworkError.INVALID_RESPONSE
        HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return NetworkError.CONNECTION_FAILED
        _: return NetworkError.REQUEST_FAILED

func _should_retry(err, code):
    if code >= 400 and code < 500: return code == 408 or code == 429
    if code >= 500: return true
    return err in [NetworkError.CONNECTION_FAILED, NetworkError.RESPONSE_TIMEOUT, NetworkError.NETWORK_UNAVAILABLE]

func send(path, data, cb = null, retry = 0, pri = RequestPriority.NORMAL):
    if OS.get_thread_caller_id() != _main_thread: call_deferred("send", path, data, cb, retry, pri); return
    if _offline: _offline_q.append({ "p": path, "d": data, "cb": cb, "r": retry, "pri": pri }); return
    if _cancelled.has(path): return
    if not _breaker.allow(): if cb: cb.call(false, _err_resp(NetworkError.CIRCUIT_OPEN)); return
    
    var host = _endpoint.split("://")[1].split("/")[0]
    _dns_lookup(host, func(ip): _do_send(path, data, cb, retry, pri))

func _do_send(path, data, cb, retry, pri):
    if not net_available(): if cb: cb.call(false, _err_resp(NetworkError.NETWORK_UNAVAILABLE)); return
    
    var size = JSON.stringify(data).length()
    if not _check_bw(size) and pri != RequestPriority.CRITICAL: pri = max(pri, RequestPriority.LOW)
    
    if _protector.is_session_expired() and path != "/handshake":
        handshake(func(ok, r): send(path, data, cb, retry, pri) if ok else cb.call(false, _err_resp(NetworkError.SESSION_EXPIRED)))
        return
    
    if not _handshake_done and path != "/handshake": if cb: cb.call(false, _err_resp(NetworkError.HANDSHAKE_REQUIRED)); return
    
    var now = Time.get_ticks_msec() / 1000.0
    _req_times = _req_times.filter(func(t): return now - t < 1.0)
    if _req_times.size() >= _max_rps and pri != RequestPriority.CRITICAL: if cb: cb.call(false, _err_resp(NetworkError.RATE_LIMITED)); return
    _req_times.append(now)
    
    var h = _get_http()
    if not h: _queue(path, data, cb, retry, pri); return
    
    var timeout = _timeout
    var rdelay = _retry_delay
    match pri:
        RequestPriority.CRITICAL: timeout = 1.0; rdelay = 0.05
        RequestPriority.HIGH: timeout = 2.0; rdelay = 0.1
        RequestPriority.LOW: timeout = 10.0; rdelay = 2.0
    
    var id = "req_%d_%d" % [_req_counter.inc(), Time.get_ticks_usec()]
    var ts = Time.get_unix_time_from_system()
    var nonce = _nonce()
    var comp = _compress(data)
    var fp = _fingerprint()
    var msg = "%s:%s:%s:%s:%s" % [path, ts, nonce, id, fp]
    
    var ed = {
        "data": comp.data, "compressed": comp.compressed, "timestamp": ts,
        "nonce": nonce, "request_id": id, "fingerprint": fp,
        "hmac": _protector.compute_hmac(msg)
    }
    
    var pkt = _protector.encrypt_packet(ed)
    var headers = ["Content-Type: application/json", "X-Request-ID: " + id, "X-Client-Version: 1.0.0", "X-Fingerprint: " + fp]
    var body = JSON.stringify({ "packet": pkt, "session": _protector.get_session_key() })
    
    _pending[id] = { "cb": cb, "timestamp": Time.get_ticks_msec(), "retries": retry, "path": path, "data": data, "pri": pri, "timeout": timeout, "http": h, "bytes": body.length() }
    h.timeout = timeout
    h.request_completed.connect(_on_resp.bind(id, h), CONNECT_ONE_SHOT)
    var err = h.request(_endpoint + path, headers, HTTPClient.METHOD_POST, body)
    
    if err != OK:
        _pending.erase(id)
        if cb: cb.call(false, _err_resp(NetworkError.REQUEST_FAILED))
        _breaker.failure()
    else:
        _stats.sent += 1; _stats.bytes_sent += body.length()
        _start_timeout(id, timeout * 1000)
        _breaker.success()
        _conn_state = ConnectionState.CONNECTED
    
    _log("sent", { "id": id, "path": path, "bytes": body.length() })
    _process_queue()

func _queue(path, data, cb, retry, pri): _queues[pri].append({ "p": path, "d": data, "cb": cb, "r": retry, "t": Time.get_ticks_msec() })

func _process_queue():
    for pri in [RequestPriority.CRITICAL, RequestPriority.HIGH, RequestPriority.NORMAL, RequestPriority.LOW]:
        if not _queues[pri].is_empty():
            var r = _queues[pri].pop_front()
            send(r.p, r.d, r.cb, r.r, pri)
            return

func _process_offline():
    for r in _offline_q: send(r.p, r.d, r.cb, r.r, r.pri)
    _offline_q.clear()

func handshake(cb):
    _conn_state = ConnectionState.HANDSHAKE
    send("/handshake", {
        "version": "1.0.0", "platform": OS.get_name(), "timestamp": Time.get_unix_time_from_system(),
        "ciphers": ["AES-256-GCM"], "fingerprint": _fingerprint()
    }, cb, 0, RequestPriority.CRITICAL)

func send_pri(path, data, pri, cb = null): send(path, data, cb, 0, pri)

func send_batch(reqs, cb = null, batch_size = 10):
    if reqs.size() > batch_size:
        var batches = []
        for i in range(0, reqs.size(), batch_size): batches.append(reqs.slice(i, min(i + batch_size, reqs.size())))
        var res = []; var done = 0
        for b in batches:
            send_batch(b, func(ok, r): done += 1; if ok: res.append_array(r); if done == batches.size() and cb: cb.call(true, res))
        return
    send("/batch", { "requests": reqs, "batch_id": _req_counter.inc() }, cb, 0, RequestPriority.HIGH)

func send_coalesced(key, data, cb = null): _coalesce(key, data, cb)

func cancel(id):
    _cancelled[id] = true
    _pending.erase(id)
    if _req_timeouts.has(id): _req_timeouts[id].queue_free(); _req_timeouts.erase(id)

func upload(path, file_path, cb = null, prog_cb = null, chunk = 65536):
    var f = FileAccess.open(file_path, FileAccess.READ)
    if not f: if cb: cb.call(false, _err_resp(NetworkError.REQUEST_FAILED, "file_not_found")); return
    
    var size = f.get_length()
    var name = file_path.get_file()
    var tid = "up_%d" % _transfer_counter.inc()
    _transfers[tid] = { "type": "up", "path": path, "file": file_path, "size": size, "cb": cb, "prog": prog_cb, "active": true }
    
    if size <= chunk:
        var data = Marshalls.raw_to_base64(f.get_buffer(size))
        send(path, { "filename": name, "data": data, "size": size, "mime": _mime(file_path), "tid": tid, "chunk": 0, "total": 1 },
            func(ok, r): _transfers.erase(tid); if prog_cb: prog_cb.call(tid, 1.0, size); if cb: cb.call(ok, r))
    else:
        var total = ceil(size / float(chunk))
        var chunks = []
        for i in range(total):
            f.seek(i * chunk)
            var d = f.get_buffer(min(chunk, size - i * chunk))
            chunks.append({ "idx": i, "data": Marshalls.raw_to_base64(d), "size": d.size() })
        _transfers[tid]["chunks"] = chunks
        _upload_next(tid, path, name, file_path, total)

func _upload_next(tid, path, name, file_path, total):
    var t = _transfers.get(tid)
    if not t or not t.active: return
    var chunks = t.chunks
    if chunks.is_empty():
        send(path, { "filename": name, "tid": tid, "complete": true, "total": total },
            func(ok, r): _transfers.erase(tid); if t.prog: t.prog.call(tid, 1.0, t.size); if t.cb: t.cb.call(ok, r))
        return
    
    var c = chunks.pop_front()
    var prog = (t.size - chunks.size() * c.size) / float(t.size) if chunks.size() > 0 else 1.0
    if t.prog: t.prog.call(tid, prog, t.size / max(1, Time.get_ticks_msec() - t.get("ts", Time.get_ticks_msec())) * 1000)
    
    send(path, {
        "filename": name, "data": c.data, "size": c.size, "mime": _mime(file_path),
        "tid": tid, "chunk": c.idx, "total": total, "complete": false
    }, func(ok, r):
        if ok: t.ts = Time.get_ticks_msec(); _upload_next(tid, path, name, file_path, total)
        else: t.active = false; if t.cb: t.cb.call(false, r)
    )

func _mime(p):
    var e = p.get_extension().to_lower()
    match e:
        "png","jpg","jpeg","gif","mp3","mp4","pdf","zip","json","txt": 
            if e in ["png","jpg","jpeg","gif"]: return "image/"+e
            elif e=="mp3": return "audio/mpeg"
            elif e=="mp4": return "video/mp4"
            else: return "application/"+e
        _: return "application/octet-stream"

func download(path, save_path, cb = null, prog_cb = null, resume = false):
    var tid = "down_%d" % _transfer_counter.inc()
    var temp = save_path + ".tmp"
    var exist = 0
    if resume and FileAccess.file_exists(temp):
        var tf = FileAccess.open(temp, FileAccess.READ)
        if tf: exist = tf.get_length(); tf.close()
    
    var h = _get_http()
    if not h: if cb: cb.call(false, _err_resp(NetworkError.REQUEST_FAILED)); return
    
    var dh = h.duplicate()
    _http_node.add_child(dh)
    _transfers[tid] = { "type": "down", "path": save_path, "temp": temp, "size": 0, "got": exist, "cb": cb, "prog": prog_cb, "http": dh, "start": Time.get_ticks_msec(), "active": true }
    
    dh.request_completed.connect(func(r, code, h, b): _on_download(tid, r, code, b))
    dh.set_download_progress_callback(func(now, total): _on_progress(tid, now, total))
    
    var headers = ["Range: bytes=" + str(exist) + "-"] if exist > 0 else []
    dh.request(_endpoint + path + ("?resume=1" if exist > 0 else ""), headers, HTTPClient.METHOD_GET)

func _on_progress(tid, now, total):
    var t = _transfers.get(tid)
    if not t or not t.active: return
    t.got = t.size + now if t.size > 0 else now
    var prog = t.got / float(total) if total > 0 else 0
    var speed = t.got / max(0.001, (Time.get_ticks_msec() - t.start) / 1000.0)
    if t.prog: t.prog.call(tid, prog, speed)

func _on_download(tid, result, code, body):
    var t = _transfers.get(tid)
    if not t: return
    _transfers.erase(tid)
    
    if (result == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 206)):
        var f = FileAccess.open(t.temp, FileAccess.WRITE_READ)
        if f:
            if code == 206: f.seek_end()
            f.store_buffer(body)
            f.close()
            if FileAccess.file_exists(t.path): DirAccess.remove_absolute(t.path)
            DirAccess.rename_absolute(t.temp, t.path)
            if t.cb: t.cb.call(true, { "path": t.path, "size": t.got + body.size() })
        else: if t.cb: t.cb.call(false, _err_resp(NetworkError.REQUEST_FAILED))
    else: if t.cb: t.cb.call(false, _err_resp(NetworkError.REQUEST_FAILED, code))
    
    t.http.queue_free()

func cancel_transfer(tid):
    if _transfers.has(tid):
        _transfers[tid].active = false
        if _transfers[tid].has("http"): _transfers[tid].http.cancel_request()
        _transfers.erase(tid)

func ws_connect(path, cb = null):
    var ws = WebSocketPeer.new()
    var url = _endpoint.replace("https://", "wss://").replace("http://", "ws://") + path
    if ws.connect_to_url(url) != OK: if cb: cb.call(false, { "error": "connect_failed" }); return
    _ws_clients[path] = ws
    _ws_urls[ws] = path
    if not Engine.get_main_loop().process_frame.is_connected(_process_ws):
        Engine.get_main_loop().process_frame.connect(_process_ws)
    if cb: cb.call(true, ws)

func _process_ws():
    var remove = []
    for ws in _ws_clients.values():
        ws.poll()
        var st = ws.get_ready_state()
        if st == WebSocketPeer.STATE_OPEN:
            while ws.get_available_packet_count() > 0: _on_ws_msg(_ws_urls[ws], ws.get_packet())
        elif st in [WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED]: remove.append(ws)
    for ws in remove: var p = _ws_urls[ws]; _ws_clients.erase(p); _ws_urls.erase(ws); ws.close()

func _on_ws_msg(path, pkt): _log("ws msg", { "path": path, "size": pkt.size() })

func ws_send(path, data):
    if _ws_clients.has(path):
        var ws = _ws_clients[path]
        if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
            if data is Dictionary or data is Array: ws.send_text(JSON.stringify(data))
            elif data is String: ws.send_text(data)
            else: ws.send(data)

func ws_close(path):
    if _ws_clients.has(path): var ws = _ws_clients[path]; ws.close(); _ws_clients.erase(path); _ws_urls.erase(ws)

func _nonce():
    var b = []; b.resize(16)
    for i in 16: b[i] = randi() % 256
    return Marshalls.raw_to_base64(b)

func _fingerprint():
    return _protector.hash(JSON.stringify({
        "screen": DisplayServer.window_get_size(), "renderer": RenderingServer.get_video_adapter_name(),
        "memory": OS.get_memory_info(), "lang": OS.get_locale(), "ts": Time.get_unix_time_from_system()
    }))

func _compress(d):
    var s = JSON.stringify(d)
    var l = s.length()
    
    if _compress_lvl == CompressionLevel.ADAPTIVE:
        if l < 512: return { "compressed": false, "data": s }
        var c = _zlib(s)
        return { "compressed": true, "data": Marshalls.raw_to_base64(c) } if c.size() < l * 0.7 else { "compressed": false, "data": s }
    
    match _compress_lvl:
        CompressionLevel.NONE: return { "compressed": false, "data": s }
        CompressionLevel.FAST: return { "compressed": true, "data": Marshalls.utf8_to_base64(s) }
        CompressionLevel.BEST: return { "compressed": true, "data": Marshalls.raw_to_base64(_zlib(s)) }
    return { "compressed": false, "data": s }

func _zlib(s): return s.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)

func _decompress(d, comp):
    if not comp: return JSON.parse_string(d)
    var b = Marshalls.base64_to_raw(d)
    return JSON.parse_string(b.decompress(-1, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8())

func _on_resp(res, code, h, body, id, http):
    if _cancelled.has(id): _cancelled.erase(id); return
    if not _pending.has(id): return
    var r = _pending[id]; _pending.erase(id)
    var cb = r.cb
    var rt = Time.get_ticks_msec() - r.timestamp
    
    if _req_timeouts.has(id): _req_timeouts[id].queue_free(); _req_timeouts.erase(id)
    
    if res != HTTPRequest.RESULT_SUCCESS or code != 200:
        var err = _map_err(res)
        if _should_retry(err, code) and r.retries < _retry_count:
            r.retries += 1; _retry(r); _breaker.failure()
        else:
            _stats.failed += 1; _breaker.failure()
            if cb: cb.call(false, _err_resp(err, code))
            request_completed.emit(id, false, rt, err)
        if code >= 500: _conn_state = ConnectionState.RECONNECTING
        return
    
    _stats.bytes_recv += body.size()
    if rt > r.timeout * 1000:
        _stats.failed += 1; _breaker.failure()
        if cb: cb.call(false, _err_resp(NetworkError.RESPONSE_TIMEOUT))
        request_completed.emit(id, false, rt, NetworkError.RESPONSE_TIMEOUT)
        return
    
    var json = JSON.parse_string(body.get_string_from_utf8())
    if not json or not json.has("packet"):
        _stats.failed += 1; _breaker.failure()
        if cb: cb.call(false, _err_resp(NetworkError.INVALID_RESPONSE))
        request_completed.emit(id, false, rt, NetworkError.INVALID_RESPONSE)
        return
    
    var data = _protector.decrypt_packet(json.packet)
    if data is Dictionary and data.has("compressed"): data = _decompress(data.data, data.compressed)
    
    if data is Dictionary and data.has("handshake_completed"):
        _handshake_done = true; _reconnect_attempts = 0; _conn_state = ConnectionState.CONNECTED
    
    if data is Dictionary and data.has("hmac"):
        var vd = data.duplicate(); vd.erase("hmac")
        var msg = "%s:%s:%s:%s:%s" % [r.path, data.timestamp, data.nonce, data.request_id, data.fingerprint]
        if not _protector.verify_hmac(msg, data.hmac):
            _stats.failed += 1; _breaker.failure()
            if cb: cb.call(false, _err_resp(NetworkError.INVALID_RESPONSE))
            request_completed.emit(id, false, rt, NetworkError.INVALID_RESPONSE)
            return
    
    if data is Dictionary and data.has("batch_response"): _stats.succeeded += data.responses.size()
    else: _stats.succeeded += 1
    
    _breaker.success()
    _update_latency(rt)
    _stats.avg_latency = _stats.avg_latency * 0.95 + rt * 0.05
    _log("resp", { "id": id, "latency": rt })
    
    if cb: cb.call(true, data)
    request_completed.emit(id, true, rt, NetworkError.OK)
    _process_queue()

func _retry(r):
    var d = _retry_delay * pow(2, r.retries - 1)
    d = min(d, 10.0)
    match r.pri:
        RequestPriority.CRITICAL: d *= 0.3
        RequestPriority.HIGH: d *= 0.5
        RequestPriority.LOW: d *= 2.0
    await _http_node.get_tree().create_timer(d).timeout
    send(r.path, r.data, r.cb, r.retries, r.pri)

func _measure_latency():
    var s = Time.get_ticks_usec()
    send("/ping", { "time": s }, func(ok, r):
        if ok and r.has("time"): _update_latency((Time.get_ticks_usec() - s) / 1000.0)
    )

func _update_latency(ms):
    _latency.append(ms)
    if _latency.size() > 20: _latency.pop_front()
    var avg = 0.0; for l in _latency: avg += l; avg /= _latency.size()
    var old = _net_quality
    if avg < 30: _net_quality = NetworkQuality.EXCELLENT
    elif avg < 80: _net_quality = NetworkQuality.GOOD
    elif avg < 150: _net_quality = NetworkQuality.FAIR
    elif avg < 300: _net_quality = NetworkQuality.POOR
    else: _net_quality = NetworkQuality.UNKNOWN
    if old != _net_quality:
        network_quality_changed.emit(old, _net_quality)
        if _net_quality == NetworkQuality.POOR and not _alerts.high_latency:
            _alerts.high_latency = true; security_alert.emit("high_latency", 1, { "latency": avg })
        elif _net_quality != NetworkQuality.POOR: _alerts.high_latency = false

func start_heartbeat():
    if _heartbeat_timer or not _http_node or not _handshake_done: return
    _heartbeat_timer = _http_node.get_tree().create_timer(_heartbeat_int)
    _heartbeat_timer.timeout.connect(_on_heartbeat)

func _on_heartbeat():
    var intv = _heartbeat_int * (2 if _pending.is_empty() else 1)
    send("/heartbeat", { "ts": Time.get_unix_time_from_system(), "pending": _pending.size(), "quality": _net_quality },
        func(ok, r): if not ok: _log("heartbeat fail", r); _on_lost(), 0, RequestPriority.LOW)
    start_heartbeat()

func _on_lost():
    if not _config.auto_reconnect: _conn_state = ConnectionState.DISCONNECTED; return
    if _reconnect_attempts >= _max_reconnect: _log("max reconnect"); _conn_state = ConnectionState.DISCONNECTED; return
    _reconnect_attempts += 1
    var d = min(30, pow(1.5, _reconnect_attempts))
    _log("lost, reconnect in %.1f" % d); _conn_state = ConnectionState.RECONNECTING; connection_lost.emit()
    _http_node.get_tree().create_timer(d).timeout.connect(func():
        handshake(func(ok, r):
            if ok: _reconnect_attempts = 0; _log("reconnected"); _conn_state = ConnectionState.CONNECTED; connection_restored.emit(); _resume()
            else: _on_lost()
        )
    )

func _resume():
    for id in _pending: var r = _pending[id]; send(r.path, r.data, r.cb, r.retries, r.pri)

func set_debug(e): _debug = e; _config.debug = e
func set_compress(l): _compress_lvl = l; _config.compress_lvl = l
func set_offline(e): _offline = e; if not e and not _offline_q.is_empty(): _process_offline(); _conn_state = ConnectionState.CONNECTED if e else ConnectionState.OFFLINE

func save_config(p = "user://network_config.json"):
    var f = FileAccess.open(p, FileAccess.WRITE); if f: f.store_string(JSON.stringify(_config))

func load_config(p = "user://network_config.json"):
    if FileAccess.file_exists(p):
        var f = FileAccess.open(p, FileAccess.READ)
        if f: var d = JSON.parse_string(f.get_as_text()); if d is Dictionary: for k in d: if _config.has(k): _config[k] = d[k]
    _timeout = _config.timeout; _retry_count = _config.retry_count; _retry_delay = _config.retry_delay
    _max_rps = _config.max_rps; _max_conn = _config.max_conn; _heartbeat_int = _config.heartbeat_int
    _bandwidth_limit = _config.bandwidth_limit; _compress_lvl = _config.compress_lvl; _debug = _config.debug

func _log(msg, d = null):
    if not _debug: return
    print("DERClient: ", msg)
    if d: print(JSON.stringify(d))

func _err_resp(code, extra = null):
    var names = NetworkError.keys()
    var r = { "error": names[code], "code": code, "ts": Time.get_unix_time_from_system() }
    if extra != null: r.extra = extra
    return r

func get_protector(): return _protector
func session_expired(): return _protector.is_session_expired()
func net_quality(): return _net_quality
func conn_state(): return _conn_state
func stats(): return _stats.duplicate()
func config(): return _config.duplicate()
func reset_breaker(): _breaker = CircuitBreaker.new()
func clear_dns(): _dns_cache.clear()

func shutdown():
    for t in _transfers: if _transfers[t].has("http"): _transfers[t].http.cancel_request()
    _cleanup()

func _cleanup():
    for id in _pending: if _pending[id].cb: _pending[id].cb = null
    for t in [_cleanup_timer, _heartbeat_timer]: if t: t.timeout.disconnect_all(); t.queue_free()
    for id in _req_timeouts: if _req_timeouts[id]: _req_timeouts[id].queue_free()
    for h in _http_pool: if h: h.request_completed.disconnect_all(); h.cancel_request(); h.queue_free()
    for ws in _ws_clients.values(): ws.close()
    if _http_node and _http_node.get_parent(): _http_node.get_parent().remove_child(_http_node); _http_node.queue_free()
    _pending.clear(); _cancelled.clear(); _dns_cache.clear(); _coalescing.clear(); _latency.clear()
    _req_times.clear(); _req_timeouts.clear(); _ws_clients.clear(); _ws_urls.clear(); _transfers.clear(); _offline_q.clear()