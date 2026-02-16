use "buffered"
use lori = "lori"

actor Session is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  A Redis client session. Manages the connection lifecycle — connecting,
  optionally authenticating, executing commands, subscribing to pub/sub
  channels, and shutting down — as a state machine.

  Create a session with `ConnectInfo` and a `SessionStatusNotify` receiver.
  Once `redis_session_ready` fires, commands can be sent via `execute()`.
  Commands are pipelined: each call to `execute()` sends the command
  immediately without waiting for prior responses. Responses are matched
  to receivers in FIFO order.

  To enter pub/sub mode, call `subscribe()` or `psubscribe()` with a
  `SubscriptionNotify` receiver. While subscribed, `execute()` is rejected
  with `SessionInSubscribedMode`. When all subscriptions are cancelled
  (count reaches 0), the session returns to ready mode and
  `redis_session_ready` fires again.
  """
  var state: _SessionState
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()

  new create(connect_info': ConnectInfo, notify': SessionStatusNotify) =>
    state = _SessionUnopened(notify', connect_info')
    _tcp_connection = match connect_info'.ssl_mode
    | SSLDisabled =>
      lori.TCPConnection.client(
        connect_info'.auth,
        connect_info'.host,
        connect_info'.port,
        "",
        this,
        this)
    | let ssl: SSLRequired =>
      lori.TCPConnection.ssl_client(
        connect_info'.auth,
        ssl.ctx,
        connect_info'.host,
        connect_info'.port,
        "",
        this,
        this)
    end

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

  be subscribe(channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    """
    Subscribe to one or more channels, entering pub/sub mode. Messages
    are delivered to the `SubscriptionNotify` receiver. While subscribed,
    `execute()` is rejected with `SessionInSubscribedMode`.

    If already subscribed, the additional channels are added to the
    existing subscription using the original `SubscriptionNotify`.
    """
    state.subscribe(this, channels, sub_notify)

  be unsubscribe(channels: Array[String] val) =>
    """
    Unsubscribe from one or more channels. Pass an empty array to
    unsubscribe from all channels. When the total subscription count
    (channels + patterns) reaches 0, the session returns to ready mode.
    """
    state.unsubscribe(this, channels)

  be psubscribe(patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    """
    Subscribe to one or more channel patterns, entering pub/sub mode.
    Messages matching the patterns are delivered to the
    `SubscriptionNotify` receiver via `redis_pmessage`.

    If already subscribed, the additional patterns are added to the
    existing subscription using the original `SubscriptionNotify`.
    """
    state.psubscribe(this, patterns, sub_notify)

  be punsubscribe(patterns: Array[String] val) =>
    """
    Unsubscribe from one or more channel patterns. Pass an empty array
    to unsubscribe from all patterns. When the total subscription count
    (channels + patterns) reaches 0, the session returns to ready mode.
    """
    state.punsubscribe(this, patterns)

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
  fun ref subscribe(s: Session ref, channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  fun ref unsubscribe(s: Session ref, channels: Array[String] val)
  fun ref psubscribe(s: Session ref, patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  fun ref punsubscribe(s: Session ref, patterns: Array[String] val)

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

trait _NotSubscribed is _SessionState
  """
  Mixin for states where pub/sub operations are no-ops. Subscribe and
  psubscribe are silently ignored because `SubscriptionNotify` has no
  error callback — there is no delivery mechanism for the failure.
  Unsubscribe and punsubscribe are also no-ops since there are no
  active subscriptions to cancel.
  """
  fun ref subscribe(s: Session ref, channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    None

  fun ref unsubscribe(s: Session ref, channels: Array[String] val) =>
    None

  fun ref psubscribe(s: Session ref, patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    None

  fun ref punsubscribe(s: Session ref, patterns: Array[String] val) =>
    None

// Session states

class ref _SessionUnopened is (_NotReadyForCommands & _NotSubscribed)
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

class ref _SessionConnected is
  (_ConnectedState & _NotReadyForCommands & _NotSubscribed)
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
  A command awaiting its response from the server.
  """
  let command: Array[ByteSeq] val
  let receiver: ResultReceiver

  new val create(command': Array[ByteSeq] val,
    receiver': ResultReceiver)
  =>
    command = command'
    receiver = receiver'

class ref _SessionReady is (_ConnectedState & _NotSubscribed)
  """
  Session is ready to execute commands. Commands are pipelined: each call
  to `execute()` sends the command immediately over the wire. Responses
  are matched to receivers in FIFO order via the `_pending` queue.
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader
  let _pending: Array[_QueuedCommand] = _pending.create()

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
    s._connection().send(_RespSerializer(command))

  fun ref on_response(s: Session ref, response: RespValue) =>
    try
      let queued = _pending.shift()?
      queued.receiver.redis_response(s, response)
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

  fun ref subscribe(s: Session ref, channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    if channels.size() == 0 then return end
    let cmd = recover val
      let arr = Array[ByteSeq](channels.size() + 1)
      arr.push("SUBSCRIBE")
      for ch in channels.values() do arr.push(ch) end
      arr
    end
    s._connection().send(_RespSerializer(cmd))
    s.state = _SessionSubscribed(_notify, _readbuf, _pending, sub_notify)

  fun ref psubscribe(s: Session ref, patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    if patterns.size() == 0 then return end
    let cmd = recover val
      let arr = Array[ByteSeq](patterns.size() + 1)
      arr.push("PSUBSCRIBE")
      for pat in patterns.values() do arr.push(pat) end
      arr
    end
    s._connection().send(_RespSerializer(cmd))
    s.state = _SessionSubscribed(_notify, _readbuf, _pending, sub_notify)

  fun ref _drain_pending(s: Session ref) =>
    for queued in _pending.values() do
      queued.receiver.redis_command_failed(s, queued.command, SessionClosed)
    end
    _pending.clear()

class ref _SessionSubscribed is _ConnectedState
  """
  Session is in pub/sub subscribed mode. Incoming responses are routed
  as pub/sub messages to the `SubscriptionNotify` receiver. Regular
  command execution is rejected with `SessionInSubscribedMode`.

  When the total subscription count (channels + patterns) reaches 0
  via unsubscribe/punsubscribe confirmations, the session transitions
  back to `_SessionReady` and `redis_session_ready` fires.
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader
  let _pending: Array[_QueuedCommand]
  let _sub_notify: SubscriptionNotify

  new ref create(notify': SessionStatusNotify, readbuf': Reader,
    pending': Array[_QueuedCommand], sub_notify': SubscriptionNotify)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _pending = pending'
    _sub_notify = sub_notify'

  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  =>
    receiver.redis_command_failed(s, command, SessionInSubscribedMode)

  // Changing this method's drain-then-route logic requires understanding
  // why the pending queue is drained first: Redis guarantees that
  // responses to commands pipelined before SUBSCRIBE are delivered before
  // the subscribe confirmation. This method relies on that ordering —
  // it dequeues from _pending until empty, then switches to pub/sub
  // message routing. If Redis changed its response ordering, in-flight
  // command responses would be misrouted as pub/sub messages.
  fun ref on_response(s: Session ref, response: RespValue) =>
    if _pending.size() > 0 then
      try
        let queued = _pending.shift()?
        queued.receiver.redis_response(s, response)
      else
        _Unreachable()
      end
      return
    end
    match response
    | let arr: RespArray => _dispatch_pubsub(s, arr)
    else
      shutdown(s)
    end

  fun ref _dispatch_pubsub(s: Session ref, arr: RespArray) =>
    try
      match arr.values(0)?
      | let type_bs: RespBulkString =>
        let msg_type = String.from_array(type_bs.value)
        if msg_type == "subscribe" then
          match (arr.values(1)?, arr.values(2)?)
          | (let ch: RespBulkString, let cnt: RespInteger) =>
            _sub_notify.redis_subscribed(s, String.from_array(ch.value),
              cnt.value.usize())
          else
            shutdown(s)
          end
        elseif msg_type == "unsubscribe" then
          match (arr.values(1)?, arr.values(2)?)
          | (let ch: RespBulkString, let cnt: RespInteger) =>
            let count = cnt.value.usize()
            _sub_notify.redis_unsubscribed(s, String.from_array(ch.value),
              count)
            if count == 0 then
              s.state = _SessionReady.from_connected(_notify, _readbuf)
              _notify.redis_session_ready(s)
            end
          else
            shutdown(s)
          end
        elseif msg_type == "message" then
          match (arr.values(1)?, arr.values(2)?)
          | (let ch: RespBulkString, let data_bs: RespBulkString) =>
            _sub_notify.redis_message(s, String.from_array(ch.value),
              data_bs.value)
          else
            shutdown(s)
          end
        elseif msg_type == "psubscribe" then
          match (arr.values(1)?, arr.values(2)?)
          | (let pat: RespBulkString, let cnt: RespInteger) =>
            _sub_notify.redis_psubscribed(s, String.from_array(pat.value),
              cnt.value.usize())
          else
            shutdown(s)
          end
        elseif msg_type == "punsubscribe" then
          match (arr.values(1)?, arr.values(2)?)
          | (let pat: RespBulkString, let cnt: RespInteger) =>
            let count = cnt.value.usize()
            _sub_notify.redis_punsubscribed(s, String.from_array(pat.value),
              count)
            if count == 0 then
              s.state = _SessionReady.from_connected(_notify, _readbuf)
              _notify.redis_session_ready(s)
            end
          else
            shutdown(s)
          end
        elseif msg_type == "pmessage" then
          match (arr.values(1)?, arr.values(2)?, arr.values(3)?)
          | (let pat: RespBulkString, let ch: RespBulkString,
            let data_bs: RespBulkString)
          =>
            _sub_notify.redis_pmessage(s, String.from_array(pat.value),
              String.from_array(ch.value), data_bs.value)
          else
            shutdown(s)
          end
        else
          shutdown(s)
        end
      else
        shutdown(s)
      end
    else
      shutdown(s)
    end

  fun ref subscribe(s: Session ref, channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    // sub_notify parameter is ignored — all messages go to _sub_notify
    // from the initial subscribe call.
    if channels.size() == 0 then return end
    let cmd = recover val
      let arr = Array[ByteSeq](channels.size() + 1)
      arr.push("SUBSCRIBE")
      for ch in channels.values() do arr.push(ch) end
      arr
    end
    s._connection().send(_RespSerializer(cmd))

  fun ref psubscribe(s: Session ref, patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    // sub_notify parameter is ignored — all messages go to _sub_notify
    // from the initial subscribe call.
    if patterns.size() == 0 then return end
    let cmd = recover val
      let arr = Array[ByteSeq](patterns.size() + 1)
      arr.push("PSUBSCRIBE")
      for pat in patterns.values() do arr.push(pat) end
      arr
    end
    s._connection().send(_RespSerializer(cmd))

  fun ref unsubscribe(s: Session ref, channels: Array[String] val) =>
    let cmd = recover val
      let arr = Array[ByteSeq](channels.size() + 1)
      arr.push("UNSUBSCRIBE")
      for ch in channels.values() do arr.push(ch) end
      arr
    end
    s._connection().send(_RespSerializer(cmd))

  fun ref punsubscribe(s: Session ref, patterns: Array[String] val) =>
    let cmd = recover val
      let arr = Array[ByteSeq](patterns.size() + 1)
      arr.push("PUNSUBSCRIBE")
      for pat in patterns.values() do arr.push(pat) end
      arr
    end
    s._connection().send(_RespSerializer(cmd))

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

  fun ref _drain_pending(s: Session ref) =>
    for queued in _pending.values() do
      queued.receiver.redis_command_failed(s, queued.command, SessionClosed)
    end
    _pending.clear()

class ref _SessionClosed is (_ClosedState & _NotSubscribed)
  """
  Terminal state. The session is closed and cannot be reused.
  """
