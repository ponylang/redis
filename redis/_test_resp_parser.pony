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
        or (b == '_') or (b == '#') or (b == ',') or (b == '(')
        or (b == '!') or (b == '=') or (b == '%') or (b == '~')
        or (b == '>')
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

    // I64.max as bulk string length should be accepted by _read_line_as_i64
    // (returns None because the buffer lacks the data bytes, not RespMalformed)
    let max_buf: Reader = Reader
    max_buf.append(_build_header('$', I64.max_value().string()))
    match _RespParser(max_buf)
    | None => None
    | let m: RespMalformed =>
      h.fail("I64.max as bulk string length should not be malformed: "
        + m.message)
    | let _: RespValue =>
      h.fail("I64.max as bulk string length should be incomplete, not a value")
    end

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

// ---------------------------------------------------------------------------
// RESP3 parser example-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRespParserResp3Null is UnitTest
  fun name(): String => "RespParser/Resp3Null"

  fun apply(h: TestHelper) =>
    let buffer: Reader = Reader
    buffer.append([as U8: '_'; '\r'; '\n'])
    match _RespParser(buffer)
    | RespNull => None
    else
      h.fail("Expected RespNull from _\\r\\n")
    end

class \nodoc\ iso _TestRespParserBoolean is UnitTest
  fun name(): String => "RespParser/Boolean"

  fun apply(h: TestHelper) =>
    // #t\r\n
    let buffer: Reader = Reader
    buffer.append([as U8: '#'; 't'; '\r'; '\n'])
    match _RespParser(buffer)
    | let b: RespBoolean => h.assert_true(b.value, "Expected true")
    else
      h.fail("Expected RespBoolean(true)")
    end

    // #f\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: '#'; 'f'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let b: RespBoolean => h.assert_false(b.value, "Expected false")
    else
      h.fail("Expected RespBoolean(false)")
    end

    // Invalid: #x\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8: '#'; 'x'; '\r'; '\n'])
    match _RespParser(buffer3)
    | let _: RespMalformed => None
    else
      h.fail("Expected RespMalformed for #x")
    end

    // Invalid: #tf\r\n (too long)
    let buffer4: Reader = Reader
    buffer4.append([as U8: '#'; 't'; 'f'; '\r'; '\n'])
    match _RespParser(buffer4)
    | let _: RespMalformed => None
    else
      h.fail("Expected RespMalformed for #tf")
    end

class \nodoc\ iso _TestRespParserDouble is UnitTest
  fun name(): String => "RespParser/Double"

  fun apply(h: TestHelper) =>
    // ,3.14\r\n
    _assert_double(h, [as U8: ','; '3'; '.'; '1'; '4'; '\r'; '\n'], 3.14)

    // ,-1.5\r\n
    _assert_double(h,
      [as U8: ','; '-'; '1'; '.'; '5'; '\r'; '\n'], -1.5)

    // ,0\r\n
    _assert_double(h, [as U8: ','; '0'; '\r'; '\n'], 0.0)

    // ,inf\r\n
    let buffer_inf: Reader = Reader
    buffer_inf.append([as U8: ','; 'i'; 'n'; 'f'; '\r'; '\n'])
    match _RespParser(buffer_inf)
    | let d: RespDouble =>
      h.assert_true((d.value == F64.max_value().mul(2)),
        "Expected positive infinity")
    else
      h.fail("Expected RespDouble(inf)")
    end

    // ,-inf\r\n
    let buffer_ninf: Reader = Reader
    buffer_ninf.append(
      [as U8: ','; '-'; 'i'; 'n'; 'f'; '\r'; '\n'])
    match _RespParser(buffer_ninf)
    | let d: RespDouble =>
      h.assert_true((d.value == F64.min_value().mul(2)),
        "Expected negative infinity")
    else
      h.fail("Expected RespDouble(-inf)")
    end

    // ,nan\r\n
    let buffer_nan: Reader = Reader
    buffer_nan.append([as U8: ','; 'n'; 'a'; 'n'; '\r'; '\n'])
    match _RespParser(buffer_nan)
    | let d: RespDouble =>
      h.assert_true(d.value.nan(), "Expected NaN")
    else
      h.fail("Expected RespDouble(nan)")
    end

  fun _assert_double(h: TestHelper, bytes: Array[U8] val,
    expected: F64)
  =>
    let buffer: Reader = Reader
    buffer.append(bytes)
    match _RespParser(buffer)
    | let d: RespDouble =>
      h.assert_true(
        (d.value - expected).abs() < 1e-10,
        "Expected " + expected.string() + ", got " + d.value.string())
    else
      h.fail("Expected RespDouble(" + expected.string() + ")")
    end

