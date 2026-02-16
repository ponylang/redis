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

  Redis AUTH sends the password in plaintext over TCP. Use `SSLRequired`
  when authenticating over untrusted networks.
  """
  let auth: lori.TCPConnectAuth
  let host: String
  let port: String
  let password: (String | None)
  let ssl_mode: SSLMode

  new val create(auth': lori.TCPConnectAuth, host': String,
    port': String = "6379", password': (String | None) = None,
    ssl_mode': SSLMode = SSLDisabled)
  =>
    auth = auth'
    host = host'
    port = port'
    password = password'
    ssl_mode = ssl_mode'
