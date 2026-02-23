use "cli"
use lori = "lori"
// in your code this `use` statement would be:
// use "redis"
use "../../redis"

actor Main
  new create(env: Env) =>
    let info = ServerInfo(env.vars)
    let auth = lori.TCPConnectAuth(env.root)
    Client(auth, info, env.out)

actor Client is (SessionStatusNotify & ResultReceiver)
  let _session: Session
  let _out: OutStream
  let _total: USize = 1000
  var _sent: USize = 0
  var _received: USize = 0

  new create(auth: lori.TCPConnectAuth, info: ServerInfo, out: OutStream) =>
    _out = out
    _session = Session(
      ConnectInfo(auth, info.host, info.port),
      this)

  be redis_session_ready(session: Session) =>
    _out.print("Connected and ready. Sending " + _total.string()
      + " SET commands...")
    _send_burst(session)

  be redis_session_throttled(session: Session) =>
    _out.print("Throttled after " + _sent.string() + " sends — "
      + "commands are being buffered.")

  be redis_session_unthrottled(session: Session) =>
    _out.print("Unthrottled — flushing buffered commands.")

  be redis_session_connection_failed(session: Session) =>
    _out.print("Failed to connect.")

  be redis_response(session: Session, response: RespValue) =>
    _received = _received + 1
    match RespConvert.as_error(response)
    | let msg: String =>
      _out.print("Error on response " + _received.string() + ": " + msg)
    end
    if _received == _total then
      _out.print("All " + _total.string() + " responses received.")
      _session.close()
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _out.print("Command failed: " + failure.message())
    _session.close()

  fun ref _send_burst(session: Session) =>
    while _sent < _total do
      let key: String val = "bp:" + _sent.string()
      session.execute(RedisString.set(key, "value"), this)
      _sent = _sent + 1
    end

class val ServerInfo
  let host: String
  let port: String

  new val create(vars: (Array[String] val | None)) =>
    let e = EnvVars(vars)
    host = try e("REDIS_HOST")? else
      ifdef linux then "127.0.0.2" else "localhost" end
    end
    port = try e("REDIS_PORT")? else "6379" end
