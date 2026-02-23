# Redis Client for Pony

## Building

```
make                    # build and run all tests (requires Redis running)
make unit-tests         # run unit tests only (no Redis needed)
make integration-tests  # run integration tests only (requires Redis)
make build-examples     # build example programs
make start-redis        # start plaintext, SSL, and RESP2-only Redis in Docker
make stop-redis         # stop and remove all Redis containers
make clean              # clean build artifacts
```

All build targets require `ssl=<version>` (e.g., `ssl=3.0.x` for OpenSSL 3.x, `ssl=libressl` for LibreSSL). This is needed because lori depends on the ssl package. Add `config=debug` for debug builds.

### Running Tests Locally

```
make start-redis
make test config=debug ssl=3.0.x
make stop-redis
```

## Dependencies

- `ponylang/lori` (0.8.1) — TCP networking (transitively depends on `ponylang/ssl`, hence the `ssl=` build flag)

## Architecture

Package: `redis`

### Protocol Layer

- `RespValue` (union type in `resp_value.pony`): Core type for RESP2/RESP3 wire format values. Union of `RespSimpleString`, `RespBulkString`, `RespInteger`, `RespArray`, `RespError`, `RespNull`, `RespBoolean`, `RespDouble`, `RespBigNumber`, `RespBulkError`, `RespVerbatimString`, `RespMap`, `RespSet`, `RespPush`.
- `RespMalformed` (in `resp_value.pony`): Parser error type indicating invalid RESP data. Not part of `RespValue` — represents a protocol violation, not a valid value.
- `_RespParser` (in `_resp_parser.pony`): Two-pass parser — peek-based completeness check, then destructive parse. Returns `(RespValue | None | RespMalformed)` from a `buffered.Reader`. Supports all RESP2 and RESP3 type bytes.
- `_RespSerializer` (in `_resp_serializer.pony`): Serializes commands (`Array[ByteSeq] val`) to RESP2 wire format.
- `ProtocolVersion` (type alias in `protocol_version.pony`): `(Resp2 | Resp3)`. Controls which protocol the session negotiates on connect.

### Session Layer

- `Session` (actor in `session.pony`): Main entry point. Manages connection lifecycle and pub/sub via a state machine. Implements `lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver`. All state machine classes (`_SessionUnopened`, `_SessionNegotiating`, `_SessionConnected`, `_SessionReady`, `_SessionSubscribed`, `_SessionClosed`) are in `session.pony`, following the postgres pattern.
- `ConnectInfo` (in `connect_info.pony`): Connection configuration (host, port, optional password, SSL mode, optional username, protocol version).
- `SessionStatusNotify` (in `session_status_notify.pony`): Lifecycle callback interface. All callbacks have default no-op implementations. Callbacks: `redis_session_connected`, `redis_session_connection_failed`, `redis_session_ready`, `redis_session_authentication_failed`, `redis_session_closed`.
- `ResultReceiver` (in `result_receiver.pony`): Command response callback interface. Callbacks: `redis_response`, `redis_command_failed`.
- `SubscriptionNotify` (in `subscription_notify.pony`): Pub/sub callback interface. All callbacks have default no-op implementations. Callbacks: `redis_subscribed`, `redis_unsubscribed`, `redis_message`, `redis_psubscribed`, `redis_punsubscribed`, `redis_pmessage`.
- `ClientError` (in `client_error.pony`): Client-side error trait with `SessionNotReady`, `SessionClosed`, `SessionConnectionLost`, `SessionProtocolError`, and `SessionInSubscribedMode` primitives.
- `_ResponseHandler` (in `_response_handler.pony`): Loops `_RespParser` over a `buffered.Reader`, routing `RespPush` to `on_push` and other `RespValue`s to `on_response`. Shuts down on `RespMalformed`.
- `_BuildHelloCommand` / `_BuildAuthCommand` (primitives in `session.pony`): Build HELLO 3 and AUTH commands for protocol negotiation and authentication.
- `_IllegalState` / `_Unreachable` (in `_mort.pony`): Primitives for detecting impossible states.

### Command Builders

Six public primitives for constructing common Redis commands as `Array[ByteSeq] val`. Each method is a pure function.

- `RedisServer` (in `redis_server.pony`): PING, ECHO, DBSIZE, FLUSHDB.
- `RedisString` (in `redis_string.pony`): GET, SET (with NX/EX variants), INCR, DECR, INCRBY, DECRBY, MGET, MSET.
- `RedisKey` (in `redis_key.pony`): DEL, EXISTS, EXPIRE, TTL, PERSIST, KEYS, RENAME, TYPE (as `type_of`).
- `RedisHash` (in `redis_hash.pony`): HGET, HSET, HDEL, HGETALL, HEXISTS.
- `RedisList` (in `redis_list.pony`): LPUSH, RPUSH, LPOP, RPOP, LLEN, LRANGE.
- `RedisSet` (in `redis_set.pony`): SADD, SREM, SMEMBERS, SISMEMBER, SCARD.

Fixed-argument commands use `recover val [as ByteSeq: ...] end`. Variadic commands use `recover val` with `Array.push` loops.

### Response Extraction

