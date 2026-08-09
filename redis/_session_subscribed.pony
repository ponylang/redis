use "buffered"
use lori = "lori"

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

  new ref create(
    notify': SessionStatusNotify,
    readbuf': Reader,
    pending': Array[_QueuedCommand],
    sub_notify': SubscriptionNotify,
    throttled': Bool,
    send_buffer': Array[_BufferedSend],
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _pending = pending'
    _sub_notify = sub_notify'
    _throttled = throttled'
    _send_buffer = send_buffer'
    _send_buffer_limit = send_buffer_limit'

  fun ref execute(
    s: Session ref,
    command: Array[ByteSeq] val,
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

  fun ref _dispatch_pubsub_values(
    s: Session ref,
    values: Array[RespValue] val)
  =>
    try
      match values(0)?
      | let type_bs: RespBulkString =>
        let msg_type = String.from_array(type_bs.value)
        if msg_type == "subscribe" then
          match (values(1)?, values(2)?)
          | (let ch: RespBulkString, let cnt: RespInteger) =>
            _sub_notify.redis_subscribed(
              s, String.from_array(ch.value), cnt.value.usize()
            )
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "unsubscribe" then
          match (values(1)?, values(2)?)
          | (let ch: RespBulkString, let cnt: RespInteger) =>
            let count = cnt.value.usize()
            _sub_notify.redis_unsubscribed(
              s, String.from_array(ch.value), count
            )
            if count == 0 then
              s.state =
                _SessionReady.from_subscribed(
                  _notify,
                  _readbuf,
                  _throttled,
                  _send_buffer,
                  _send_buffer_limit
                )
              _notify.redis_session_ready(s)
            end
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "message" then
          match (values(1)?, values(2)?)
          | (let ch: RespBulkString, let data_bs: RespBulkString) =>
            _sub_notify.redis_message(
              s, String.from_array(ch.value), data_bs.value
            )
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "psubscribe" then
          match (values(1)?, values(2)?)
          | (let pat: RespBulkString, let cnt: RespInteger) =>
            _sub_notify.redis_psubscribed(
              s, String.from_array(pat.value), cnt.value.usize()
            )
          else
            shutdown(s, SessionProtocolError)
          end
        elseif msg_type == "punsubscribe" then
          match (values(1)?, values(2)?)
          | (let pat: RespBulkString, let cnt: RespInteger) =>
            let count = cnt.value.usize()
            _sub_notify.redis_punsubscribed(
              s, String.from_array(pat.value), count
            )
            if count == 0 then
              s.state =
                _SessionReady.from_subscribed(
                  _notify,
                  _readbuf,
                  _throttled,
                  _send_buffer,
                  _send_buffer_limit
                )
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
            _sub_notify.redis_pmessage(
              s,
              String.from_array(pat.value),
              String.from_array(ch.value),
              data_bs.value
            )
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

  fun ref subscribe(
    s: Session ref,
    channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    // sub_notify parameter is ignored — all messages go to _sub_notify
    // from the initial subscribe call.
    if channels.size() == 0 then return end
    let cmd =
      recover val
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
      | lori.SendAccepted => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
      end
    end

  fun ref psubscribe(
    s: Session ref,
    patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
    // sub_notify parameter is ignored — all messages go to _sub_notify
    // from the initial subscribe call.
    if patterns.size() == 0 then return end
    let cmd =
      recover val
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
      | lori.SendAccepted => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
      end
    end

  fun ref unsubscribe(s: Session ref, channels: Array[String] val) =>
    let cmd =
      recover val
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
      | lori.SendAccepted => None
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(_BufferedSend(data))
        _notify.redis_session_throttled(s)
      | lori.SendErrorNotConnected =>
        shutdown(s, SessionConnectionLost)
      end
    end

  fun ref punsubscribe(s: Session ref, patterns: Array[String] val) =>
    let cmd =
      recover val
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
      | lori.SendAccepted => None
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
        | lori.SendAccepted =>
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

