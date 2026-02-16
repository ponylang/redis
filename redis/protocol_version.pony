// Type alias can't have a docstring in Pony — see redis.pony for documentation.
type ProtocolVersion is (Resp2 | Resp3)

primitive Resp2
  """RESP2 protocol (default). Compatible with all Redis versions."""

primitive Resp3
  """
  RESP3 protocol. Requires Redis 6.0+. Enables richer response types
  (maps, sets, booleans, doubles) and server-initiated push messages.
  Falls back to RESP2 if the server does not support HELLO.
  """
