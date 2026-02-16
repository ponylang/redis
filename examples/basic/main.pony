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

  new create(auth: lori.TCPConnectAuth, info: ServerInfo, out: OutStream) =>
    _out = out
    _session = Session(
      ConnectInfo(auth, info.host, info.port),
      this)

  be redis_session_ready(session: Session) =>
    _out.print("Connected and ready.")
    let cmd: Array[ByteSeq] val = ["SET"; "hello"; "world"]
    session.execute(cmd, this)

  be redis_session_connection_failed(session: Session) =>
    _out.print("Failed to connect.")

  be redis_response(session: Session, response: RespValue) =>
    match response
    | let s: RespSimpleString => _out.print("Response: " + s.value)
    | let e: RespError => _out.print("Error: " + e.message)
    end
    _session.close()

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
