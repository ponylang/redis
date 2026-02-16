use "cli"
use "files"
use lori = "lori"
use "ssl/net"
// in your code this `use` statement would be:
// use "redis"
use "../../redis"

actor Main
  """
  Connects to a TLS-enabled Redis server and issues a PING.

  Requires a Redis server configured for TLS (typically on port 6380).
  Set REDIS_HOST / REDIS_PORT / REDIS_CA_PATH environment variables
  to match your server configuration.
  """
  new create(env: Env) =>
    let info = ServerInfo(env.vars)
    let auth = lori.TCPConnectAuth(env.root)
    let file_auth = FileAuth(env.root)
    try
      let sslctx: SSLContext val =
        recover val
          SSLContext
            .> set_authority(FilePath(file_auth, info.ca_path))?
        end
      Client(auth, info, sslctx, env.out)
    else
      env.err.print("Failed to create SSLContext. "
        + "Check that REDIS_CA_PATH points to a valid CA certificate.")
    end

actor Client is (SessionStatusNotify & ResultReceiver)
  let _session: Session
  let _out: OutStream

  new create(auth: lori.TCPConnectAuth, info: ServerInfo,
    sslctx: SSLContext val, out: OutStream)
  =>
    _out = out
    _session = Session(
      ConnectInfo(auth, info.host, info.port where
        ssl_mode' = SSLRequired(sslctx)),
      this)

  be redis_session_ready(session: Session) =>
    _out.print("Connected over TLS and ready.")
    let cmd: Array[ByteSeq] val = ["PING"]
    session.execute(cmd, this)

  be redis_session_connection_failed(session: Session) =>
    _out.print("Failed to connect (TLS handshake or TCP failure).")

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
  let ca_path: String

  new val create(vars: (Array[String] val | None)) =>
    let e = EnvVars(vars)
    host = try e("REDIS_HOST")? else
      ifdef linux then "127.0.0.2" else "localhost" end
    end
    port = try e("REDIS_PORT")? else "6380" end
    ca_path = try e("REDIS_CA_PATH")? else "/path/to/ca.pem" end
