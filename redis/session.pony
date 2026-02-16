use "buffered"
use lori = "lori"

actor Session is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  A Redis client session. Manages the connection lifecycle — connecting,
  optionally authenticating, executing commands, and shutting down — as
  a state machine.

  Create a session with `ConnectInfo` and a `SessionStatusNotify` receiver.
  Once `redis_session_ready` fires, commands can be sent via `execute()`.
  Command execution is serialized: only one command is in flight at a time.
  Additional calls to `execute()` are queued and dispatched in order.
  """
  var state: _SessionState
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()

  new create(connect_info': ConnectInfo, notify': SessionStatusNotify) =>
    state = _SessionUnopened(notify', connect_info')
    _tcp_connection = lori.TCPConnection.client(
      connect_info'.auth,
      connect_info'.host,
      connect_info'.port,
      "",
      this,
      this)

  be execute(command: Array[ByteSeq] val, receiver: ResultReceiver) =>
    """
    Execute a Redis command. The command is an array of bulk strings
    (e.g., `["SET", "key", "value"]`). The response is delivered to the
    receiver via `redis_response` or `redis_command_failed`.
    """
    state.execute(this, command, receiver)

  be close() =>
    """
    Close the session. Sends a QUIT command to the server before closing
    the TCP connection. Pending commands receive `SessionClosed` via
    `redis_command_failed`.
    """
    state.close(this)

  // Lori callbacks — delegate to state machine.
  fun ref _on_connected() =>
    state.on_connected(this)

  fun ref _on_connection_failure() =>
    state.on_failure(this)

  fun ref _on_received(data: Array[U8] iso) =>
    state.on_received(this, consume data)

  fun ref _on_closed() =>
    state.on_closed(this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

// State machine interface

interface _SessionState
  fun on_connected(s: Session ref)
  fun on_failure(s: Session ref)
  fun ref on_received(s: Session ref, data: Array[U8] iso)
  fun ref on_closed(s: Session ref)
  fun ref on_response(s: Session ref, response: RespValue)
  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  fun ref close(s: Session ref)
  fun ref shutdown(s: Session ref)

// Trait composition

trait _ClosedState is _SessionState
  """
  Terminal state mixin. All operations are either illegal (protocol
  anomaly), no-ops (already closed), or error-delivering (execute).
  """
  fun on_connected(s: Session ref) =>
    _IllegalState()

  fun on_failure(s: Session ref) =>
    _IllegalState()

  fun ref on_received(s: Session ref, data: Array[U8] iso) =>
    // Data may arrive after close — silently drop.
    None

  fun ref on_closed(s: Session ref) =>
    // Already closed.
    None

  fun ref on_response(s: Session ref, response: RespValue) =>
    _IllegalState()

  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  =>
    receiver.redis_command_failed(s, command, SessionClosed)

  fun ref close(s: Session ref) =>
    None

  fun ref shutdown(s: Session ref) =>
    ifdef debug then
      _IllegalState()
    end

trait _ConnectedState is _SessionState
  """
  Mixin for states that have a readbuf and process incoming data.
  Connected states are not connectable — receiving a connect event
  while already connected is a protocol anomaly.

  All connected states must clear the readbuf before transitioning to
  `_SessionClosed` on shutdown/error paths. This stops the
  `_ResponseHandler` loop — the next `_RespParser` call returns `None`
  and the loop exits naturally.
  """
  fun on_connected(s: Session ref) =>
    _IllegalState()

  fun on_failure(s: Session ref) =>
    _IllegalState()

  fun ref on_received(s: Session ref, data: Array[U8] iso) =>
    readbuf().append(consume data)
    _ResponseHandler(s, readbuf())

  fun ref readbuf(): Reader
  fun notify(): SessionStatusNotify

trait _NotReadyForCommands is _SessionState
  """
  Mixin for states that reject command execution because the session
  is not yet ready.
  """
  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  =>
    receiver.redis_command_failed(s, command, SessionNotReady)

// Session states

class ref _SessionUnopened is _NotReadyForCommands
  """
  Initial state — waiting for TCP connection to be established.
  """
  let _notify: SessionStatusNotify
  let _connect_info: ConnectInfo

  new ref create(notify': SessionStatusNotify, connect_info': ConnectInfo) =>
    _notify = notify'
    _connect_info = connect_info'

  fun on_connected(s: Session ref) =>
    _notify.redis_session_connected(s)
    match _connect_info.password
    | let password: String =>
      let st = _SessionConnected(_notify)
      s.state = st
      let cmd: Array[ByteSeq] val = ["AUTH"; password]
      s._connection().send(_RespSerializer(cmd))
    | None =>
      s.state = _SessionReady(_notify)
      _notify.redis_session_ready(s)
    end

  fun on_failure(s: Session ref) =>
    s.state = _SessionClosed
    _notify.redis_session_connection_failed(s)

  fun ref on_received(s: Session ref, data: Array[U8] iso) =>
    _IllegalState()

  fun ref on_response(s: Session ref, response: RespValue) =>
    _IllegalState()

  fun ref on_closed(s: Session ref) =>
    // Defensive — lori fires _on_closed only for established connections,
    // so this is unlikely to be reached from _SessionUnopened.
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref close(s: Session ref) =>
    s._connection().close()

  fun ref shutdown(s: Session ref) =>
    s._connection().close()

class ref _SessionConnected is (_ConnectedState & _NotReadyForCommands)
  """
  TCP connected, AUTH command sent, waiting for the server's response.

  AUTH is sent from `_SessionUnopened.on_connected` after transitioning
  to this state (not from the constructor — constructors don't have
  `Session ref`).
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader = _readbuf.create()

  new ref create(notify': SessionStatusNotify) =>
    _notify = notify'

  fun ref on_response(s: Session ref, response: RespValue) =>
    match response
    | let ok: RespSimpleString if ok.value == "OK" =>
      s.state = _SessionReady.from_connected(_notify, _readbuf)
      _notify.redis_session_ready(s)
    | let err: RespError =>
      _notify.redis_session_authentication_failed(s, err.message)
      shutdown(s)
    else
      // Unexpected AUTH response — protocol violation.
      shutdown(s)
    end

  fun ref on_closed(s: Session ref) =>
    _readbuf.clear()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref close(s: Session ref) =>
    s._connection().close()

  fun ref shutdown(s: Session ref) =>
    _readbuf.clear()
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref readbuf(): Reader =>
    _readbuf

  fun notify(): SessionStatusNotify =>
    _notify

class val _QueuedCommand
  """
  A command waiting to be sent or awaiting its response.
  """
  let command: Array[ByteSeq] val
  let receiver: ResultReceiver

  new val create(command': Array[ByteSeq] val,
    receiver': ResultReceiver)
  =>
    command = command'
    receiver = receiver'

class ref _SessionReady is _ConnectedState
  """
  Session is ready to execute commands. Command execution is serialized:
  only one command is in flight at a time. Additional calls to `execute()`
  are queued and dispatched in order. Phase 3 (pipelining) will remove
  the in-flight gate.
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader
  let _pending: Array[_QueuedCommand] = _pending.create()
  var _in_flight: Bool = false

  new ref create(notify': SessionStatusNotify) =>
    _notify = notify'
    _readbuf = Reader

  new ref from_connected(notify': SessionStatusNotify, readbuf': Reader) =>
    _notify = notify'
    _readbuf = readbuf'

  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  =>
    _pending.push(_QueuedCommand(command, receiver))
    if not _in_flight then
      _send_next(s)
    end

  fun ref on_response(s: Session ref, response: RespValue) =>
    try
      let queued = _pending.shift()?
      _in_flight = false
      queued.receiver.redis_response(s, response)
      if _pending.size() > 0 then
        _send_next(s)
      end
    else
      _Unreachable()
    end

  fun ref on_closed(s: Session ref) =>
    _readbuf.clear()
    _drain_pending(s)
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref close(s: Session ref) =>
    _drain_pending(s)
    _readbuf.clear()
    s._connection().send(_RespSerializer(["QUIT"]))
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref shutdown(s: Session ref) =>
    _readbuf.clear()
    _drain_pending(s)
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref readbuf(): Reader =>
    _readbuf

  fun notify(): SessionStatusNotify =>
    _notify

  fun ref _send_next(s: Session ref) =>
    try
      let queued = _pending(0)?
      s._connection().send(_RespSerializer(queued.command))
      _in_flight = true
    else
      _Unreachable()
    end

  fun ref _drain_pending(s: Session ref) =>
    for queued in _pending.values() do
      queued.receiver.redis_command_failed(s, queued.command, SessionClosed)
    end
    _pending.clear()

class ref _SessionClosed is _ClosedState
  """
  Terminal state. The session is closed and cannot be reused.
  """