class \nodoc\ iso _TestRespParserBigNumber is UnitTest
  fun name(): String => "RespParser/BigNumber"

  fun apply(h: TestHelper) =>
    // (12345\r\n
    let buffer: Reader = Reader
    buffer.append(
      [as U8: '('; '1'; '2'; '3'; '4'; '5'; '\r'; '\n'])
    match _RespParser(buffer)
    | let bn: RespBigNumber =>
      h.assert_eq[String]("12345", bn.value)
    else
      h.fail("Expected RespBigNumber(12345)")
    end

    // Negative: (-99\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: '('; '-'; '9'; '9'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let bn: RespBigNumber =>
      h.assert_eq[String]("-99", bn.value)
    else
      h.fail("Expected RespBigNumber(-99)")
    end

class \nodoc\ iso _TestRespParserBulkError is UnitTest
  fun name(): String => "RespParser/BulkError"

  fun apply(h: TestHelper) =>
    // !11\r\nERR unknown\r\n
    let buffer: Reader = Reader
    buffer.append([as U8:
      '!'; '1'; '1'; '\r'; '\n'
      'E'; 'R'; 'R'; ' '; 'u'; 'n'; 'k'; 'n'; 'o'; 'w'; 'n'
      '\r'; '\n'])
    match _RespParser(buffer)
    | let be': RespBulkError =>
      h.assert_array_eq[U8](
        [as U8: 'E'; 'R'; 'R'; ' '; 'u'; 'n'; 'k'; 'n'; 'o'; 'w'; 'n'],
        be'.message)
    else
      h.fail("Expected RespBulkError")
    end

    // Empty: !0\r\n\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: '!'; '0'; '\r'; '\n'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let be': RespBulkError =>
      h.assert_eq[USize](0, be'.message.size())
    else
      h.fail("Expected empty RespBulkError")
    end

    // Null bulk error is malformed: !-1\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8: '!'; '-'; '1'; '\r'; '\n'])
    match _RespParser(buffer3)
    | let _: RespMalformed => None
    else
      h.fail("Expected RespMalformed for null bulk error")
    end

class \nodoc\ iso _TestRespParserVerbatimString is UnitTest
  fun name(): String => "RespParser/VerbatimString"

  fun apply(h: TestHelper) =>
    // =10\r\ntxt:hello!\r\n
    let buffer: Reader = Reader
    buffer.append([as U8:
      '='; '1'; '0'; '\r'; '\n'
      't'; 'x'; 't'; ':'; 'h'; 'e'; 'l'; 'l'; 'o'; '!'
      '\r'; '\n'])
    match _RespParser(buffer)
    | let vs: RespVerbatimString =>
      h.assert_eq[String]("txt", vs.encoding)
      h.assert_array_eq[U8](
        [as U8: 'h'; 'e'; 'l'; 'l'; 'o'; '!'], vs.value)
    else
      h.fail("Expected RespVerbatimString")
    end

    // Minimum valid: =4\r\ntxt:\r\n (empty data)
    let buffer2: Reader = Reader
    buffer2.append([as U8:
      '='; '4'; '\r'; '\n'
      't'; 'x'; 't'; ':'
      '\r'; '\n'])
    match _RespParser(buffer2)
    | let vs: RespVerbatimString =>
      h.assert_eq[String]("txt", vs.encoding)
      h.assert_eq[USize](0, vs.value.size())
    else
      h.fail("Expected empty RespVerbatimString")
    end

    // Too short (missing colon): =3\r\ntxt\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8:
      '='; '3'; '\r'; '\n'
      't'; 'x'; 't'
      '\r'; '\n'])
    match _RespParser(buffer3)
    | let _: RespMalformed => None
    else
      h.fail("Expected RespMalformed for verbatim string without colon")
    end

