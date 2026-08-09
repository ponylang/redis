use "buffered"
use lori = "lori"

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

  new ref create(
    notify': SessionStatusNotify,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = Reader
    _throttled = false
    _send_buffer = Array[_BufferedSend]
    _send_buffer_limit = send_buffer_limit'

  new ref from_connected(
    notify': SessionStatusNotify,
    readbuf': Reader,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _throttled = false
    _send_buffer = Array[_BufferedSend]
    _send_buffer_limit = send_buffer_limit'

  new ref from_subscribed(
    notify': SessionStatusNotify,
    readbuf': Reader,
    throttled': Bool,
    send_buffer': Array[_BufferedSend],
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _throttled = throttled'
    _send_buffer = send_buffer'
    _send_buffer_limit = send_buffer_limit'

  fun ref execute(
    s: Session ref,
    command: Array[ByteSeq] val,
    receiver: ResultReceiver)
  =>
    if _throttled then
      if _send_buffer.size() >= _send_buffer_limit then
        receiver.redis_command_failed(
          s, command, SessionBackpressureOverflow
        )
        return
      end
      _send_buffer.push(
        _BufferedSend(
          _RespSerializer(command),
          _QueuedCommand(command, receiver)
        )
      )
    else
      let data = _RespSerializer(command)
      match \exhaustive\ s._connection().send(data)
      | lori.SendAccepted =>
        _pending.push(_QueuedCommand(command, receiver))
      | lori.SendErrorNotWriteable =>
        _throttled = true
        _send_buffer.push(
          _BufferedSend(data, _QueuedCommand(command, receiver))
        )
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

  fun ref readbuf(): Reader =>
    _readbuf

  fun notify(): SessionStatusNotify =>
    _notify

  fun ref subscribe(
    s: Session ref,
    channels: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
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
        return
      end
    end
    s.state =
      _SessionSubscribed(
        _notify,
        _readbuf,
        _pending,
        sub_notify,
        _throttled,
        _send_buffer,
        _send_buffer_limit
      )

  fun ref psubscribe(
    s: Session ref,
    patterns: Array[String] val,
    sub_notify: SubscriptionNotify)
  =>
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
        return
      end
    end
    s.state =
      _SessionSubscribed(
        _notify,
        _readbuf,
        _pending,
        sub_notify,
        _throttled,
        _send_buffer,
        _send_buffer_limit
      )

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

