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
  var _step: USize = 0

  new create(auth: lori.TCPConnectAuth, info: ServerInfo, out: OutStream) =>
    _out = out
    _session = Session(
      ConnectInfo(auth, info.host, info.port),
      this)

  be redis_session_ready(session: Session) =>
    _out.print("Connected and ready.")

    // Pipeline 3 SET commands — all sent immediately without waiting
    // for individual responses.
    _out.print("Pipelining SET commands...")
    let fruits: Array[String] val = ["apple"; "banana"; "cherry"]
    for fruit in fruits.values() do
      let cmd: Array[ByteSeq] val = ["SET"; "fruit:" + fruit; fruit]
      session.execute(cmd, this)
    end

    // Pipeline 3 GET commands to retrieve the values we just set.
    _out.print("Pipelining GET commands...")
    for fruit in fruits.values() do
      let cmd: Array[ByteSeq] val = ["GET"; "fruit:" + fruit]
      session.execute(cmd, this)
    end

  be redis_session_connection_failed(session: Session) =>
    _out.print("Failed to connect.")

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    if _step <= 3 then
      match response
      | let s: RespSimpleString => _out.print("SET response: " + s.value)
      | let e: RespError => _out.print("SET error: " + e.message)
      end
    elseif _step <= 6 then
      match response
      | let b: RespBulkString =>
        _out.print("GET response: " + String.from_array(b.value))
      | let e: RespError => _out.print("GET error: " + e.message)
      end
    end
    if _step == 6 then
      _out.print("All responses received.")
      _session.close()
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _out.print("Command failed: " + failure.message())
    _session.close()

class val ServerInfo
  let host: String
  let port: String

  new val create(vars: (Array[String] val | None)) =>
    let e = EnvVars(vars)
    host = try e("REDIS_HOST")? else
      ifdef linux then "127.0.0.2" else "localhost" end
    end
    port = try e("REDIS_PORT")? else "6379" end
