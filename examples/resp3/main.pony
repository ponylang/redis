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
      ConnectInfo(auth, info.host, info.port where protocol' = Resp3),
      this)

  be redis_session_ready(session: Session) =>
    _out.print("Connected with RESP3 protocol.")
    // HSET writes fields on a hash key.
    let cmd: Array[ByteSeq] val =
      ["HSET"; "_resp3_example"; "name"; "Pony"; "version"; "0.60"]
    session.execute(cmd, this)

  be redis_session_connection_failed(session: Session) =>
    _out.print("Failed to connect.")

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    if _step == 1 then
      // HSET response — integer count of fields added.
      _out.print("HSET done.")
      // HGETALL returns a map in RESP3 mode.
      let cmd: Array[ByteSeq] val = ["HGETALL"; "_resp3_example"]
      session.execute(cmd, this)
    elseif _step == 2 then
      // HGETALL response — RespMap in RESP3, RespArray in RESP2.
      match response
      | let m: RespMap =>
        _out.print("HGETALL returned a map with "
          + m.pairs.size().string() + " pairs:")
        for (k, v) in m.pairs.values() do
          let ks = match k
          | let b: RespBulkString => String.from_array(b.value)
          else "?"
          end
          let vs = match v
          | let b: RespBulkString => String.from_array(b.value)
          else "?"
          end
          _out.print("  " + ks + " = " + vs)
        end
      | let a: RespArray =>
        // Fallback to RESP2 — server didn't support HELLO.
        _out.print("HGETALL returned an array (RESP2 fallback) with "
          + a.values.size().string() + " elements.")
      else
        _out.print("Unexpected response type from HGETALL.")
      end
      // Clean up.
      let cmd: Array[ByteSeq] val = ["DEL"; "_resp3_example"]
      session.execute(cmd, this)
    else
      _out.print("Cleaned up. Done.")
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
