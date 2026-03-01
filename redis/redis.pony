"""
Redis client for Pony.

## Quick Start

Create a `Session` with connection info and a notification receiver. The
session connects asynchronously — wait for `redis_session_ready` before
sending commands. Use command builder primitives to construct commands and
`RespConvert` to extract typed values from responses:

```pony
actor MyApp is (SessionStatusNotify & ResultReceiver)
  let _session: Session

  new create(env: Env) =>
    let auth = lori.TCPConnectAuth(env.root)
    _session = Session(ConnectInfo(auth, "localhost"), this)

  be redis_session_ready(session: Session) =>
    session.execute(RedisString.set("key", "value"), this)

  be redis_response(session: Session, response: RespValue) =>
    if RespConvert.is_ok(response) then
      session.execute(RedisString.get("key"), this)
    else
      match \exhaustive\ RespConvert.as_string(response)
      | let value: String => // use value
        None
      end
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    // handle failure
    None
```

## Session API

* `ConnectInfo` — connection configuration (host, port, optional password,
  SSL mode, protocol version, optional username, send buffer limit)
* `Session` — the main entry point; manages connection lifecycle
* `SessionStatusNotify` — lifecycle callbacks (connected, ready, closed, etc.)
* `ResultReceiver` — command result callbacks

Commands are arrays of `ByteSeq`. Use the command builder primitives (see
below) for common commands, or construct arrays directly for commands not
yet covered. Responses are `RespValue` variants — including `RespError` for
server-side errors.

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

## Backpressure

When the TCP connection's send buffer fills (the OS socket buffer is full),
commands are buffered internally up to `send_buffer_limit` commands
(default 1024, configurable via `ConnectInfo`). The buffer is flushed
automatically when the connection becomes writeable.

If the buffer is full when `execute()` is called, the command is rejected
immediately via `redis_command_failed` with `SessionBackpressureOverflow`.
This prevents unbounded memory growth when a producer outpaces the network:

```pony
actor MyApp is (SessionStatusNotify & ResultReceiver)
  // ...

  be redis_session_throttled(session: Session) =>
    // TCP send buffer full — commands are being buffered internally.
    // Optionally reduce sending rate.
    None

  be redis_session_unthrottled(session: Session) =>
    // Backpressure released — buffered commands are being flushed.
    None

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    match \exhaustive\ failure
    | SessionBackpressureOverflow =>
      // Buffer full — stop sending until unthrottled.
      None
    end
```

To increase the buffer limit for bursty workloads:

```pony
let info = ConnectInfo(auth, host where send_buffer_limit' = 4096)
```

## RESP3

To enable RESP3 protocol features, set `protocol' = Resp3` in `ConnectInfo`:

```pony
let info = ConnectInfo(auth, host where protocol' = Resp3)
```

The session sends HELLO 3 on connect. If the server supports RESP3 (Redis
6.0+), responses may include richer types like maps, sets, booleans, and
doubles. If the server doesn't support HELLO, the session falls back to
RESP2 automatically.

For Redis 6.0+ ACL authentication, provide a `username`:

```pony
let info = ConnectInfo(auth, host where
  password' = "secret", username' = "myuser", protocol' = Resp3)
```

## Value Types

The protocol layer uses `RespValue` as the core type for data exchanged with
a Redis server. This is a union of:

### RESP2 types
* `RespSimpleString` — short status responses like "OK"
* `RespBulkString` — binary-safe string data
* `RespInteger` — signed 64-bit integers
* `RespArray` — ordered collections of values
* `RespError` — error responses from the server
* `RespNull` — null/nil values

### RESP3 types (require `Resp3` protocol)
* `RespBoolean` — true/false values
* `RespDouble` — double-precision floating-point values
* `RespBigNumber` — arbitrary-precision integers (stored as string)
* `RespBulkError` — binary-safe error messages
* `RespVerbatimString` — strings with a 3-character encoding hint
* `RespMap` — ordered key-value pairs
* `RespSet` — unordered collections
* `RespPush` — server-initiated out-of-band messages

## Command Builders

Six primitives provide type-safe command construction for common Redis
operations, replacing raw `Array[ByteSeq] val` arrays:

* `RedisServer` — PING, ECHO, DBSIZE, FLUSHDB
* `RedisString` — GET, SET (with NX/EX variants), INCR, DECR, INCRBY,
  DECRBY, MGET, MSET
* `RedisKey` — DEL, EXISTS, EXPIRE, TTL, PERSIST, KEYS, RENAME, TYPE
* `RedisHash` — HGET, HSET, HDEL, HGETALL, HEXISTS
* `RedisList` — LPUSH, RPUSH, LPOP, RPOP, LLEN, LRANGE
* `RedisSet` — SADD, SREM, SMEMBERS, SISMEMBER, SCARD

Each method returns `Array[ByteSeq] val` ready to pass to `session.execute`:

```pony
session.execute(RedisString.set("key", "value"), this)
session.execute(RedisKey.expire("key", 300), this)
```

For commands not covered by the builders, construct the array directly:
`session.execute(["ZADD"; "myzset"; "1"; "member"], this)`.

## Response Extraction

`RespConvert` provides total functions for extracting typed values from
`RespValue` responses. Each extractor returns a three-way result:

* The extracted value when the response matches (e.g., `String` from
  `as_string`)
* `RespNull` when the response is null
* `None` when the response is a non-matching type

```pony
// Check for OK
if RespConvert.is_ok(response) then ... end

// Extract a string (from simple string, bulk string, or verbatim string)
match \exhaustive\ RespConvert.as_string(response)
| let value: String => // use value
| RespNull => // key did not exist
end

// Extract an error message (from RespError or RespBulkError)
match \exhaustive\ RespConvert.as_error(response)
| let msg: String => // handle error
end
```
"""