- `RespConvert` (primitive in `resp_convert.pony`): Total functions for extracting typed values from `RespValue`. Each extractor returns `(T | RespNull | None)` except `as_error` → `(String | None)` and `is_ok` → `Bool`. Methods: `as_string`, `as_bytes`, `as_integer`, `as_bool`, `as_array`, `as_double`, `as_big_number`, `as_map`, `as_set`, `as_error`, `is_ok`.

### SSL/TLS

- `SSLMode` (type alias in `ssl_mode.pony`): `(SSLDisabled | SSLRequired)`. Controls whether the session uses plaintext TCP or SSL/TLS.
- `SSLDisabled` (primitive in `ssl_mode.pony`): Plaintext TCP connection (default).
- `SSLRequired` (class val in `ssl_mode.pony`): Wraps an `SSLContext val` for direct TLS connections. Redis uses direct TLS (typically port 6380) rather than STARTTLS.
- The `ssl/net` package is a transitive dependency via lori (no `corral.json` change needed). Adding `use "ssl/net"` in source files is sufficient.

### Trait Composition

- `_ClosedState`: Mixin for the terminal state — rejects or no-ops all operations.
- `_ConnectedState`: Mixin for states with a readbuf — handles `on_received` and `_ResponseHandler` dispatch.
- `_NotReadyForCommands`: Mixin that rejects `execute()` with `SessionNotReady`.
- `_NotSubscribed`: Mixin that no-ops `subscribe`, `unsubscribe`, `psubscribe`, `punsubscribe` for states where pub/sub is not applicable. Also provides a no-op `on_push` for states that don't handle push messages (only trait that provides `on_push`, to avoid diamond inheritance in `_SessionClosed`).

### State Machine

```
_SessionUnopened ──on_connected──► _SessionNegotiating (if Resp3)
                 ──on_connected──► _SessionConnected (if Resp2 + password)
                 ──on_connected──► _SessionReady (if Resp2, no password)

_SessionNegotiating ──HELLO map──► _SessionReady
                    ──HELLO error──► _SessionConnected (if password, send AUTH)
                    ──HELLO error──► _SessionReady (if no password)

_SessionConnected ──AUTH OK──► _SessionReady
                  ──AUTH error──► _SessionClosed

_SessionReady ──subscribe/psubscribe──► _SessionSubscribed
              ──close/error──► _SessionClosed

_SessionSubscribed ──unsub count 0──► _SessionReady
                   ──close/error──► _SessionClosed
```

Commands are pipelined in `_SessionReady`: each `execute()` call sends the command immediately over the wire without waiting for prior responses. Responses are matched to receivers in FIFO order.

In `_SessionSubscribed`, any pipelined commands that were in-flight when SUBSCRIBE was sent are drained first (Redis guarantees in-order response delivery), then incoming responses are routed as pub/sub messages. In RESP3 mode, pub/sub messages arrive as `RespPush` via `on_push`; in RESP2 mode they arrive as `RespArray` via `on_response`.

## Test Infrastructure

- Unit tests: `--exclude=integration/` — no external dependencies
- Integration tests: `--only=integration/` — require a running Redis server
- Test names prefixed with `integration/` for filtering
- `_RedisTestConfiguration` reads environment variables for plaintext, SSL, and RESP2-only Redis:
  - `REDIS_HOST` / `REDIS_PORT` — plaintext (defaults to `127.0.0.2`/`6379` on Linux)
  - `REDIS_SSL_HOST` / `REDIS_SSL_PORT` — TLS (defaults to same host/`6380`)
  - `REDIS_RESP2_HOST` / `REDIS_RESP2_PORT` — RESP2-only Redis 5 (defaults to same host/`6381`)

### SSL-to-Plaintext Deadlock

Do not write tests that connect with SSL to a plaintext Redis server. The TLS ClientHello is binary data with no `\r\n`, so Redis's RESP parser buffers it waiting for a line terminator. Meanwhile the SSL client waits for a ServerHello. Neither side sends more data — both block indefinitely. To test the SSL constructor path, connect to a non-listening port instead (TCP connection refused is fast and deterministic).

### CI

Both `pr.yml` and `breakage-against-ponyc-latest.yml` use the `shared-docker-ci-standard-builder-with-libressl-4.2.0` image (for ssl support) and three Redis service containers: `redis` (plaintext, Redis 7), `redis-ssl` (TLS via `ghcr.io/ponylang/redis-ci-redis-ssl:latest`), and `redis-resp2` (Redis 5, RESP2-only for HELLO fallback testing). Integration tests receive `REDIS_HOST=redis`, `REDIS_PORT=6379`, `REDIS_SSL_HOST=redis-ssl`, `REDIS_SSL_PORT=6379`, `REDIS_RESP2_HOST=redis-resp2`, and `REDIS_RESP2_PORT=6379`. All make targets pass `ssl=libressl`.

The `redis-ssl` CI image is built via `build-ci-image.yml` (manually triggered `workflow_dispatch`). Source: `.ci-dockerfiles/redis-ssl/Dockerfile`. Build locally with `.ci-dockerfiles/redis-ssl/build-and-push.bash`.

## File Layout

- `redis/` — main package source
- `examples/` — example programs
- `assets/` — test certificates for SSL Redis container
- `.ci-dockerfiles/` — Dockerfiles for CI service containers
