use lori = "lori"

class val ConnectInfo
  """
  Connection configuration for a Redis session.

  Note: Redis AUTH sends the password in plaintext over TCP.
  Use SSL/TLS when authenticating over untrusted networks.
  """
  let auth: lori.TCPConnectAuth
  let host: String
  let port: String
  let password: (String | None)

  new val create(auth': lori.TCPConnectAuth, host': String,
    port': String = "6379", password': (String | None) = None)
  =>
    auth = auth'
    host = host'
    port = port'
    password = password'
