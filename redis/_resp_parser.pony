use "buffered"

primitive _RespParser
  """
  Parse a single RESP2 value from the buffer. Returns the parsed value if a
  complete message is available, None if the buffer contains an incomplete
  message, or raises an error if the buffer contains malformed data.

  The buffer is only modified when a complete value is successfully parsed.
  Incomplete data leaves the buffer unchanged. Malformed data leaves the
  buffer in an indeterminate state (the session should be closed anyway).
  """
  fun apply(buffer: Reader): (RespValue | None) ? =>
    match _complete_size(buffer, 0)?
    | let _: USize => _parse(buffer)?
    | None => None
    end

  fun _complete_size(buffer: Reader, offset: USize): (USize | None) ? =>
    """
    Non-destructive scan to determine if a complete RESP value starts at
    the given offset. Returns the total byte count of the complete value,
    None if incomplete, or raises an error if malformed.
    """
    if buffer.size() <= offset then
      return None
    end

    let type_byte = buffer.peek_u8(offset)?
    match type_byte
    | '+' => _line_size(buffer, offset)
    | '-' => _line_size(buffer, offset)
    | ':' => _line_size(buffer, offset)
    | '$' => _bulk_string_size(buffer, offset)?
    | '*' => _array_size(buffer, offset)?
    else
      error
    end

  fun _line_size(buffer: Reader, offset: USize): (USize | None) =>
    """
    Scan for \r\n starting after the type byte at offset. Returns total byte
    count from offset to end of \r\n (inclusive), or None if \r\n not found.
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

  fun _bulk_string_size(buffer: Reader, offset: USize): (USize | None) ? =>
    """
    Determine size of a bulk string at offset.
    Format: $<length>\r\n<data>\r\n  or  $-1\r\n for null.
    """
    match _line_size(buffer, offset)
    | let header_size: USize =>
      let len = _read_line_as_i64(buffer, offset + 1, (offset + header_size) - 2)?
      if len == -1 then
        return header_size
      end
      if len < 0 then
        error
      end
      let total = header_size + len.usize() + 2
      if buffer.size() >= (offset + total) then
        total
      else
        None
      end
    | None => None
    end

  fun _array_size(buffer: Reader, offset: USize): (USize | None) ? =>
    """
    Determine size of an array at offset.
    Format: *<count>\r\n<element>...<element>  or  *-1\r\n for null.
    """
    match _line_size(buffer, offset)
    | let header_size: USize =>
      let count = _read_line_as_i64(
        buffer, offset + 1, (offset + header_size) - 2)?
      if count == -1 then
        return header_size
      end
      if count < 0 then
        error
      end
      var total = header_size
      var i: I64 = 0
      while i < count do
        match _complete_size(buffer, offset + total)?
        | let elem_size: USize => total = total + elem_size
        | None => return None
        end
        i = i + 1
      end
      total
    | None => None
    end

  fun _read_line_as_i64(buffer: Reader, from: USize, to: USize)
    : I64 ?
  =>
    """
    Read bytes from buffer[from..to) via peek and parse as a decimal I64.
    Handles optional leading minus sign. Errors on empty range or non-digit
    characters.
    """
    if from >= to then error end

    var negative = false
    var start = from
    if buffer.peek_u8(start)? == '-' then
      negative = true
      start = start + 1
      if start >= to then error end
    end

    var result: I64 = 0
    var i = start
    while i < to do
      let b = buffer.peek_u8(i)?
      if (b < '0') or (b > '9') then error end
      result = (result * 10) + (b - '0').i64()
      i = i + 1
    end

    if negative then -result else result end

  fun _parse(buffer: Reader): RespValue ? =>
    """
    Destructive parse of a complete RESP value. Only called after
    _complete_size has confirmed the value is complete.

    This method uses Reader.line() which accepts bare \n as a line
    terminator, but RESP requires \r\n. This is safe because _complete_size
    validates \r\n explicitly before _parse runs — a future change to
    _complete_size that relaxes \r\n validation would break this guarantee.
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
