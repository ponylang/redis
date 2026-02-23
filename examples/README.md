# Examples

Each subdirectory is a self-contained Pony program demonstrating a different part of the redis library.

## basic

Minimal example. Connects to Redis, executes `SET hello world`, prints the response, and closes the session. Shows how to create a `ConnectInfo`, implement `SessionStatusNotify` and `ResultReceiver` on a single actor, and match on `RespValue` variants. Start here if you're new to the library.

## pipeline

Command pipelining. Sends 3 SET commands followed by 3 GET commands without waiting for individual responses — all 6 commands are dispatched immediately in `redis_session_ready`. Responses arrive in order and are tracked with a step counter. Shows how pipelining eliminates round-trip latency for independent commands.

## pubsub

Pub/sub messaging using two sessions. One session subscribes to `demo-channel`, the other publishes a message to it. Demonstrates the `SubscriptionNotify` interface (`redis_subscribed`, `redis_message`, `redis_unsubscribed`) and the two-session pattern required because a subscribed session cannot execute regular commands.

## backpressure

TCP backpressure handling. Sends 1000 SET commands in a burst to exercise backpressure, implements `redis_session_throttled` and `redis_session_unthrottled` to observe when the TCP send buffer fills and drains. Shows that commands sent during backpressure are buffered internally and flushed automatically — no application-side retry logic is needed.

## ssl

SSL/TLS-encrypted connection. Same workflow as `basic` (connects and sends PING) but over TLS using `SSLRequired`. Demonstrates how to create an `SSLContext` with a CA certificate, wrap it in `SSLRequired`, and pass it to `ConnectInfo`. Requires a Redis server configured for TLS. Set `REDIS_HOST`, `REDIS_PORT`, and `REDIS_CA_PATH` environment variables to match your server.
