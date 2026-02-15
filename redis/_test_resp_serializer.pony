use "buffered"
use "pony_check"
use "pony_test"

// ---------------------------------------------------------------------------
// Test helpers used by both parser and serializer tests
// ---------------------------------------------------------------------------

primitive _TestRespSerializer
  """
  Serialize any RespValue into RESP2 wire format bytes. Unlike
  _RespSerializer (which only serializes commands as arrays of bulk strings),
  this handles all RESP value types for roundtrip testing.

  RespNull serializes canonically as $-1\r\n.
  """
  fun apply(value: RespValue): Array[U8] val =>
    recover val
      let buf = Array[U8]
      _serialize(buf, value)
      buf
    end

  fun _serialize(buf: Array[U8] ref, value: RespValue) =>
    match value
    | let s: RespSimpleString =>
      buf.push('+')
      for byte in s.value.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let e: RespError =>
      buf.push('-')
      for byte in e.message.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let i: RespInteger =>
      buf.push(':')
      let int_s: String val = i.value.string()
      for byte in int_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let b: RespBulkString =>
      buf.push('$')
      let len_s: String val = b.value.size().string()
      for byte in len_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
      for byte in b.value.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let a: RespArray =>
      buf.push('*')
      let arr_s: String val = a.values.size().string()
      for byte in arr_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
      for elem in a.values.values() do
        _serialize(buf, elem)
      end
    | RespNull =>
      buf.push('$')
      buf.push('-')
      buf.push('1')
      buf.push('\r')
      buf.push('\n')
    end

primitive _RespValueEq
  """
  Structural equality comparison for RespValue. Used in tests where values
  are reconstructed through parse/serialize cycles.
  """
  fun apply(a: RespValue, b: RespValue): Bool =>
    match (a, b)
    | (let a': RespSimpleString, let b': RespSimpleString) =>
      a'.value == b'.value
    | (let a': RespError, let b': RespError) =>
      a'.message == b'.message
    | (let a': RespInteger, let b': RespInteger) =>
      a'.value == b'.value
    | (let a': RespBulkString, let b': RespBulkString) =>
      _byte_arrays_eq(a'.value, b'.value)
    | (let a': RespArray, let b': RespArray) =>
      if a'.values.size() != b'.values.size() then
        return false
      end
      try
        var i: USize = 0
        while i < a'.values.size() do
          if not apply(a'.values(i)?, b'.values(i)?) then
            return false
          end
          i = i + 1
        end
        true
      else
        false
      end
    | (RespNull, RespNull) => true
    else
      false
    end

  fun _byte_arrays_eq(a: Array[U8] val, b: Array[U8] val): Bool =>
    if a.size() != b.size() then return false end
    try
      var i: USize = 0
      while i < a.size() do
        if a(i)? != b(i)? then return false end
        i = i + 1
      end
      true
    else
      false
    end

