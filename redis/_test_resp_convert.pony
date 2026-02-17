use "pony_check"
use "pony_test"

// ---------------------------------------------------------------------------
// RespConvert property-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRespConvertAsString is Property1[RespValue]
  fun name(): String => "RespConvert/as_string/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_string(value)
    match value
    | let s: RespSimpleString =>
      match result
      | let r: String => h.assert_eq[String](s.value, r)
      else h.fail("Expected String for RespSimpleString")
      end
    | let b: RespBulkString =>
      match result
      | let r: String =>
        h.assert_eq[String](String.from_array(b.value), r)
      else h.fail("Expected String for RespBulkString")
      end
    | let v: RespVerbatimString =>
      match result
      | let r: String =>
        h.assert_eq[String](String.from_array(v.value), r)
      else h.fail("Expected String for RespVerbatimString")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsBytes is Property1[RespValue]
  fun name(): String => "RespConvert/as_bytes/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_bytes(value)
    match value
    | let b: RespBulkString =>
      match result
      | let bytes: Array[U8] val =>
        h.assert_true(bytes is b.value)
      else h.fail("Expected Array[U8] for RespBulkString")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsInteger is Property1[RespValue]
  fun name(): String => "RespConvert/as_integer/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_integer(value)
    match value
    | let i: RespInteger =>
      match result
      | let r: I64 => h.assert_eq[I64](i.value, r)
      else h.fail("Expected I64 for RespInteger")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsBool is Property1[RespValue]
  fun name(): String => "RespConvert/as_bool/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_bool(value)
    match value
    | let b: RespBoolean =>
      match result
      | let r: Bool => h.assert_eq[Bool](b.value, r)
      else h.fail("Expected Bool for RespBoolean")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsArray is Property1[RespValue]
  fun name(): String => "RespConvert/as_array/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_array(value)
    match value
    | let a: RespArray =>
      match result
      | let arr: Array[RespValue] val =>
        h.assert_true(arr is a.values)
      else h.fail("Expected Array[RespValue] for RespArray")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsDouble is Property1[RespValue]
  fun name(): String => "RespConvert/as_double/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_double(value)
    match value
    | let d: RespDouble =>
      match result
      | let r: F64 => h.assert_eq[F64](d.value, r)
      else h.fail("Expected F64 for RespDouble")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsBigNumber is Property1[RespValue]
  fun name(): String => "RespConvert/as_big_number/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_big_number(value)
    match value
    | let bn: RespBigNumber =>
      match result
      | let r: String => h.assert_eq[String](bn.value, r)
      else h.fail("Expected String for RespBigNumber")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsMap is Property1[RespValue]
  fun name(): String => "RespConvert/as_map/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_map(value)
    match value
    | let m: RespMap =>
      match result
      | let pairs: Array[(RespValue, RespValue)] val =>
        h.assert_true(pairs is m.pairs)
      else h.fail("Expected Array pairs for RespMap")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsSet is Property1[RespValue]
  fun name(): String => "RespConvert/as_set/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_set(value)
    match value
    | let s: RespSet =>
      match result
      | let arr: Array[RespValue] val =>
        h.assert_true(arr is s.values)
      else h.fail("Expected Array[RespValue] for RespSet")
      end
    | RespNull =>
      match result
      | RespNull => None
      else h.fail("Expected RespNull for RespNull input")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-matching type")
      end
    end

class \nodoc\ iso _TestRespConvertAsError is Property1[RespValue]
  fun name(): String => "RespConvert/as_error/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.as_error(value)
    match value
    | let e: RespError =>
      match result
      | let r: String => h.assert_eq[String](e.message, r)
      else h.fail("Expected String for RespError")
      end
    | let be': RespBulkError =>
      match result
      | let r: String =>
        h.assert_eq[String](String.from_array(be'.message), r)
      else h.fail("Expected String for RespBulkError")
      end
    else
      match result
      | None => None
      else h.fail("Expected None for non-error type")
      end
    end

class \nodoc\ iso _TestRespConvertIsOk is Property1[RespValue]
  fun name(): String => "RespConvert/is_ok/Property"

  fun gen(): Generator[RespValue] => _RespGens.value()

  fun property(value: RespValue, h: PropertyHelper) =>
    let result = RespConvert.is_ok(value)
    match value
    | let s: RespSimpleString =>
      h.assert_eq[Bool](s.value == "OK", result)
    else
      h.assert_eq[Bool](false, result)
    end

// ---------------------------------------------------------------------------
// RespConvert example-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRespConvertIsOkExamples is UnitTest
  fun name(): String => "RespConvert/is_ok/Examples"

  fun apply(h: TestHelper) =>
    h.assert_true(RespConvert.is_ok(RespSimpleString("OK")))
    h.assert_false(RespConvert.is_ok(RespSimpleString("QUEUED")))
    h.assert_false(RespConvert.is_ok(RespInteger(1)))
    h.assert_false(RespConvert.is_ok(
      RespBulkString(recover val [as U8: 'O'; 'K'] end)))
    h.assert_false(RespConvert.is_ok(RespNull))

class \nodoc\ iso _TestRespConvertAsErrorBulkExample is UnitTest
  fun name(): String => "RespConvert/as_error/BulkExample"

  fun apply(h: TestHelper) =>
    let bytes: Array[U8] val =
      recover val [as U8: 'E'; 'R'; 'R'; ' '; 'f'; 'a'; 'i'; 'l'] end
    let bulk_err = RespBulkError(bytes)
    match RespConvert.as_error(bulk_err)
    | let s: String =>
      h.assert_eq[String]("ERR fail", s)
    else
      h.fail("Expected String from as_error on RespBulkError")
    end
