use "buffered"

primitive _RespParser
  """
  Parse a single RESP2 value from the buffer. Returns the parsed value if a
  complete message is available, None if the buffer contains an incomplete
  message, or RespMalformed if the buffer contains invalid data.

  The buffer is only modified when a complete value is successfully parsed.
  Incomplete data leaves the buffer unchanged. Malformed data leaves the
  buffer in an indeterminate state (the session should be closed anyway).
  """
  fun apply(buffer: Reader): (RespValue | None | RespMalformed) =>
    match _complete_size(buffer, 0)
    | let _: USize =>
      try
        _parse(buffer)?
      else
        RespMalformed("failed to parse complete RESP value")
      end
    | None => None
    | let m: RespMalformed => m
    end

  fun _complete_size(buffer: Reader, offset: USize)
    : (USize | None | RespMalformed)
  =>
    """
    Non-destructive scan to determine if a complete RESP value starts at
    the given offset. Returns the total byte count of the complete value,
    None if incomplete, or RespMalformed if the data is invalid.
    """
    if buffer.size() <= offset then
      return None
    end

    let type_byte = try buffer.peek_u8(offset)?
    else return RespMalformed("unexpected end of buffer") end

    match type_byte
    | '+' => _line_size(buffer, offset)
    | '-' => _line_size(buffer, offset)
    | ':' => _line_size(buffer, offset)
    | '$' => _bulk_string_size(buffer, offset)
    | '*' => _array_size(buffer, offset)
    else
      RespMalformed("unknown RESP type byte: " + type_byte.string())
    end

  fun _line_size(buffer: Reader, offset: USize): (USize | None) =>
    """
    Scan for \r\n starting after the type byte at offset. Returns total byte
    count from offset to end of \r\n (inclusive), or None if \r\n not found.

    This method requires a full \r\n sequence — bare \n is not accepted.
    _parse depends on this: it uses Reader.line() which accepts bare \n,
    but is only called after _complete_size (which delegates here) confirms
    the data has proper \r\n terminators.
    """
    var i = offset + 1
    let buf_size = buffer.size()

    while i < buf_size do
      try
        if buffer.peek_u8(i)? == '\r' then
          if (i + 1) < buf_size then
            if buffer.peek_u8(i + 1)? == '\n' then
              return (i + 2) - offset
            end
          else
            return None
          end
        end
      end
      i = i + 1
    end
    None

  fun _bulk_string_size(buffer: Reader, offset: USize)
    : (USize | None | RespMalformed)
  =>
    """
    Determine size of a bulk string at offset.
    Format: $<length>\r\n<data>\r\n  or  $-1\r\n for null.
    """
    match _line_size(buffer, offset)
    | let header_size: USize =>
      match _read_line_as_i64(buffer, offset + 1, (offset + header_size) - 2)
      | let len: I64 =>
        if len == -1 then
          return header_size
        end
        if len < 0 then
          return RespMalformed(
            "negative bulk string length: " + len.string())
        end
        let total = header_size + len.usize() + 2
        if buffer.size() >= (offset + total) then
          total
        else
          None
        end
      | let m: RespMalformed => m
      end
    | None => None
    end

  fun _array_size(buffer: Reader, offset: USize)
    : (USize | None | RespMalformed)
  =>
    """
    Determine size of an array at offset.
    Format: *<count>\r\n<element>...<element>  or  *-1\r\n for null.
    """
    match _line_size(buffer, offset)
    | let header_size: USize =>
      match _read_line_as_i64(
        buffer, offset + 1, (offset + header_size) - 2)
      | let count: I64 =>
        if count == -1 then
          return header_size
        end
        if count < 0 then
          return RespMalformed(
            "negative array count: " + count.string())
        end
        var total = header_size
        var i: I64 = 0
        while i < count do
          match _complete_size(buffer, offset + total)
          | let elem_size: USize => total = total + elem_size
          | None => return None
          | let m: RespMalformed => return m
          end
          i = i + 1
        end
        total
      | let m: RespMalformed => m
      end
    | None => None
    end

  fun _read_line_as_i64(buffer: Reader, from: USize, to: USize)
    : (I64 | RespMalformed)
  =>
    """
    Read bytes from buffer[from..to) via peek and parse as a decimal I64.
    Handles optional leading minus sign. Returns RespMalformed on empty
    range or non-digit characters.
    """
    if from >= to then return RespMalformed("empty integer value") end

    var negative = false
    var start = from
    let first = try buffer.peek_u8(start)?
    else return RespMalformed("unexpected end of buffer") end

    if first == '-' then
      negative = true
      start = start + 1
      if start >= to then
        return RespMalformed("integer has only a minus sign")
      end
    end

    var result: I64 = 0
    var i = start
    while i < to do
      let b = try buffer.peek_u8(i)?
      else return RespMalformed("unexpected end of buffer") end
      if (b < '0') or (b > '9') then
        return RespMalformed("non-digit byte in integer value")
      end
      result = (result * 10) + (b - '0').i64()
      i = i + 1
    end

    if negative then -result else result end

  fun _parse(buffer: Reader): RespValue ? =>
    """
    Destructive parse of a complete RESP value. Only called after
    _complete_size has confirmed the value is complete.

    This method uses Reader.line() which accepts bare \n as a line
    terminator, but RESP requires \r\n. See _line_size docstring for the
    coupling guarantee that makes this safe.
    """
    let type_byte = buffer.u8()?
    match type_byte
    | '+' =>
      let line = buffer.line()?
      RespSimpleString(consume line)
    | '-' =>
      let line = buffer.line()?
      RespError(consume line)
    | ':' =>
      let line = buffer.line()?
      RespInteger((consume line).i64()?)
    | '$' =>
      let line = buffer.line()?
      let len = (consume line).i64()?
      if len == -1 then
        RespNull
      else
        let data = buffer.block(len.usize())?
        buffer.skip(2)?
        RespBulkString(consume data)
      end
    | '*' =>
      let line = buffer.line()?
      let count = (consume line).i64()?
      if count == -1 then
        RespNull
      else
        let arr: Array[RespValue] iso = recover iso
          Array[RespValue](count.usize())
        end
        var i: I64 = 0
        while i < count do
          arr.push(_parse(buffer)?)
          i = i + 1
        end
        RespArray(consume arr)
      end
    else
      error
    end
