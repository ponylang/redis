# Redis Client for Pony

## Building

```
make                    # build and run all tests (requires Redis running)
make unit-tests         # run unit tests only (no Redis needed)
make integration-tests  # run integration tests only (requires Redis)
make build-examples     # build example programs
make start-redis        # start Redis in Docker for local testing
make stop-redis         # stop and remove Docker Redis
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

### RESP2 Protocol Layer

- `RespValue` (union type in `resp_value.pony`): Core type for RESP2 wire format values. Union of `RespSimpleString`, `RespBulkString`, `RespInteger`, `RespArray`, `RespError`, `RespNull`.
- `RespMalformed` (in `resp_value.pony`): Parser error type indicating invalid RESP data. Not part of `RespValue` — represents a protocol violation, not a valid value.
- `_RespParser` (in `_resp_parser.pony`): Two-pass parser — peek-based completeness check, then destructive parse. Returns `(RespValue | None | RespMalformed)` from a `buffered.Reader`.
- `_RespSerializer` (in `_resp_serializer.pony`): Serializes commands (`Array[ByteSeq] val`) to RESP2 wire format.

### Session Layer

- `Session` (actor in `session.pony`): Main entry point. Manages connection lifecycle and pub/sub via a state machine. Implements `lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver`. All state machine classes (`_SessionUnopened`, `_SessionConnected`, `_SessionReady`, `_SessionSubscribed`, `_SessionClosed`) are in `session.pony`, following the postgres pattern.
- `ConnectInfo` (in `connect_info.pony`): Connection configuration (host, port, optional password).
- `SessionStatusNotify` (in `session_status_notify.pony`): Lifecycle callback interface. All callbacks have default no-op implementations. Callbacks: `redis_session_connected`, `redis_session_connection_failed`, `redis_session_ready`, `redis_session_authentication_failed`, `redis_session_closed`.
- `ResultReceiver` (in `result_receiver.pony`): Command response callback interface. Callbacks: `redis_response`, `redis_command_failed`.
- `SubscriptionNotify` (in `subscription_notify.pony`): Pub/sub callback interface. All callbacks have default no-op implementations. Callbacks: `redis_subscribed`, `redis_unsubscribed`, `redis_message`, `redis_psubscribed`, `redis_punsubscribed`, `redis_pmessage`.
- `ClientError` (in `client_error.pony`): Client-side error trait with `SessionNotReady`, `SessionClosed`, and `SessionInSubscribedMode` primitives.
- `_ResponseHandler` (in `_response_handler.pony`): Loops `_RespParser` over a `buffered.Reader`, delivering parsed `RespValue`s to the current state. Shuts down on `RespMalformed`.
- `_IllegalState` / `_Unreachable` (in `_mort.pony`): Primitives for detecting impossible states.

### Trait Composition

- `_ClosedState`: Mixin for the terminal state — rejects or no-ops all operations.
- `_ConnectedState`: Mixin for states with a readbuf — handles `on_received` and `_ResponseHandler` dispatch.
- `_NotReadyForCommands`: Mixin that rejects `execute()` with `SessionNotReady`.
- `_NotSubscribed`: Mixin that no-ops `subscribe`, `unsubscribe`, `psubscribe`, `punsubscribe` for states where pub/sub is not applicable.

### State Machine

```
_SessionUnopened ──on_connected──► _SessionConnected (if password)
                 ──on_connected──► _SessionReady (if no password)

_SessionConnected ──AUTH OK──► _SessionReady
                  ──AUTH error──► _SessionClosed

_SessionReady ──subscribe/psubscribe──► _SessionSubscribed
              ──close/error──► _SessionClosed

_SessionSubscribed ──unsub count 0──► _SessionReady
                   ──close/error──► _SessionClosed
```

Commands are pipelined in `_SessionReady`: each `execute()` call sends the command immediately over the wire without waiting for prior responses. Responses are matched to receivers in FIFO order.

In `_SessionSubscribed`, any pipelined commands that were in-flight when SUBSCRIBE was sent are drained first (Redis guarantees in-order response delivery), then incoming responses are routed as pub/sub messages.

## Test Infrastructure

- Unit tests: `--exclude=integration/` — no external dependencies
- Integration tests: `--only=integration/` — require a running Redis server
- Test names prefixed with `integration/` for filtering
- `_RedisTestConfiguration` reads `REDIS_HOST` and `REDIS_PORT` from environment (defaults to `127.0.0.2`/`6379` on Linux for WSL2 compatibility)

### CI

Both `pr.yml` and `breakage-against-ponyc-latest.yml` use the `shared-docker-ci-standard-builder-with-libressl-4.2.0` image (for ssl support) and a `redis:7` service container with health checks. Integration tests receive `REDIS_HOST=redis` and `REDIS_PORT=6379` as environment variables. All make targets pass `ssl=libressl`.

## File Layout

- `redis/` — main package source
- `examples/` — example programs
