trait val ClientError
  """
  A client-side error delivered via `redis_command_failed`. Covers two
  categories: pre-condition failures (the command was never sent) and
  in-flight losses (the command was sent but its response will never arrive
  because the connection was lost or the data stream became corrupt).
  """
  fun message(): String

primitive SessionNotReady is ClientError
  """
  Error returned when a command is attempted on a session that is not yet
  ready. This covers sessions that haven't connected, are in the process of
  connecting, or are authenticating.
  """
  fun message(): String => "Session is not ready for commands"

primitive SessionClosed is ClientError
  """
  Error returned when a command is attempted on a session that has already
  been closed, or when a user-initiated `close()` drains in-flight commands
  from the pending queue. Does not cover connection drops
  (`SessionConnectionLost`) or protocol errors (`SessionProtocolError`).
  """
  fun message(): String => "Session is closed"

primitive SessionConnectionLost is ClientError
  """
  Error returned when a command could not be completed because the
  connection to the Redis server was lost. This covers commands that
  could not be sent (the connection was already lost when `execute()`
  was called) and in-flight commands that were awaiting responses when
  the connection dropped.
  """
  fun message(): String => "Connection to Redis server was lost"

primitive SessionProtocolError is ClientError
  """
  Error returned when the server sent data that does not conform to the
  RESP protocol. The data stream is corrupt and cannot be resynchronized,
  so the connection is closed. In-flight commands receive this error via
  `redis_command_failed`.
  """
  fun message(): String => "Protocol error: received malformed data"

primitive SessionInSubscribedMode is ClientError
  """
  Error returned when `execute()` is called on a session that is in
  pub/sub subscribed mode. Commands cannot be sent while subscribed —
  unsubscribe from all channels and patterns first, or use a separate
  session for commands.
  """
  fun message(): String => "Session is in subscribed mode"
