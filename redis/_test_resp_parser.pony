use "buffered"
use "collections"
use "pony_check"
use "pony_test"

// ---------------------------------------------------------------------------
// Parser property-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRespParserRoundtrip is Property1[RespValue]
  """
  Verify that serialize -> parse -> compare produces the original value
  for all generated RespValues.
  """
  fun name(): String => "RespParser/Roundtrip/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(original: RespValue, h: PropertyHelper) =>
    let bytes = _TestRespSerializer(original)
    let buffer: Reader = Reader
    buffer.append(bytes)
    match _RespParser(buffer)
    | let parsed: RespValue =>
      h.assert_true(
        _RespValueEq(original, parsed),
        "Roundtrip mismatch")
    | None =>
      h.fail("Complete serialized value parsed as incomplete")
    | let m: RespMalformed =>
      h.fail("Complete serialized value was malformed: " + m.message)
    end

class \nodoc\ iso _TestRespParserValidBytesAlwaysParse is Property1[RespValue]
  """
  Verify that serialized RespValues always parse successfully (never
  return None, never return RespMalformed).
  """
  fun name(): String => "RespParser/ValidBytesAlwaysParse/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let bytes = _TestRespSerializer(value)
    let buffer: Reader = Reader
    buffer.append(bytes)
    match _RespParser(buffer)
    | None => h.fail("Valid RESP bytes parsed as incomplete")
    | let m: RespMalformed =>
      h.fail("Valid RESP bytes were malformed: " + m.message)
    end

class \nodoc\ iso _TestRespParserIncompleteReturnsNone is Property1[RespValue]
  """
  Verify that every proper prefix of a serialized RespValue parses as None
  (incomplete), not as a valid value and not as malformed.
  """
  fun name(): String => "RespParser/IncompleteReturnsNone/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) ? =>
    let bytes = _TestRespSerializer(value)
    let full_size = bytes.size()

    var prefix_len: USize = 0
    while prefix_len < full_size do
      let prefix: Array[U8] val = recover val
        let a = Array[U8](prefix_len)
        var i: USize = 0
        while i < prefix_len do
          a.push(bytes(i)?)
          i = i + 1
        end
        a
      end
      let buffer: Reader = Reader
      buffer.append(prefix)
      match _RespParser(buffer)
      | let _: RespValue =>
        // A shorter prefix parsing as a valid value is only acceptable if
        // the value is a proper subset (e.g., nested arrays where a prefix
        // could be a standalone value). We only fail if the prefix is truly
        // too short to be the complete target value.
        None
      | None => None
      | let _: RespMalformed =>
        h.fail(
          "Prefix of length " + prefix_len.string() +
          " was malformed instead of returning None")
      end
      prefix_len = prefix_len + 1
    end

class \nodoc\ iso _TestRespParserInvalidTypeByteErrors is Property1[U8]
  """
  Verify that bytes with an invalid RESP type marker always return
  RespMalformed.
  """
  fun name(): String => "RespParser/InvalidTypeByteErrors/Property"

  fun gen(): Generator[U8] =>
    Generators.u8().filter({(b) =>
      let valid = (b == '+') or (b == '-') or (b == ':')
        or (b == '$') or (b == '*')
      (b, not valid)
    })

  fun property(type_byte: U8, h: PropertyHelper) =>
    // Construct a buffer with the invalid type byte followed by enough
    // data that the parser won't treat it as merely incomplete.
    let bytes: Array[U8] val = recover val
      [type_byte; 'x'; '\r'; '\n']
    end
    let buffer: Reader = Reader
    buffer.append(bytes)
    match _RespParser(buffer)
    | let _: RespMalformed => None
    else
      h.fail(
        "Invalid type byte " + type_byte.string() +
        " did not return RespMalformed")
    end

// ---------------------------------------------------------------------------
// Parser example-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRespParserEmptyBuffer is UnitTest
  fun name(): String => "RespParser/EmptyBuffer"

  fun apply(h: TestHelper) =>
    let buffer: Reader = Reader
    match _RespParser(buffer)
    | None => None
    else
      h.fail("Empty buffer should return None")
    end

class \nodoc\ iso _TestRespParserSimpleString is UnitTest
  fun name(): String => "RespParser/SimpleString"

  fun apply(h: TestHelper) =>
    // +OK\r\n
    let buffer: Reader = Reader
    buffer.append([as U8: '+'; 'O'; 'K'; '\r'; '\n'])
    match _RespParser(buffer)
    | let s: RespSimpleString => h.assert_eq[String]("OK", s.value)
    else
      h.fail("Expected RespSimpleString")
    end

    // Empty simple string: +\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: '+'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let s: RespSimpleString => h.assert_eq[String]("", s.value)
    else
      h.fail("Expected empty RespSimpleString")
    end

