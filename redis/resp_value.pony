// Type alias can't have a docstring in Pony — see redis.pony for documentation.
type RespValue is
  ( RespSimpleString
  | RespBulkString
  | RespInteger
  | RespArray
  | RespError
  | RespNull
  | RespBoolean
  | RespDouble
  | RespBigNumber
  | RespBulkError
  | RespVerbatimString
  | RespMap
  | RespSet
  | RespPush )

class val RespSimpleString
  """
  A RESP simple string value. Simple strings cannot contain CR or LF
  characters. They are used for short, non-binary status responses like "OK".
  """
  let value: String

  new val create(value': String) =>
    value = value'

class val RespBulkString
  """
  A RESP bulk string value. Bulk strings can contain any binary data,
  including bytes that would be invalid in simple strings (CR, LF, null).
  The length is explicitly encoded in the wire format.
  """
  let value: Array[U8] val

  new val create(value': Array[U8] val) =>
    value = value'

class val RespInteger
  """
  A RESP integer value. Redis integers are signed 64-bit values.
  """
  let value: I64

  new val create(value': I64) =>
    value = value'

class val RespArray
  """
  A RESP array value. Arrays can contain any mix of RESP value types,
  including nested arrays.
  """
  let values: Array[RespValue] val

  new val create(values': Array[RespValue] val) =>
    values = values'

class val RespError
  """
  A RESP error value. Errors are similar to simple strings but indicate
  an error condition. The message typically starts with a type prefix like
  "ERR" or "WRONGTYPE".
  """
  let message: String

  new val create(message': String) =>
    message = message'

primitive RespNull
  """
  The RESP null value. In RESP2, represents null bulk strings (`$-1\r\n`)
  and null arrays (`*-1\r\n`). In RESP3, also represents the explicit null
  type (`_\r\n`) and null maps (`%-1\r\n`) and null sets (`~-1\r\n`).
  """

class val RespBoolean
  """
  A RESP3 boolean value. Wire format: `#t\r\n` (true) or `#f\r\n` (false).
  """
  let value: Bool

  new val create(value': Bool) =>
    value = value'

class val RespDouble
  """
  A RESP3 double-precision floating-point value. Wire format:
  `,<value>\r\n`. Supports standard decimal notation, scientific notation,
  and the special values `inf`, `-inf`, and `nan`.
  """
  let value: F64

  new val create(value': F64) =>
    value = value'

class val RespBigNumber
  """
  A RESP3 arbitrary-precision integer. Wire format: `(<digits>\r\n`.
  Stored as a string because the value may exceed the range of any
  fixed-width integer type.
  """
  let value: String

  new val create(value': String) =>
    value = value'

class val RespBulkError
  """
  A RESP3 bulk error. Like `RespError` but binary-safe — the message
  can contain any bytes. Wire format: `!<len>\r\n<message>\r\n`.
  """
  let message: Array[U8] val

  new val create(message': Array[U8] val) =>
    message = message'

class val RespVerbatimString
  """
  A RESP3 verbatim string. Carries a 3-character encoding hint (e.g.,
  `"txt"` for plain text, `"mkd"` for Markdown) followed by the data.
  Wire format: `=<len>\r\n<enc>:<data>\r\n` where `<enc>` is exactly
  3 characters and `<len>` includes the encoding prefix and colon.
  """
  let encoding: String
  let value: Array[U8] val

  new val create(encoding': String, value': Array[U8] val) =>
    encoding = encoding'
    value = value'

class val RespMap
  """
  A RESP3 map (dictionary). An ordered sequence of key-value pairs where
  both keys and values are arbitrary RESP values. Wire format:
  `%<count>\r\n<key><value>...` where `<count>` is the number of pairs.
  """
  let pairs: Array[(RespValue, RespValue)] val

  new val create(pairs': Array[(RespValue, RespValue)] val) =>
    pairs = pairs'

class val RespSet
  """
  A RESP3 set. An unordered collection of RESP values. Wire format:
  `~<count>\r\n<element>...`.
  """
  let values: Array[RespValue] val

  new val create(values': Array[RespValue] val) =>
    values = values'

class val RespPush
  """
  A RESP3 push message. Server-initiated out-of-band data, used for
  pub/sub messages and other server notifications. Wire format:
  `><count>\r\n<element>...`. The first element is typically a bulk
  string identifying the message type (e.g., "message", "subscribe").
  """
  let values: Array[RespValue] val

  new val create(values': Array[RespValue] val) =>
    values = values'

class val RespMalformed
  """
  Indicates that the parser encountered malformed RESP data. The message
  describes what was invalid. This is not part of `RespValue` — it represents
  a protocol violation, not a valid RESP value.
  """
  let message: String

  new val create(message': String) =>
    message = message'
