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

* `ConnectInfo` — connection configuration (host, port, optional password)
* `Session` — the main entry point; manages connection lifecycle
* `SessionStatusNotify` — lifecycle callbacks (connected, ready, closed, etc.)
* `ResultReceiver` — command result callbacks

Commands are arrays of `ByteSeq` (e.g., `["GET", "mykey"]`). Responses are
`RespValue` variants — including `RespError` for server-side errors.

## Security

Redis AUTH sends the password in plaintext over TCP. Use SSL/TLS when
authenticating over untrusted networks.

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
