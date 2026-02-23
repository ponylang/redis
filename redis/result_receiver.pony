interface tag ResultReceiver
  """
  Receives the result of a Redis command execution. Both callbacks must
  be implemented — unlike lifecycle events, command results always need
  to be handled.
  """
  be redis_response(session: Session, response: RespValue)
    """
    Called when the server responds to a command. The response is the
    raw RESP value — it may be any variant of `RespValue` including
    `RespError` for server-side errors (e.g., wrong number of arguments).
    """

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
    """
    Called when a command failed due to a client-side error. This covers
    both commands that could not be sent (e.g., session not ready or
    closed) and in-flight commands whose responses will never arrive
    (e.g., connection lost or protocol error). The original command and
    the specific `ClientError` are provided so the caller knows which
    command failed and why.
    """
