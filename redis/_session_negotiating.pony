use "buffered"
use lori = "lori"

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
      s.state =
        _SessionReady.from_connected(
          _notify,
          _readbuf,
          _connect_info.send_buffer_limit
        )
      _notify.redis_session_ready(s)
    | let err: RespError =>
      // HELLO not supported — fall back to RESP2.
      match \exhaustive\ _connect_info.password
      | let password: String =>
        let cmd = _BuildAuthCommand(_connect_info.username, password)
        let data = _RespSerializer(cmd)
        match s._connection().send(data)
        | lori.SendAccepted =>
          s.state =
            _SessionConnected.from_negotiating(
              _notify,
              _readbuf,
              _connect_info.send_buffer_limit
            )
        else
          shutdown(s, SessionConnectionLost)
        end
      | None =>
        s.state =
          _SessionReady.from_connected(
            _notify,
            _readbuf,
            _connect_info.send_buffer_limit
          )
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

