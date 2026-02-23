use lori = "lori"

class val ConnectInfo
  """
  Connection configuration for a Redis session.

  The default `ssl_mode` is `SSLDisabled` (plaintext TCP). To connect
  over TLS, pass `SSLRequired` with a configured `SSLContext`:

  ```pony
  let sslctx: SSLContext val =
    recover val
      SSLContext
        .> set_authority(FilePath(file_auth, "/path/to/ca.pem"))?
    end
  let info = ConnectInfo(auth, host, "6380" where
    ssl_mode' = SSLRequired(sslctx))
  ```

  Note: `SSLContext.set_authority()` is partial — the above must be in
  a partial context or wrapped in `try`.

  To use RESP3 protocol features (maps, sets, booleans, doubles), set
  `protocol' = Resp3`. The session sends HELLO 3 on connect and falls
  back to RESP2 if the server doesn't support it:

  ```pony
  let info = ConnectInfo(auth, host where protocol' = Resp3)
  ```

  For Redis 6.0+ ACL authentication, provide a `username`. In RESP3 mode,
  the username is included in the HELLO command. In RESP2 mode, it is
  sent via `AUTH username password`.

  Redis AUTH sends the password in plaintext over TCP. Use `SSLRequired`
  when authenticating over untrusted networks.

  When the TCP connection's send buffer fills, commands are buffered
  internally up to `send_buffer_limit` commands (default 1024). If the
  buffer is full, `execute()` rejects the command immediately via
  `redis_command_failed` with `SessionBackpressureOverflow`. Set a
  higher limit for bursty workloads or a lower limit to fail fast.
  """
  let auth: lori.TCPConnectAuth
  let host: String
  let port: String
  let password: (String | None)
  let ssl_mode: SSLMode
  let username: (String | None)
  let protocol: ProtocolVersion
  let send_buffer_limit: USize

  new val create(auth': lori.TCPConnectAuth, host': String,
    port': String = "6379", password': (String | None) = None,
    ssl_mode': SSLMode = SSLDisabled,
    username': (String | None) = None,
    protocol': ProtocolVersion = Resp2,
    send_buffer_limit': USize = 1024)
  =>
    auth = auth'
    host = host'
    port = port'
    password = password'
    ssl_mode = ssl_mode'
    username = username'
    protocol = protocol'
    send_buffer_limit = send_buffer_limit'