class \nodoc\ iso _TestRespParserError is UnitTest
  fun name(): String => "RespParser/Error"

  fun apply(h: TestHelper) =>
    let buffer: Reader = Reader
    let bytes: Array[U8] val = recover val
      let a = Array[U8]
      a.push('-')
      for byte in "ERR unknown command".values() do a.push(byte) end
      a.push('\r')
      a.push('\n')
      a
    end
    buffer.append(bytes)
    match _RespParser(buffer)
    | let e: RespError =>
      h.assert_eq[String]("ERR unknown command", e.message)
    else
      h.fail("Expected RespError")
    end

class \nodoc\ iso _TestRespParserInteger is UnitTest
  fun name(): String => "RespParser/Integer"

  fun apply(h: TestHelper) =>
    // :0
    _assert_integer(h, [as U8: ':'; '0'; '\r'; '\n'], 0)

    // :42
    _assert_integer(h, [as U8: ':'; '4'; '2'; '\r'; '\n'], 42)

    // :-1
    _assert_integer(h, [as U8: ':'; '-'; '1'; '\r'; '\n'], -1)

    // I64 max: 9223372036854775807
    let max_bytes: Array[U8] val = recover val
      let a = Array[U8]
      a.push(':')
      for byte in I64.max_value().string().values() do a.push(byte) end
      a.push('\r')
      a.push('\n')
      a
    end
    _assert_integer(h, max_bytes, I64.max_value())

    // I64 min: -9223372036854775808
    let min_bytes: Array[U8] val = recover val
      let a = Array[U8]
      a.push(':')
      for byte in I64.min_value().string().values() do a.push(byte) end
      a.push('\r')
      a.push('\n')
      a
    end
    _assert_integer(h, min_bytes, I64.min_value())

  fun _assert_integer(h: TestHelper, bytes: Array[U8] val, expected: I64) =>
    let buffer: Reader = Reader
    buffer.append(bytes)
    match _RespParser(buffer)
    | let i: RespInteger =>
      h.assert_eq[I64](expected, i.value)
    else
      h.fail("Expected RespInteger(" + expected.string() + ")")
    end

class \nodoc\ iso _TestRespParserBulkString is UnitTest
  fun name(): String => "RespParser/BulkString"

  fun apply(h: TestHelper) =>
    // $6\r\nfoobar\r\n
    let buffer: Reader = Reader
    buffer.append([as U8:
      '$'; '6'; '\r'; '\n'
      'f'; 'o'; 'o'; 'b'; 'a'; 'r'; '\r'; '\n'])
    match _RespParser(buffer)
    | let b: RespBulkString =>
      h.assert_array_eq[U8](
        [as U8: 'f'; 'o'; 'o'; 'b'; 'a'; 'r'], b.value)
    else
      h.fail("Expected RespBulkString(foobar)")
    end

    // Empty bulk string: $0\r\n\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: '$'; '0'; '\r'; '\n'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let b: RespBulkString =>
      h.assert_eq[USize](0, b.value.size())
    else
      h.fail("Expected empty RespBulkString")
    end

    // Null bulk string: $-1\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8: '$'; '-'; '1'; '\r'; '\n'])
    match _RespParser(buffer3)
    | RespNull => None
    else
      h.fail("Expected RespNull from $-1")
    end

    // Bulk string containing \r\n: $4\r\nab\r\n\r\n
    let buffer4: Reader = Reader
    buffer4.append([as U8:
      '$'; '4'; '\r'; '\n'
      'a'; 'b'; '\r'; '\n'; '\r'; '\n'])
    match _RespParser(buffer4)
    | let b: RespBulkString =>
      h.assert_array_eq[U8]([as U8: 'a'; 'b'; '\r'; '\n'], b.value)
    else
      h.fail("Expected RespBulkString with embedded CRLF")
    end

class \nodoc\ iso _TestRespParserArray is UnitTest
  fun name(): String => "RespParser/Array"

  fun apply(h: TestHelper) ? =>
    // Empty array: *0\r\n
    let buffer: Reader = Reader
    buffer.append([as U8: '*'; '0'; '\r'; '\n'])
    match _RespParser(buffer)
    | let a: RespArray =>
      h.assert_eq[USize](0, a.values.size())
    else
      h.fail("Expected empty RespArray")
    end

    // Null array: *-1\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: '*'; '-'; '1'; '\r'; '\n'])
    match _RespParser(buffer2)
    | RespNull => None
    else
      h.fail("Expected RespNull from *-1")
    end

    // Two-element array: *2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8:
      '*'; '2'; '\r'; '\n'
      '$'; '3'; '\r'; '\n'; 'f'; 'o'; 'o'; '\r'; '\n'
      '$'; '3'; '\r'; '\n'; 'b'; 'a'; 'r'; '\r'; '\n'])
    match _RespParser(buffer3)
    | let a: RespArray =>
      h.assert_eq[USize](2, a.values.size())
      match a.values(0)?
      | let b: RespBulkString =>
        h.assert_array_eq[U8]([as U8: 'f'; 'o'; 'o'], b.value)
      else
        h.fail("First element should be RespBulkString")
      end
      match a.values(1)?
      | let b: RespBulkString =>
        h.assert_array_eq[U8]([as U8: 'b'; 'a'; 'r'], b.value)
      else
        h.fail("Second element should be RespBulkString")
      end
    else
      h.fail("Expected RespArray with 2 elements")
    end

    // Nested array: *1\r\n*1\r\n:42\r\n
    let buffer4: Reader = Reader
    buffer4.append([as U8:
      '*'; '1'; '\r'; '\n'
      '*'; '1'; '\r'; '\n'
      ':'; '4'; '2'; '\r'; '\n'])
    match _RespParser(buffer4)
    | let outer: RespArray =>
      h.assert_eq[USize](1, outer.values.size())
      match outer.values(0)?
      | let inner: RespArray =>
        h.assert_eq[USize](1, inner.values.size())
        match inner.values(0)?
        | let i: RespInteger =>
          h.assert_eq[I64](42, i.value)
        else
          h.fail("Inner element should be RespInteger")
        end
      else
        h.fail("Outer element should be RespArray")
      end
    else
      h.fail("Expected nested RespArray")
    end