primitive _RespGens
  """
  PonyCheck generators for RESP2 values. Used in property-based tests.
  """
  fun simple_string(): Generator[RespSimpleString] =>
    """
    Generate simple strings without CR or LF (as required by RESP2 spec).
    """
    Generators.ascii_printable(0, 50)
      .filter({(s) =>
        var ok = true
        for byte in s.values() do
          if (byte == '\r') or (byte == '\n') then
            ok = false
            break
          end
        end
        (s, ok)
      })
      .map[RespSimpleString]({(s) => RespSimpleString(s) })

  fun bulk_string(): Generator[RespBulkString] =>
    """
    Generate bulk strings with arbitrary byte content.
    """
    Generators.byte_string(Generators.u8(), 0, 100)
      .map[RespBulkString]({(s) =>
        RespBulkString(
          recover val
            let out = Array[U8](s.size())
            for b in s.values() do out.push(b) end
            out
          end)
      })

  fun integer(): Generator[RespInteger] =>
    Generators.i64().map[RespInteger]({(i) => RespInteger(i) })

  fun resp_error(): Generator[RespError] =>
    """
    Generate error messages without CR or LF, at least 1 character.
    """
    Generators.ascii_printable(1, 50)
      .filter({(s) =>
        var ok = true
        for byte in s.values() do
          if (byte == '\r') or (byte == '\n') then
            ok = false
            break
          end
        end
        (s, ok)
      })
      .map[RespError]({(s) => RespError(s) })

  fun null_value(): Generator[RespNull] =>
    Generators.unit[RespNull](RespNull)

  fun value(max_depth: USize = 2): Generator[RespValue] =>
    """
    Generate any RespValue. Arrays are depth-limited to prevent unbounded
    recursion.
    """
    if max_depth == 0 then
      _leaf_value()
    else
      Generators.frequency[RespValue]([
        (3, simple_string().map[RespValue]({(s) => s }))
        (3, bulk_string().map[RespValue]({(b) => b }))
        (3, integer().map[RespValue]({(i) => i }))
        (2, resp_error().map[RespValue]({(e) => e }))
        (1, null_value().map[RespValue]({(n) => n }))
        (2, array(max_depth - 1).map[RespValue]({(a) => a }))
      ])
    end

  fun array(max_depth: USize = 2): Generator[RespArray] =>
    """
    Generate arrays with 0-5 elements using depth-limited value generation.
    """
    let elem_gen = value(max_depth)
    Generators.usize(0, 5)
      .flat_map[RespArray]({(count)(elem_gen) =>
        if count == 0 then
          Generators.unit[RespArray](
            RespArray(recover val Array[RespValue] end))
        else
          Generators.iso_seq_of[RespValue, Array[RespValue] iso](
            elem_gen, count, count)
            .map[RespArray]({(arr) =>
              RespArray(consume arr)
            })
        end
      })

  fun _leaf_value(): Generator[RespValue] =>
    """
    Generate only non-recursive RespValue types.
    """
    Generators.frequency[RespValue]([
      (3, simple_string().map[RespValue]({(s) => s }))
      (3, bulk_string().map[RespValue]({(b) => b }))
      (3, integer().map[RespValue]({(i) => i }))
      (2, resp_error().map[RespValue]({(e) => e }))
      (1, null_value().map[RespValue]({(n) => n }))
    ])

  fun command(): Generator[Array[ByteSeq] val] =>
    """
    Generate arrays of ByteSeq suitable for _RespSerializer input.
    """
    Generators.iso_seq_of[String, Array[String] iso](
      Generators.ascii_printable(0, 50), 0, 5)
      .map[Array[ByteSeq] val]({(arr) =>
        let strings: Array[String] val = consume arr
        recover val
          let out = Array[ByteSeq](strings.size())
          for s in strings.values() do out.push(s) end
          out
        end
      })

// ---------------------------------------------------------------------------
// Serializer property-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRespSerializerCommandRoundtrip is Property1[Array[ByteSeq] val]
  """
  Verify that serialized commands parse back to a RespArray of RespBulkStrings
  matching the original input.
  """
  fun name(): String => "RespSerializer/CommandRoundtrip/Property"

  fun gen(): Generator[Array[ByteSeq] val] => _RespGens.command()

  fun property(command: Array[ByteSeq] val, h: PropertyHelper) ? =>
    let bytes = _RespSerializer(command)
    let buffer: Reader = Reader
    buffer.append(bytes)

    match _RespParser(buffer)
    | let arr: RespArray =>
      h.assert_eq[USize](command.size(), arr.values.size())
      var i: USize = 0
      while i < command.size() do
        match arr.values(i)?
        | let bs: RespBulkString =>
          let expected: Array[U8] val = match command(i)?
          | let s: String val =>
            recover val
              let a = Array[U8](s.size())
              for byte in s.values() do a.push(byte) end
              a
            end
          | let a: Array[U8] val => a
          end
          h.assert_true(
            _RespValueEq._byte_arrays_eq(expected, bs.value),
            "Element " + i.string() + " mismatch")
        else
          h.fail("Element " + i.string() + " is not a RespBulkString")
        end
        i = i + 1
      end
    | let m: RespMalformed =>
      h.fail("Serialized command was malformed: " + m.message)
    else
      h.fail("Serialized command did not parse to RespArray")
    end

