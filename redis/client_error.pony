trait val ClientError
  """
  A client-side error that prevented a command from being sent to the server.
  Each subtype represents a specific pre-condition failure.
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
  Error returned when a command is attempted on a session that has been
  closed. Includes sessions closed by the user, by the server, or due to
  connection or authentication failures.
  """
  fun message(): String => "Session is closed"
