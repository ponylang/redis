use "buffered"
use lori = "lori"

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

  new ref create(
    notify': SessionStatusNotify,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = Reader
    _send_buffer_limit = send_buffer_limit'

  new ref from_negotiating(
    notify': SessionStatusNotify,
    readbuf': Reader,
    send_buffer_limit': USize)
  =>
    _notify = notify'
    _readbuf = readbuf'
    _send_buffer_limit = send_buffer_limit'

  fun ref on_response(s: Session ref, response: RespValue) =>
    match \exhaustive\ response
    | let ok: RespSimpleString if ok.value == "OK" =>
      s.state =
        _SessionReady.from_connected(
          _notify, _readbuf, _send_buffer_limit
        )
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

