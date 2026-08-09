use "buffered"

interface _SessionState
  fun on_connected(s: Session ref)

  fun on_failure(s: Session ref, reason: ConnectionFailureReason)

  fun ref on_received(s: Session ref, data: Array[U8] iso)

  fun ref on_closed(s: Session ref)

  fun ref on_response(s: Session ref, response: RespValue)

  fun ref on_push(s: Session ref, push: RespPush)

  fun ref execute(
    s: Session ref,
    command: Array[ByteSeq] val,
    receiver: ResultReceiver)

  fun ref close(s: Session ref)

  fun ref shutdown(s: Session ref, reason: ClientError)

  fun ref subscribe(
    s: Session ref,
    channels: Array[String] val,
    sub_notify: SubscriptionNotify)

  fun ref unsubscribe(s: Session ref, channels: Array[String] val)

  fun ref psubscribe(
    s: Session ref,
    patterns: Array[String] val,
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

  fun on_failure(s: Session ref, reason: ConnectionFailureReason) =>
    _IllegalState()

  fun ref on_received(s: Session ref, data: Array[U8] iso) =>
    // Data may arrive after close — silently drop.
    None

  fun ref on_closed(s: Session ref) =>
    // Already closed.
    None

  fun ref on_response(s: Session ref, response: RespValue) =>
    _IllegalState()

  fun ref execute(
    s: Session ref,
    command: Array[ByteSeq] val,
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

  fun on_failure(s: Session ref, reason: ConnectionFailureReason) =>
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
  fun ref execute(
    s: Session ref,
    command: Array[ByteSeq] val,
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

  fun ref subscribe(
    s: Session ref,
    channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    None

  fun ref unsubscribe(s: Session ref, channels: Array[String] val) =>
    None

  fun ref psubscribe(
    s: Session ref,
    patterns: Array[String] val,
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

