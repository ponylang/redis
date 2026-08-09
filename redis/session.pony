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
    _tcp_connection =
      match \exhaustive\ connect_info'.ssl_mode
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

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    let r: ConnectionFailureReason =
      match \exhaustive\ reason
      | let _: lori.ConnectionFailedDNS => ConnectionFailedDNS
      | let _: lori.ConnectionFailedTCP => ConnectionFailedTCP
      | let _: lori.ConnectionFailedSSL => ConnectionFailedSSL
      | let _: lori.ConnectionFailedTimeout =>
        ConnectionFailedTimeout
      | let _: lori.ConnectionFailedTimerError =>
        ConnectionFailedTimerError
      end
    state.on_failure(this, r)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    state.on_received(this, consume data)
    lori.KeepReading

  fun ref _on_closed() =>
    state.on_closed(this)

  fun ref _on_throttled() =>
    state.on_throttled(this)

  fun ref _on_unthrottled() =>
    state.on_unthrottled(this)

  fun ref _on_idle_timer_failure() =>
    _Unreachable()

  fun ref _on_timer_failure() =>
    _Unreachable()

  be _flush_backpressure() =>
    """
    Deferred flush of the backpressure send buffer. Triggered by
    on_unthrottled to avoid calling send() from within lori's pending
    writes processing.
    """
    state.flush_send_buffer(this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