class \nodoc\ iso _TestRespParserMap is UnitTest
  fun name(): String => "RespParser/Map"

  fun apply(h: TestHelper) ? =>
    // Empty map: %0\r\n
    let buffer: Reader = Reader
    buffer.append([as U8: '%'; '0'; '\r'; '\n'])
    match _RespParser(buffer)
    | let m: RespMap =>
      h.assert_eq[USize](0, m.pairs.size())
    else
      h.fail("Expected empty RespMap")
    end

    // Single pair: %1\r\n+key\r\n:42\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8:
      '%'; '1'; '\r'; '\n'
      '+'; 'k'; 'e'; 'y'; '\r'; '\n'
      ':'; '4'; '2'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let m: RespMap =>
      h.assert_eq[USize](1, m.pairs.size())
      (let k, let v) = m.pairs(0)?
      match k
      | let s: RespSimpleString =>
        h.assert_eq[String]("key", s.value)
      else
        h.fail("Map key should be RespSimpleString")
      end
      match v
      | let i: RespInteger =>
        h.assert_eq[I64](42, i.value)
      else
        h.fail("Map value should be RespInteger")
      end
    else
      h.fail("Expected RespMap with 1 pair")
    end

    // Null map: %-1\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8: '%'; '-'; '1'; '\r'; '\n'])
    match _RespParser(buffer3)
    | RespNull => None
    else
      h.fail("Expected RespNull from %-1")
    end

class \nodoc\ iso _TestRespParserSet is UnitTest
  fun name(): String => "RespParser/Set"

  fun apply(h: TestHelper) ? =>
    // Empty set: ~0\r\n
    let buffer: Reader = Reader
    buffer.append([as U8: '~'; '0'; '\r'; '\n'])
    match _RespParser(buffer)
    | let s: RespSet =>
      h.assert_eq[USize](0, s.values.size())
    else
      h.fail("Expected empty RespSet")
    end

    // Two elements: ~2\r\n:1\r\n:2\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8:
      '~'; '2'; '\r'; '\n'
      ':'; '1'; '\r'; '\n'
      ':'; '2'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let s: RespSet =>
      h.assert_eq[USize](2, s.values.size())
      match s.values(0)?
      | let i: RespInteger => h.assert_eq[I64](1, i.value)
      else h.fail("Set element 0 should be RespInteger")
      end
      match s.values(1)?
      | let i: RespInteger => h.assert_eq[I64](2, i.value)
      else h.fail("Set element 1 should be RespInteger")
      end
    else
      h.fail("Expected RespSet with 2 elements")
    end

    // Null set: ~-1\r\n
    let buffer3: Reader = Reader
    buffer3.append([as U8: '~'; '-'; '1'; '\r'; '\n'])
    match _RespParser(buffer3)
    | RespNull => None
    else
      h.fail("Expected RespNull from ~-1")
    end

class \nodoc\ iso _TestRespParserPush is UnitTest
  fun name(): String => "RespParser/Push"

  fun apply(h: TestHelper) ? =>
    // >2\r\n$7\r\nmessage\r\n$5\r\nhello\r\n
    let buffer: Reader = Reader
    buffer.append([as U8:
      '>'; '2'; '\r'; '\n'
      '$'; '7'; '\r'; '\n'
      'm'; 'e'; 's'; 's'; 'a'; 'g'; 'e'; '\r'; '\n'
      '$'; '5'; '\r'; '\n'
      'h'; 'e'; 'l'; 'l'; 'o'; '\r'; '\n'])
    match _RespParser(buffer)
    | let p: RespPush =>
      h.assert_eq[USize](2, p.values.size())
      match p.values(0)?
      | let b: RespBulkString =>
        h.assert_array_eq[U8](
          [as U8: 'm'; 'e'; 's'; 's'; 'a'; 'g'; 'e'], b.value)
      else
        h.fail("Push element 0 should be RespBulkString")
      end
    else
      h.fail("Expected RespPush")
    end

    // Null push is malformed: >-1\r\n
    let buffer2: Reader = Reader
    buffer2.append([as U8: '>'; '-'; '1'; '\r'; '\n'])
    match _RespParser(buffer2)
    | let _: RespMalformed => None
    else
      h.fail("Expected RespMalformed for null push")
    end
