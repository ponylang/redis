use lori = "lori"

type SSLMode is (SSLDisabled | SSLRequired)

primitive SSLDisabled
  """
  Plaintext TCP connection (default).
  """

class val SSLRequired
  """
  SSL/TLS connection. Wraps an `lori.SSLContext val` configured by the caller.
  Redis uses direct TLS (typically port 6380) rather than STARTTLS, so
  the SSL handshake happens during TCP connection establishment.
  """
  let ctx: lori.SSLContext val

  new val create(ctx': lori.SSLContext val) =>
    ctx = ctx'
