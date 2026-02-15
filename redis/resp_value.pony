type RespValue is
  ( RespSimpleString
  | RespBulkString
  | RespInteger
  | RespArray
  | RespError
  | RespNull )

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
  The RESP null value. Represents both null bulk strings (`$-1\r\n`) and
  null arrays (`*-1\r\n`).
  """
