use "buffered"
use lori = "lori"

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
      | lori.SendAccepted =>
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
        | lori.SendAccepted =>
          s.state =
            _SessionConnected(
              _notify,
              _connect_info.send_buffer_limit
            )
        else
          s._connection().close()
          s.state = _SessionClosed
          _notify.redis_session_closed(s)
        end
      | None =>
        s.state =
          _SessionReady(
            _notify,
            _connect_info.send_buffer_limit
          )
        _notify.redis_session_ready(s)
      end
    end

  fun on_failure(s: Session ref, reason: ConnectionFailureReason) =>
    s.state = _SessionClosed
    _notify.redis_session_connection_failed(s, reason)

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

