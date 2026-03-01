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

  When the TCP connection's send buffer fills, the session buffers commands
  internally (up to `send_buffer_limit` commands, default 1024) and
  flushes them when the connection becomes writeable. If the buffer is
  full, `execute()` rejects the command via `redis_command_failed` with
  `SessionBackpressureOverflow`. The `redis_session_throttled` and
  `redis_session_unthrottled` callbacks on `SessionStatusNotify` inform
  the application of backpressure state changes.

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
    _tcp_connection = match \exhaustive\ connect_info'.ssl_mode
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
    the TCP connection. Buffered commands (queued during backpressure)
    and in-flight commands in the pending queue receive `SessionClosed`
    via `redis_command_failed`. Commands sent after the session is
    closed also receive `SessionClosed`.
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

  fun ref _on_throttled() =>
    state.on_throttled(this)

  fun ref _on_unthrottled() =>
    state.on_unthrottled(this)

  be _flush_backpressure() =>
    """
    Deferred flush of the backpressure send buffer. Triggered by
    on_unthrottled to avoid calling send() from within lori's pending
    writes processing.
    """
    state.flush_send_buffer(this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

// State machine interface

interface _SessionState
  fun on_connected(s: Session ref)
  fun on_failure(s: Session ref)
  fun ref on_received(s: Session ref, data: Array[U8] iso)
  fun ref on_closed(s: Session ref)
  fun ref on_response(s: Session ref, response: RespValue)
  fun ref on_push(s: Session ref, push: RespPush)
  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  fun ref close(s: Session ref)
  fun ref shutdown(s: Session ref, reason: ClientError)
  fun ref subscribe(s: Session ref, channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  fun ref unsubscribe(s: Session ref, channels: Array[String] val)
  fun ref psubscribe(s: Session ref, patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  fun ref punsubscribe(s: Session ref, patterns: Array[String] val)
  fun ref on_throttled(s: Session ref)
  fun ref on_unthrottled(s: Session ref)
  fun ref flush_send_buffer(s: Session ref)

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

  fun ref shutdown(s: Session ref, reason: ClientError) =>
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
  Mixin for states where pub/sub operations are no-ops and push messages
  are silently dropped. Subscribe and psubscribe are silently ignored
  because `SubscriptionNotify` has no error callback — there is no
  delivery mechanism for the failure. Unsubscribe and punsubscribe are
  also no-ops since there are no active subscriptions to cancel.

  Push messages (RESP3 server-initiated notifications) are dropped in
  non-subscribed states. This is the only trait that provides `on_push`
  to avoid diamond inheritance in `_SessionClosed`.
  """
  fun ref on_push(s: Session ref, push: RespPush) =>
    None

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

trait _NotThrottleable is _SessionState
  """
  Mixin for states where backpressure events are no-ops. States that don't
  send user commands (pre-ready states, closed state) ignore throttle and
  unthrottle — lori manages partial writes internally during negotiation,
  and no application commands are pending in those states.
  """
  fun ref on_throttled(s: Session ref) => None
  fun ref on_unthrottled(s: Session ref) => None
  fun ref flush_send_buffer(s: Session ref) => None

// Session states

class ref _SessionUnopened is
  (_NotReadyForCommands & _NotSubscribed & _NotThrottleable)
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
    match \exhaustive\ _connect_info.protocol
    | Resp3 =>
      let cmd = _BuildHelloCommand(_connect_info)
      let data = _RespSerializer(cmd)
      match s._connection().send(data)
      | let _: lori.SendToken =>
        s.state = _SessionNegotiating(_notify, _connect_info)
      else
        s._connection().close()
        s.state = _SessionClosed
        _notify.redis_session_closed(s)
      end
    | Resp2 =>
      match \exhaustive\ _connect_info.password
      | let password: String =>
        let cmd = _BuildAuthCommand(_connect_info.username, password)
        let data = _RespSerializer(cmd)
        match s._connection().send(data)
        | let _: lori.SendToken =>
          s.state = _SessionConnected(_notify,
            _connect_info.send_buffer_limit)
        else
          s._connection().close()
          s.state = _SessionClosed
          _notify.redis_session_closed(s)
        end
      | None =>
        s.state = _SessionReady(_notify,
          _connect_info.send_buffer_limit)
        _notify.redis_session_ready(s)
      end
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

  fun ref shutdown(s: Session ref, reason: ClientError) =>
    s._connection().close()

class ref _SessionNegotiating is
  (_ConnectedState & _NotReadyForCommands & _NotSubscribed & _NotThrottleable)
  """
  TCP connected, HELLO command sent, waiting for the server's response.
  If the server supports RESP3, the response is a map with server info
  and the session transitions to ready. If the server doesn't support
  HELLO, the response is an error and the session falls back to RESP2,
  optionally sending AUTH if a password is configured.
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader = _readbuf.create()
  let _connect_info: ConnectInfo

  new ref create(notify': SessionStatusNotify,
    connect_info': ConnectInfo)
  =>
    _notify = notify'
    _connect_info = connect_info'

  fun ref on_response(s: Session ref, response: RespValue) =>
    match response
    | let _: RespMap =>
      s.state = _SessionReady.from_connected(_notify, _readbuf,
        _connect_info.send_buffer_limit)
      _notify.redis_session_ready(s)
    | let err: RespError =>
      // HELLO not supported — fall back to RESP2.
      match \exhaustive\ _connect_info.password
      | let password: String =>
        let cmd = _BuildAuthCommand(_connect_info.username, password)
        let data = _RespSerializer(cmd)
        match s._connection().send(data)
        | let _: lori.SendToken =>
          s.state = _SessionConnected.from_negotiating(_notify, _readbuf,
            _connect_info.send_buffer_limit)
        else
          shutdown(s, SessionConnectionLost)
        end
      | None =>
        s.state = _SessionReady.from_connected(_notify, _readbuf,
          _connect_info.send_buffer_limit)
        _notify.redis_session_ready(s)
      end
    else
      // Unexpected HELLO response — protocol violation.
      shutdown(s, SessionProtocolError)
    end

  fun ref on_closed(s: Session ref) =>
    _readbuf.clear()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref close(s: Session ref) =>
    s._connection().close()

  fun ref shutdown(s: Session ref, reason: ClientError) =>
    _readbuf.clear()
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref readbuf(): Reader =>
    _readbuf

  fun notify(): SessionStatusNotify =>
    _notify

class ref _SessionConnected is
  (_ConnectedState & _NotReadyForCommands & _NotSubscribed & _NotThrottleable)
  """
  TCP connected, AUTH command sent, waiting for the server's response.

  AUTH is sent from `_SessionUnopened.on_connected` (or from
  `_SessionNegotiating.on_response` during HELLO fallback) before
  transitioning to this state — the transition only happens on
  successful send.
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader
  let _send_buffer_limit: USize

  new ref create(notify': SessionStatusNotify,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = Reader
    _send_buffer_limit = send_buffer_limit'

  new ref from_negotiating(notify': SessionStatusNotify, readbuf': Reader,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _send_buffer_limit = send_buffer_limit'

  fun ref on_response(s: Session ref, response: RespValue) =>
    match \exhaustive\ response
    | let ok: RespSimpleString if ok.value == "OK" =>
      s.state = _SessionReady.from_connected(_notify, _readbuf,
        _send_buffer_limit)
      _notify.redis_session_ready(s)
    | let err: RespError =>
      _notify.redis_session_authentication_failed(s, err.message)
      shutdown(s, SessionProtocolError)
    else
      // Unexpected AUTH response — protocol violation.
      shutdown(s, SessionProtocolError)
    end

  fun ref on_closed(s: Session ref) =>
    _readbuf.clear()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref close(s: Session ref) =>
    s._connection().close()

  fun ref shutdown(s: Session ref, reason: ClientError) =>
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

class val _BufferedSend
  """
  A serialized command buffered during backpressure. Holds wire-format
  bytes ready to send, and optionally a queued command for response
  matching. User commands from `execute()` have a `_QueuedCommand`;
  internal commands (SUBSCRIBE, UNSUBSCRIBE, etc.) do not.
  """
  let data: Array[U8] val
  let queued: (_QueuedCommand | None)

  new val create(data': Array[U8] val,
    queued': (_QueuedCommand | None) = None)
  =>
    data = data'
    queued = queued'

class ref _SessionReady is (_ConnectedState & _NotSubscribed)
  """
  Session is ready to execute commands. Commands are pipelined: each call
  to `execute()` sends the command immediately over the wire. Responses
  are matched to receivers in FIFO order via the `_pending` queue.

  When TCP backpressure is active (`_throttled`), commands are serialized
  and buffered in `_send_buffer` instead of being sent immediately. The
  buffer is bounded by `_send_buffer_limit` — commands that exceed the
  limit are rejected with `SessionBackpressureOverflow`. The buffer is
  flushed when backpressure is released.
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader
  let _pending: Array[_QueuedCommand] = _pending.create()
  var _throttled: Bool
  let _send_buffer: Array[_BufferedSend]
  let _send_buffer_limit: USize

  new ref create(notify': SessionStatusNotify,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = Reader
    _throttled = false
    _send_buffer = Array[_BufferedSend]
    _send_buffer_limit = send_buffer_limit'

  new ref from_connected(notify': SessionStatusNotify, readbuf': Reader,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _throttled = false
    _send_buffer = Array[_BufferedSend]
    _send_buffer_limit = send_buffer_limit'

  new ref from_subscribed(notify': SessionStatusNotify, readbuf': Reader,
    throttled': Bool, send_buffer': Array[_BufferedSend],
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _throttled = throttled'
    _send_buffer = send_buffer'
    _send_buffer_limit = send_buffer_limit'

  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  =>
    if _throttled then
      if _send_buffer.size() >= _send_buffer_limit then
        receiver.redis_command_failed(s, command,
          SessionBackpressureOverflow)
        return
      end
      _send_buffer.push(
        _BufferedSend(_RespSerializer(command),
          _QueuedCommand(command, receiver)))
    else
      let data = _RespSerializer(command)
      match \exhaustive\ s._connection().send(data)
      | let _: lori.SendToken =>
        _pending.push(_QueuedCommand(command, receiver))
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(
          _BufferedSend(data, _QueuedCommand(command, receiver)))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        receiver.redis_command_failed(s, command, SessionConnectionLost)
        shutdown(s, SessionConnectionLost)
      end
    end

  fun ref on_response(s: Session ref, response: RespValue) =>
    try
      let queued = _pending.shift()?
      queued.receiver.redis_response(s, response)
    else
      _Unreachable()
    end

  fun ref on_closed(s: Session ref) =>
    _readbuf.clear()
    _drain_send_buffer(s, SessionConnectionLost)
    _drain_pending(s, SessionConnectionLost)
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref close(s: Session ref) =>
    _drain_send_buffer(s, SessionClosed)
    _drain_pending(s, SessionClosed)
    _readbuf.clear()
    s._connection().send(_RespSerializer(["QUIT"]))
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref shutdown(s: Session ref, reason: ClientError) =>
    _readbuf.clear()
    _drain_send_buffer(s, reason)
    _drain_pending(s, reason)
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref on_throttled(s: Session ref) =>
    _throttled = true
    _notify.redis_session_throttled(s)

  fun ref on_unthrottled(s: Session ref) =>
    _notify.redis_session_unthrottled(s)
    s._flush_backpressure()

  fun ref flush_send_buffer(s: Session ref) =>
    _throttled = false
    while _send_buffer.size() > 0 do
      try
        let buffered = _send_buffer.shift()?
        match \exhaustive\ s._connection().send(buffered.data)
        | let _: lori.SendToken =>
          match buffered.queued
          | let qc: _QueuedCommand => _pending.push(qc)
          end
        | lori.SendErrorNotWriteable =>
          _send_buffer.unshift(buffered)
          _throttled = true
          return
        | lori.SendErrorNotConnected =>
          _send_buffer.unshift(buffered)
          shutdown(s, SessionConnectionLost)
          return
        end
      else
        _Unreachable()
      end
    end

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
    if _throttled then
      _send_buffer.push(_BufferedSend(_RespSerializer(cmd)))
    else
      let data = _RespSerializer(cmd)
      match \exhaustive\ s._connection().send(data)
      | let _: lori.SendToken => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
        return
      end
    end
    s.state = _SessionSubscribed(_notify, _readbuf, _pending, sub_notify,
      _throttled, _send_buffer, _send_buffer_limit)

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
    if _throttled then
      _send_buffer.push(_BufferedSend(_RespSerializer(cmd)))
    else
      let data = _RespSerializer(cmd)
      match \exhaustive\ s._connection().send(data)
      | let _: lori.SendToken => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
        return
      end
    end
    s.state = _SessionSubscribed(_notify, _readbuf, _pending, sub_notify,
      _throttled, _send_buffer, _send_buffer_limit)

  fun ref _drain_pending(s: Session ref, reason: ClientError) =>
    for queued in _pending.values() do
      queued.receiver.redis_command_failed(s, queued.command, reason)
    end
    _pending.clear()

  fun ref _drain_send_buffer(s: Session ref, reason: ClientError) =>
    for buffered in _send_buffer.values() do
      match buffered.queued
      | let qc: _QueuedCommand =>
        qc.receiver.redis_command_failed(s, qc.command, reason)
      end
    end
    _send_buffer.clear()

class ref _SessionSubscribed is _ConnectedState
  """
  Session is in pub/sub subscribed mode. Incoming responses are routed
  as pub/sub messages to the `SubscriptionNotify` receiver. Regular
  command execution is rejected with `SessionInSubscribedMode`.

  When the total subscription count (channels + patterns) reaches 0
  via unsubscribe/punsubscribe confirmations, the session transitions
  back to `_SessionReady` and `redis_session_ready` fires.

  When TCP backpressure is active (`_throttled`), subscribe/unsubscribe
  commands are buffered in `_send_buffer` instead of being sent
  immediately.
  """
  let _notify: SessionStatusNotify
  let _readbuf: Reader
  let _pending: Array[_QueuedCommand]
  let _sub_notify: SubscriptionNotify
  var _throttled: Bool
  let _send_buffer: Array[_BufferedSend]
  let _send_buffer_limit: USize

  new ref create(notify': SessionStatusNotify, readbuf': Reader,
    pending': Array[_QueuedCommand], sub_notify': SubscriptionNotify,
    throttled': Bool, send_buffer': Array[_BufferedSend],
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _pending = pending'
    _sub_notify = sub_notify'
    _throttled = throttled'
    _send_buffer = send_buffer'
    _send_buffer_limit = send_buffer_limit'

  fun ref execute(s: Session ref, command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  =>
    receiver.redis_command_failed(s, command, SessionInSubscribedMode)

  fun ref on_push(s: Session ref, push: RespPush) =>
    _dispatch_pubsub_values(s, push.values)

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
    | let arr: RespArray => _dispatch_pubsub_values(s, arr.values)
    else
      shutdown(s, SessionProtocolError)
    end

  fun ref _dispatch_pubsub_values(s: Session ref,
    values: Array[RespValue] val)
  =>
    try
      match values(0)?
      | let type_bs: RespBulkString =>
        let msg_type = String.from_array(type_bs.value)
        if msg_type == "subscribe" then
          match (values(1)?, values(2)?)
          | (let ch: RespBulkString, let cnt: RespInteger) =>
            _sub_notify.redis_subscribed(s, String.from_array(ch.value),
              cnt.value.usize())
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "unsubscribe" then
          match (values(1)?, values(2)?)
          | (let ch: RespBulkString, let cnt: RespInteger) =>
            let count = cnt.value.usize()
            _sub_notify.redis_unsubscribed(s, String.from_array(ch.value),
              count)
            if count == 0 then
              s.state = _SessionReady.from_subscribed(_notify, _readbuf,
                _throttled, _send_buffer, _send_buffer_limit)
              _notify.redis_session_ready(s)
            end
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "message" then
          match (values(1)?, values(2)?)
          | (let ch: RespBulkString, let data_bs: RespBulkString) =>
            _sub_notify.redis_message(s, String.from_array(ch.value),
              data_bs.value)
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "psubscribe" then
          match (values(1)?, values(2)?)
          | (let pat: RespBulkString, let cnt: RespInteger) =>
            _sub_notify.redis_psubscribed(s, String.from_array(pat.value),
              cnt.value.usize())
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "punsubscribe" then
          match (values(1)?, values(2)?)
          | (let pat: RespBulkString, let cnt: RespInteger) =>
            let count = cnt.value.usize()
            _sub_notify.redis_punsubscribed(s, String.from_array(pat.value),
              count)
            if count == 0 then
              s.state = _SessionReady.from_subscribed(_notify, _readbuf,
                _throttled, _send_buffer, _send_buffer_limit)
              _notify.redis_session_ready(s)
            end
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "pmessage" then
          match (values(1)?, values(2)?, values(3)?)
          | (let pat: RespBulkString, let ch: RespBulkString,
            let data_bs: RespBulkString)
          =>
            _sub_notify.redis_pmessage(s, String.from_array(pat.value),
              String.from_array(ch.value), data_bs.value)
          else
            shutdown(s, SessionProtocolError)
          end
        else
          shutdown(s, SessionProtocolError)
        end
      else
        shutdown(s, SessionProtocolError)
      end
    else
      shutdown(s, SessionProtocolError)
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
    if _throttled then
      _send_buffer.push(_BufferedSend(_RespSerializer(cmd)))
    else
      let data = _RespSerializer(cmd)
      match \exhaustive\ s._connection().send(data)
      | let _: lori.SendToken => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
      end
    end

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
    if _throttled then
      _send_buffer.push(_BufferedSend(_RespSerializer(cmd)))
    else
      let data = _RespSerializer(cmd)
      match \exhaustive\ s._connection().send(data)
      | let _: lori.SendToken => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
      end
    end

  fun ref unsubscribe(s: Session ref, channels: Array[String] val) =>
    let cmd = recover val
      let arr = Array[ByteSeq](channels.size() + 1)
      arr.push("UNSUBSCRIBE")
      for ch in channels.values() do arr.push(ch) end
      arr
    end
    if _throttled then
      _send_buffer.push(_BufferedSend(_RespSerializer(cmd)))
    else
      let data = _RespSerializer(cmd)
      match \exhaustive\ s._connection().send(data)
      | let _: lori.SendToken => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
      end
    end

  fun ref punsubscribe(s: Session ref, patterns: Array[String] val) =>
    let cmd = recover val
      let arr = Array[ByteSeq](patterns.size() + 1)
      arr.push("PUNSUBSCRIBE")
      for pat in patterns.values() do arr.push(pat) end
      arr
    end
    if _throttled then
      _send_buffer.push(_BufferedSend(_RespSerializer(cmd)))
    else
      let data = _RespSerializer(cmd)
      match \exhaustive\ s._connection().send(data)
      | let _: lori.SendToken => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
      end
    end

  fun ref on_throttled(s: Session ref) =>
    _throttled = true
    _notify.redis_session_throttled(s)

  fun ref on_unthrottled(s: Session ref) =>
    _notify.redis_session_unthrottled(s)
    s._flush_backpressure()

  fun ref flush_send_buffer(s: Session ref) =>
    _throttled = false
    while _send_buffer.size() > 0 do
      try
        let buffered = _send_buffer.shift()?
        match \exhaustive\ s._connection().send(buffered.data)
        | let _: lori.SendToken =>
          match buffered.queued
          | let qc: _QueuedCommand => _pending.push(qc)
          end
        | lori.SendErrorNotWriteable =>
          _send_buffer.unshift(buffered)
          _throttled = true
          return
        | lori.SendErrorNotConnected =>
          _send_buffer.unshift(buffered)
          shutdown(s, SessionConnectionLost)
          return
        end
      else
        _Unreachable()
      end
    end

  fun ref on_closed(s: Session ref) =>
    _readbuf.clear()
    _drain_send_buffer(s, SessionConnectionLost)
    _drain_pending(s, SessionConnectionLost)
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref close(s: Session ref) =>
    _drain_send_buffer(s, SessionClosed)
    _drain_pending(s, SessionClosed)
    _readbuf.clear()
    s._connection().send(_RespSerializer(["QUIT"]))
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref shutdown(s: Session ref, reason: ClientError) =>
    _readbuf.clear()
    _drain_send_buffer(s, reason)
    _drain_pending(s, reason)
    s._connection().close()
    s.state = _SessionClosed
    _notify.redis_session_closed(s)

  fun ref readbuf(): Reader =>
    _readbuf

  fun notify(): SessionStatusNotify =>
    _notify

  fun ref _drain_pending(s: Session ref, reason: ClientError) =>
    for queued in _pending.values() do
      queued.receiver.redis_command_failed(s, queued.command, reason)
    end
    _pending.clear()

  fun ref _drain_send_buffer(s: Session ref, reason: ClientError) =>
    for buffered in _send_buffer.values() do
      match buffered.queued
      | let qc: _QueuedCommand =>
        qc.receiver.redis_command_failed(s, qc.command, reason)
      end
    end
    _send_buffer.clear()

class ref _SessionClosed is (_ClosedState & _NotSubscribed & _NotThrottleable)
  """
  Terminal state. The session is closed and cannot be reused.
  """

primitive _BuildHelloCommand
  """
  Build the HELLO 3 command for RESP3 negotiation. If a password is
  configured, includes AUTH credentials in the HELLO command.
  """
  fun apply(info: ConnectInfo): Array[ByteSeq] val =>
    match \exhaustive\ info.password
    | let password: String =>
      let user = match \exhaustive\ info.username
      | let u: String => u
      | None => "default"
      end
      recover val [as ByteSeq: "HELLO"; "3"; "AUTH"; user; password] end
    | None =>
      recover val [as ByteSeq: "HELLO"; "3"] end
    end

primitive _BuildAuthCommand
  """
  Build an AUTH command. Includes the username for Redis 6.0+ ACL
  authentication when provided.
  """
  fun apply(username: (String | None), password: String)
    : Array[ByteSeq] val
  =>
    match \exhaustive\ username
    | let user: String =>
      recover val [as ByteSeq: "AUTH"; user; password] end
    | None =>
      recover val [as ByteSeq: "AUTH"; password] end
    end
