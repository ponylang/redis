primitive RespConvert
  """
  Total functions for extracting typed values from `RespValue` responses.

  Each extractor returns a three-way result:
  * The extracted value when the input matches the expected type(s)
  * `RespNull` when the input is `RespNull`
  * `None` when the input is a non-matching type

  Exceptions: `as_error` returns `(String | None)` (no null case — null is
  not an error), and `is_ok` returns `Bool`.
  """

  fun as_string(value: RespValue): (String | RespNull | None) =>
    """
    Extract a string value. Matches `RespSimpleString` (returns its value),
    `RespBulkString` (decodes bytes to string), and `RespVerbatimString`
    (decodes data bytes, discarding the encoding hint).
    """
    match value
    | let s: RespSimpleString => s.value
    | let b: RespBulkString => String.from_array(b.value)
    | let v: RespVerbatimString => String.from_array(v.value)
    | RespNull => RespNull
    else
      None
    end

  fun as_bytes(value: RespValue): (Array[U8] val | RespNull | None) =>
    """
    Extract raw bytes from a `RespBulkString` or `RespVerbatimString`.
    """
    match value
    | let b: RespBulkString => b.value
    | let v: RespVerbatimString => v.value
    | RespNull => RespNull
    else
      None
    end

  fun as_integer(value: RespValue): (I64 | RespNull | None) =>
    """
    Extract an integer value from a `RespInteger`.
    """
    match value
    | let i: RespInteger => i.value
    | RespNull => RespNull
    else
      None
    end

  fun as_bool(value: RespValue): (Bool | RespNull | None) =>
    """
    Extract a boolean value from a `RespBoolean`.
    """
    match value
    | let b: RespBoolean => b.value
    | RespNull => RespNull
    else
      None
    end

  fun as_array(value: RespValue): (Array[RespValue] val | RespNull | None) =>
    """
    Extract the elements array from a `RespArray`.
    """
    match value
    | let a: RespArray => a.values
    | RespNull => RespNull
    else
      None
    end

  fun as_double(value: RespValue): (F64 | RespNull | None) =>
    """
    Extract a floating-point value from a `RespDouble`.
    """
    match value
    | let d: RespDouble => d.value
    | RespNull => RespNull
    else
      None
    end

  fun as_big_number(value: RespValue): (String | RespNull | None) =>
    """
    Extract an arbitrary-precision integer string from a `RespBigNumber`.
    """
    match value
    | let b: RespBigNumber => b.value
    | RespNull => RespNull
    else
      None
    end

  fun as_map(value: RespValue)
    : (Array[(RespValue, RespValue)] val | RespNull | None)
  =>
    """
    Extract the key-value pairs from a `RespMap`.
    """
    match value
    | let m: RespMap => m.pairs
    | RespNull => RespNull
    else
      None
    end

  fun as_set(value: RespValue): (Array[RespValue] val | RespNull | None) =>
    """
    Extract the elements array from a `RespSet`.
    """
    match value
    | let s: RespSet => s.values
    | RespNull => RespNull
    else
      None
    end

  fun as_error(value: RespValue): (String | None) =>
    """
    Extract an error message. Matches `RespError` (returns its message
    string) and `RespBulkError` (decodes bytes to string).
    """
    match value
    | let e: RespError => e.message
    | let be': RespBulkError => String.from_array(be'.message)
    else
      None
    end

  fun is_ok(value: RespValue): Bool =>
    """
    Check whether the response is the "OK" simple string that Redis returns
    for successful commands like SET, RENAME, and FLUSHDB.
    """
    match value
    | let s: RespSimpleString => s.value == "OK"
    else
      false
    end
