use "buffered"
use "pony_check"
use "pony_test"

// ---------------------------------------------------------------------------
// Test helpers used by both parser and serializer tests
// ---------------------------------------------------------------------------

primitive _TestRespSerializer
  """
  Serialize any RespValue into RESP2/RESP3 wire format bytes. Unlike
  _RespSerializer (which only serializes commands as arrays of bulk strings),
  this handles all RESP value types for roundtrip testing.

  RespNull serializes canonically as _\r\n.
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
      buf.push('_')
      buf.push('\r')
      buf.push('\n')
    | let b: RespBoolean =>
      buf.push('#')
      buf.push(if b.value then 't' else 'f' end)
      buf.push('\r')
      buf.push('\n')
    | let d: RespDouble =>
      buf.push(',')
      let d_s: String val = d.value.string()
      for byte in d_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let bn: RespBigNumber =>
      buf.push('(')
      for byte in bn.value.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let be': RespBulkError =>
      buf.push('!')
      let len_s: String val = be'.message.size().string()
      for byte in len_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
      for byte in be'.message.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let vs: RespVerbatimString =>
      let total = vs.encoding.size() + 1 + vs.value.size()
      buf.push('=')
      let len_s: String val = total.string()
      for byte in len_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
      for byte in vs.encoding.values() do buf.push(byte) end
      buf.push(':')
      for byte in vs.value.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
    | let m: RespMap =>
      buf.push('%')
      let map_s: String val = m.pairs.size().string()
      for byte in map_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
      for (k, v) in m.pairs.values() do
        _serialize(buf, k)
        _serialize(buf, v)
      end
    | let set: RespSet =>
      buf.push('~')
      let set_s: String val = set.values.size().string()
      for byte in set_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
      for elem in set.values.values() do
        _serialize(buf, elem)
      end
    | let p: RespPush =>
      buf.push('>')
      let push_s: String val = p.values.size().string()
      for byte in push_s.values() do buf.push(byte) end
      buf.push('\r')
      buf.push('\n')
      for elem in p.values.values() do
        _serialize(buf, elem)
      end
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
    | (let a': RespBoolean, let b': RespBoolean) =>
      a'.value == b'.value
    | (let a': RespDouble, let b': RespDouble) =>
      a'.value == b'.value
    | (let a': RespBigNumber, let b': RespBigNumber) =>
      a'.value == b'.value
    | (let a': RespBulkError, let b': RespBulkError) =>
      _byte_arrays_eq(a'.message, b'.message)
    | (let a': RespVerbatimString, let b': RespVerbatimString) =>
      (a'.encoding == b'.encoding) and _byte_arrays_eq(a'.value, b'.value)
    | (let a': RespMap, let b': RespMap) =>
      if a'.pairs.size() != b'.pairs.size() then
        return false
      end
      try
        var i: USize = 0
        while i < a'.pairs.size() do
          (let ak, let av) = a'.pairs(i)?
          (let bk, let bv) = b'.pairs(i)?
          if not apply(ak, bk) then return false end
          if not apply(av, bv) then return false end
          i = i + 1
        end
        true
      else
        false
      end
    | (let a': RespSet, let b': RespSet) =>
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
    | (let a': RespPush, let b': RespPush) =>
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
  PonyCheck generators for RESP2/RESP3 values. Used in property-based tests.
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

  fun boolean(): Generator[RespBoolean] =>
    Generators.bool().map[RespBoolean]({(b) => RespBoolean(b) })

  fun double(): Generator[RespDouble] =>
    """
    Generate doubles from integer values. F64.string() uses %g format which
    doesn't preserve enough precision for arbitrary floats to roundtrip
    through string serialization. Integer-valued doubles roundtrip exactly.
    """
    Generators.i64(-1_000_000, 1_000_000)
      .map[RespDouble]({(i) => RespDouble(i.f64()) })

  fun big_number(): Generator[RespBigNumber] =>
    """
    Generate big number strings from I64 values.
    """
    Generators.i64()
      .map[RespBigNumber]({(i) => RespBigNumber(i.string()) })

  fun bulk_error(): Generator[RespBulkError] =>
    Generators.byte_string(Generators.u8(), 0, 100)
      .map[RespBulkError]({(s) =>
        RespBulkError(
          recover val
            let out = Array[U8](s.size())
            for b in s.values() do out.push(b) end
            out
          end)
      })

  fun verbatim_string(): Generator[RespVerbatimString] =>
    """
    Generate verbatim strings with a 3-character encoding and arbitrary data.
    """
    Generators.byte_string(Generators.u8(), 0, 80)
      .map[RespVerbatimString]({(s) =>
        RespVerbatimString("txt",
          recover val
            let out = Array[U8](s.size())
            for b in s.values() do out.push(b) end
            out
          end)
      })

  fun resp_map(max_depth: USize = 2): Generator[RespMap] =>
    """
    Generate maps with 0-3 key-value pairs using depth-limited values.
    Uses twice the number of elements and pairs them up.
    """
    let elem_gen = value(max_depth)
    Generators.usize(0, 3)
      .flat_map[RespMap]({(count)(elem_gen) =>
        if count == 0 then
          Generators.unit[RespMap](
            RespMap(recover val Array[(RespValue, RespValue)] end))
        else
          // Generate count*2 elements, pair them up as key-value pairs.
          Generators.iso_seq_of[RespValue, Array[RespValue] iso](
            elem_gen, count * 2, count * 2)
            .map[RespMap]({(elems) =>
              let arr: Array[RespValue] val = consume elems
              let pairs = recover val
                let p = Array[(RespValue, RespValue)](arr.size() / 2)
                try
                  var i: USize = 0
                  while i < arr.size() do
                    p.push((arr(i)?, arr(i + 1)?))
                    i = i + 2
                  end
                end
                p
              end
              RespMap(pairs)
            })
        end
      })

  fun resp_set(max_depth: USize = 2): Generator[RespSet] =>
    """
    Generate sets with 0-5 elements using depth-limited value generation.
    """
    let elem_gen = value(max_depth)
    Generators.usize(0, 5)
      .flat_map[RespSet]({(count)(elem_gen) =>
        if count == 0 then
          Generators.unit[RespSet](
            RespSet(recover val Array[RespValue] end))
        else
          Generators.iso_seq_of[RespValue, Array[RespValue] iso](
            elem_gen, count, count)
            .map[RespSet]({(arr) =>
              RespSet(consume arr)
            })
        end
      })

  fun push(max_depth: USize = 2): Generator[RespPush] =>
    """
    Generate push messages with 0-4 elements using depth-limited values.
    """
    let elem_gen = value(max_depth)
    Generators.usize(0, 4)
      .flat_map[RespPush]({(count)(elem_gen) =>
        if count == 0 then
          Generators.unit[RespPush](
            RespPush(recover val Array[RespValue] end))
        else
          Generators.iso_seq_of[RespValue, Array[RespValue] iso](
            elem_gen, count, count)
            .map[RespPush]({(arr) =>
              RespPush(consume arr)
            })
        end
      })

  fun value(max_depth: USize = 2): Generator[RespValue] =>
    """
    Generate any RespValue. Recursive types (arrays, maps, sets, push) are
    depth-limited to prevent unbounded recursion.
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
        (2, boolean().map[RespValue]({(b) => b }))
        (2, double().map[RespValue]({(d) => d }))
        (1, big_number().map[RespValue]({(b) => b }))
        (1, bulk_error().map[RespValue]({(b) => b }))
        (1, verbatim_string().map[RespValue]({(v) => v }))
        (2, resp_map(max_depth - 1).map[RespValue]({(m) => m }))
        (2, resp_set(max_depth - 1).map[RespValue]({(s) => s }))
        (1, push(max_depth - 1).map[RespValue]({(p) => p }))
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
      (2, boolean().map[RespValue]({(b) => b }))
      (2, double().map[RespValue]({(d) => d }))
      (1, big_number().map[RespValue]({(b) => b }))
      (1, bulk_error().map[RespValue]({(b) => b }))
      (1, verbatim_string().map[RespValue]({(v) => v }))
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
