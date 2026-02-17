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
    test(_TestRespParserIntegerOverflow)
    test(_TestRespParserResp3Null)
    test(_TestRespParserBoolean)
    test(_TestRespParserDouble)
    test(_TestRespParserBigNumber)
    test(_TestRespParserBulkError)
    test(_TestRespParserVerbatimString)
    test(_TestRespParserMap)
    test(_TestRespParserSet)
    test(_TestRespParserPush)

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
    test(_TestSessionPipeline)
    test(_TestSessionPipelineMixedResponses)
    test(_TestSessionPipelineClose)
    test(_TestSessionServerError)
    test(_TestSessionPubSub)
    test(_TestSessionPubSubPattern)
    test(_TestSessionExecuteWhileSubscribed)
    test(_TestSessionPubSubBackToReady)
    test(_TestSessionPipelineDrain)
    test(_TestSessionSSLConnectionFailure)
    test(_TestSessionSSLConnectAndReady)
    test(_TestSessionSSLSetAndGet)
    test(_TestSessionResp3ConnectAndReady)
    test(_TestSessionResp3SetAndGet)
    test(_TestSessionResp3FallbackToResp2)

    // Command construction unit tests
    test(_TestBuildHelloCommand)
    test(_TestBuildAuthCommand)

    // RespConvert property tests
    test(Property1UnitTest[RespValue](_TestRespConvertAsString))
    test(Property1UnitTest[RespValue](_TestRespConvertAsBytes))
    test(Property1UnitTest[RespValue](_TestRespConvertAsInteger))
    test(Property1UnitTest[RespValue](_TestRespConvertAsBool))
    test(Property1UnitTest[RespValue](_TestRespConvertAsArray))
    test(Property1UnitTest[RespValue](_TestRespConvertAsDouble))
    test(Property1UnitTest[RespValue](_TestRespConvertAsBigNumber))
    test(Property1UnitTest[RespValue](_TestRespConvertAsMap))
    test(Property1UnitTest[RespValue](_TestRespConvertAsSet))
    test(Property1UnitTest[RespValue](_TestRespConvertAsError))
    test(Property1UnitTest[RespValue](_TestRespConvertIsOk))

    // RespConvert example tests
    test(_TestRespConvertIsOkExamples)
    test(_TestRespConvertAsErrorBulkExample)

    // Command builder property tests
    test(Property1UnitTest[Array[String] val](_TestRedisKeyDelProperty))
    test(Property1UnitTest[Array[String] val](_TestRedisKeyExistsProperty))
    test(Property1UnitTest[Array[String] val](
      _TestRedisStringMgetProperty))
    test(Property1UnitTest[(String, Array[String] val)](
      _TestRedisListLpushProperty))
    test(Property1UnitTest[(String, Array[String] val)](
      _TestRedisListRpushProperty))
    test(Property1UnitTest[(String, Array[String] val)](
      _TestRedisSetSaddProperty))
    test(Property1UnitTest[(String, Array[String] val)](
      _TestRedisSetSremProperty))
    test(Property1UnitTest[(String, Array[String] val)](
      _TestRedisHashHdelProperty))
    test(Property1UnitTest[Array[(String, String)] val](
      _TestRedisStringMsetProperty))

    // Command builder example tests
    test(_TestRedisServerExamples)
    test(_TestRedisStringExamples)
    test(_TestRedisKeyExamples)
    test(_TestRedisHashExamples)
    test(_TestRedisListExamples)
    test(_TestRedisSetExamples)

    // Command API integration test
    test(_TestCommandApiSetAndGet)