class \nodoc\ iso _TestRespSerializerOutputIsValidResp is Property1[Array[ByteSeq] val]
  """
  Verify that _RespSerializer output always parses successfully.
  """
  fun name(): String => "RespSerializer/OutputIsValidResp/Property"

  fun gen(): Generator[Array[ByteSeq] val] => _RespGens.command()

  fun property(command: Array[ByteSeq] val, h: PropertyHelper) =>
    let bytes = _RespSerializer(command)
    let buffer: Reader = Reader
    buffer.append(bytes)
    match _RespParser(buffer)
    | None => h.fail("Serialized output parsed as incomplete")
    | let m: RespMalformed =>
      h.fail("Serialized output was malformed: " + m.message)
    end

// ---------------------------------------------------------------------------
// Serializer example-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRespSerializerSimpleCommand is UnitTest
  fun name(): String => "RespSerializer/SimpleCommand"

  fun apply(h: TestHelper) =>
    let command: Array[ByteSeq] val = recover val
      [as ByteSeq: "GET"; "key"]
    end
    let result = _RespSerializer(command)
    let expected: Array[U8] val = recover val
      [as U8:
        '*'; '2'; '\r'; '\n'
        '$'; '3'; '\r'; '\n'; 'G'; 'E'; 'T'; '\r'; '\n'
        '$'; '3'; '\r'; '\n'; 'k'; 'e'; 'y'; '\r'; '\n']
    end
    h.assert_array_eq[U8](expected, result)

class \nodoc\ iso _TestRespSerializerSingleElement is UnitTest
  fun name(): String => "RespSerializer/SingleElement"

  fun apply(h: TestHelper) =>
    let command: Array[ByteSeq] val = recover val
      [as ByteSeq: "PING"]
    end
    let result = _RespSerializer(command)
    let expected: Array[U8] val = recover val
      [as U8:
        '*'; '1'; '\r'; '\n'
        '$'; '4'; '\r'; '\n'; 'P'; 'I'; 'N'; 'G'; '\r'; '\n']
    end
    h.assert_array_eq[U8](expected, result)

class \nodoc\ iso _TestRespSerializerEmptyCommand is UnitTest
  fun name(): String => "RespSerializer/EmptyCommand"

  fun apply(h: TestHelper) =>
    let command: Array[ByteSeq] val = recover val
      Array[ByteSeq]
    end
    let result = _RespSerializer(command)
    let expected: Array[U8] val = recover val
      [as U8: '*'; '0'; '\r'; '\n']
    end
    h.assert_array_eq[U8](expected, result)

class \nodoc\ iso _TestRespSerializerBinaryData is UnitTest
  fun name(): String => "RespSerializer/BinaryData"

  fun apply(h: TestHelper) =>
    let binary: Array[U8] val = recover val
      [as U8: 0x00; 0xFF; '\r'; '\n'; 0x42]
    end
    let command: Array[ByteSeq] val = recover val
      [as ByteSeq: "SET"; "key"; binary]
    end
    let result = _RespSerializer(command)
    let expected: Array[U8] val = recover val
      [as U8:
        '*'; '3'; '\r'; '\n'
        '$'; '3'; '\r'; '\n'; 'S'; 'E'; 'T'; '\r'; '\n'
        '$'; '3'; '\r'; '\n'; 'k'; 'e'; 'y'; '\r'; '\n'
        '$'; '5'; '\r'; '\n'; 0x00; 0xFF; '\r'; '\n'; 0x42; '\r'; '\n']
    end
    h.assert_array_eq[U8](expected, result)
