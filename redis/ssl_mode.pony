use "ssl/net"

type SSLMode is (SSLDisabled | SSLRequired)

primitive SSLDisabled
  """Plaintext TCP connection (default)."""

class val SSLRequired
  """
  SSL/TLS connection. Wraps an `SSLContext val` configured by the caller.
  Redis uses direct TLS (typically port 6380) rather than STARTTLS, so
  the SSL handshake happens during TCP connection establishment.
  """
  let ctx: SSLContext val

  new val create(ctx': SSLContext val) =>
    ctx = ctx'
