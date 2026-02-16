interface tag SessionStatusNotify
  """
  Receives session lifecycle events: connection, authentication, and
  shutdown. All callbacks have default no-op implementations, so consumers
  only need to override the events they care about.
  """
  be redis_session_connected(session: Session) =>
    """
    Called when the TCP connection to the server is established. This is
    informational — the session is not yet ready for commands. Wait for
    `redis_session_ready` before sending commands.
    """
    None

  be redis_session_connection_failed(session: Session) =>
    """
    Called when the TCP connection to the server fails. The session is
    terminal after this callback.
    """
    None

  be redis_session_ready(session: Session) =>
    """
    Called when the session is ready to accept commands. Fires after
    successful AUTH when a password is configured, or immediately after
    TCP connect when no password is set. Also fires when the session
    exits pub/sub subscribed mode (subscription count reaches 0).
    """
    None

  be redis_session_authentication_failed(session: Session,
    message: String)
  =>
    """
    Called when the AUTH command returns an error. The session closes
    after this callback.
    """
    None

  be redis_session_closed(session: Session) =>
    """
    Called when the session has closed, whether by user request, server
    disconnect, or error.
    """
    None
