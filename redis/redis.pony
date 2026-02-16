"""
Redis client for Pony.

## Quick Start

Create a `Session` with connection info and a notification receiver. The
session connects asynchronously — wait for `redis_session_ready` before
sending commands:

```pony
actor MyApp is (SessionStatusNotify & ResultReceiver)
  let _session: Session

  new create(env: Env) =>
    let auth = lori.TCPConnectAuth(env.root)
    _session = Session(ConnectInfo(auth, "localhost"), this)

  be redis_session_ready(session: Session) =>
    session.execute(["SET"; "key"; "value"], this)

  be redis_response(session: Session, response: RespValue) =>
    // handle response
    None

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    // handle failure
    None
```

## Session API

* `ConnectInfo` — connection configuration (host, port, optional password,
  SSL mode)
* `Session` — the main entry point; manages connection lifecycle
* `SessionStatusNotify` — lifecycle callbacks (connected, ready, closed, etc.)
* `ResultReceiver` — command result callbacks

Commands are arrays of `ByteSeq` (e.g., `["GET", "mykey"]`). Responses are
`RespValue` variants — including `RespError` for server-side errors.

## Pub/Sub

To enter pub/sub mode, call `subscribe()` or `psubscribe()` on a ready
session with a `SubscriptionNotify` receiver:

```pony
actor MySubscriber is (SessionStatusNotify & SubscriptionNotify)
  let _session: Session

  new create(env: Env) =>
    let auth = lori.TCPConnectAuth(env.root)
    _session = Session(ConnectInfo(auth, "localhost"), this)

  be redis_session_ready(session: Session) =>
    let channels: Array[String] val = ["my-channel"]
    session.subscribe(channels, this)

  be redis_message(session: Session, channel: String,
    data: Array[U8] val)
  =>
    // handle incoming message
    None
```

While subscribed, `execute()` is rejected with `SessionInSubscribedMode`.
To publish messages, use a separate session — the subscribed session cannot
send commands. When all subscriptions are cancelled (the server's
subscription count reaches 0), the session returns to ready mode and
`redis_session_ready` fires again.

Implement `SessionStatusNotify` alongside `SubscriptionNotify` to detect
connection loss during subscribed mode — `SubscriptionNotify` receives no
notification when the connection closes; `redis_session_closed` fires on
`SessionStatusNotify` instead.

## Security

Redis AUTH sends the password in plaintext over TCP. Use `SSLRequired` to
encrypt the connection:

```pony
use "ssl/net"

// SSLContext.set_authority() is partial
let sslctx: SSLContext val =
  recover val
    SSLContext
      .> set_authority(FilePath(file_auth, "/path/to/ca.pem"))?
  end
let info = ConnectInfo(auth, host, "6380" where
  ssl_mode' = SSLRequired(sslctx))
let session = Session(info, notify)
```

Redis uses direct TLS (typically on port 6380) rather than STARTTLS
negotiation.

## RESP2 Value Types

The protocol layer uses `RespValue` as the core type for data exchanged with
a Redis server. This is a union of:

* `RespSimpleString` — short status responses like "OK"
* `RespBulkString` — binary-safe string data
* `RespInteger` — signed 64-bit integers
* `RespArray` — ordered collections of values
* `RespError` — error responses from the server
* `RespNull` — null/nil values
"""