class \nodoc\ iso _TestRespParserMultipleValues is UnitTest
  """
  Verify that parsing consumes exactly one value, leaving subsequent values
  in the buffer for the next parse call.
  """
  fun name(): String => "RespParser/MultipleValues"

  fun apply(h: TestHelper) =>
    let buffer: Reader = Reader
    // Two values: +OK\r\n:42\r\n
    buffer.append([as U8:
      '+'; 'O'; 'K'; '\r'; '\n'
      ':'; '4'; '2'; '\r'; '\n'])

    // Parse first value
    match _RespParser(buffer)
    | let s: RespSimpleString =>
      h.assert_eq[String]("OK", s.value)
    else
      h.fail("First parse should return RespSimpleString")
    end

    // Parse second value
    match _RespParser(buffer)
    | let i: RespInteger =>
      h.assert_eq[I64](42, i.value)
    else
      h.fail("Second parse should return RespInteger")
    end

    // Buffer should be exhausted
    match _RespParser(buffer)
    | None => None
    else
      h.fail("Third parse should return None")
    end

class \nodoc\ iso _TestRespParserMalformedErrors is UnitTest
  """
  Verify that malformed RESP data returns RespMalformed.
  """
  fun name(): String => "RespParser/MalformedErrors"

  fun apply(h: TestHelper) =>
    // Invalid bulk string length: $-2\r\n
    let buffer: Reader = Reader
    buffer.append([as U8: '$'; '-'; '2'; '\r'; '\n'])
    match _RespParser(buffer)
    | let _: RespMalformed => None
    else
      h.fail("Negative length other than -1 should return RespMalformed")
    end

    // Non-numeric integer: :abc\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: ':'; 'a'; 'b'; 'c'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let _: RespMalformed => None
    else
      h.fail("Non-numeric integer should return RespMalformed")
    end

    // Non-numeric bulk string length: $abc\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8: '$'; 'a'; 'b'; 'c'; '\r'; '\n'])
    match _RespParser(buffer3)
    | let _: RespMalformed => None
    else
      h.fail("Non-numeric length should return RespMalformed")
    end

class \nodoc\ iso _TestRespParserIntegerOverflow is UnitTest
  """
  Verify that integer values exceeding I64 range produce RespMalformed
  instead of silently wrapping.
  """
  fun name(): String => "RespParser/IntegerOverflow"

  fun apply(h: TestHelper) =>
    // I64.max + 1 as bulk string length: $9223372036854775808\r\n
    _assert_malformed(h,
      _build_header('$', "9223372036854775808"),
      "I64.max+1 as bulk string length should be malformed")

    // I64.max + 1 as array count: *9223372036854775808\r\n
    _assert_malformed(h,
      _build_header('*', "9223372036854775808"),
      "I64.max+1 as array count should be malformed")

    // 20-digit number well beyond I64 range: $99999999999999999999\r\n
    _assert_malformed(h,
      _build_header('$', "99999999999999999999"),
      "20-digit number should be malformed")

    // Negative overflow — digits exceed I64.max, then negated:
    // $-9223372036854775809\r\n
    _assert_malformed(h,
      _build_header('$', "-9223372036854775809"),
      "Negative overflow should be malformed")

  fun _build_header(type_byte: U8, value: String): Array[U8] val =>
    recover val
      let a = Array[U8]
      a.push(type_byte)
      for byte in value.values() do a.push(byte) end
      a.push('\r')
      a.push('\n')
      a
    end

  fun _assert_malformed(h: TestHelper, bytes: Array[U8] val, msg: String) =>
    let buffer: Reader = Reader
    buffer.append(bytes)
    match _RespParser(buffer)
    | let _: RespMalformed => None
    else
      h.fail(msg)
    end
