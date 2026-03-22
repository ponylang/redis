primitive ConnectionFailedDNS
  """
  Name resolution failed — the server hostname could not be resolved.
  """

primitive ConnectionFailedTCP
  """
  TCP connection failed — the server is not reachable.
  """

primitive ConnectionFailedSSL
  """
  The SSL/TLS handshake failed before the connection was established.
  """

primitive ConnectionFailedTimeout
  """
  The connection attempt timed out before completing.
  """

type ConnectionFailureReason is
  ( ConnectionFailedDNS
  | ConnectionFailedTCP
  | ConnectionFailedSSL
  | ConnectionFailedTimeout )
