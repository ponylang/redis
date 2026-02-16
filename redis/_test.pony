use "buffered"
use "pony_check"
use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
    // Parser property tests
    test(Property1UnitTest[RespValue](_TestRespParserRoundtrip))
    test(Property1UnitTest[RespValue](_TestRespParserValidBytesAlwaysParse))
    test(Property1UnitTest[RespValue](_TestRespParserIncompleteReturnsNone))
    test(Property1UnitTest[U8](_TestRespParserInvalidTypeByteErrors))

    // Parser example tests
    test(_TestRespParserEmptyBuffer)
    test(_TestRespParserSimpleString)
    test(_TestRespParserError)
    test(_TestRespParserInteger)
    test(_TestRespParserBulkString)
    test(_TestRespParserArray)
    test(_TestRespParserMultipleValues)
    test(_TestRespParserMalformedErrors)

    // Serializer property tests
    test(Property1UnitTest[Array[ByteSeq] val](
      _TestRespSerializerCommandRoundtrip))
    test(Property1UnitTest[Array[ByteSeq] val](
      _TestRespSerializerOutputIsValidResp))

    // Serializer example tests
    test(_TestRespSerializerSimpleCommand)
    test(_TestRespSerializerSingleElement)
    test(_TestRespSerializerEmptyCommand)
    test(_TestRespSerializerBinaryData)

    // Session integration tests
    test(_TestSessionConnectAndReady)
    test(_TestSessionSetAndGet)
    test(_TestSessionConnectionFailure)
    test(_TestSessionExecuteBeforeReady)
    test(_TestSessionExecuteAfterClose)
    test(_TestSessionMultipleCommands)
    test(_TestSessionServerError)
