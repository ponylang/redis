use "buffered"

primitive _ResponseHandler
  """
  Loops `_RespParser` over a buffered Reader, delivering each parsed
  `RespValue` to the session's current state. Called from `on_received`
  after new data is appended to the reader.

  If parsing returns `RespMalformed`, the session is shut down — once
  the protocol stream is corrupt, there is no way to resynchronize.

  If a callback triggers shutdown, the shutdown path clears the readbuf,
  causing the next `_RespParser` call to return `None` and exit the loop
  naturally.
  """
  fun apply(s: Session ref, readbuf: Reader) =>
    while true do
      match \exhaustive\ _RespParser(readbuf)
      | let push: RespPush => s.state.on_push(s, push)
      | let v: RespValue => s.state.on_response(s, v)
      | None => return
      | let _: RespMalformed =>
        s.state.shutdown(s, SessionProtocolError)
        return
      end
    end
