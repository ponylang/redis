
## Fix send() return value checks in non-throttled code paths

Previously, when `execute()`, `subscribe()`, `psubscribe()`, `unsubscribe()`, or `punsubscribe()` sent a command while the session was not throttled, the return value from the underlying TCP send was ignored. If the connection had been lost, the command would be queued in the pending list but never actually sent over the wire, causing all subsequent command responses to be delivered to the wrong receivers.

Now, all non-throttled send paths check the result. If the connection is no longer writeable, the session enters throttled mode and buffers the command for retry. If the connection is lost, the session shuts down and delivers appropriate errors to all pending command receivers.

